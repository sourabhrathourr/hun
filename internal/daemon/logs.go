package daemon

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/sourabhrathourr/hun/internal/config"
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

// LogManager handles log buffering and disk writing for all services.
type LogManager struct {
	buffers map[string]*RingBuffer // "project:service" → buffer
	writers map[string]*os.File
	mu      sync.RWMutex
	logDir  string
}

// NewLogManager creates a new log manager.
func NewLogManager() (*LogManager, error) {
	dir, err := config.HunDir()
	if err != nil {
		return nil, err
	}
	logDir := filepath.Join(dir, "logs")
	if err := os.MkdirAll(logDir, 0755); err != nil {
		return nil, err
	}
	return &LogManager{
		buffers: make(map[string]*RingBuffer),
		writers: make(map[string]*os.File),
		logDir:  logDir,
	}, nil
}

func (lm *LogManager) bufferKey(project, service string) string {
	return project + ":" + service
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

// WriteLog writes a log line to both ring buffer and disk.
func (lm *LogManager) WriteLog(line LogLine) {
	rb := lm.GetBuffer(line.Project, line.Service)
	rb.Write(line)

	// Write to disk
	lm.writeToDisk(line)
}

func (lm *LogManager) writeToDisk(line LogLine) {
	key := lm.bufferKey(line.Project, line.Service)
	lm.mu.Lock()
	f, ok := lm.writers[key]
	if !ok {
		projDir := filepath.Join(lm.logDir, line.Project)
		os.MkdirAll(projDir, 0755)
		path := filepath.Join(projDir, line.Service+".log")
		var err error
		f, err = os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
		if err != nil {
			lm.mu.Unlock()
			return
		}
		lm.writers[key] = f
	}
	lm.mu.Unlock()

	ts := line.Timestamp.Format("2006-01-02 15:04:05")
	stream := "out"
	if line.IsErr {
		stream = "err"
	}
	fmt.Fprintf(f, "[%s] [%s] %s\n", ts, stream, line.Text)
}

// GetLines returns buffered log lines for a service.
func (lm *LogManager) GetLines(project, service string, n int) []LogLine {
	rb := lm.GetBuffer(project, service)
	return rb.Lines(n)
}

// Close closes all open log files.
func (lm *LogManager) Close() {
	lm.mu.Lock()
	defer lm.mu.Unlock()
	for _, f := range lm.writers {
		f.Close()
	}
}

// CleanProject removes buffers and writers for a project.
func (lm *LogManager) CleanProject(project string) {
	lm.mu.Lock()
	defer lm.mu.Unlock()
	for key, f := range lm.writers {
		if len(key) > len(project) && key[:len(project)+1] == project+":" {
			f.Close()
			delete(lm.writers, key)
			delete(lm.buffers, key)
		}
	}
}
