package daemon

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/sourabhrathourr/hun/internal/config"
	"gopkg.in/natefinch/lumberjack.v2"
)

// LogLine represents a single log entry.
type LogLine struct {
	Timestamp time.Time `json:"timestamp"`
	Service   string    `json:"service"`
	Project   string    `json:"project"`
	Text      string    `json:"text"`
	IsErr     bool      `json:"is_err"`
}

// RingBuffer is a circular buffer for log lines.
type RingBuffer struct {
	lines []LogLine
	size  int
	head  int
	count int
	mu    sync.RWMutex
}

// NewRingBuffer creates a ring buffer with the given capacity.
func NewRingBuffer(size int) *RingBuffer {
	return &RingBuffer{
		lines: make([]LogLine, size),
		size:  size,
	}
}

// Write adds a log line to the ring buffer.
func (rb *RingBuffer) Write(line LogLine) {
	rb.mu.Lock()
	defer rb.mu.Unlock()
	rb.lines[rb.head] = line
	rb.head = (rb.head + 1) % rb.size
	if rb.count < rb.size {
		rb.count++
	}
}

// Lines returns the last n lines from the buffer (or all if n <= 0).
func (rb *RingBuffer) Lines(n int) []LogLine {
	rb.mu.RLock()
	defer rb.mu.RUnlock()

	if n <= 0 || n > rb.count {
		n = rb.count
	}

	result := make([]LogLine, n)
	start := (rb.head - n + rb.size) % rb.size
	for i := 0; i < n; i++ {
		result[i] = rb.lines[(start+i)%rb.size]
	}
	return result
}

type rotationConfig struct {
	maxSizeMB    int
	maxFiles     int
	retentionDay int
}

func defaultRotationConfig() rotationConfig {
	return rotationConfig{
		maxSizeMB:    10,
		maxFiles:     3,
		retentionDay: 7,
	}
}

type serviceLogWriter struct {
	ch      chan LogLine
	closed  atomic.Bool
	closeMu sync.Mutex
	done    chan struct{}
}

func (w *serviceLogWriter) close() {
	w.closeMu.Lock()
	defer w.closeMu.Unlock()
	if w.closed.Load() {
		return
	}
	w.closed.Store(true)
	close(w.ch)
	<-w.done
}

// LogManager handles log buffering and disk writing for all services.
type LogManager struct {
	buffers    map[string]*RingBuffer // "project:service" → buffer
	writers    map[string]*serviceLogWriter
	projectCfg map[string]rotationConfig
	mu         sync.RWMutex
	logDir     string
}

// NewLogManager creates a new log manager.
func NewLogManager() (*LogManager, error) {
	dir, err := config.HunDir()
	if err != nil {
		return nil, err
	}
	logDir := filepath.Join(dir, "logs")
	if err := os.MkdirAll(logDir, 0o755); err != nil {
		return nil, err
	}
	return &LogManager{
		buffers:    make(map[string]*RingBuffer),
		writers:    make(map[string]*serviceLogWriter),
		projectCfg: make(map[string]rotationConfig),
		logDir:     logDir,
	}, nil
}

func (lm *LogManager) bufferKey(project, service string) string {
	return project + ":" + service
}

// SetProjectConfig stores per-project log rotation settings.
func (lm *LogManager) SetProjectConfig(project string, logs config.LogsConfig) {
	cfg := defaultRotationConfig()
	if logs.MaxSize != "" {
		if v := parseSizeMB(logs.MaxSize); v > 0 {
			cfg.maxSizeMB = v
		}
	}
	if logs.MaxFiles > 0 {
		cfg.maxFiles = logs.MaxFiles
	}
	if logs.Retention != "" {
		if v := parseRetentionDays(logs.Retention); v > 0 {
			cfg.retentionDay = v
		}
	}

	lm.mu.Lock()
	lm.projectCfg[project] = cfg
	lm.mu.Unlock()
}

// GetBuffer returns the ring buffer for a service, creating one if needed.
func (lm *LogManager) GetBuffer(project, service string) *RingBuffer {
	key := lm.bufferKey(project, service)
	lm.mu.Lock()
	defer lm.mu.Unlock()
	if rb, ok := lm.buffers[key]; ok {
		return rb
	}
	rb := NewRingBuffer(10000)
	lm.buffers[key] = rb
	return rb
}

// WriteLog writes a log line to both ring buffer and asynchronous disk writer.
func (lm *LogManager) WriteLog(line LogLine) {
	rb := lm.GetBuffer(line.Project, line.Service)
	rb.Write(line)
	lm.writeAsync(line)
}

