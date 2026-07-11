package config

import (
	"path/filepath"
	"testing"
)

func TestHunDirHonorsExplicitHome(t *testing.T) {
	custom := filepath.Join(t.TempDir(), "hun-dev")
	t.Setenv("HUN_HOME", custom)

	dir, err := HunDir()
	if err != nil {
		t.Fatalf("HunDir: %v", err)
	}
	if dir != custom {
		t.Fatalf("HunDir = %q, want explicit HUN_HOME %q", dir, custom)
	}
}
