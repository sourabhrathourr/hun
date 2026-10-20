package daemon

import (
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"testing"
	"time"

	"github.com/sourabhrathourr/hun/internal/config"
	"github.com/sourabhrathourr/hun/internal/state"
)

func TestMain(m *testing.M) {
	// Tests never see the developer's real containers.
	listComposeContainers = func() ([]ObservedContainer, error) { return nil, nil }
	os.Exit(m.Run())
}

// startOutsideHun runs a TCP listener from dir the way a terminal or agent
// would, without the daemon knowing about it.
func startOutsideHun(t *testing.T, dir string, port int) *exec.Cmd {
	t.Helper()
	cmd := exec.Command("sh", "-c", tcpServerCommand(port))
	cmd.Dir = dir
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		t.Fatalf("start outside listener: %v", err)
	}
	exited := make(chan struct{})
	go func() {
		_ = cmd.Wait() // reap promptly so stop paths do not wait on a zombie
		close(exited)
	}()
	t.Cleanup(func() {
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		<-exited
	})
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if conn, err := net.DialTimeout("tcp4", fmt.Sprintf("127.0.0.1:%d", port), 100*time.Millisecond); err == nil {
			_ = conn.Close()
			return cmd
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatalf("outside listener never bound port %d", port)
	return nil
}

func portListening(port int) bool {
	conn, err := net.DialTimeout("tcp4", fmt.Sprintf("127.0.0.1:%d", port), 100*time.Millisecond)
	if err != nil {
		return false
	}
	_ = conn.Close()
	return true
}

type externalFixture struct {
	daemon *Daemon
	root   string
}

func newExternalFixture(t *testing.T, projects map[string]string) (*externalFixture, map[string]string) {
	t.Helper()
	requireRuntimePortInspection(t)
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	writeDaemonGlobalConfig(t, home, root)

	st, err := state.Load()
	if err != nil {
		t.Fatalf("load state: %v", err)
	}
	dirs := make(map[string]string)
	for name, raw := range projects {
		dirs[name] = writeDaemonProjectRaw(t, root, name, raw)
		st.Register(name, dirs[name])
	}
	if err := st.Save(); err != nil {
		t.Fatalf("save state: %v", err)
	}
	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	t.Cleanup(m.Shutdown)
	return &externalFixture{daemon: &Daemon{manager: m}, root: root}, dirs
}

func TestSnapshotShowsServiceStartedOutsideHun(t *testing.T) {
	port := freeTCPPort(t)
	fx, dirs := newExternalFixture(t, map[string]string{
		"shop": fmt.Sprintf("name: shop\nservices:\n  web:\n    cmd: sleep 5\n    port: %d\n", port),
	})
	startOutsideHun(t, dirs["shop"], port)

	snapshot, err := fx.daemon.manager.Snapshot(true)
	if err != nil {
		t.Fatalf("snapshot: %v", err)
	}
	if len(snapshot.Projects) != 1 || len(snapshot.Projects[0].Services) != 1 {
		t.Fatalf("snapshot projects = %+v", snapshot.Projects)
	}
	project := snapshot.Projects[0]
	svc := project.Services[0]
	if project.Status != "running" || !svc.Running || svc.Origin != "external" || svc.Port != port || svc.PID <= 0 {
		t.Fatalf("project=%s service=%+v, want external running on %d", project.Status, svc, port)
	}

	// Starting it again must not spawn a duplicate or fail on the port.
	resp := fx.daemon.HandleRequest(Request{Action: "start_service", Project: "shop", Service: "web", Mode: "parallel"})
	if !resp.OK {
		t.Fatalf("start_service: %s", resp.Error)
	}
	if fx.daemon.manager.IsServiceRunning("shop", "web") {
		t.Fatal("hun spawned a duplicate of a service already running outside it")
	}

	// Stop works on it even though Hun never started it.
	resp = fx.daemon.HandleRequest(Request{Action: "stop", Project: "shop"})
	if !resp.OK {
		t.Fatalf("stop: %s", resp.Error)
	}
	if portListening(port) {
		t.Fatal("external service still listening after stop")
	}
}

func TestRestartTakesOverExternalService(t *testing.T) {
	port := freeTCPPort(t)
	fx, dirs := newExternalFixture(t, map[string]string{
		"shop": fmt.Sprintf("name: shop\nservices:\n  web:\n    cmd: %q\n    port: %d\n", tcpServerCommand(port), port),
	})
	outside := startOutsideHun(t, dirs["shop"], port)

	resp := fx.daemon.HandleRequest(Request{Action: "restart", Project: "shop", Service: "web"})
	if !resp.OK {
		t.Fatalf("restart: %s", resp.Error)
	}
	if syscall.Kill(outside.Process.Pid, 0) == nil {
		t.Fatal("outside instance still alive after restart")
	}
	waitForServiceRunning(t, fx.daemon.manager, "shop", "web")
}