func (lm *LogManager) writeAsync(line LogLine) {
	writer := lm.getOrCreateWriter(line.Project, line.Service)
	if writer == nil {
		return
	}
	select {
	case writer.ch <- line:
	default:
		// Drop disk write if queue is full; ring buffer still keeps recent logs.
	}
}

func (lm *LogManager) getOrCreateWriter(project, service string) *serviceLogWriter {
	key := lm.bufferKey(project, service)

	lm.mu.RLock()
	if w, ok := lm.writers[key]; ok {
		lm.mu.RUnlock()
		return w
	}
	cfg, ok := lm.projectCfg[project]
	if !ok {
		cfg = defaultRotationConfig()
	}
	logDir := lm.logDir
	lm.mu.RUnlock()

	projDir := filepath.Join(logDir, project)
	if err := os.MkdirAll(projDir, 0o755); err != nil {
		return nil
	}

	path := filepath.Join(projDir, service+".log")
	rotator := &lumberjack.Logger{
		Filename:   path,
		MaxSize:    cfg.maxSizeMB,
		MaxBackups: cfg.maxFiles,
		MaxAge:     cfg.retentionDay,
		Compress:   false,
	}

	writer := &serviceLogWriter{
		ch:   make(chan LogLine, 2048),
		done: make(chan struct{}),
	}
	go func() {
		defer close(writer.done)
		for line := range writer.ch {
			ts := line.Timestamp.Format("2006-01-02 15:04:05")
			stream := "out"
			if line.IsErr {
				stream = "err"
			}
			_, _ = fmt.Fprintf(rotator, "[%s] [%s] %s\n", ts, stream, line.Text)
		}
		_ = rotator.Close()
	}()

	lm.mu.Lock()
	if existing, ok := lm.writers[key]; ok {
		lm.mu.Unlock()
		writer.close()
		return existing
	}
	lm.writers[key] = writer
	lm.mu.Unlock()
	return writer
}

// GetLines returns buffered log lines for a service.
func (lm *LogManager) GetLines(project, service string, n int) []LogLine {
	rb := lm.GetBuffer(project, service)
	return rb.Lines(n)
}

// Close closes all asynchronous log writers.
func (lm *LogManager) Close() {
	lm.mu.Lock()
	writers := make([]*serviceLogWriter, 0, len(lm.writers))
	for _, w := range lm.writers {
		writers = append(writers, w)
	}
	lm.writers = make(map[string]*serviceLogWriter)
	lm.mu.Unlock()

	for _, w := range writers {
		w.close()
	}
}

// CleanProject removes buffers and writers for a project.
func (lm *LogManager) CleanProject(project string) {
	lm.mu.Lock()
	writers := make([]*serviceLogWriter, 0)
	prefix := project + ":"
	for key, w := range lm.writers {
		if strings.HasPrefix(key, prefix) {
			writers = append(writers, w)
			delete(lm.writers, key)
			delete(lm.buffers, key)
		}
	}
	delete(lm.projectCfg, project)
	lm.mu.Unlock()

	for _, w := range writers {
		w.close()
	}
}

func parseSizeMB(raw string) int {
	s := strings.TrimSpace(strings.ToUpper(raw))
	if s == "" {
		return 0
	}
	if strings.HasSuffix(s, "MB") {
		n, _ := strconv.Atoi(strings.TrimSpace(strings.TrimSuffix(s, "MB")))
		return n
	}
	if strings.HasSuffix(s, "M") {
		n, _ := strconv.Atoi(strings.TrimSpace(strings.TrimSuffix(s, "M")))
		return n
	}
	if strings.HasSuffix(s, "GB") {
		n, _ := strconv.Atoi(strings.TrimSpace(strings.TrimSuffix(s, "GB")))
		if n > 0 {
			return n * 1024
		}
	}
	n, _ := strconv.Atoi(s)
	return n
}

func parseRetentionDays(raw string) int {
	s := strings.TrimSpace(strings.ToLower(raw))
	if s == "" {
		return 0
	}
	if strings.HasSuffix(s, "d") {
		n, _ := strconv.Atoi(strings.TrimSpace(strings.TrimSuffix(s, "d")))
		return n
	}
	if d, err := time.ParseDuration(s); err == nil {
		days := int(d.Hours() / 24)
		if days > 0 {
			return days
		}
	}
	n, _ := strconv.Atoi(s)
	return n
}
