package daemon

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"
)

// Process represents a single running service process.
type Process struct {
	Name             string
	Cmd              string
	Dir              string
	Env              map[string]string
	PortEnv          string
	ReadyPattern     string
	observedPort     int  // currently reported to status and UI
	basePort         int  // configured port before any availability fallback
	launchPort       int  // port selected and requested at process launch
	allowRuntimePort bool // multitask services may adopt another verified owned listener

	cmd       *exec.Cmd
	stdin     io.Closer
	pid       int
	running   bool
	ready     bool
	stopping  bool
	startedAt time.Time
	exited    chan struct{}
	portLease *portLease
	mu        sync.Mutex

	onOutput func(line string, isErr bool)
	onExit   func(err error, intentional bool)
	onReady  func()
}

// Start launches the process in its own process group.
func (p *Process) Start() error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.running {
		return fmt.Errorf("process %s already running", p.Name)
	}

	shell := os.Getenv("SHELL")
	if shell == "" {
		shell = "/bin/sh"
	}
	p.cmd = exec.Command(shell, "-c", p.Cmd)

	if p.Dir != "" {
		p.cmd.Dir = p.Dir
	}

	// Build environment
	launchPort := p.launchPort
	if launchPort <= 0 {
		launchPort = p.observedPort
	}
	p.cmd.Env = buildServiceEnvironment(p.Env, p.PortEnv, launchPort)

	// Start in own process group for clean kill
	p.cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	stdout, err := p.cmd.StdoutPipe()
	if err != nil {
		return fmt.Errorf("stdout pipe: %w", err)
	}
	stderr, err := p.cmd.StderrPipe()
	if err != nil {
		return fmt.Errorf("stderr pipe: %w", err)
	}
	stdin, err := p.cmd.StdinPipe()
	if err != nil {
		return fmt.Errorf("stdin pipe: %w", err)
	}

	if err := p.cmd.Start(); err != nil {
		_ = stdin.Close()
		return fmt.Errorf("starting %s: %w", p.Name, err)
	}

	p.stdin = stdin
	p.pid = p.cmd.Process.Pid
	p.running = true
	p.ready = false
	p.stopping = false
	p.startedAt = time.Now().UTC()
	p.exited = make(chan struct{})

	go p.scanOutput(stdout, false)
	go p.scanOutput(stderr, true)
	go p.waitForExit(p.cmd, p.exited)

	if p.ReadyPattern == "" {
		go p.markReadyAfterGracePeriod()
	}

	return nil
}

func buildServiceEnvironment(overrides map[string]string, portEnv string, port int) []string {
	env := withDeveloperEnvironment(os.Environ())
	for k, v := range overrides {
		env = setEnv(env, k, v)
	}
	if port > 0 {
		selectedPort := fmt.Sprintf("%d", port)
		env = setEnv(env, "PORT", selectedPort)
		if portEnv != "" {
			env = setEnv(env, portEnv, selectedPort)
		}
	}
	return env
}

func withDeveloperEnvironment(env []string) []string {
	home := envValue(env, "HOME")
	if home == "" {
		if detectedHome, err := os.UserHomeDir(); err == nil {
			home = detectedHome
			env = setEnv(env, "HOME", home)
		}
	}

	path := envValue(env, "PATH")
	path = mergePath(path, developerPathCandidates(home), shouldPrependDeveloperPaths(path, home))
	env = setEnv(env, "PATH", path)

	if home != "" {
		pnpmHome := filepath.Join(home, "Library", "pnpm")
		if envValue(env, "PNPM_HOME") == "" && dirExists(pnpmHome) {
			env = setEnv(env, "PNPM_HOME", pnpmHome)
		}
		bunInstall := filepath.Join(home, ".bun")
		if envValue(env, "BUN_INSTALL") == "" && dirExists(bunInstall) {
			env = setEnv(env, "BUN_INSTALL", bunInstall)
		}
	}

	return env
}

