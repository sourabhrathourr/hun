package daemon

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/sourabhrathourr/hun/internal/state"
)

type registryFixture struct {
	t    *testing.T
	home string
	root string
	d    *Daemon
}

func newRegistryFixture(t *testing.T, withScanRoot bool) *registryFixture {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := filepath.Join(home, "work")
	if err := os.MkdirAll(root, 0o755); err != nil {
		t.Fatal(err)
	}
	if withScanRoot {
		writeDaemonGlobalConfig(t, home, root)
	}
	m, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(m.Shutdown)
	return &registryFixture{t: t, home: home, root: root, d: &Daemon{manager: m}}
}

func (f *registryFixture) write(dir, name string) string {
	f.t.Helper()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		f.t.Fatal(err)
	}
	raw := "name: " + name + "\nservices:\n  web:\n    cmd: sleep 5\n"
	if err := os.WriteFile(filepath.Join(dir, ".hun.yml"), []byte(raw), 0o644); err != nil {
		f.t.Fatal(err)
	}
	return dir
}

func (f *registryFixture) request(req Request) Response {
	f.t.Helper()
	resp := f.d.HandleRequest(req)
	if !resp.OK {
		f.t.Fatalf("%s: %s", req.Action, resp.Error)
	}
	return resp
}

// projects maps snapshot project IDs to their paths.
func (f *registryFixture) projects() map[string]string {
	f.t.Helper()
	snap, err := f.d.manager.Snapshot(true)
	if err != nil {
		f.t.Fatal(err)
	}
	out := make(map[string]string)
	for _, p := range snap.Projects {
		out[p.ID] = p.Path
	}
	return out
}

func TestRenamedProjectIsNotListedTwice(t *testing.T) {
	f := newRegistryFixture(t, true)
	dir := f.write(filepath.Join(f.root, "shop"), "shop")
	f.request(Request{Action: "register_project", Path: dir})
	f.write(dir, "storefront")

	got := f.projects()
	if len(got) != 1 || got["storefront"] != dir {
		t.Fatalf("projects after rename = %v", got)
	}
}

func TestAddingProjectOutsideScanRootsDoesNotPullInItsNeighbours(t *testing.T) {
	f := newRegistryFixture(t, false)
	added := f.write(filepath.Join(f.home, "Desktop", "demo"), "demo")
	f.write(filepath.Join(f.home, "Desktop", "old-copy"), "stray")
	f.request(Request{Action: "register_project", Path: added})

	got := f.projects()
	if len(got) != 1 || got["demo"] != added {
		t.Fatalf("projects = %v", got)
	}
}

func TestSameNamedFolderCanBeAdded(t *testing.T) {
	f := newRegistryFixture(t, true)
	first := f.write(filepath.Join(f.root, "client-a", "web"), "web")
	second := f.write(filepath.Join(f.root, "client-b", "web"), "web")
	f.request(Request{Action: "register_project", Path: first})
	f.request(Request{Action: "register_project", Path: second})

	got := f.projects()
	if got["web"] != first || got["client-b-web"] != second {
		t.Fatalf("projects = %v", got)
	}
}

func TestRemovedProjectStaysRemoved(t *testing.T) {
	f := newRegistryFixture(t, true)
	dir := f.write(filepath.Join(f.root, "shop"), "shop")
	f.request(Request{Action: "register_project", Path: dir})
	f.request(Request{Action: "remove_project", Project: "shop"})

	if got := f.projects(); len(got) != 0 {
		t.Fatalf("removed project came back: %v", got)
	}
	f.request(Request{Action: "register_project", Path: dir})
	if got := f.projects(); got["shop"] != dir {
		t.Fatalf("re-added project missing: %v", got)
	}
}

func TestMissingConfigKeepsProjectAndItsSettings(t *testing.T) {
	f := newRegistryFixture(t, true)
	dir := f.write(filepath.Join(f.root, "shop"), "shop")
	f.request(Request{Action: "register_project", Path: dir})
	_ = f.d.manager.mutateState(func(st *state.State) {
		ps := st.Projects["shop"]
		ps.IconPath = "/custom/icon.png"
		ps.LastNote = "handoff note"
		st.Projects["shop"] = ps
	})
	if err := os.Remove(filepath.Join(dir, ".hun.yml")); err != nil {
		t.Fatal(err)
	}

	snap, err := f.d.manager.Snapshot(true)
	if err != nil {
		t.Fatal(err)
	}
	if len(snap.Projects) != 1 || snap.Projects[0].ConfigError == "" {
		t.Fatalf("project while .hun.yml is missing = %+v", snap.Projects)
	}
	f.write(dir, "shop")
	f.projects()
	if ps := f.d.manager.StateSnapshot().Projects["shop"]; ps.IconPath != "/custom/icon.png" || ps.LastNote != "handoff note" {
		t.Fatalf("settings lost: %+v", ps)
	}
}
