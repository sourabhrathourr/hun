package daemon

import (
	"bufio"
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

	cmd     *exec.Cmd
	pid     int
	running bool
	ready   bool
	mu      sync.Mutex

	onOutput func(line string, isErr bool)
	onExit   func(err error)
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

	go p.scanOutput(stdout, false)
	go p.scanOutput(stderr, true)
	go p.waitForExit()

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
	p.mu.Unlock()

	// Send SIGTERM to entire process group
	if err := syscall.Kill(-pid, syscall.SIGTERM); err != nil {
		// Process might already be dead
		return nil
	}

	// Wait up to 5 seconds for graceful shutdown
	done := make(chan struct{})
	go func() {
		for i := 0; i < 50; i++ {
			p.mu.Lock()
			running := p.running
			p.mu.Unlock()
			if !running {
				close(done)
				return
			}
			time.Sleep(100 * time.Millisecond)
		}
		close(done)
	}()

	<-done

	p.mu.Lock()
	if p.running {
		p.mu.Unlock()
		// Force kill
		syscall.Kill(-pid, syscall.SIGKILL)
	} else {
		p.mu.Unlock()
	}

	return nil
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

func (p *Process) waitForExit() {
	err := p.cmd.Wait()
	p.mu.Lock()
	p.running = false
	p.mu.Unlock()
	if p.onExit != nil {
		p.onExit(err)
	}
}
