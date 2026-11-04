package daemon

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/sourabhrathourr/hun/internal/config"
)

// A start stuck waiting for a Docker that never answers ends promptly when
// force-stopped, launches nothing, and leaves the project free to run again.
func TestForceStopEndsAStartStuckOnDocker(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	oldCheck, oldLaunch, oldSleep, oldTimeout := checkDockerDaemon, launchDockerApp, sleepBeforeRecheck, dockerReadyTimeout
	defer func() {
		checkDockerDaemon, launchDockerApp, sleepBeforeRecheck, dockerReadyTimeout = oldCheck, oldLaunch, oldSleep, oldTimeout
	}()
	checkDockerDaemon = func(context.Context) error { return errors.New("docker is wedged") }
	launchDockerApp = func() error { return nil }
	sleepBeforeRecheck = func(time.Duration) { time.Sleep(20 * time.Millisecond) }
	dockerReadyTimeout = time.Minute

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	proj := &config.Project{
		Name:     "wedged",
		Services: map[string]*config.Service{"db": {Cmd: "docker compose up db"}},
	}
	done := make(chan error, 1)
	go func() { done <- m.StartProject("wedged", proj, t.TempDir(), false) }()

	time.Sleep(200 * time.Millisecond)
	select {
	case err := <-done:
		t.Fatalf("start returned before force stop: %v", err)
	default:
	}

	m.ForceStop("wedged", "")
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("start succeeded after force stop")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("start was still waiting 2s after force stop")
	}
	if procs := m.Status()["wedged"]; len(procs) > 0 {
		t.Fatalf("a process was left registered: %v", procs)
	}

	// It can run again (with Docker answering this time).
	checkDockerDaemon = func(context.Context) error { return nil }
	proj.Services["db"].Cmd = "sleep 2 # docker"
	if err := m.StartProject("wedged", proj, t.TempDir(), false); err != nil {
		t.Fatalf("run after force stop: %v", err)
	}
	if !m.Status()["wedged"]["db"].Running {
		t.Fatal("service not running after starting again")
	}
}

// Force stop kills a running service without its grace period, and a service
// that ignores SIGTERM is gone at once, not restarted.
func TestForceStopKillsAndDoesNotRestart(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	proj := &config.Project{
		Name: "stubborn",
		Services: map[string]*config.Service{
			"api": {Cmd: "trap '' TERM; sleep 60", Restart: "on_failure"},
		},
	}
	if err := m.StartProject("stubborn", proj, t.TempDir(), false); err != nil {
		t.Fatalf("start: %v", err)
	}
	started := time.Now()
	m.ForceStop("stubborn", "")
	m.FinishForceStop("stubborn", "")
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if len(m.Status()["stubborn"]) == 0 {
			break
		}
		time.Sleep(50 * time.Millisecond)
		m.FinishForceStop("stubborn", "")
	}
	if procs := m.Status()["stubborn"]; len(procs) > 0 {
		t.Fatalf("still registered %s after force stop: %v", time.Since(started), procs)
	}
	time.Sleep(1500 * time.Millisecond)
	if procs := m.Status()["stubborn"]; len(procs) > 0 {
		t.Fatalf("restarted after force stop: %v", procs)
	}
}

// A force stop while an action is still in its pre-start hook (before any
// service has begun) cancels it: when the hook ends, nothing launches.
func TestForceStopDuringPreStartHookLaunchesNothing(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	proj := &config.Project{
		Name:     "slowhook",
		Hooks:    config.Hooks{PreStart: "sleep 1"},
		Services: map[string]*config.Service{"web": {Cmd: "sleep 60"}},
	}
	// As the daemon does on receiving the request.
	m.beginAction("slowhook", m.cancelGeneration("slowhook"))
	defer m.endAction("slowhook")
	done := make(chan error, 1)
	go func() { done <- m.StartProject("slowhook", proj, t.TempDir(), false) }()

	time.Sleep(300 * time.Millisecond) // inside the hook
	m.ForceStop("slowhook", "")
	if err := <-done; err == nil {
		t.Fatal("start succeeded after force stop")
	}
	if procs := m.Status()["slowhook"]; len(procs) > 0 {
		t.Fatalf("launched after force stop: %v", procs)
	}
}
