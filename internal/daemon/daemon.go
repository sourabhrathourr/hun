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
	"sort"
	"strings"
	"syscall"

	"github.com/sourabhrathourr/hun/internal/config"
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

	// Recover previously running projects from persisted state in background.
	// The daemon should start serving socket requests immediately.
	go d.recoverRunningProjects()

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

func (d *Daemon) saveGitContext(project string) {
	path, ok := d.manager.ProjectPath(project)
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
	d.manager.SetGitBranch(project, branch)
}

func (d *Daemon) recoverRunningProjects() {
	snapshot := d.manager.StateSnapshot()
	type projectToRecover struct {
		name   string
		path   string
		offset int
	}

	var running []projectToRecover
	for name, ps := range snapshot.Projects {
		if ps.Status != "running" {
			continue
		}
		path, ok := snapshot.Registry[name]
		if !ok {
			continue
		}
		running = append(running, projectToRecover{name: name, path: path, offset: ps.Offset})
	}
	sort.Slice(running, func(i, j int) bool { return running[i].offset < running[j].offset })

	for idx, item := range running {
		proj, err := config.LoadProject(item.path)
		if err != nil {
			continue
		}
		d.manager.ports.SetOffset(item.name, item.offset)
		exclusive := snapshot.Mode == "focus" && len(running) == 1 && idx == 0
		if err := d.manager.StartProject(item.name, proj, item.path, exclusive); err != nil {
			continue
		}
	}
	_ = d.manager.SetFocus(snapshot.ActiveProject, snapshot.Mode)
}

// SocketPath returns the daemon socket path.
func SocketPath() (string, error) {
	dir, err := config.HunDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "daemon.sock"), nil
}

// PIDPath returns the daemon pid-file path.
func PIDPath() (string, error) {
	dir, err := config.HunDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "daemon.pid"), nil
}
