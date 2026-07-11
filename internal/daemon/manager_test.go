package daemon

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/sourabhrathourr/hun/internal/config"
)

func TestStartProjectRollsBackOnServiceStartFailure(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	projectPath := t.TempDir()
	proj := &config.Project{
		Name: "broken",
		Services: map[string]*config.Service{
			"svc1": {
				Cmd: "sleep 5",
			},
			"svc2": {
				Cmd:       "echo should-not-start",
				Cwd:       "./missing-subdir",
				DependsOn: []string{"svc1"},
			},
		},
	}

	err = m.StartProject("broken", proj, projectPath, false)
	if err == nil {
		t.Fatal("expected start error, got nil")
	}

	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if !m.IsRunning("broken") {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	if m.IsRunning("broken") {
		t.Fatal("project should not remain running after rollback")
	}

	if status := m.Status(); len(status) != 0 {
		t.Fatalf("expected no running projects after rollback, got %v", status)
	}

	snap := m.StateSnapshot()
	if ps, ok := snap.Projects["broken"]; ok && ps.Status == "running" {
		t.Fatalf("state marked project as running after rollback: %+v", ps)
	}
}

func TestStatusShowsProjectDuringStartup(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	projectPath := t.TempDir()
	proj := &config.Project{
		Name: "booting",
		Services: map[string]*config.Service{
			"svc1": {Cmd: "sleep 3"},
		},
	}

	done := make(chan error, 1)
	go func() {
		done <- m.StartProject("booting", proj, projectPath, false)
	}()

	time.Sleep(150 * time.Millisecond)

	status := m.Status()
	projectStatus, ok := status["booting"]
	if !ok {
		t.Fatalf("expected booting project in status during startup, got %v", status)
	}
	if _, ok := projectStatus["svc1"]; !ok {
		t.Fatalf("expected svc1 to appear during startup, got %v", projectStatus)
	}

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("start project returned error: %v", err)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("timeout waiting for StartProject completion")
	}

	if err := m.StopProject("booting"); err != nil {
		t.Fatalf("stop project: %v", err)
	}
}

func TestRuntimePortDetectionUpdatesLiveStatusWithoutPersistingOverride(t *testing.T) {
	requireRuntimePortInspection(t)
	home := t.TempDir()
	t.Setenv("HOME", home)
	runtimePort := freeTCPPort(t)

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	projectPath := t.TempDir()
	proj := &config.Project{
		Name: "runtime-port",
		Services: map[string]*config.Service{
			"web": {
				Cmd:     fmt.Sprintf(`python3 -u -c 'import socket,time; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind(("127.0.0.1",%d)); s.listen(); print("Local: http://127.0.0.1:%d/",flush=True); time.sleep(30)'`, runtimePort, runtimePort),
				Port:    0,
				PortEnv: "PORT",
			},
		},
	}

	if err := m.StartProject("runtime-port", proj, projectPath, true); err != nil {
		t.Fatalf("start project: %v", err)
	}

	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		status := m.Status()
		if svc, ok := status["runtime-port"]["web"]; ok && svc.Port == runtimePort {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}

	status := m.Status()
	if got := status["runtime-port"]["web"].Port; got != runtimePort {
		t.Fatalf("runtime detected port = %d, want %d", got, runtimePort)
	}

	stateJSON, err := json.Marshal(m.StateSnapshot())
	if err != nil {
		t.Fatalf("marshal state: %v", err)
	}
	if strings.Contains(string(stateJSON), "port_overrides") {
		t.Fatalf("runtime port must not be persisted as a launch override: %s", stateJSON)
	}

	if err := m.StopProject("runtime-port"); err != nil {
		t.Fatalf("stop project: %v", err)
	}
}

func TestSilentRuntimeListenerUpdatesLivePort(t *testing.T) {
	requireRuntimePortInspection(t)
	home := t.TempDir()
	t.Setenv("HOME", home)
	runtimePort := freeTCPPort(t)

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	proj := &config.Project{
		Name: "silent-runtime-port",
		Services: map[string]*config.Service{
			"web": {
				Cmd:  fmt.Sprintf(`python3 -u -c 'import socket,time; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind(("127.0.0.1",%d)); s.listen(); time.sleep(30)'`, runtimePort),
				Port: 0,
			},
		},
	}
	if err := m.StartProject(proj.Name, proj, t.TempDir(), true); err != nil {
		t.Fatalf("start project: %v", err)
	}
	waitForServicePort(t, m, proj.Name, "web", runtimePort)
}

