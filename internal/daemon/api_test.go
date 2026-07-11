package daemon

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/sourabhrathourr/hun/internal/config"
	"github.com/sourabhrathourr/hun/internal/state"
)

func TestHandleRequestStopServiceStopsOnlyTargetService(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	proj := &config.Project{
		Name: "api-stop-service",
		Services: map[string]*config.Service{
			"a": {Cmd: "sleep 5"},
			"b": {Cmd: "sleep 5"},
		},
	}
	if err := m.StartProject("api-stop-service", proj, t.TempDir(), false); err != nil {
		t.Fatalf("start project: %v", err)
	}

	waitForServiceRunning(t, m, "api-stop-service", "a")
	waitForServiceRunning(t, m, "api-stop-service", "b")

	d := &Daemon{manager: m}
	resp := d.HandleRequest(Request{
		Action:  "stop_service",
		Project: "api-stop-service",
		Service: "a",
	})
	if !resp.OK {
		t.Fatalf("stop_service response error: %s", resp.Error)
	}

	waitForServiceStopped(t, m, "api-stop-service", "a")

	status := m.Status()
	a := status["api-stop-service"]["a"]
	b := status["api-stop-service"]["b"]
	if a.Running {
		t.Fatalf("expected service a stopped, got %+v", a)
	}
	if !b.Running {
		t.Fatalf("expected service b still running, got %+v", b)
	}
}

func TestHandleRequestStopServiceRequiresProjectAndService(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	d := &Daemon{manager: m}

	resp := d.HandleRequest(Request{Action: "stop_service", Service: "api"})
	if resp.OK || resp.Error == "" {
		t.Fatalf("expected missing project error, got %+v", resp)
	}

	resp = d.HandleRequest(Request{Action: "stop_service", Project: "proj"})
	if resp.OK || resp.Error == "" {
		t.Fatalf("expected missing service error, got %+v", resp)
	}
}

func TestHandleRequestPingReturnsProtocol(t *testing.T) {
	startedAt := time.Date(2026, time.July, 11, 12, 0, 0, 0, time.UTC)
	d := &Daemon{version: "v0.2.1", commit: "abc1234", startedAt: startedAt}
	resp := d.HandleRequest(Request{Action: "ping"})
	if !resp.OK {
		t.Fatalf("ping response error: %s", resp.Error)
	}
	var payload struct {
		Status    string    `json:"status"`
		Protocol  int       `json:"protocol"`
		Version   string    `json:"version"`
		Commit    string    `json:"commit"`
		PID       int       `json:"pid"`
		StartedAt time.Time `json:"started_at"`
	}
	if err := json.Unmarshal(resp.Data, &payload); err != nil {
		t.Fatalf("unmarshal ping payload: %v", err)
	}
	if payload.Status != "pong" {
		t.Fatalf("ping status = %q, want %q", payload.Status, "pong")
	}
	if payload.Protocol != CurrentProtocolVersion {
		t.Fatalf("ping protocol = %d, want %d", payload.Protocol, CurrentProtocolVersion)
	}
	if payload.Version != "v0.2.1" || payload.Commit != "abc1234" {
		t.Fatalf("ping build = %s (%s), want v0.2.1 (abc1234)", payload.Version, payload.Commit)
	}
	if payload.PID != os.Getpid() {
		t.Fatalf("ping pid = %d, want %d", payload.PID, os.Getpid())
	}
	if !payload.StartedAt.Equal(startedAt) {
		t.Fatalf("ping started_at = %s, want %s", payload.StartedAt, startedAt)
	}
}

func TestSnapshotIncludesStoppedRegisteredProjectServices(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	writeDaemonGlobalConfig(t, home, root)
	projectDir := writeDaemonProject(t, root, "snap-stopped", "web")

	st, err := state.Load()
	if err != nil {
		t.Fatalf("load state: %v", err)
	}
	st.Register("snap-stopped", projectDir)
	if err := st.Save(); err != nil {
		t.Fatalf("save state: %v", err)
	}

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	d := &Daemon{manager: m}
	resp := d.HandleRequest(Request{Action: "refresh"})
	if !resp.OK {
		t.Fatalf("snapshot error: %s", resp.Error)
	}
	var snapshot Snapshot
	if err := json.Unmarshal(resp.Data, &snapshot); err != nil {
		t.Fatalf("unmarshal snapshot: %v", err)
	}
	if len(snapshot.Projects) != 1 {
		t.Fatalf("projects len = %d, want 1: %#v", len(snapshot.Projects), snapshot.Projects)
	}
	project := snapshot.Projects[0]
	if project.Status != "stopped" {
		t.Fatalf("project status = %q, want stopped", project.Status)
	}
	if len(project.Services) != 1 || project.Services[0].Name != "web" || project.Services[0].Cmd != "sleep 5" {
		t.Fatalf("services = %#v, want stopped web config service", project.Services)
	}
}

