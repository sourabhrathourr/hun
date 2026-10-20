package daemon

import (
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"

	"github.com/sourabhrathourr/hun/internal/config"
	"github.com/sourabhrathourr/hun/internal/state"
)

const profileProjectYAML = `name: shop
services:
  db:
    cmd: sleep 30
  api:
    cmd: sleep 30
    depends_on: [db]
  web:
    cmd: sleep 30
  worker:
    cmd: sleep 30
    depends_on: [db]
profiles:
  ui: [web]
  app: [web, api]
  jobs: [worker]
`

func newProfileDaemon(t *testing.T) (*Daemon, *Manager, string) {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	writeDaemonGlobalConfig(t, home, root)
	projectDir := writeDaemonProjectRaw(t, root, "shop", profileProjectYAML)

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
	t.Cleanup(m.Shutdown)
	return &Daemon{manager: m}, m, projectDir
}

func runningServices(m *Manager, project string) []string {
	var names []string
	for name, info := range m.Status()[project] {
		if info.Running {
			names = append(names, name)
		}
	}
	sort.Strings(names)
	return names
}

func TestStartWithProfileRunsOnlyItsServices(t *testing.T) {
	d, m, _ := newProfileDaemon(t)

	resp := d.HandleRequest(Request{Action: "start", Project: "shop", Profile: "app", Mode: "parallel"})
	if !resp.OK {
		t.Fatalf("start: %s", resp.Error)
	}
	if got, want := runningServices(m, "shop"), []string{"api", "db", "web"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("running = %v, want %v", got, want)
	}
	if got := m.StateSnapshot().Projects["shop"].Profile; got != "app" {
		t.Fatalf("remembered profile = %q, want app", got)
	}
}

func TestSwitchingProfilesOnlyChangesTheDifference(t *testing.T) {
	d, m, _ := newProfileDaemon(t)

	if resp := d.HandleRequest(Request{Action: "start", Project: "shop", Profile: "app", Mode: "parallel"}); !resp.OK {
		t.Fatalf("start app: %s", resp.Error)
	}
	dbPID := m.Status()["shop"]["db"].PID

	resp := d.HandleRequest(Request{Action: "start", Project: "shop", Profile: "jobs", Mode: "parallel"})
	if !resp.OK {
		t.Fatalf("switch to jobs: %s", resp.Error)
	}
	if got, want := runningServices(m, "shop"), []string{"db", "worker"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("running = %v, want %v", got, want)
	}
	if got := m.Status()["shop"]["db"].PID; got != dbPID {
		t.Fatalf("db was restarted (pid %d → %d); shared services should keep running", dbPID, got)
	}
}

func TestStartWithoutProfileRepeatsTheLastOne(t *testing.T) {
	d, m, _ := newProfileDaemon(t)

	if resp := d.HandleRequest(Request{Action: "start", Project: "shop", Profile: "ui", Mode: "parallel"}); !resp.OK {
		t.Fatalf("start ui: %s", resp.Error)
	}
	if resp := d.HandleRequest(Request{Action: "stop", Project: "shop"}); !resp.OK {
		t.Fatalf("stop: %s", resp.Error)
	}
	if resp := d.HandleRequest(Request{Action: "start", Project: "shop", Mode: "parallel"}); !resp.OK {
		t.Fatalf("start again: %s", resp.Error)
	}
	if got, want := runningServices(m, "shop"), []string{"web"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("running = %v, want %v", got, want)
	}

	// "all" runs everything and is remembered as the default.
	if resp := d.HandleRequest(Request{Action: "start", Project: "shop", Profile: "all", Mode: "parallel"}); !resp.OK {
		t.Fatalf("start all: %s", resp.Error)
	}
	if got, want := runningServices(m, "shop"), []string{"api", "db", "web", "worker"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("running = %v, want %v", got, want)
	}
	if got := m.StateSnapshot().Projects["shop"].Profile; got != "" {
		t.Fatalf("remembered profile = %q, want every service", got)
	}
}

func TestStartWithUnknownProfileFails(t *testing.T) {
	d, m, _ := newProfileDaemon(t)

	resp := d.HandleRequest(Request{Action: "start", Project: "shop", Profile: "nope", Mode: "parallel"})
	if resp.OK {
		t.Fatalf("expected an unknown profile to fail")
	}
	if got := runningServices(m, "shop"); len(got) != 0 {
		t.Fatalf("nothing should start, running = %v", got)
	}
}