func TestConfiguredPortWinsOverPreviouslyDetectedRuntimePort(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	hunDir := filepath.Join(home, ".hun")
	if err := os.MkdirAll(hunDir, 0o755); err != nil {
		t.Fatalf("create hun dir: %v", err)
	}
	legacyState := `{"schema_version":2,"mode":"focus","projects":{"configured-port-priority":{"port_overrides":{"web":5173}}},"registry":{}}`
	if err := os.WriteFile(filepath.Join(hunDir, "state.json"), []byte(legacyState), 0o644); err != nil {
		t.Fatalf("write legacy state: %v", err)
	}

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	projectPath := t.TempDir()
	proj := &config.Project{
		Name: "configured-port-priority",
		Services: map[string]*config.Service{
			"web": {
				Cmd:     "sleep 2",
				Port:    3000,
				PortEnv: "PORT",
			},
		},
	}

	if err := m.StartProject(proj.Name, proj, projectPath, true); err != nil {
		t.Fatalf("start: %v", err)
	}

	if got := m.Status()[proj.Name]["web"].Port; got != 3000 {
		t.Fatalf("port with legacy runtime override = %d, want configured port 3000", got)
	}
}

func TestConfiguredPortMustBeAvailableBeforeLaunch(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("occupy port: %v", err)
	}
	defer listener.Close()
	port := listener.Addr().(*net.TCPAddr).Port

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	proj := &config.Project{
		Name: "occupied-configured-port",
		Services: map[string]*config.Service{
			"web": {Cmd: "sleep 2", Port: port, PortEnv: "PORT"},
		},
	}
	err = m.StartProject(proj.Name, proj, t.TempDir(), true)
	if err == nil || !strings.Contains(err.Error(), fmt.Sprintf("port %d", port)) {
		t.Fatalf("start error = %v, want occupied configured port error", err)
	}
}

func TestPortLeasePreventsConcurrentDelayedBindStarts(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	port := freeTCPPort(t)

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	project := func(name string) *config.Project {
		return &config.Project{
			Name: name,
			Services: map[string]*config.Service{
				"web": {Cmd: "sleep 30", Port: port, PortEnv: "PORT"},
			},
		}
	}
	if err := m.StartProject("lease-first", project("lease-first"), t.TempDir(), true); err != nil {
		t.Fatalf("start first project: %v", err)
	}
	err = m.StartProject("lease-second", project("lease-second"), t.TempDir(), true)
	if err == nil || !strings.Contains(err.Error(), fmt.Sprintf("port %d", port)) {
		t.Fatalf("second start error = %v, want port lease conflict", err)
	}
}

func TestMultitaskOffsetDoesNotCreatePortForPortlessService(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	for _, name := range []string{"first-portless", "second-portless"} {
		proj := &config.Project{
			Name: name,
			Services: map[string]*config.Service{
				"worker": {Cmd: "sleep 3"},
			},
		}
		if err := m.StartProject(name, proj, t.TempDir(), false); err != nil {
			t.Fatalf("start %s: %v", name, err)
		}
	}

	if got := m.Status()["second-portless"]["worker"].Port; got != 0 {
		t.Fatalf("portless service received multitask offset as port %d", got)
	}
}

func TestServiceRestartReinjectsConfiguredPortAfterRuntimeMismatch(t *testing.T) {
	requireRuntimePortInspection(t)
	home := t.TempDir()
	t.Setenv("HOME", home)

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	projectPath := t.TempDir()
	configuredPort := freeTCPPort(t)
	firstPort := freeTCPPort(t)
	for firstPort == configuredPort {
		firstPort = freeTCPPort(t)
	}
	cmd := fmt.Sprintf(`python3 -u -c 'import os,socket,time; first=not os.path.exists(".started"); open(".started","a").close(); port=%d if first else int(os.environ["PORT"]); s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind(("127.0.0.1",port)); s.listen(); print(f"Uvicorn running on http://127.0.0.1:{port}",flush=True); time.sleep(30)'`, firstPort)
	proj := &config.Project{
		Name: "service-restart-port-priority",
		Services: map[string]*config.Service{
			"web": {Cmd: cmd, Port: configuredPort, PortEnv: "PORT"},
		},
	}
	if err := m.StartProject(proj.Name, proj, projectPath, true); err != nil {
		t.Fatalf("start project: %v", err)
	}
	waitForServicePort(t, m, proj.Name, "web", firstPort)
	waitForServiceStatus(t, m, proj.Name, "web", "crashed")

	if err := m.RestartService(proj.Name, "web"); err != nil {
		t.Fatalf("restart service: %v", err)
	}
	waitForServicePort(t, m, proj.Name, "web", configuredPort)
}