func TestRegisterProjectAddsProjectOutsideScanRoots(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	projectDir := writeDaemonProject(t, root, "manual-add", "web")

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	d := &Daemon{manager: m}
	resp := d.HandleRequest(Request{Action: "register_project", Path: projectDir})
	if !resp.OK {
		t.Fatalf("register_project response error: %s", resp.Error)
	}

	snapshot, err := m.Snapshot(true)
	if err != nil {
		t.Fatalf("snapshot: %v", err)
	}
	if len(snapshot.Projects) != 1 {
		t.Fatalf("projects len = %d, want 1: %#v", len(snapshot.Projects), snapshot.Projects)
	}
	if snapshot.Projects[0].Name != "manual-add" || snapshot.Projects[0].Path != projectDir {
		t.Fatalf("registered project = %#v, want manual-add at %s", snapshot.Projects[0], projectDir)
	}
}

func TestDiscoveryRemovalStopsRunningProject(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	writeDaemonGlobalConfig(t, home, root)
	projectDir := writeDaemonProject(t, root, "remove-running", "web")

	st, err := state.Load()
	if err != nil {
		t.Fatalf("load state: %v", err)
	}
	st.Register("remove-running", projectDir)
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
	if err := m.StartProject("remove-running", proj, projectDir, true); err != nil {
		t.Fatalf("start project: %v", err)
	}
	waitForServiceRunning(t, m, "remove-running", "web")

	if err := os.Remove(filepath.Join(projectDir, ".hun.yml")); err != nil {
		t.Fatalf("remove .hun.yml: %v", err)
	}

	if _, err := m.ReconcileDiscovery(true); err != nil {
		t.Fatalf("reconcile discovery: %v", err)
	}
	if m.IsRunning("remove-running") {
		t.Fatal("expected running project stopped after config removal")
	}
	snap := m.StateSnapshot()
	if _, ok := snap.Registry["remove-running"]; ok {
		t.Fatal("expected project removed from registry")
	}
	if _, ok := snap.Projects["remove-running"]; ok {
		t.Fatal("expected project state removed")
	}
}

func TestHandleStartServiceStartsOnlyRequestedService(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	writeDaemonGlobalConfig(t, home, root)
	projectDir := writeDaemonProjectRaw(t, root, "start-one", `name: start-one
services:
  web:
    cmd: sleep 5
  worker:
    cmd: sleep 5
`)

	st, err := state.Load()
	if err != nil {
		t.Fatalf("load state: %v", err)
	}
	st.Register("start-one", projectDir)
	if err := st.Save(); err != nil {
		t.Fatalf("save state: %v", err)
	}

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	d := &Daemon{manager: m}
	resp := d.HandleRequest(Request{Action: "start_service", Project: "start-one", Service: "web", Mode: "parallel"})
	if !resp.OK {
		t.Fatalf("start_service response error: %s", resp.Error)
	}
	waitForServiceRunning(t, m, "start-one", "web")
	status := m.Status()["start-one"]
	if _, ok := status["worker"]; ok {
		t.Fatalf("expected worker not started, got status %#v", status["worker"])
	}
}

func TestHandleStartAlreadyRunningParallelUpdatesMode(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	writeDaemonGlobalConfig(t, home, root)
	projectDir := writeDaemonProject(t, root, "already-running-mode", "web")

	st, err := state.Load()
	if err != nil {
		t.Fatalf("load state: %v", err)
	}
	st.Register("already-running-mode", projectDir)
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
	if err := m.StartProject("already-running-mode", proj, projectDir, true); err != nil {
		t.Fatalf("start project: %v", err)
	}
	waitForServiceRunning(t, m, "already-running-mode", "web")

	d := &Daemon{manager: m}
	resp := d.HandleRequest(Request{Action: "start", Project: "already-running-mode", Mode: "parallel"})
	if !resp.OK {
		t.Fatalf("start response error: %s", resp.Error)
	}

	snap := m.StateSnapshot()
	if snap.Mode != "multitask" {
		t.Fatalf("mode = %q, want multitask", snap.Mode)
	}
	if snap.ActiveProject != "already-running-mode" {
		t.Fatalf("active project = %q, want already-running-mode", snap.ActiveProject)
	}
}