func TestSaveProfileWritesConfigAndRemembersIt(t *testing.T) {
	d, m, projectDir := newProfileDaemon(t)

	resp := d.HandleRequest(Request{Action: "save_profile", Project: "shop", Profile: "backend", Services: []string{"api", "worker"}})
	if !resp.OK {
		t.Fatalf("save_profile: %s", resp.Error)
	}
	proj, err := config.LoadProject(projectDir)
	if err != nil {
		t.Fatalf("load project: %v", err)
	}
	if backend, ok := proj.Profile("backend"); !ok || !reflect.DeepEqual(backend.Services, []string{"api", "worker"}) {
		t.Fatalf("backend = %+v, %v", backend, ok)
	}
	if got := m.RememberedProfile("shop", proj); got != "backend" {
		t.Fatalf("remembered profile = %q, want backend", got)
	}

	if resp := d.HandleRequest(Request{Action: "save_profile", Project: "shop", Profile: "bad", Services: []string{"ghost"}}); resp.OK {
		t.Fatalf("expected saving an unknown service to fail")
	}
}

func TestSelectProfileRemembersItWithoutStarting(t *testing.T) {
	d, m, projectDir := newProfileDaemon(t)
	proj, err := config.LoadProject(projectDir)
	if err != nil {
		t.Fatalf("load project: %v", err)
	}

	if resp := d.HandleRequest(Request{Action: "select_profile", Project: "shop", Profile: "app"}); !resp.OK {
		t.Fatalf("select_profile: %s", resp.Error)
	}
	if got := runningServices(m, "shop"); len(got) != 0 {
		t.Fatalf("selecting a profile must not start anything, running = %v", got)
	}
	if got := m.RememberedProfile("shop", proj); got != "app" {
		t.Fatalf("remembered profile = %q, want app", got)
	}

	if resp := d.HandleRequest(Request{Action: "select_profile", Project: "shop", Profile: "all"}); !resp.OK {
		t.Fatalf("select all: %s", resp.Error)
	}
	if got := m.RememberedProfile("shop", proj); got != "" {
		t.Fatalf("remembered profile = %q, want every service", got)
	}

	if resp := d.HandleRequest(Request{Action: "select_profile", Project: "shop", Profile: "nope"}); resp.OK {
		t.Fatalf("expected an unknown profile to fail")
	}
}

func TestSnapshotListsProfiles(t *testing.T) {
	d, m, _ := newProfileDaemon(t)
	if resp := d.HandleRequest(Request{Action: "start", Project: "shop", Profile: "app", Mode: "parallel"}); !resp.OK {
		t.Fatalf("start: %s", resp.Error)
	}

	snap, err := m.Snapshot(false)
	if err != nil {
		t.Fatalf("snapshot: %v", err)
	}
	var project *SnapshotProject
	for i := range snap.Projects {
		if snap.Projects[i].ID == "shop" {
			project = &snap.Projects[i]
		}
	}
	if project == nil {
		t.Fatalf("shop missing from snapshot")
	}
	if project.Profile != "app" {
		t.Fatalf("profile = %q, want app", project.Profile)
	}
	want := []SnapshotProfile{
		{Name: "ui", Services: []string{"web"}, Resolved: []string{"web"}},
		{Name: "app", Services: []string{"web", "api"}, Resolved: []string{"api", "db", "web"}},
		{Name: "jobs", Services: []string{"worker"}, Resolved: []string{"db", "worker"}},
	}
	if !reflect.DeepEqual(project.Profiles, want) {
		t.Fatalf("profiles = %+v, want %+v", project.Profiles, want)
	}
}

func TestStoppingTheLastServiceStopsTheProject(t *testing.T) {
	d, m, _ := newProfileDaemon(t)

	if resp := d.HandleRequest(Request{Action: "start", Project: "shop", Profile: "app", Mode: "parallel"}); !resp.OK {
		t.Fatalf("start: %s", resp.Error)
	}
	for i, service := range []string{"web", "api", "db"} {
		if resp := d.HandleRequest(Request{Action: "stop_service", Project: "shop", Service: service}); !resp.OK {
			t.Fatalf("stop %s: %s", service, resp.Error)
		}
		wantRunning := i < 2
		if got := m.IsRunning("shop"); got != wantRunning {
			t.Fatalf("after stopping %s, project running = %v, want %v", service, got, wantRunning)
		}
	}
	if status := m.StateSnapshot().Projects["shop"].Status; status != "stopped" {
		t.Fatalf("project status = %q, want stopped", status)
	}
	// It still remembers its profile, and Run brings it back.
	if resp := d.HandleRequest(Request{Action: "start", Project: "shop", Mode: "parallel"}); !resp.OK {
		t.Fatalf("start again: %s", resp.Error)
	}
	if got, want := runningServices(m, "shop"), []string{"api", "db", "web"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("running = %v, want %v", got, want)
	}
}

