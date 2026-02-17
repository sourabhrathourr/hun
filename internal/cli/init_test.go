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

func TestParseConfirmPromptAnswer(t *testing.T) {
	tests := []struct {
		name       string
		answer     string
		defaultYes bool
		want       bool
	}{
		{name: "empty uses default yes", answer: "", defaultYes: true, want: true},
		{name: "empty uses default no", answer: "", defaultYes: false, want: false},
		{name: "yes short", answer: "y", defaultYes: false, want: true},
		{name: "yes long", answer: " yes ", defaultYes: false, want: true},
		{name: "no short", answer: "n", defaultYes: true, want: false},
		{name: "no long", answer: "No", defaultYes: true, want: false},
		{name: "unknown falls back to default", answer: "maybe", defaultYes: true, want: true},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := parseConfirmPromptAnswer(tc.answer, tc.defaultYes)
			if got != tc.want {
				t.Fatalf("parseConfirmPromptAnswer(%q, %v) = %v, want %v", tc.answer, tc.defaultYes, got, tc.want)
			}
		})
	}
}
