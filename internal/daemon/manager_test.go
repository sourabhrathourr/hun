package daemon

import (
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