func TestSwitchingAwayFromEveryRunningServiceKeepsTheProjectUp(t *testing.T) {
	d, m, _ := newProfileDaemon(t)

	if resp := d.HandleRequest(Request{Action: "start", Project: "shop", Profile: "ui", Mode: "parallel"}); !resp.OK {
		t.Fatalf("start ui: %s", resp.Error)
	}
	offset := m.StateSnapshot().Projects["shop"].Offset
	// ui runs only web; jobs shares nothing with it.
	if resp := d.HandleRequest(Request{Action: "start", Project: "shop", Profile: "jobs", Mode: "parallel"}); !resp.OK {
		t.Fatalf("switch to jobs: %s", resp.Error)
	}
	if got, want := runningServices(m, "shop"), []string{"db", "worker"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("running = %v, want %v", got, want)
	}
	if got := m.StateSnapshot().Projects["shop"]; got.Status != "running" || got.Offset != offset {
		t.Fatalf("project = %s offset %d, want running offset %d", got.Status, got.Offset, offset)
	}
}

func TestValidateAndSaveConfig(t *testing.T) {
	d, _, projectDir := newProfileDaemon(t)

	if resp := d.HandleRequest(Request{Action: "validate_config", Content: "name: x\nservices:\n  web:\n    cmd: [oops\n"}); resp.OK || !strings.Contains(resp.Error, "line") {
		t.Fatalf("broken YAML should fail with a line number, got ok=%v %q", resp.OK, resp.Error)
	}
	if resp := d.HandleRequest(Request{Action: "validate_config", Content: "name: x\nservices:\n  web:\n    port: 3000\n"}); resp.OK {
		t.Fatalf("a service without cmd should fail validation")
	}

	before, _ := os.ReadFile(filepath.Join(projectDir, ".hun.yml"))
	if resp := d.HandleRequest(Request{Action: "save_config", Project: "shop", Content: "name: shop\nservices: {}\n"}); resp.OK {
		t.Fatalf("an invalid config must not be saved")
	}
	if after, _ := os.ReadFile(filepath.Join(projectDir, ".hun.yml")); string(after) != string(before) {
		t.Fatalf("a rejected save changed the file")
	}

	edited := "# kept as typed\nname: shop\nservices:\n  web:\n    cmd: sleep 30   # trailing comment\n"
	if resp := d.HandleRequest(Request{Action: "save_config", Project: "shop", Content: edited}); !resp.OK {
		t.Fatalf("save_config: %s", resp.Error)
	}
	if after, _ := os.ReadFile(filepath.Join(projectDir, ".hun.yml")); string(after) != edited {
		t.Fatalf("saved file = %q, want it exactly as typed", after)
	}
	if leftovers, _ := filepath.Glob(filepath.Join(projectDir, ".hun.yml.*")); len(leftovers) > 0 {
		t.Fatalf("temp files left behind: %v", leftovers)
	}
}

func TestSaveConfigByFolderPath(t *testing.T) {
	d, _, projectDir := newProfileDaemon(t)
	edited := "name: shop\nservices:\n  web:\n    cmd: sleep 30\n"
	if resp := d.HandleRequest(Request{Action: "save_config", Path: projectDir, Content: edited}); !resp.OK {
		t.Fatalf("save by path: %s", resp.Error)
	}
	if resp := d.HandleRequest(Request{Action: "save_config", Path: t.TempDir(), Content: edited}); resp.OK {
		t.Fatalf("a folder without .hun.yml must be refused")
	}
	if resp := d.HandleRequest(Request{Action: "save_config", Path: "relative", Content: edited}); resp.OK {
		t.Fatalf("a relative path must be refused")
	}
}

func TestRunRestartsAProjectWhoseServicesAllCrashed(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	writeDaemonGlobalConfig(t, home, root)
	projectDir := writeDaemonProjectRaw(t, root, "flaky", "name: flaky\nservices:\n  web:\n    cmd: exit 127\n")
	st, err := state.Load()
	if err != nil {
		t.Fatal(err)
	}
	st.Register("flaky", projectDir)
	if err := st.Save(); err != nil {
		t.Fatal(err)
	}
	m, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(m.Shutdown)
	d := &Daemon{manager: m}

	if resp := d.HandleRequest(Request{Action: "start", Project: "flaky", Mode: "parallel"}); !resp.OK {
		t.Fatalf("first start: %s", resp.Error)
	}
	waitForServiceStopped(t, m, "flaky", "web")
	if !m.IsRunning("flaky") || m.HasLiveServices("flaky") {
		t.Fatalf("expected a crashed project: known but with nothing alive")
	}

	// Fix the command, then Run again: it must start, not report "already running".
	if err := os.WriteFile(filepath.Join(projectDir, ".hun.yml"), []byte("name: flaky\nservices:\n  web:\n    cmd: sleep 30\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	resp := d.HandleRequest(Request{Action: "start", Project: "flaky", Mode: "parallel"})
	if !resp.OK {
		t.Fatalf("second start: %s", resp.Error)
	}
	if strings.Contains(string(resp.Data), "already_running") {
		t.Fatalf("a crashed project was treated as already running")
	}
	waitForServiceRunning(t, m, "flaky", "web")
}
