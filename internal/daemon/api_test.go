package daemon

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
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

func TestHandleFocusKeepsPreferredRunningProjectAndNormalizesOffset(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	writeDaemonGlobalConfig(t, home, root)
	firstPort := freeTCPPort(t)
	secondPort := freeTCPPort(t)
	for secondPort == firstPort || secondPort+1 == firstPort {
		secondPort = freeTCPPort(t)
	}
	firstDir := writeDaemonProjectRaw(t, root, "focus-first", fmt.Sprintf("name: focus-first\nservices:\n  web:\n    cmd: sleep 5\n    port: %d\n", firstPort))
	secondDir := writeDaemonProjectRaw(t, root, "focus-second", fmt.Sprintf("name: focus-second\nservices:\n  web:\n    cmd: sleep 5\n    port: %d\n", secondPort))

	st, err := state.Load()
	if err != nil {
		t.Fatalf("load state: %v", err)
	}
	st.Register("focus-first", firstDir)
	st.Register("focus-second", secondDir)
	if err := st.Save(); err != nil {
		t.Fatalf("save state: %v", err)
	}

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	projects := []struct {
		name string
		path string
	}{
		{name: "focus-first", path: firstDir},
		{name: "focus-second", path: secondDir},
	}
	for _, item := range projects {
		name, path := item.name, item.path
		proj, loadErr := config.LoadProject(path)
		if loadErr != nil {
			t.Fatalf("load project %s: %v", name, loadErr)
		}
		if startErr := m.StartProject(name, proj, path, false); startErr != nil {
			t.Fatalf("start project %s: %v", name, startErr)
		}
		waitForServiceRunning(t, m, name, "web")
	}

	oldPID := m.Status()["focus-second"]["web"].PID
	if port := m.Status()["focus-second"]["web"].Port; port != secondPort+1 {
		t.Fatalf("preferred project port = %d, want multitask port %d", port, secondPort+1)
	}
	if offset := m.ports.GetOffset("focus-second"); offset == 0 {
		t.Fatal("expected preferred project to start with a multitask offset")
	}

	d := &Daemon{manager: m}
	resp := d.HandleRequest(Request{Action: "focus", Project: "focus-second", Mode: "focus"})
	if !resp.OK {
		t.Fatalf("focus response error: %s", resp.Error)
	}

	if m.IsRunning("focus-first") {
		t.Fatal("expected non-preferred project to stop")
	}
	if !m.IsRunning("focus-second") {
		t.Fatal("expected preferred project to remain running")
	}
	if offset := m.ports.GetOffset("focus-second"); offset != 0 {
		t.Fatalf("preferred project offset = %d, want 0", offset)
	}
	newPID := m.Status()["focus-second"]["web"].PID
	if newPID == oldPID {
		t.Fatalf("preferred project PID = %d, want restart at base ports", newPID)
	}
	if port := m.Status()["focus-second"]["web"].Port; port != secondPort {
		t.Fatalf("preferred project port = %d, want configured base port %d", port, secondPort)
	}

	snap := m.StateSnapshot()
	if snap.Mode != "focus" || snap.ActiveProject != "focus-second" {
		t.Fatalf("focus state = mode %q active %q, want focus/focus-second", snap.Mode, snap.ActiveProject)
	}
}