func TestSingleUvicornListeningLineRejectsConfiguredPortMismatch(t *testing.T) {
	requireRuntimePortInspection(t)
	home := t.TempDir()
	t.Setenv("HOME", home)
	configuredPort := freeTCPPort(t)
	runtimePort := freeTCPPort(t)
	for runtimePort == configuredPort {
		runtimePort = freeTCPPort(t)
	}

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	proj := &config.Project{
		Name: "single-listening-line",
		Services: map[string]*config.Service{
			"webcam": {
				Cmd:  fmt.Sprintf(`python3 -u -c 'import socket,time; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind(("127.0.0.1",%d)); s.listen(); print("INFO: Uvicorn running on http://127.0.0.1:%d (Press CTRL+C to quit)",flush=True); time.sleep(30)'`, runtimePort, runtimePort),
				Port: configuredPort,
			},
		},
	}

	if err := m.StartProject(proj.Name, proj, t.TempDir(), true); err != nil {
		t.Fatalf("start project: %v", err)
	}
	waitForServiceStatus(t, m, proj.Name, "webcam", "crashed")
	if got := m.Status()[proj.Name]["webcam"].Port; got != runtimePort {
		t.Fatalf("diagnostic live port = %d, want observed port %d", got, runtimePort)
	}
	logs := m.GetLogs(proj.Name, "webcam", 20)
	foundMismatch := false
	for _, line := range logs {
		if strings.Contains(line.Text, fmt.Sprintf("configured port %d but service bound %d", configuredPort, runtimePort)) {
			foundMismatch = true
			break
		}
	}
	if !foundMismatch {
		t.Fatalf("expected explicit port mismatch log, got %#v", logs)
	}
}

func TestAdditionalOwnedListenerDoesNotOverrideConfiguredPort(t *testing.T) {
	requireRuntimePortInspection(t)
	home := t.TempDir()
	t.Setenv("HOME", home)
	configuredPort := freeTCPPort(t)
	additionalPort := freeTCPPort(t)
	for additionalPort == configuredPort {
		additionalPort = freeTCPPort(t)
	}

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	cmd := fmt.Sprintf(`python3 -u -c 'import socket,time; a=socket.socket(); a.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); a.bind(("127.0.0.1",%d)); a.listen(); b=socket.socket(); b.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); b.bind(("127.0.0.1",%d)); b.listen(); print("Local: http://127.0.0.1:%d/",flush=True); time.sleep(30)'`, configuredPort, additionalPort, additionalPort)
	proj := &config.Project{
		Name: "additional-owned-listener",
		Services: map[string]*config.Service{
			"web": {Cmd: cmd, Port: configuredPort, PortEnv: "PORT"},
		},
	}
	if err := m.StartProject(proj.Name, proj, t.TempDir(), true); err != nil {
		t.Fatalf("start project: %v", err)
	}
	time.Sleep(500 * time.Millisecond)
	status := m.Status()[proj.Name]["web"]
	if !status.Running || status.Port != configuredPort {
		t.Fatalf("service status = %+v, want running on configured port %d", status, configuredPort)
	}
}

func TestMultipleWrongListenersRejectConfiguredPortMismatch(t *testing.T) {
	requireRuntimePortInspection(t)
	home := t.TempDir()
	t.Setenv("HOME", home)
	configuredPort := freeTCPPort(t)
	firstRuntimePort := freeTCPPort(t)
	secondRuntimePort := freeTCPPort(t)
	for firstRuntimePort == configuredPort {
		firstRuntimePort = freeTCPPort(t)
	}
	for secondRuntimePort == configuredPort || secondRuntimePort == firstRuntimePort {
		secondRuntimePort = freeTCPPort(t)
	}

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	cmd := fmt.Sprintf(`python3 -u -c 'import socket,time; a=socket.socket(); a.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); a.bind(("127.0.0.1",%d)); a.listen(); b=socket.socket(); b.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); b.bind(("127.0.0.1",%d)); b.listen(); time.sleep(30)'`, firstRuntimePort, secondRuntimePort)
	proj := &config.Project{
		Name: "multiple-wrong-listeners",
		Services: map[string]*config.Service{
			"web": {Cmd: cmd, Port: configuredPort, PortEnv: "PORT"},
		},
	}
	if err := m.StartProject(proj.Name, proj, t.TempDir(), true); err != nil {
		t.Fatalf("start project: %v", err)
	}
	waitForServiceStatus(t, m, proj.Name, "web", "crashed")
}

