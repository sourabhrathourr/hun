package state

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadMigratesLegacyStateDefaults(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	hunDir := filepath.Join(home, ".hun")
	if err := os.MkdirAll(hunDir, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}

	legacy := `{"projects":{"proj":{"status":"running"}},"registry":{"proj":"/tmp/proj"}}`
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