func TestHandleRestartPreservesMultitaskModeWithZeroOffset(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	writeDaemonGlobalConfig(t, home, root)
	projectDir := writeDaemonProject(t, root, "restart-multitask", "web")

	st, err := state.Load()
	if err != nil {
		t.Fatalf("load state: %v", err)
	}
	st.Register("restart-multitask", projectDir)
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
	if err := m.StartProject("restart-multitask", proj, projectDir, false); err != nil {
		t.Fatalf("start project: %v", err)
	}
	waitForServiceRunning(t, m, "restart-multitask", "web")
	if offset := m.ports.GetOffset("restart-multitask"); offset != 0 {
		t.Fatalf("offset = %d, want 0 for first multitask project", offset)
	}

	d := &Daemon{manager: m}
	resp := d.HandleRequest(Request{Action: "restart", Project: "restart-multitask"})
	if !resp.OK {
		t.Fatalf("restart response error: %s", resp.Error)
	}
	waitForServiceRunning(t, m, "restart-multitask", "web")

	snap := m.StateSnapshot()
	if snap.Mode != "multitask" {
		t.Fatalf("mode = %q, want multitask", snap.Mode)
	}
}

func TestHandleRemoveServiceStopsAndDeletesFromConfig(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	writeDaemonGlobalConfig(t, home, root)
	projectDir := writeDaemonProjectRaw(t, root, "remove-service", `name: remove-service
services:
  web:
    cmd: sleep 30
  worker:
    cmd: sleep 30
    depends_on:
      - web
`)

	st, err := state.Load()
	if err != nil {
		t.Fatalf("load state: %v", err)
	}
	st.Register("remove-service", projectDir)
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
	if err := m.StartService("remove-service", "web", proj, projectDir, false); err != nil {
		t.Fatalf("start service: %v", err)
	}
	waitForServiceRunning(t, m, "remove-service", "web")

	d := &Daemon{manager: m}
	resp := d.HandleRequest(Request{Action: "remove_service", Project: "remove-service", Service: "web"})
	if !resp.OK {
		t.Fatalf("remove_service response error: %s", resp.Error)
	}

	updated, err := config.LoadProject(projectDir)
	if err != nil {
		t.Fatalf("load updated project: %v", err)
	}
	if _, ok := updated.Services["web"]; ok {
		t.Fatal("expected web removed from config")
	}
	if deps := updated.Services["worker"].DependsOn; len(deps) != 0 {
		t.Fatalf("expected removed service pruned from dependencies, got %#v", deps)
	}
	if m.IsServiceRunning("remove-service", "web") {
		t.Fatal("expected removed service stopped")
	}
}

func waitForServiceRunning(t *testing.T, m *Manager, project, service string) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		status := m.Status()
		if status[project][service].Running {
			return
		}
		time.Sleep(25 * time.Millisecond)
	}
	t.Fatalf("service %s/%s did not reach running state", project, service)
}

func writeDaemonGlobalConfig(t *testing.T, home, root string) {
	t.Helper()
	hunDir := filepath.Join(home, ".hun")
	if err := os.MkdirAll(hunDir, 0o755); err != nil {
		t.Fatalf("mkdir hun dir: %v", err)
	}
	raw := "scan_dirs:\n  - " + root + "\n"
	if err := os.WriteFile(filepath.Join(hunDir, "config.yml"), []byte(raw), 0o644); err != nil {
		t.Fatalf("write global config: %v", err)
	}
}

func writeDaemonProject(t *testing.T, root, name, service string) string {
	t.Helper()
	return writeDaemonProjectRaw(t, root, name, "name: "+name+"\nservices:\n  "+service+":\n    cmd: sleep 5\n")
}

func writeDaemonProjectRaw(t *testing.T, root, name, raw string) string {
	t.Helper()
	dir := filepath.Join(root, name)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatalf("mkdir project: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, ".hun.yml"), []byte(raw), 0o644); err != nil {
		t.Fatalf("write project config: %v", err)
	}
	return dir
}

func waitForServiceStopped(t *testing.T, m *Manager, project, service string) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		status := m.Status()
		if !status[project][service].Running {
			return
		}
		time.Sleep(25 * time.Millisecond)
	}
	t.Fatalf("service %s/%s did not stop", project, service)
}