func TestHandleFocusFallsBackToDaemonActiveProject(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	writeDaemonGlobalConfig(t, home, root)
	firstDir := writeDaemonProject(t, root, "active-first", "web")
	secondDir := writeDaemonProject(t, root, "active-second", "web")

	st, err := state.Load()
	if err != nil {
		t.Fatalf("load state: %v", err)
	}
	st.Register("active-first", firstDir)
	st.Register("active-second", secondDir)
	if err := st.Save(); err != nil {
		t.Fatalf("save state: %v", err)
	}

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	for _, item := range []struct {
		name string
		path string
	}{{"active-first", firstDir}, {"active-second", secondDir}} {
		proj, loadErr := config.LoadProject(item.path)
		if loadErr != nil {
			t.Fatalf("load project %s: %v", item.name, loadErr)
		}
		if startErr := m.StartProject(item.name, proj, item.path, false); startErr != nil {
			t.Fatalf("start project %s: %v", item.name, startErr)
		}
		waitForServiceRunning(t, m, item.name, "web")
	}
	if err := m.SetFocus("active-first", "multitask"); err != nil {
		t.Fatalf("set daemon-active project: %v", err)
	}

	d := &Daemon{manager: m}
	resp := d.HandleRequest(Request{Action: "focus", Project: "not-running", Mode: "focus"})
	if !resp.OK {
		t.Fatalf("focus response error: %s", resp.Error)
	}

	if !m.IsRunning("active-first") || m.IsRunning("active-second") {
		t.Fatalf("running projects = %#v, want only active-first", m.RunningProjects())
	}
	snap := m.StateSnapshot()
	if snap.Mode != "focus" || snap.ActiveProject != "active-first" {
		t.Fatalf("focus state = mode %q active %q, want focus/active-first", snap.Mode, snap.ActiveProject)
	}
}

func TestHandleFocusPreservesSurvivorRunningServiceSet(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	writeDaemonGlobalConfig(t, home, root)
	otherDir := writeDaemonProject(t, root, "partial-other", "web")
	port := freeTCPPort(t)
	partialDir := writeDaemonProjectRaw(t, root, "partial-survivor", fmt.Sprintf(`name: partial-survivor
services:
  web:
    cmd: sleep 5
    port: %d
  worker:
    cmd: sleep 5
`, port))

	st, err := state.Load()
	if err != nil {
		t.Fatalf("load state: %v", err)
	}
	st.Register("partial-other", otherDir)
	st.Register("partial-survivor", partialDir)
	if err := st.Save(); err != nil {
		t.Fatalf("save state: %v", err)
	}

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	other, err := config.LoadProject(otherDir)
	if err != nil {
		t.Fatalf("load other project: %v", err)
	}
	if err := m.StartProject("partial-other", other, otherDir, false); err != nil {
		t.Fatalf("start other project: %v", err)
	}

	partial, err := config.LoadProject(partialDir)
	if err != nil {
		t.Fatalf("load partial project: %v", err)
	}
	if err := m.StartService("partial-survivor", "web", partial, partialDir, false); err != nil {
		t.Fatalf("start partial service: %v", err)
	}
	waitForServiceRunning(t, m, "partial-survivor", "web")

	d := &Daemon{manager: m}
	resp := d.HandleRequest(Request{Action: "focus", Project: "partial-survivor", Mode: "focus"})
	if !resp.OK {
		t.Fatalf("focus response error: %s", resp.Error)
	}

	status := m.Status()["partial-survivor"]
	if !status["web"].Running {
		t.Fatal("expected previously running web service to survive")
	}
	if _, exists := status["worker"]; exists {
		t.Fatalf("expected stopped worker to remain stopped, got %+v", status["worker"])
	}
	if status["web"].Port != port {
		t.Fatalf("web port = %d, want configured base port %d", status["web"].Port, port)
	}
}