func requireRuntimePortInspection(t *testing.T) {
	t.Helper()
	if _, err := exec.LookPath("python3"); err != nil {
		t.Skip("python3 is required for runtime listener tests")
	}
	if _, err := lsofPath(); err != nil {
		t.Skip("lsof is required for runtime listener tests")
	}
}

func freeTCPPort(t *testing.T) int {
	t.Helper()
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("allocate test port: %v", err)
	}
	port := listener.Addr().(*net.TCPAddr).Port
	if err := listener.Close(); err != nil {
		t.Fatalf("release test port: %v", err)
	}
	return port
}

func waitForServicePort(t *testing.T, m *Manager, project, service string, want int) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if got := m.Status()[project][service].Port; got == want {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatalf("service port = %d, want %d", m.Status()[project][service].Port, want)
}

func waitForServiceStatus(t *testing.T, m *Manager, project, service, want string) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if got := m.Status()[project][service].Status; got == want {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatalf("service status = %q, want %q", m.Status()[project][service].Status, want)
}

func TestStartProjectSkipsLeafServiceStartupDelay(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	projectPath := t.TempDir()
	proj := &config.Project{
		Name: "fast-start",
		Services: map[string]*config.Service{
			"svc-a": {Cmd: "sleep 3"},
			"svc-b": {Cmd: "sleep 3"},
			"svc-c": {Cmd: "sleep 3"},
		},
	}

	started := time.Now()
	if err := m.StartProject("fast-start", proj, projectPath, false); err != nil {
		t.Fatalf("start project: %v", err)
	}
	elapsed := time.Since(started)
	if elapsed > 1500*time.Millisecond {
		t.Fatalf("start took %v, expected no per-service 1s delay", elapsed)
	}

	if err := m.StopProject("fast-start"); err != nil {
		t.Fatalf("stop project: %v", err)
	}
}

func TestStopProjectStopsServicesConcurrently(t *testing.T) {
	if _, err := exec.LookPath("python3"); err != nil {
		t.Skip("python3 not available; skipping concurrent stop timing test")
	}

	home := t.TempDir()
	t.Setenv("HOME", home)

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	projectPath := t.TempDir()
	ignoreTerm := `python3 -c "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN);` +
		`exec('while True:\\n  time.sleep(1)')"`
	proj := &config.Project{
		Name: "slow-stop",
		Services: map[string]*config.Service{
			"a": {Cmd: ignoreTerm},
			"b": {Cmd: ignoreTerm},
		},
	}

	if err := m.StartProject("slow-stop", proj, projectPath, false); err != nil {
		t.Fatalf("start project: %v", err)
	}
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		status := m.Status()
		a, aok := status["slow-stop"]["a"]
		b, bok := status["slow-stop"]["b"]
		if aok && bok && a.Running && b.Running && a.PID > 0 && b.PID > 0 && pidAlive(a.PID) && pidAlive(b.PID) {
			break
		}
		time.Sleep(25 * time.Millisecond)
	}
	status := m.Status()
	a, aok := status["slow-stop"]["a"]
	b, bok := status["slow-stop"]["b"]
	if !aok || !bok || !a.Running || !b.Running || a.PID <= 0 || b.PID <= 0 {
		t.Fatalf("services must be running before stop timing check, got status: %+v", status["slow-stop"])
	}
	time.Sleep(250 * time.Millisecond)
	if !pidAlive(a.PID) || !pidAlive(b.PID) {
		t.Fatalf("services exited before stop timing check, got pids a=%d b=%d", a.PID, b.PID)
	}

	stopped := time.Now()
	if err := m.StopProject("slow-stop"); err != nil {
		t.Fatalf("stop project: %v", err)
	}
	elapsed := time.Since(stopped)
	if elapsed > 8*time.Second {
		t.Fatalf("stop took %v, expected concurrent shutdown across services", elapsed)
	}
}

