package daemon

import (
	"context"
	"errors"
	"testing"

	"github.com/sourabhrathourr/hun/internal/config"
	"github.com/sourabhrathourr/hun/internal/state"
)

func TestDockerWatchStopsDockerServicesWhenDockerStopsAnswering(t *testing.T) {
	restore := replaceDockerHooks(t)
	defer restore()
	dockerUp := true
	checks := 0
	checkDockerDaemon = func(context.Context) error {
		checks++
		if dockerUp {
			return nil
		}
		return errors.New("daemon down")
	}

	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	writeDaemonGlobalConfig(t, home, root)
	// `db` stands in for `docker compose up db`: it needs Docker but only sleeps.
	projectDir := writeDaemonProjectRaw(t, root, "shop", `name: shop
services:
  db:
    cmd: sleep 30 || docker compose up db
  web:
    cmd: sleep 30
`)
	st, err := state.Load()
	if err != nil {
		t.Fatalf("load state: %v", err)
	}
	st.Register("shop", projectDir)
	if err := st.Save(); err != nil {
		t.Fatalf("save state: %v", err)
	}
	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()
	proj, err := config.LoadProject(projectDir)
	if err != nil {
		t.Fatalf("load project: %v", err)
	}

	// Nothing that needs Docker runs yet, so Docker is not asked.
	if misses := m.checkDockerServices(0); misses != 0 || checks != 0 {
		t.Fatalf("misses = %d, checks = %d before any Docker service runs", misses, checks)
	}

	for _, service := range []string{"db", "web"} {
		if err := m.StartService("shop", service, proj, projectDir, false); err != nil {
			t.Fatalf("start %s: %v", service, err)
		}
		waitForServiceRunning(t, m, "shop", service)
	}

	if misses := m.checkDockerServices(0); misses != 0 {
		t.Fatalf("misses = %d while Docker answers", misses)
	}

	dockerUp = false
	misses := m.checkDockerServices(0)
	if misses != 1 || !m.IsServiceRunning("shop", "db") {
		t.Fatalf("one missed check should only count: misses = %d, db running = %v", misses, m.IsServiceRunning("shop", "db"))
	}
	m.checkDockerServices(misses)

	if m.IsServiceRunning("shop", "db") {
		t.Fatal("db should stop once Docker misses two checks")
	}
	if status := m.Status()["shop"]["db"].Status; status != "crashed" {
		t.Fatalf("db status = %q, want crashed", status)
	}
	if !m.IsServiceRunning("shop", "web") {
		t.Fatal("a service that does not use Docker must keep running")
	}
}