func TestStartReportsWhoHoldsThePort(t *testing.T) {
	port := freeTCPPort(t)
	fx, _ := newExternalFixture(t, map[string]string{
		"shop": fmt.Sprintf("name: shop\nservices:\n  web:\n    cmd: sleep 5\n    port: %d\n", port),
	})
	elsewhere := filepath.Join(fx.root, "scratch")
	if err := os.MkdirAll(elsewhere, 0o755); err != nil {
		t.Fatal(err)
	}
	holder := startOutsideHun(t, elsewhere, port)

	resp := fx.daemon.HandleRequest(Request{Action: "start", Project: "shop", Mode: "exclusive"})
	if resp.OK {
		t.Fatal("expected start to fail on an occupied port")
	}
	if resp.Conflict == nil || resp.Conflict.Port != port || resp.Conflict.PID <= 0 {
		t.Fatalf("conflict = %+v, error = %s", resp.Conflict, resp.Error)
	}
	if syscall.Kill(holder.Process.Pid, 0) != nil {
		t.Fatal("focus mode stopped an unrelated process")
	}

	resp = fx.daemon.HandleRequest(Request{Action: "free_port", Port: port})
	if !resp.OK {
		t.Fatalf("free_port: %s", resp.Error)
	}
	resp = fx.daemon.HandleRequest(Request{Action: "start", Project: "shop", Mode: "exclusive"})
	if !resp.OK {
		t.Fatalf("start after free_port: %s", resp.Error)
	}
}

func TestFreePortRefusesProcessesOutsideFolders(t *testing.T) {
	port := freeTCPPort(t)
	fx, _ := newExternalFixture(t, map[string]string{})
	startOutsideHun(t, "/", port)

	resp := fx.daemon.HandleRequest(Request{Action: "free_port", Port: port})
	if resp.OK {
		t.Fatal("free_port stopped a process running from /")
	}
	if !portListening(port) {
		t.Fatal("process from / was stopped")
	}
}

func TestFocusStopsOtherProjectsStartedOutsideHun(t *testing.T) {
	shopPort := freeTCPPort(t)
	blogPort := freeTCPPort(t)
	fx, dirs := newExternalFixture(t, map[string]string{
		"shop": fmt.Sprintf("name: shop\nservices:\n  web:\n    cmd: sleep 5\n    port: %d\n", shopPort),
		"blog": fmt.Sprintf("name: blog\nservices:\n  web:\n    cmd: sleep 5\n    port: %d\n", blogPort),
	})
	startOutsideHun(t, dirs["shop"], shopPort)

	resp := fx.daemon.HandleRequest(Request{Action: "start", Project: "blog", Mode: "exclusive"})
	if !resp.OK {
		t.Fatalf("focus start: %s", resp.Error)
	}
	if portListening(shopPort) {
		t.Fatal("focus left another project's outside-started service running")
	}
	waitForServiceRunning(t, fx.daemon.manager, "blog", "web")
}

func TestFocusTakesPortBackFromAnotherProject(t *testing.T) {
	port := freeTCPPort(t)
	fx, dirs := newExternalFixture(t, map[string]string{
		"shop": fmt.Sprintf("name: shop\nservices:\n  web:\n    cmd: sleep 5\n    port: %d\n", port),
		"blog": fmt.Sprintf("name: blog\nservices:\n  web:\n    cmd: %q\n    port: %d\n", tcpServerCommand(port), port),
	})
	startOutsideHun(t, dirs["shop"], port)

	m := fx.daemon.manager
	proj, err := config.LoadProject(dirs["blog"])
	if err != nil {
		t.Fatal(err)
	}
	// Exclusive start without the focus sweep: the port check itself must
	// reclaim the port from another registered project.
	if err := m.StartProject("blog", proj, dirs["blog"], true); err != nil {
		var conflict *PortConflictError
		if errors.As(err, &conflict) {
			t.Fatalf("unexpected conflict: %v", err)
		}
		t.Fatalf("start: %v", err)
	}
	waitForServiceRunning(t, m, "blog", "web")
}

func TestShutdownLeavesServicesStartedOutsideHun(t *testing.T) {
	port := freeTCPPort(t)
	fx, dirs := newExternalFixture(t, map[string]string{
		"shop": fmt.Sprintf("name: shop\nservices:\n  web:\n    cmd: sleep 5\n    port: %d\n  worker:\n    cmd: sleep 30\n", port),
	})
	startOutsideHun(t, dirs["shop"], port)
	m := fx.daemon.manager
	proj, err := config.LoadProject(dirs["shop"])
	if err != nil {
		t.Fatal(err)
	}
	if err := m.StartService("shop", "worker", proj, dirs["shop"], false); err != nil {
		t.Fatalf("start worker: %v", err)
	}

	m.Shutdown()

	if m.IsServiceRunning("shop", "worker") {
		t.Fatal("hun-started worker survived shutdown")
	}
	if !portListening(port) {
		t.Fatal("daemon shutdown stopped a service it did not start")
	}
}

func TestFocusOnProjectRunningOnlyOutsideHunKeepsIt(t *testing.T) {
	shopPort := freeTCPPort(t)
	fx, dirs := newExternalFixture(t, map[string]string{
		"shop": fmt.Sprintf("name: shop\nservices:\n  web:\n    cmd: sleep 5\n    port: %d\n", shopPort),
		"blog": "name: blog\nservices:\n  web:\n    cmd: sleep 30\n",
	})
	startOutsideHun(t, dirs["shop"], shopPort)
	resp := fx.daemon.HandleRequest(Request{Action: "start", Project: "blog", Mode: "parallel"})
	if !resp.OK {
		t.Fatalf("start blog: %s", resp.Error)
	}
	waitForServiceRunning(t, fx.daemon.manager, "blog", "web")

	resp = fx.daemon.HandleRequest(Request{Action: "focus", Project: "shop", Mode: "focus"})
	if !resp.OK {
		t.Fatalf("focus: %s", resp.Error)
	}
	if !portListening(shopPort) {
		t.Fatal("focusing shop stopped shop's own service")
	}
	if fx.daemon.manager.IsServiceRunning("blog", "web") {
		t.Fatal("focus kept another project running")
	}
}