func TestStopServiceStopsOnlySelectedService(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	projectPath := t.TempDir()
	proj := &config.Project{
		Name: "service-stop",
		Services: map[string]*config.Service{
			"a": {Cmd: "sleep 5"},
			"b": {Cmd: "sleep 5"},
		},
	}

	if err := m.StartProject("service-stop", proj, projectPath, false); err != nil {
		t.Fatalf("start project: %v", err)
	}

	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		status := m.Status()
		a, aok := status["service-stop"]["a"]
		b, bok := status["service-stop"]["b"]
		if aok && bok && a.Running && b.Running && a.PID > 0 && b.PID > 0 {
			break
		}
		time.Sleep(25 * time.Millisecond)
	}

	if err := m.StopService("service-stop", "a"); err != nil {
		t.Fatalf("stop service: %v", err)
	}

	status := m.Status()
	a, aok := status["service-stop"]["a"]
	b, bok := status["service-stop"]["b"]
	if !aok || !bok {
		t.Fatalf("expected both services in status, got: %+v", status["service-stop"])
	}
	if a.Running {
		t.Fatalf("expected service a stopped, got %+v", a)
	}
	if a.Status != "stopped" {
		t.Fatalf("expected service a status=stopped, got %q", a.Status)
	}
	if a.PID != 0 {
		t.Fatalf("expected service a pid=0 after stop, got %d", a.PID)
	}
	if !b.Running {
		t.Fatalf("expected service b still running, got %+v", b)
	}
}

func pidAlive(pid int) bool {
	if pid <= 0 {
		return false
	}
	return syscall.Kill(pid, 0) == nil
}

func TestRestartServiceResetsServiceLogsAndStartedAt(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	projectPath := t.TempDir()
	proj := &config.Project{
		Name: "fresh-restart",
		Services: map[string]*config.Service{
			"svc": {
				Cmd: "echo started && sleep 5",
			},
		},
	}

	if err := m.StartProject("fresh-restart", proj, projectPath, true); err != nil {
		t.Fatalf("start project: %v", err)
	}

	waitForLogLine(t, m, "fresh-restart", "svc", "started", 3*time.Second)

	before := m.Status()["fresh-restart"]["svc"].StartedAt
	if before.IsZero() {
		t.Fatal("expected non-zero started_at before restart")
	}

	if err := m.RestartService("fresh-restart", "svc"); err != nil {
		t.Fatalf("restart service: %v", err)
	}

	deadline := time.Now().Add(4 * time.Second)
	updated := before
	for time.Now().Before(deadline) {
		updated = m.Status()["fresh-restart"]["svc"].StartedAt
		if updated.After(before) {
			break
		}
		time.Sleep(40 * time.Millisecond)
	}
	if !updated.After(before) {
		t.Fatalf("expected started_at to advance after restart, before=%s after=%s", before, updated)
	}

	waitForLogLine(t, m, "fresh-restart", "svc", "started", 3*time.Second)
	lines := m.GetLogs("fresh-restart", "svc", 200)
	count := 0
	for _, line := range lines {
		if strings.Contains(line.Text, "started") {
			count++
		}
	}
	if count != 1 {
		t.Fatalf("expected exactly 1 'started' line after reset, got %d (%v)", count, lines)
	}
}

func TestOnFailureRestartKeepsOnlyFreshServiceLogs(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	projectPath := t.TempDir()
	proj := &config.Project{
		Name: "fresh-crash",
		Services: map[string]*config.Service{
			"svc": {
				Cmd:     "echo crash-line && exit 1",
				Restart: "on_failure",
			},
		},
	}

	if err := m.StartProject("fresh-crash", proj, projectPath, true); err != nil {
		t.Fatalf("start project: %v", err)
	}

	waitForLogLine(t, m, "fresh-crash", "svc", "crash-line", 3*time.Second)
	time.Sleep(1600 * time.Millisecond)

	lines := m.GetLogs("fresh-crash", "svc", 200)
	count := 0
	for _, line := range lines {
		if strings.Contains(line.Text, "crash-line") {
			count++
		}
	}
	if count > 1 {
		t.Fatalf("expected at most one crash-line after reset-per-restart, got %d (%v)", count, lines)
	}
}

func waitForLogLine(t *testing.T, m *Manager, project, service, contains string, timeout time.Duration) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		lines := m.GetLogs(project, service, 200)
		for _, line := range lines {
			if strings.Contains(line.Text, contains) {
				return
			}
		}
		time.Sleep(30 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for log containing %q for %s:%s", contains, project, service)
}
