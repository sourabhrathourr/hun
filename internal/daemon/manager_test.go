package daemon

import (
	"os/exec"
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

func TestRuntimePortDetectionUpdatesStatusAndOverrides(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

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
				Cmd:     `printf 'Local: http://localhost:5173/\nLocal: http://localhost:5173/\n'; sleep 2`,
				Port:    3000,
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
		if svc, ok := status["runtime-port"]["web"]; ok && svc.Port == 5173 {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}

	status := m.Status()
	if got := status["runtime-port"]["web"].Port; got != 5173 {
		t.Fatalf("runtime detected port = %d, want 5173", got)
	}

	snap := m.StateSnapshot()
	ps := snap.Projects["runtime-port"]
	if ps.PortOverrides["web"] != 5173 {
		t.Fatalf("port override = %d, want 5173", ps.PortOverrides["web"])
	}

	if err := m.StopProject("runtime-port"); err != nil {
		t.Fatalf("stop project: %v", err)
	}
}

func TestRuntimePortOverrideStoresBasePortWithOffset(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	basePath := t.TempDir()
	if err := m.StartProject("offset-base", &config.Project{
		Name: "offset-base",
		Services: map[string]*config.Service{
			"svc": {Cmd: "sleep 3", Port: 3000, PortEnv: "PORT"},
		},
	}, basePath, false); err != nil {
		t.Fatalf("start base project: %v", err)
	}

	targetPath := t.TempDir()
	if err := m.StartProject("offset-target", &config.Project{
		Name: "offset-target",
		Services: map[string]*config.Service{
			"web": {
				Cmd:     `printf 'Local: http://localhost:5174/\nLocal: http://localhost:5174/\n'; sleep 2`,
				Port:    3000,
				PortEnv: "PORT",
			},
		},
	}, targetPath, false); err != nil {
		t.Fatalf("start target project: %v", err)
	}

	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		snap := m.StateSnapshot()
		if snap.Projects["offset-target"].PortOverrides["web"] == 5173 {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}

	snap := m.StateSnapshot()
	if got := snap.Projects["offset-target"].PortOverrides["web"]; got != 5173 {
		t.Fatalf("base port override = %d, want 5173 (detected 5174 with +1 offset)", got)
	}

	_ = m.StopProject("offset-target")
	_ = m.StopProject("offset-base")
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
