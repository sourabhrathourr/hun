package daemon

import (
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

var errPortInspectionUnavailable = errors.New("process listener inspection unavailable")
var errPortUnavailable = errors.New("port unavailable")

func isPortUnavailable(err error) bool {
	return errors.Is(err, errPortUnavailable)
}

var localPortLeases = struct {
	sync.Mutex
	ports map[int]bool
}{ports: make(map[int]bool)}

type portLease struct {
	port int
	file *os.File
}

func acquirePortLease(port int) (*portLease, error) {
	if port <= 0 {
		return nil, nil
	}

	localPortLeases.Lock()
	if localPortLeases.ports[port] {
		localPortLeases.Unlock()
		return nil, fmt.Errorf("configured port %d is reserved by another hun service: %w", port, errPortUnavailable)
	}
	localPortLeases.ports[port] = true
	localPortLeases.Unlock()

	releaseLocal := func() {
		localPortLeases.Lock()
		delete(localPortLeases.ports, port)
		localPortLeases.Unlock()
	}

	dir := filepath.Join(os.TempDir(), fmt.Sprintf("hun-port-leases-%d", os.Getuid()))
	if err := os.MkdirAll(dir, 0o700); err != nil {
		releaseLocal()
		return nil, fmt.Errorf("create port lease directory: %w", err)
	}
	path := filepath.Join(dir, strconv.Itoa(port)+".lock")
	file, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		releaseLocal()
		return nil, fmt.Errorf("open port lease for %d: %w", port, err)
	}
	if err := syscall.Flock(int(file.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		_ = file.Close()
		releaseLocal()
		return nil, fmt.Errorf("configured port %d is reserved by another hun instance: %w", port, errPortUnavailable)
	}
	return &portLease{port: port, file: file}, nil
}

func (l *portLease) release() {
	if l == nil || l.file == nil {
		return
	}
	_ = syscall.Flock(int(l.file.Fd()), syscall.LOCK_UN)
	_ = l.file.Close()
	l.file = nil
	localPortLeases.Lock()
	delete(localPortLeases.ports, l.port)
	localPortLeases.Unlock()
}

func ensureTCPPortAvailable(port int) error {
	if port <= 0 {
		return nil
	}
	address := "127.0.0.1:" + strconv.Itoa(port)
	if conn, err := net.DialTimeout("tcp4", address, 100*time.Millisecond); err == nil {
		_ = conn.Close()
		return fmt.Errorf("configured port %d is unavailable: already accepting TCP connections: %w", port, errPortUnavailable)
	}
	listener, err := net.Listen("tcp4", "0.0.0.0:"+strconv.Itoa(port))
	if err != nil {
		return fmt.Errorf("configured port %d is unavailable: %v: %w", port, err, errPortUnavailable)
	}
	return listener.Close()
}

func processGroupListeningTCPPorts(processGroupID int) (map[int]bool, error) {
	ports := make(map[int]bool)
	if processGroupID <= 0 {
		return ports, nil
	}

	lsof, err := lsofPath()
	if err != nil {
		return nil, err
	}
	cmd := exec.Command(lsof, "-nP", "-a", "-g", strconv.Itoa(processGroupID), "-iTCP", "-sTCP:LISTEN", "-Fn")
	output, err := cmd.Output()
	if err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) && exitErr.ExitCode() == 1 {
			return ports, nil
		}
		return nil, fmt.Errorf("inspect process listeners: %w", err)
	}

	for _, line := range strings.Split(string(output), "\n") {
		if len(line) < 2 || line[0] != 'n' {
			continue
		}
		endpoint := line[1:]
		colon := strings.LastIndex(endpoint, ":")
		if colon < 0 {
			continue
		}
		rawPort := endpoint[colon+1:]
		if end := strings.IndexFunc(rawPort, func(r rune) bool { return r < '0' || r > '9' }); end >= 0 {
			rawPort = rawPort[:end]
		}
		port, parseErr := strconv.Atoi(rawPort)
		if parseErr == nil && port > 0 && port <= 65535 {
			ports[port] = true
		}
	}
	return ports, nil
}

func lsofPath() (string, error) {
	if path, err := exec.LookPath("lsof"); err == nil {
		return path, nil
	}
	for _, path := range []string{"/usr/sbin/lsof", "/usr/bin/lsof"} {
		if info, err := os.Stat(path); err == nil && !info.IsDir() {
			return filepath.Clean(path), nil
		}
	}
	return "", errPortInspectionUnavailable
}
