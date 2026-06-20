package daemon

import (
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestPrepareSocketDoesNotRemoveLiveDaemonSocket(t *testing.T) {
	sockPath := shortTestSocketPath(t)
	listener, err := net.Listen("unix", sockPath)
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	defer listener.Close()

	d := &Daemon{sockPath: sockPath}
	err = d.prepareSocket()
	if err == nil || !strings.Contains(err.Error(), "daemon already running") {
		t.Fatalf("prepareSocket error = %v, want daemon already running", err)
	}

	if _, err := os.Stat(sockPath); err != nil {
		t.Fatalf("expected live socket to remain: %v", err)
	}
}

func TestPrepareSocketRemovesStaleDaemonSocket(t *testing.T) {
	sockPath := shortTestSocketPath(t)
	if err := os.WriteFile(sockPath, []byte("stale"), 0o644); err != nil {
		t.Fatalf("write stale socket placeholder: %v", err)
	}

	d := &Daemon{sockPath: sockPath}
	if err := d.prepareSocket(); err != nil {
		t.Fatalf("prepareSocket: %v", err)
	}

	if _, err := os.Stat(sockPath); !os.IsNotExist(err) {
		t.Fatalf("expected stale socket removed, stat err = %v", err)
	}
}

func TestAcquireLockPreventsConcurrentDaemonStartup(t *testing.T) {
	lockPath := filepath.Join(t.TempDir(), "daemon.lock")
	first := &Daemon{lockPath: lockPath, sockPath: shortTestSocketPath(t)}
	if err := first.acquireLock(); err != nil {
		t.Fatalf("first acquireLock: %v", err)
	}
	defer first.releaseLock()

	second := &Daemon{lockPath: lockPath, sockPath: shortTestSocketPath(t)}
	err := second.acquireLock()
	if err == nil || !strings.Contains(err.Error(), "daemon already") {
		t.Fatalf("second acquireLock error = %v, want daemon already", err)
	}
}

func shortTestSocketPath(t *testing.T) string {
	t.Helper()
	path := filepath.Join(os.TempDir(), fmt.Sprintf("hun-%d-%d.sock", os.Getpid(), time.Now().UnixNano()))
	t.Cleanup(func() { _ = os.Remove(path) })
	return path
}
