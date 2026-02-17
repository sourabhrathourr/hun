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
