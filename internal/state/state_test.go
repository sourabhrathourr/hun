package state

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadMigratesLegacyStateDefaults(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	projectDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(projectDir, ".hun.yml"), []byte("name: proj\nservices:\n  app:\n    cmd: echo ok\n"), 0o644); err != nil {
		t.Fatalf("write project config: %v", err)
	}

	hunDir := filepath.Join(home, ".hun")
	if err := os.MkdirAll(hunDir, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}

	legacy := `{"projects":{"proj":{"status":"running"}},"registry":{"proj":"` + projectDir + `"}}`
	if err := os.WriteFile(filepath.Join(hunDir, "state.json"), []byte(legacy), 0o644); err != nil {
		t.Fatalf("write legacy state: %v", err)
	}

	st, err := Load()
	if err != nil {
		t.Fatalf("load: %v", err)
	}

	if st.SchemaVersion != CurrentSchemaVersion {
		t.Fatalf("schema version = %d, want %d", st.SchemaVersion, CurrentSchemaVersion)
	}
	if st.Mode != "focus" {
		t.Fatalf("mode = %q, want focus", st.Mode)
	}
	if st.ActiveProject != "proj" {
		t.Fatalf("active project = %q, want proj", st.ActiveProject)
	}

	if err := st.Save(); err != nil {
		t.Fatalf("save: %v", err)
	}

	reloaded, err := Load()
	if err != nil {
		t.Fatalf("reload: %v", err)
	}
	if reloaded.SchemaVersion != CurrentSchemaVersion {
		t.Fatalf("reloaded schema version = %d, want %d", reloaded.SchemaVersion, CurrentSchemaVersion)
	}
	if reloaded.ActiveProject != "proj" {
		t.Fatalf("reloaded active project = %q, want proj", reloaded.ActiveProject)
	}
}

func TestLoadPrunesRegistryEntriesWithoutProjectConfig(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	validDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(validDir, ".hun.yml"), []byte("name: keep\nservices:\n  app:\n    cmd: echo ok\n"), 0o644); err != nil {
		t.Fatalf("write valid config: %v", err)
	}

	missingDir := t.TempDir()

	hunDir := filepath.Join(home, ".hun")
	if err := os.MkdirAll(hunDir, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	raw := `{
  "schema_version": 2,
  "mode": "focus",
  "active_project": "missing",
  "projects": {
    "keep": {"status":"stopped"},
    "missing": {"status":"running"}
  },
  "registry": {
    "keep": "` + validDir + `",
    "missing": "` + missingDir + `"
  }
}`
	if err := os.WriteFile(filepath.Join(hunDir, "state.json"), []byte(raw), 0o644); err != nil {
		t.Fatalf("write state: %v", err)
	}

	st, err := Load()
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if _, ok := st.Registry["missing"]; ok {
		t.Fatalf("expected missing project removed from registry")
	}
	if _, ok := st.Projects["missing"]; ok {
		t.Fatalf("expected missing project removed from projects map")
	}
	if st.ActiveProject != "" {
		t.Fatalf("active project = %q, want empty after prune", st.ActiveProject)
	}

	reloaded, err := Load()
	if err != nil {
		t.Fatalf("reload: %v", err)
	}
	if _, ok := reloaded.Registry["missing"]; ok {
		t.Fatalf("expected missing project absent after persistence")
	}
}
