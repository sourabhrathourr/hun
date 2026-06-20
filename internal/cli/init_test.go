package cli

import (
	"os"
	"path/filepath"
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

func TestPrepareProjectFromDetectionRequiresApprovalWhenNonInteractive(t *testing.T) {
	dir := t.TempDir()
	if err := writeFile(t, filepath.Join(dir, "package.json"), `{"scripts":{"dev":"vite --host 0.0.0.0"}}`); err != nil {
		t.Fatalf("write package: %v", err)
	}

	_, _, err := prepareProjectFromDetection("demo", dir, "hybrid", false, false)
	if err == nil {
		t.Fatalf("expected non-interactive detection to require approval")
	}
}

func TestPrepareProjectFromDetectionRequiresApprovalForMinimalConfig(t *testing.T) {
	dir := t.TempDir()

	_, _, err := prepareProjectFromDetection("demo", dir, "hybrid", false, false)
	if err == nil {
		t.Fatalf("expected non-interactive minimal config generation to require approval")
	}
}

func TestPrepareProjectFromDetectionAllowsExplicitYes(t *testing.T) {
	dir := t.TempDir()
	if err := writeFile(t, filepath.Join(dir, "package.json"), `{"scripts":{"dev":"vite --host 0.0.0.0"}}`); err != nil {
		t.Fatalf("write package: %v", err)
	}

	proj, aborted, err := prepareProjectFromDetection("demo", dir, "hybrid", false, true)
	if err != nil {
		t.Fatalf("prepare: %v", err)
	}
	if aborted {
		t.Fatalf("unexpected abort")
	}
	if len(proj.Services) == 0 {
		t.Fatalf("expected detected services")
	}
}

func TestPrepareProjectFromDetectionAllowsExplicitYesForMinimalConfig(t *testing.T) {
	dir := t.TempDir()

	proj, aborted, err := prepareProjectFromDetection("demo", dir, "hybrid", false, true)
	if err != nil {
		t.Fatalf("prepare: %v", err)
	}
	if aborted {
		t.Fatalf("unexpected abort")
	}
	if got := proj.Services["app"].Cmd; got != "echo 'replace with your command'" {
		t.Fatalf("app cmd = %q", got)
	}
}

func TestInitNoRegisterWritesConfigWithoutStateRegistration(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	dir := t.TempDir()
	chdir(t, dir)
	if err := writeFile(t, filepath.Join(dir, "package.json"), `{"scripts":{"dev":"vite --host 0.0.0.0"}}`); err != nil {
		t.Fatalf("write package: %v", err)
	}

	t.Cleanup(func() {
		rootCmd.SetArgs(nil)
		rootCmd.SetOut(nil)
		rootCmd.SetErr(nil)
	})
	rootCmd.SetArgs([]string{"init", "--name", "demo", "--profile", "hybrid", "--yes", "--no-register"})

	if err := rootCmd.Execute(); err != nil {
		t.Fatalf("execute init: %v", err)
	}
	if !config.ProjectExists(dir) {
		t.Fatalf("expected .hun.yml to be written")
	}
	st, err := state.Load()
	if err != nil {
		t.Fatalf("load state: %v", err)
	}
	if st.IsRegistered("demo") {
		t.Fatalf("project should not be registered when --no-register is set")
	}
}

func writeFile(t *testing.T, path string, contents string) error {
	t.Helper()
	return os.WriteFile(path, []byte(contents), 0o644)
}

func chdir(t *testing.T, dir string) {
	t.Helper()

	previous, err := os.Getwd()
	if err != nil {
		t.Fatalf("get cwd: %v", err)
	}
	if err := os.Chdir(dir); err != nil {
		t.Fatalf("chdir %q: %v", dir, err)
	}
	t.Cleanup(func() {
		if err := os.Chdir(previous); err != nil {
			t.Fatalf("restore cwd: %v", err)
		}
	})
}