func TestHandleFocusKeepsOffsetSurvivorRunningWhenBasePortIsBusy(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	writeDaemonGlobalConfig(t, home, root)
	otherDir := writeDaemonProject(t, root, "busy-other", "web")
	basePort := freeTCPPort(t)
	survivorDir := writeDaemonProjectRaw(t, root, "busy-survivor", fmt.Sprintf("name: busy-survivor\nservices:\n  web:\n    cmd: sleep 5\n    port: %d\n", basePort))

	st, err := state.Load()
	if err != nil {
		t.Fatalf("load state: %v", err)
	}
	st.Register("busy-other", otherDir)
	st.Register("busy-survivor", survivorDir)
	if err := st.Save(); err != nil {
		t.Fatalf("save state: %v", err)
	}

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	other, err := config.LoadProject(otherDir)
	if err != nil {
		t.Fatalf("load other project: %v", err)
	}
	if err := m.StartProject("busy-other", other, otherDir, false); err != nil {
		t.Fatalf("start other project: %v", err)
	}
	survivor, err := config.LoadProject(survivorDir)
	if err != nil {
		t.Fatalf("load survivor project: %v", err)
	}
	if err := m.StartProject("busy-survivor", survivor, survivorDir, false); err != nil {
		t.Fatalf("start survivor project: %v", err)
	}
	waitForServiceRunning(t, m, "busy-survivor", "web")
	original := m.Status()["busy-survivor"]["web"]

	blocker, err := net.Listen("tcp4", fmt.Sprintf("127.0.0.1:%d", basePort))
	if err != nil {
		t.Fatalf("occupy base port: %v", err)
	}
	defer blocker.Close()

	d := &Daemon{manager: m}
	resp := d.HandleRequest(Request{Action: "focus", Project: "busy-survivor", Mode: "focus"})
	if resp.OK {
		t.Fatalf("expected busy base port error, got %+v", resp)
	}

	current := m.Status()["busy-survivor"]["web"]
	if !current.Running || current.PID != original.PID || current.Port != original.Port {
		t.Fatalf("survivor changed after preflight failure: before=%+v after=%+v", original, current)
	}
	if m.IsRunning("busy-other") {
		t.Fatal("expected non-survivor to remain stopped")
	}
	snap := m.StateSnapshot()
	if snap.Mode != "focus" || snap.ActiveProject != "busy-survivor" {
		t.Fatalf("focus state = mode %q active %q, want focus/busy-survivor", snap.Mode, snap.ActiveProject)
	}
}

func TestHandleFocusWaitsForConcurrentProjectStart(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	writeDaemonGlobalConfig(t, home, root)
	keepDir := writeDaemonProject(t, root, "serialized-keep", "web")
	marker := filepath.Join(t.TempDir(), "pre-started")
	startingDir := writeDaemonProjectRaw(t, root, "serialized-starting", fmt.Sprintf(`name: serialized-starting
hooks:
  pre_start: touch %s && sleep 0.2
services:
  web:
    cmd: sleep 5
`, marker))

	st, err := state.Load()
	if err != nil {
		t.Fatalf("load state: %v", err)
	}
	st.Register("serialized-keep", keepDir)
	st.Register("serialized-starting", startingDir)
	if err := st.Save(); err != nil {
		t.Fatalf("save state: %v", err)
	}

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()
	keep, err := config.LoadProject(keepDir)
	if err != nil {
		t.Fatalf("load keep project: %v", err)
	}
	if err := m.StartProject("serialized-keep", keep, keepDir, false); err != nil {
		t.Fatalf("start keep project: %v", err)
	}

	d := &Daemon{manager: m}
	startResult := make(chan Response, 1)
	go func() {
		startResult <- d.HandleRequest(Request{Action: "start", Project: "serialized-starting", Mode: "parallel"})
	}()

	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if _, err := os.Stat(marker); err == nil {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if _, err := os.Stat(marker); err != nil {
		t.Fatalf("concurrent start did not enter pre_start hook: %v", err)
	}
	hookRequestStarted := time.Now()
	hookResp := d.HandleRequest(Request{Action: "focus", Project: "serialized-keep", Mode: "focus", Origin: "hook"})
	if hookResp.OK || !strings.Contains(hookResp.Error, "cannot run recursively") {
		t.Fatalf("hook lifecycle response = %+v, want immediate recursive-operation error", hookResp)
	}
	if elapsed := time.Since(hookRequestStarted); elapsed > 100*time.Millisecond {
		t.Fatalf("hook lifecycle request took %s, want fail-fast response", elapsed)
	}

	focusResult := make(chan Response, 1)
	go func() {
		focusResult <- d.HandleRequest(Request{Action: "focus", Project: "serialized-keep", Mode: "focus"})
	}()

	if resp := <-startResult; !resp.OK {
		t.Fatalf("start response error: %s", resp.Error)
	}
	if resp := <-focusResult; !resp.OK {
		t.Fatalf("focus response error: %s", resp.Error)
	}
	if !m.IsRunning("serialized-keep") || m.IsRunning("serialized-starting") {
		t.Fatalf("running projects = %#v, want only serialized-keep", m.RunningProjects())
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
