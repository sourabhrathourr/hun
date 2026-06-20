package daemon

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/sourabhrathourr/hun/internal/state"
)

func TestFindProjectIconPrefersPublicFavicon(t *testing.T) {
	root := t.TempDir()
	writeTestFile(t, filepath.Join(root, "src/assets/logo.svg"))
	want := filepath.Join(root, "public/favicon.png")
	writeTestFile(t, want)

	if got := findProjectIcon(root); got != want {
		t.Fatalf("findProjectIcon() = %q, want %q", got, want)
	}
}

func TestFindProjectIconScansNestedLogoAndSkipsHeavyDirs(t *testing.T) {
	root := t.TempDir()
	writeTestFile(t, filepath.Join(root, "node_modules/pkg/favicon.png"))
	want := filepath.Join(root, "apps/web/src/assets/logo.svg")
	writeTestFile(t, want)

	if got := findProjectIcon(root); got != want {
		t.Fatalf("findProjectIcon() = %q, want %q", got, want)
	}
}

func TestFindProjectIconScansNestedPublicFavicon(t *testing.T) {
	root := t.TempDir()
	want := filepath.Join(root, "apps/web/public/favicon.ico")
	writeTestFile(t, want)

	if got := findProjectIcon(root); got != want {
		t.Fatalf("findProjectIcon() = %q, want %q", got, want)
	}
}

func TestFindProjectIconPrefersHighResolutionNestedIcon(t *testing.T) {
	root := t.TempDir()
	writeTestFile(t, filepath.Join(root, "frontend/app/favicon.svg"))
	writeTestFile(t, filepath.Join(root, "frontend/public/logos/otto-icon-192.png"))
	want := filepath.Join(root, "frontend/public/logos/otto-icon-512.png")
	writeTestFile(t, want)

	if got := findProjectIcon(root); got != want {
		t.Fatalf("findProjectIcon() = %q, want %q", got, want)
	}
}

func TestSetProjectIconCopiesAndPersistsOverride(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	projectRoot := t.TempDir()
	writeTestFile(t, filepath.Join(projectRoot, ".hun.yml"))
	sourcePath := filepath.Join(t.TempDir(), "logo.png")
	writeTestFile(t, sourcePath)

	st, err := state.Load()
	if err != nil {
		t.Fatalf("load state: %v", err)
	}
	st.Register("app", projectRoot)
	if err := st.Save(); err != nil {
		t.Fatalf("save state: %v", err)
	}

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	iconPath, err := m.SetProjectIcon("app", sourcePath)
	if err != nil {
		t.Fatalf("set project icon: %v", err)
	}
	if !fileExists(iconPath) {
		t.Fatalf("expected copied icon at %s", iconPath)
	}
	snapshot := m.StateSnapshot()
	if got := snapshot.Projects["app"].IconPath; got != iconPath {
		t.Fatalf("state icon path = %q, want %q", got, iconPath)
	}
	if got := m.projectIconPath(projectRoot, iconPath); got != iconPath {
		t.Fatalf("projectIconPath() = %q, want override %q", got, iconPath)
	}
}

func writeTestFile(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir %s: %v", filepath.Dir(path), err)
	}
	if err := os.WriteFile(path, []byte("icon"), 0o644); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}
