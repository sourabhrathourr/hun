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
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/sourabhrathourr/hun/internal/daemon"
)

// Client communicates with the hun daemon over a Unix socket.
type Client struct {
	sockPath string
}

type daemonProbe struct {
	ok       bool
	protocol int
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
	probe := c.pingProbe()
	if probe.ok && probe.protocol == daemon.CurrentProtocolVersion {
		return nil
	}
	if probe.ok && probe.protocol != daemon.CurrentProtocolVersion {
		if err := c.restartDaemon(); err != nil {
			return fmt.Errorf("restarting stale daemon: %w", err)
		}
		return nil
	}

	if err := c.startDaemonProcess(); err != nil {
		return fmt.Errorf("starting daemon: %w", err)
	}
	if err := c.waitForDaemonProtocol(daemon.CurrentProtocolVersion, 5*time.Second); err != nil {
		return err
	}
	return nil
}

func (c *Client) startDaemonProcess() error {
	exe, err := os.Executable()
	if err != nil {
		return fmt.Errorf("finding executable: %w", err)
	}
	cmd := exec.Command(exe, "daemon")
	cmd.Stdout = nil
	cmd.Stderr = nil
	cmd.Stdin = nil
	if err := cmd.Start(); err != nil {
		return err
	}
	// Detach
	_ = cmd.Process.Release()
	return nil
}

func (c *Client) waitForDaemonProtocol(protocol int, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		time.Sleep(100 * time.Millisecond)
		probe := c.pingProbe()
		if probe.ok && probe.protocol == protocol {
			return nil
		}
	}
	return fmt.Errorf("daemon did not become ready with protocol %d within %s", protocol, timeout)
}

func (c *Client) restartDaemon() error {
	if err := c.stopDaemonProcess(); err != nil {
		return err
	}
	if err := c.startDaemonProcess(); err != nil {
		return fmt.Errorf("starting daemon: %w", err)
	}
	return c.waitForDaemonProtocol(daemon.CurrentProtocolVersion, 5*time.Second)
}

func (c *Client) stopDaemonProcess() error {
	pidPath, err := daemon.PIDPath()
	if err != nil {
		return err
	}
	raw, err := os.ReadFile(pidPath)
	if err != nil {
		return fmt.Errorf("reading daemon pid: %w", err)
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(raw)))
	if err != nil || pid <= 0 {
		return fmt.Errorf("invalid daemon pid file")
	}

	proc, err := os.FindProcess(pid)
	if err != nil {
		return fmt.Errorf("finding daemon process: %w", err)
	}
	if err := proc.Signal(syscall.SIGTERM); err != nil && !errors.Is(err, os.ErrProcessDone) && !errors.Is(err, syscall.ESRCH) {
		return fmt.Errorf("stopping daemon: %w", err)
	}
	if c.waitForDaemonDown(3 * time.Second) {
		return nil
	}
	_ = proc.Signal(syscall.SIGKILL)
	if c.waitForDaemonDown(2 * time.Second) {
		return nil
	}
	return fmt.Errorf("daemon did not stop in time")
}

func (c *Client) waitForDaemonDown(timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if !c.pingProbe().ok {
			return true
		}
		time.Sleep(100 * time.Millisecond)
	}
	return false
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
	return c.pingProbe().ok
}

func (c *Client) pingProbe() daemonProbe {
	probe := daemonProbe{ok: false, protocol: 0}
	conn, err := net.DialTimeout("unix", c.sockPath, 250*time.Millisecond)
	if err != nil {
		return probe
	}
	defer conn.Close()

	req := daemon.Request{Action: "ping"}
	data, _ := json.Marshal(req)
	conn.Write(append(data, '\n'))

	conn.SetReadDeadline(time.Now().Add(250 * time.Millisecond))
	scanner := bufio.NewScanner(conn)
	if !scanner.Scan() {
		return probe
	}

	var resp daemon.Response
	if err := json.Unmarshal(scanner.Bytes(), &resp); err != nil {
		return probe
	}
	if !resp.OK {
		return probe
	}
	probe.ok = true
	probe.protocol = parsePingProtocol(resp.Data)
	return probe
}

func parsePingProtocol(data json.RawMessage) int {
	type pingPayload struct {
		Status   string `json:"status"`
		Protocol int    `json:"protocol"`
	}
	var payload pingPayload
	if err := json.Unmarshal(data, &payload); err == nil {
		if payload.Protocol > 0 {
			return payload.Protocol
		}
		if strings.EqualFold(payload.Status, "pong") {
			return daemon.LegacyProtocolVersion
		}
	}
	var pong string
	if err := json.Unmarshal(data, &pong); err == nil && strings.EqualFold(pong, "pong") {
		return daemon.LegacyProtocolVersion
	}
	return daemon.LegacyProtocolVersion
}