func developerPathCandidates(home string) []string {
	candidates := []string{
		"/opt/homebrew/bin",
		"/opt/homebrew/sbin",
		"/usr/local/bin",
		"/usr/local/sbin",
		"/Applications/Docker.app/Contents/Resources/bin",
		"/usr/bin",
		"/bin",
		"/usr/sbin",
		"/sbin",
	}
	if home != "" {
		homeCandidates := []string{
			filepath.Join(home, "Library", "pnpm"),
			filepath.Join(home, ".bun", "bin"),
			filepath.Join(home, ".deno", "bin"),
			filepath.Join(home, ".volta", "bin"),
			filepath.Join(home, ".local", "share", "mise", "shims"),
			filepath.Join(home, ".mise", "shims"),
			filepath.Join(home, ".asdf", "shims"),
			filepath.Join(home, ".asdf", "bin"),
			filepath.Join(home, ".cargo", "bin"),
			filepath.Join(home, "go", "bin"),
			filepath.Join(home, ".local", "bin"),
			filepath.Join(home, ".rbenv", "shims"),
			filepath.Join(home, ".pyenv", "shims"),
		}
		candidates = append(homeCandidates, candidates...)

		nvmBins, _ := filepath.Glob(filepath.Join(home, ".nvm", "versions", "node", "*", "bin"))
		sort.Sort(sort.Reverse(sort.StringSlice(nvmBins)))
		candidates = append(nvmBins, candidates...)
	}

	existing := candidates[:0]
	for _, candidate := range candidates {
		if dirExists(candidate) {
			existing = append(existing, candidate)
		}
	}
	return existing
}

func shouldPrependDeveloperPaths(path, home string) bool {
	if strings.TrimSpace(path) == "" {
		return true
	}
	if strings.Contains(path, "/opt/homebrew/bin") || strings.Contains(path, "/usr/local/bin") {
		return false
	}
	return home != "" && !strings.Contains(path, home)
}

func mergePath(path string, candidates []string, prepend bool) string {
	parts := splitPath(path)
	if prepend {
		return strings.Join(appendUnique(candidates, parts...), string(os.PathListSeparator))
	}
	return strings.Join(appendUnique(parts, candidates...), string(os.PathListSeparator))
}

func splitPath(path string) []string {
	if path == "" {
		return nil
	}
	raw := strings.Split(path, string(os.PathListSeparator))
	parts := make([]string, 0, len(raw))
	for _, part := range raw {
		if part != "" {
			parts = append(parts, part)
		}
	}
	return parts
}

func appendUnique(primary []string, secondary ...string) []string {
	seen := make(map[string]bool, len(primary)+len(secondary))
	out := make([]string, 0, len(primary)+len(secondary))
	for _, part := range append(primary, secondary...) {
		if part == "" || seen[part] {
			continue
		}
		seen[part] = true
		out = append(out, part)
	}
	return out
}

func envValue(env []string, key string) string {
	prefix := key + "="
	for _, pair := range env {
		if strings.HasPrefix(pair, prefix) {
			return strings.TrimPrefix(pair, prefix)
		}
	}
	return ""
}

func setEnv(env []string, key, value string) []string {
	prefix := key + "="
	for i, pair := range env {
		if strings.HasPrefix(pair, prefix) {
			env[i] = prefix + value
			return env
		}
	}
	return append(env, prefix+value)
}

func dirExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}

// Stop sends SIGTERM to the process group, then SIGKILL after timeout.
func (p *Process) Stop() error {
	p.mu.Lock()
	if !p.running {
		p.mu.Unlock()
		return nil
	}
	pid := p.pid
	exited := p.exited
	p.stopping = true
	p.mu.Unlock()

	// Send SIGTERM to entire process group
	if err := syscall.Kill(-pid, syscall.SIGTERM); err != nil && !errors.Is(err, syscall.ESRCH) {
		return fmt.Errorf("sending SIGTERM to %s: %w", p.Name, err)
	}

	if waitForProcessExit(exited, 5*time.Second) {
		return nil
	}

	// Force kill remaining process group and wait for final exit notification.
	if err := syscall.Kill(-pid, syscall.SIGKILL); err != nil && !errors.Is(err, syscall.ESRCH) {
		return fmt.Errorf("sending SIGKILL to %s: %w", p.Name, err)
	}
	if waitForProcessExit(exited, 2*time.Second) {
		return nil
	}
	return fmt.Errorf("process %s did not exit after SIGKILL", p.Name)
}

