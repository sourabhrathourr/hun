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

func TestReconcileStateRemovesProjectsWithoutConfig(t *testing.T) {
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
	if err := os.Remove(filepath.Join(projectDir, ".hun.yml")); err != nil {
		t.Fatalf("remove project config: %v", err)
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

func TestScanDuplicateNamesKeepRegisteredPath(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	root := t.TempDir()
	writeGlobalConfig(t, home, root)
	first := writeProject(t, root, "dupe", "api")
	secondParent := filepath.Join(root, "z-second")
	if err := os.MkdirAll(secondParent, 0o755); err != nil {
		t.Fatalf("mkdir second parent: %v", err)
	}
	second := writeProject(t, secondParent, "dupe", "api")

	result, err := Scan(&config.Global{ScanDirs: []string{root}}, map[string]string{"dupe": second})
	if err != nil {
		t.Fatalf("scan: %v", err)
	}
	if got := result.Projects["dupe"]; got != second {
		t.Fatalf("selected duplicate = %q, want registered path %q (first was %q)", got, second, first)
	}
	if len(result.Warnings) == 0 {
		t.Fatal("expected duplicate warning")
	}
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
