package daemon

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"sync"
	"syscall"
	"time"
)

// Process represents a single running service process.
type Process struct {
	Name         string
	Cmd          string
	Dir          string
	Env          map[string]string
	Port         int
	PortEnv      string
	ReadyPattern string

	cmd      *exec.Cmd
	pid      int
	running  bool
	ready    bool
	stopping bool
	exited   chan struct{}
	exitOnce sync.Once
	mu       sync.Mutex

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
	p.cmd.Env = os.Environ()
	for k, v := range p.Env {
		p.cmd.Env = append(p.cmd.Env, k+"="+v)
	}
	if p.PortEnv != "" && p.Port > 0 {
		p.cmd.Env = append(p.cmd.Env, fmt.Sprintf("%s=%d", p.PortEnv, p.Port))
	}

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

	if err := p.cmd.Start(); err != nil {
		return fmt.Errorf("starting %s: %w", p.Name, err)
	}

	p.pid = p.cmd.Process.Pid
	p.running = true
	p.ready = false
	p.stopping = false
	p.exited = make(chan struct{})
	p.exitOnce = sync.Once{}

	go p.scanOutput(stdout, false)
	go p.scanOutput(stderr, true)
	go p.waitForExit(p.cmd)

	if p.ReadyPattern == "" {
		go p.markReadyAfterGracePeriod()
	}

	return nil
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

func (p *Process) waitForExit(cmd *exec.Cmd) {
	err := cmd.Wait()
	p.mu.Lock()
	p.running = false
	intentional := p.stopping
	p.stopping = false
	p.mu.Unlock()
	p.signalExited()
	if p.onExit != nil {
		p.onExit(err, intentional)
	}
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

func (p *Process) signalExited() {
	p.exitOnce.Do(func() {
		close(p.exited)
	})
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