// IsRunning returns whether the process is currently running.
func (p *Process) IsRunning() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.running
}

// IsReady returns whether the process has matched its ready pattern.
func (p *Process) IsReady() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.ready
}

// PID returns the process ID.
func (p *Process) PID() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.pid
}

// StartedAt returns the timestamp when the process last started.
func (p *Process) StartedAt() time.Time {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.startedAt
}

// ObservedPort returns the port currently reported to status consumers.
func (p *Process) ObservedPort() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.observedPort
}

// LaunchPort returns the authoritative port injected at process launch.
func (p *Process) LaunchPort() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.launchPort
}

// SetObservedPort updates live status without changing future launches.
func (p *Process) SetObservedPort(port int) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.observedPort = port
}

// ResetObservedPort restores live status to the authoritative launch port.
func (p *Process) ResetObservedPort() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.observedPort = p.launchPort
	return p.observedPort
}

// BasePort returns the configured port before multitask availability fallback.
func (p *Process) BasePort() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.basePort
}

// AllowsRuntimePort reports whether a verified alternative listener may be
// adopted instead of terminating the service.
func (p *Process) AllowsRuntimePort() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.allowRuntimePort
}

// PreparePort updates the selected launch port and installs its reservation.
func (p *Process) PreparePort(port int, lease *portLease) {
	p.mu.Lock()
	oldLease := p.portLease
	p.portLease = lease
	p.launchPort = port
	p.observedPort = port
	p.mu.Unlock()
	oldLease.release()
}

// AdoptRuntimePort transfers the service reservation to a verified listener.
func (p *Process) AdoptRuntimePort(port int) error {
	p.mu.Lock()
	if p.portLease != nil && p.portLease.port == port {
		p.launchPort = port
		p.observedPort = port
		p.mu.Unlock()
		return nil
	}
	p.mu.Unlock()

	lease, err := acquirePortLease(port)
	if err != nil {
		return err
	}
	p.PreparePort(port, lease)
	return nil
}

func (p *Process) SetPortLease(lease *portLease) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.portLease = lease
}

func (p *Process) ReleasePortLease() {
	p.mu.Lock()
	lease := p.portLease
	p.portLease = nil
	p.mu.Unlock()
	lease.release()
}

func (p *Process) scanOutput(r io.Reader, isErr bool) {
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 64*1024), 64*1024)
	for scanner.Scan() {
		line := scanner.Text()
		if p.onOutput != nil {
			p.onOutput(line, isErr)
		}
		if !p.IsReady() && p.ReadyPattern != "" {
			if strings.Contains(line, p.ReadyPattern) {
				p.mu.Lock()
				p.ready = true
				p.mu.Unlock()
				if p.onReady != nil {
					p.onReady()
				}
			}
		}
	}
}

func (p *Process) waitForExit(cmd *exec.Cmd, exited chan struct{}) {
	err := cmd.Wait()
	p.mu.Lock()
	p.running = false
	p.ready = false
	p.pid = 0
	stdin := p.stdin
	p.stdin = nil
	intentional := p.stopping
	p.stopping = false
	p.mu.Unlock()
	if stdin != nil {
		_ = stdin.Close()
	}
	if p.onExit != nil {
		p.onExit(err, intentional)
	}
	signalExited(exited)
}

func (p *Process) markReadyAfterGracePeriod() {
	time.Sleep(time.Second)
	p.mu.Lock()
	if !p.running || p.ready {
		p.mu.Unlock()
		return
	}
	p.ready = true
	p.mu.Unlock()
	if p.onReady != nil {
		p.onReady()
	}
}

func signalExited(exited chan struct{}) {
	close(exited)
}

func waitForProcessExit(exited <-chan struct{}, timeout time.Duration) bool {
	if exited == nil {
		return true
	}
	select {
	case <-exited:
		return true
	case <-time.After(timeout):
		return false
	}
}
