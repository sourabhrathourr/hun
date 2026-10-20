package discovery

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/sourabhrathourr/hun/internal/config"
	"github.com/sourabhrathourr/hun/internal/state"
)

func TestReconcileStateRegistersProjectsUnderConfiguredRoots(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	writeGlobalConfig(t, home, root)
	projectDir := writeProject(t, root, "app-a", "web")

	st, err := state.Load()
	if err != nil {
		t.Fatalf("load state: %v", err)
	}
	result, dirty, err := ReconcileState(st)
	if err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if !dirty {
		t.Fatal("expected dirty state")
	}
	if got := st.Registry["app-a"]; got != projectDir {
		t.Fatalf("registry path = %q, want %q", got, projectDir)
	}
	if len(result.ScanDirs) != 1 || result.ScanDirs[0] != root {
		t.Fatalf("scan dirs = %#v, want %q", result.ScanDirs, root)
	}
}

func TestReconcileStateRemovesProjectsWhoseFolderIsGone(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	writeGlobalConfig(t, home, root)
	projectDir := writeProject(t, root, "gone", "web")

	st, err := state.Load()
	if err != nil {
		t.Fatalf("load state: %v", err)
	}
	st.Registry["gone"] = projectDir
	st.Projects["gone"] = state.ProjectState{Status: "running"}
	if err := os.RemoveAll(projectDir); err != nil {
		t.Fatalf("delete project folder: %v", err)
	}

	_, dirty, err := ReconcileState(st)
	if err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if !dirty {
		t.Fatal("expected dirty state")
	}
	if _, ok := st.Registry["gone"]; ok {
		t.Fatal("expected project removed from registry")
	}
	if _, ok := st.Projects["gone"]; ok {
		t.Fatal("expected project removed from project state")
	}
}

func TestReconcileRegistersSameNamedFoldersUnderDistinctKeys(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	writeGlobalConfig(t, home, root)
	first := writeProjectNamed(t, filepath.Join(root, "client-a", "web"), "web")
	second := writeProjectNamed(t, filepath.Join(root, "client-b", "web"), "web")

	st, err := state.Load()
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := ReconcileState(st); err != nil {
		t.Fatal(err)
	}
	if st.Registry["web"] != first || st.Registry["client-b-web"] != second {
		t.Fatalf("registry = %v", st.Registry)
	}
}

func TestReconcileFollowsRenameWithoutDuplicating(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	writeGlobalConfig(t, home, root)
	dir := writeProjectNamed(t, filepath.Join(root, "shop"), "shop")

	st, err := state.Load()
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := ReconcileState(st); err != nil {
		t.Fatal(err)
	}
	st.Projects["shop"] = state.ProjectState{Path: dir, IconPath: "/icon.png"}
	writeProjectNamed(t, dir, "storefront")

	// A running project keeps its key until it stops.
	st.Projects["shop"] = state.ProjectState{Path: dir, IconPath: "/icon.png", Status: "running"}
	if _, _, err := ReconcileState(st); err != nil {
		t.Fatal(err)
	}
	if len(st.Registry) != 1 || st.Registry["shop"] != dir {
		t.Fatalf("while running: registry = %v", st.Registry)
	}

	st.Projects["shop"] = state.ProjectState{Path: dir, IconPath: "/icon.png", Status: "stopped"}
	if _, _, err := ReconcileState(st); err != nil {
		t.Fatal(err)
	}
	if len(st.Registry) != 1 || st.Registry["storefront"] != dir || st.Projects["storefront"].IconPath != "/icon.png" {
		t.Fatalf("after stop: registry = %v projects = %v", st.Registry, st.Projects)
	}
}

func TestReconcileCollapsesFolderRegisteredTwice(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	writeGlobalConfig(t, home, root)
	dir := writeProjectNamed(t, filepath.Join(root, "shop"), "storefront")

	st, err := state.Load()
	if err != nil {
		t.Fatal(err)
	}
	st.Registry["shop"] = dir
	st.Registry["storefront"] = dir
	if _, _, err := ReconcileState(st); err != nil {
		t.Fatal(err)
	}
	if len(st.Registry) != 1 || st.Registry["storefront"] != dir {
		t.Fatalf("registry = %v", st.Registry)
	}
}

func TestReconcileKeepsRemovedProjectsOut(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	writeGlobalConfig(t, home, root)
	dir := writeProjectNamed(t, filepath.Join(root, "shop"), "shop")

	st, err := state.Load()
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := ReconcileState(st); err != nil {
		t.Fatal(err)
	}
	st.RemoveProject("shop")
	if _, _, err := ReconcileState(st); err != nil {
		t.Fatal(err)
	}
	if len(st.Registry) != 0 {
		t.Fatalf("removed project came back: %v", st.Registry)
	}

	// Adding it explicitly again lifts the removal.
	if key := st.RegisterPath("shop", dir); key != "shop" || st.IsIgnored(dir) {
		t.Fatalf("re-add: key=%q ignored=%v", key, st.IsIgnored(dir))
	}
}

func TestReconcileKeepsProjectWhoseConfigIsTemporarilyMissing(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	writeGlobalConfig(t, home, root)
	dir := writeProjectNamed(t, filepath.Join(root, "shop"), "shop")

	st, err := state.Load()
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := ReconcileState(st); err != nil {
		t.Fatal(err)
	}
	st.Projects["shop"] = state.ProjectState{Path: dir, IconPath: "/icon.png", LastNote: "note"}
	if err := os.Remove(filepath.Join(dir, ".hun.yml")); err != nil {
		t.Fatal(err)
	}
	if _, _, err := ReconcileState(st); err != nil {
		t.Fatal(err)
	}
	if st.Registry["shop"] != dir || st.Projects["shop"].IconPath != "/icon.png" {
		t.Fatalf("project lost while .hun.yml was missing: %v %v", st.Registry, st.Projects)
	}
}

func TestScanOnlyWalksConfiguredRoots(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	writeProjectNamed(t, filepath.Join(home, "Desktop", "demo"), "demo")
	writeProjectNamed(t, filepath.Join(home, "Desktop", "stray"), "stray")

	result, err := Scan(&config.Global{})
	if err != nil {
		t.Fatal(err)
	}
	if len(result.ScanDirs) != 0 || len(result.Projects) != 0 {
		t.Fatalf("scanned outside the default roots: %+v", result)
	}
}

func writeProjectNamed(t *testing.T, dir, name string) string {
	t.Helper()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	raw := "name: " + name + "\nservices:\n  web:\n    cmd: sleep 5\n"
	if err := os.WriteFile(filepath.Join(dir, ".hun.yml"), []byte(raw), 0o644); err != nil {
		t.Fatal(err)
	}
	return dir
}

func writeGlobalConfig(t *testing.T, home, root string) {
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

func writeProject(t *testing.T, root, name, service string) string {
	t.Helper()
	dir := filepath.Join(root, name)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatalf("mkdir project: %v", err)
	}
	raw := "name: " + name + "\nservices:\n  " + service + ":\n    cmd: sleep 5\n"
	if err := os.WriteFile(filepath.Join(dir, ".hun.yml"), []byte(raw), 0o644); err != nil {
		t.Fatalf("write project config: %v", err)
	}
	return dir
}
