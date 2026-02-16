package daemon

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"

	"github.com/hun-sh/hun/internal/config"
	"github.com/hun-sh/hun/internal/state"
)

// Daemon is the background process managing all services.
type Daemon struct {
	manager  *Manager
	listener net.Listener
	sockPath string
	pidPath  string
}

// New creates a new daemon instance.
func New() (*Daemon, error) {
	dir, err := config.HunDir()
	if err != nil {
		return nil, err
	}

	mgr, err := NewManager()
	if err != nil {
		return nil, err
	}

	return &Daemon{
		manager:  mgr,
		sockPath: filepath.Join(dir, "daemon.sock"),
		pidPath:  filepath.Join(dir, "daemon.pid"),
	}, nil
}

// Run starts the daemon and listens for connections.
func (d *Daemon) Run() error {
	// Clean up stale socket
	os.Remove(d.sockPath)

	listener, err := net.Listen("unix", d.sockPath)
	if err != nil {
		return fmt.Errorf("listening on socket: %w", err)
	}
	d.listener = listener

	// Write PID file
	os.WriteFile(d.pidPath, []byte(fmt.Sprintf("%d", os.Getpid())), 0644)

	// Handle signals for graceful shutdown
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)
	go func() {
		<-sigCh
		d.shutdown()
		os.Exit(0)
	}()

	// Accept connections
	for {
		conn, err := listener.Accept()
		if err != nil {
			// Listener closed
			return nil
		}
		go d.handleConnection(conn)
	}
}

func (d *Daemon) handleConnection(conn net.Conn) {
	defer conn.Close()
	scanner := bufio.NewScanner(conn)
	scanner.Buffer(make([]byte, 1024*1024), 1024*1024)

	for scanner.Scan() {
		line := scanner.Text()
		var req Request
		if err := json.Unmarshal([]byte(line), &req); err != nil {
			resp := errorResponse(fmt.Sprintf("invalid JSON: %v", err))
			data, _ := json.Marshal(resp)
			conn.Write(append(data, '\n'))
			continue
		}

		// Handle subscribe specially — keep connection open for streaming
		if req.Action == "subscribe" {
			d.handleSubscribe(conn, req)
			return // Connection stays open for subscriber
		}

		resp := d.HandleRequest(req)
		data, _ := json.Marshal(resp)
		conn.Write(append(data, '\n'))
	}
}

func (d *Daemon) handleSubscribe(conn net.Conn, req Request) {
	sub := d.manager.Subscribe(req.Project, req.Service)
	defer d.manager.Unsubscribe(sub.ID)

	// Send OK response
	resp := successResponse(map[string]int{"subscriber_id": sub.ID})
	data, _ := json.Marshal(resp)
	conn.Write(append(data, '\n'))

	// Stream log lines
	for line := range sub.Ch {
		data, err := json.Marshal(line)
		if err != nil {
			continue
		}
		_, err = conn.Write(append(data, '\n'))
		if err != nil {
			return // Connection closed
		}
	}
}

func (d *Daemon) shutdown() {
	d.manager.Shutdown()
	if d.listener != nil {
		d.listener.Close()
	}
	os.Remove(d.sockPath)
	os.Remove(d.pidPath)
}

func (d *Daemon) loadState() (*state.State, error) {
	return state.Load()
}

func (d *Daemon) saveGitContext(project string) {
	st, err := d.loadState()
	if err != nil {
		return
	}
	path, ok := st.Registry[project]
	if !ok {
		return
	}
	// Get current git branch
	cmd := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD")
	cmd.Dir = path
	out, err := cmd.Output()
	if err != nil {
		return
	}
	branch := strings.TrimSpace(string(out))
	ps := st.Projects[project]
	ps.GitBranch = branch
	st.Projects[project] = ps
	st.Save()
}

// SocketPath returns the daemon socket path.
func SocketPath() (string, error) {
	dir, err := config.HunDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "daemon.sock"), nil
}
