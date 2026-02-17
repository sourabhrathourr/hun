package cli

import (
	"testing"

	"github.com/sourabhrathourr/hun/internal/config"
	"github.com/sourabhrathourr/hun/internal/state"
)

func TestApplyPortOverridesToProject(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	st, err := state.Load()
	if err != nil {
		t.Fatalf("load state: %v", err)
	}
	ps := st.Projects["demo"]
	ps.PortOverrides = map[string]int{"web": 5180}
	st.Projects["demo"] = ps
	if err := st.Save(); err != nil {
		t.Fatalf("save state: %v", err)
	}

	proj := &config.Project{
		Name: "demo",
		Services: map[string]*config.Service{
			"web": {Cmd: "bun run dev", Port: 5173},
		},
	}

	applied, err := applyPortOverridesToProject("demo", proj)
	if err != nil {
		t.Fatalf("apply overrides: %v", err)
	}
	if applied != 1 {
		t.Fatalf("applied = %d, want 1", applied)
	}
	if proj.Services["web"].Port != 5180 {
		t.Fatalf("web port = %d, want 5180", proj.Services["web"].Port)
	}
}
