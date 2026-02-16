package client

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"time"

	"github.com/sourabhrathourr/hun/internal/daemon"
)

// Client communicates with the hun daemon over a Unix socket.
type Client struct {
	sockPath string
}

// New creates a new daemon client.
func New() (*Client, error) {
	sockPath, err := daemon.SocketPath()
	if err != nil {
		return nil, err
	}
	return &Client{sockPath: sockPath}, nil
}

// EnsureDaemon starts the daemon if not running.
func (c *Client) EnsureDaemon() error {
	if c.ping() {
		return nil
	}

	// Start daemon in background
	exe, err := os.Executable()
	if err != nil {
		return fmt.Errorf("finding executable: %w", err)
	}
	cmd := exec.Command(exe, "daemon")
	cmd.Stdout = nil
	cmd.Stderr = nil
	cmd.Stdin = nil
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("starting daemon: %w", err)
	}
	// Detach
	cmd.Process.Release()

	// Wait for socket to appear
	for i := 0; i < 50; i++ {
		time.Sleep(100 * time.Millisecond)
		if c.ping() {
			return nil
		}
	}
	return fmt.Errorf("daemon did not start within 5 seconds")
}

// Send sends a request to the daemon and returns the response.
func (c *Client) Send(req daemon.Request) (*daemon.Response, error) {
	if err := c.EnsureDaemon(); err != nil {
		return nil, err
	}

	conn, err := net.DialTimeout("unix", c.sockPath, 5*time.Second)
	if err != nil {
		return nil, fmt.Errorf("connecting to daemon: %w", err)
	}
	defer conn.Close()

	data, err := json.Marshal(req)
	if err != nil {
		return nil, err
	}
	conn.Write(append(data, '\n'))

	scanner := bufio.NewScanner(conn)
	scanner.Buffer(make([]byte, 1024*1024), 1024*1024)
	if !scanner.Scan() {
		return nil, fmt.Errorf("no response from daemon")
	}

	var resp daemon.Response
	if err := json.Unmarshal(scanner.Bytes(), &resp); err != nil {
		return nil, fmt.Errorf("parsing response: %w", err)
	}

	return &resp, nil
}

// Subscribe connects to the daemon and streams log lines.
func (c *Client) Subscribe(project, service string, callback func(daemon.LogLine)) error {
	if err := c.EnsureDaemon(); err != nil {
		return err
	}

	conn, err := net.DialTimeout("unix", c.sockPath, 5*time.Second)
	if err != nil {
		return fmt.Errorf("connecting to daemon: %w", err)
	}
	defer conn.Close()

	req := daemon.Request{
		Action:  "subscribe",
		Project: project,
		Service: service,
	}
	data, _ := json.Marshal(req)
	conn.Write(append(data, '\n'))

	scanner := bufio.NewScanner(conn)
	scanner.Buffer(make([]byte, 1024*1024), 1024*1024)

	// First line is the OK response
	if !scanner.Scan() {
		return fmt.Errorf("no response from daemon")
	}

	// Stream log lines
	for scanner.Scan() {
		var line daemon.LogLine
		if err := json.Unmarshal(scanner.Bytes(), &line); err != nil {
			continue
		}
		callback(line)
	}
	return nil
}

func (c *Client) ping() bool {
	conn, err := net.DialTimeout("unix", c.sockPath, time.Second)
	if err != nil {
		return false
	}
	defer conn.Close()

	req := daemon.Request{Action: "ping"}
	data, _ := json.Marshal(req)
	conn.Write(append(data, '\n'))

	conn.SetReadDeadline(time.Now().Add(time.Second))
	scanner := bufio.NewScanner(conn)
	if !scanner.Scan() {
		return false
	}

	var resp daemon.Response
	if err := json.Unmarshal(scanner.Bytes(), &resp); err != nil {
		return false
	}
	return resp.OK
}
