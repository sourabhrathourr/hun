package client

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
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

	// Wait for daemon to become responsive with a hard deadline.
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
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
	return c.SubscribeWithContext(context.Background(), project, service, callback)
}

// SubscribeWithContext connects to the daemon and streams log lines until context cancellation.
func (c *Client) SubscribeWithContext(ctx context.Context, project, service string, callback func(daemon.LogLine)) error {
	if err := c.EnsureDaemon(); err != nil {
		return err
	}

	conn, err := net.DialTimeout("unix", c.sockPath, 5*time.Second)
	if err != nil {
		return fmt.Errorf("connecting to daemon: %w", err)
	}
	defer conn.Close()
	go func() {
		<-ctx.Done()
		_ = conn.Close()
	}()

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
		if errors.Is(ctx.Err(), context.Canceled) {
			return nil
		}
		return fmt.Errorf("no response from daemon")
	}
	var ack daemon.Response
	if err := json.Unmarshal(scanner.Bytes(), &ack); err == nil && !ack.OK {
		return fmt.Errorf("subscribe rejected: %s", ack.Error)
	}

	// Stream log lines
	for scanner.Scan() {
		var line daemon.LogLine
		if err := json.Unmarshal(scanner.Bytes(), &line); err != nil {
			continue
		}
		callback(line)
	}
	if errors.Is(ctx.Err(), context.Canceled) {
		return nil
	}
	if err := scanner.Err(); err != nil {
		return err
	}
	return nil
}

func (c *Client) ping() bool {
	conn, err := net.DialTimeout("unix", c.sockPath, 250*time.Millisecond)
	if err != nil {
		return false
	}
	defer conn.Close()

	req := daemon.Request{Action: "ping"}
	data, _ := json.Marshal(req)
	conn.Write(append(data, '\n'))

	conn.SetReadDeadline(time.Now().Add(250 * time.Millisecond))
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
