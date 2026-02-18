package cli

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/sourabhrathourr/hun/internal/state"
)

func TestShouldPromptAutoOnboard(t *testing.T) {
	tests := []struct {
		name         string
		interactive  bool
		registrySize int
		want         bool
	}{
		{name: "interactive empty registry", interactive: true, registrySize: 0, want: true},
		{name: "interactive non-empty registry", interactive: true, registrySize: 1, want: false},
		{name: "non-interactive empty registry", interactive: false, registrySize: 0, want: false},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := shouldPromptAutoOnboard(tc.interactive, tc.registrySize)
			if got != tc.want {
				t.Fatalf("shouldPromptAutoOnboard(%v, %d) = %v, want %v", tc.interactive, tc.registrySize, got, tc.want)
			}
		})
	}
}

func TestResolveOnboardingPath(t *testing.T) {
	dir := t.TempDir()
	got, err := resolveOnboardingPath(dir)
	if err != nil {
		t.Fatalf("resolveOnboardingPath(%q): %v", dir, err)
	}
	if got != dir {
		t.Fatalf("resolved path = %q, want %q", got, dir)
	}
}

func TestResolveOnboardingPathExpandsHome(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	got, err := resolveOnboardingPath("~")
	if err != nil {
		t.Fatalf("resolveOnboardingPath(~): %v", err)
	}
	if got != home {
		t.Fatalf("resolved home path = %q, want %q", got, home)
	}
}

func TestResolveOnboardingPathRejectsFile(t *testing.T) {
	dir := t.TempDir()
	file := filepath.Join(dir, "note.txt")
	if err := os.WriteFile(file, []byte("x"), 0o644); err != nil {
		t.Fatalf("write file: %v", err)
	}

	if _, err := resolveOnboardingPath(file); err == nil {
		t.Fatalf("expected error for file path")
	}
}

func TestParseSelectionIndex(t *testing.T) {
	if idx, ok := parseSelectionIndex("2", 3); !ok || idx != 1 {
		t.Fatalf("parseSelectionIndex valid = (%d, %v), want (1, true)", idx, ok)
	}
	if _, ok := parseSelectionIndex("0", 3); ok {
		t.Fatalf("expected invalid for zero index")
	}
	if _, ok := parseSelectionIndex("x", 3); ok {
		t.Fatalf("expected invalid for non-number")
	}
}

func TestLooksLikeProjectDirByMarker(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "package.json"), []byte(`{"name":"x"}`), 0o644); err != nil {
		t.Fatalf("write marker: %v", err)
	}
	if !looksLikeProjectDir(dir) {
		t.Fatalf("expected marker directory to be recognized as project")
	}
}

func TestDiscoverPathSuggestionsIncludesCurrentAndCommonRoots(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	cwd := t.TempDir()
	if err := os.WriteFile(filepath.Join(cwd, "go.mod"), []byte("module x"), 0o644); err != nil {
		t.Fatalf("write go.mod: %v", err)
	}

	sideProjects := filepath.Join(home, "side-projects")
	if err := os.MkdirAll(sideProjects, 0o755); err != nil {
		t.Fatalf("mkdir side-projects: %v", err)
	}
	other := filepath.Join(sideProjects, "demo-app")
	if err := os.MkdirAll(other, 0o755); err != nil {
		t.Fatalf("mkdir demo app: %v", err)
	}
	if err := os.WriteFile(filepath.Join(other, "package.json"), []byte(`{"name":"demo"}`), 0o644); err != nil {
		t.Fatalf("write package.json: %v", err)
	}

	suggestions := discoverPathSuggestions(cwd)
	if !containsPath(suggestions, cwd) {
		t.Fatalf("expected suggestions to include cwd: %v", suggestions)
	}
	if !containsPath(suggestions, other) {
		t.Fatalf("expected suggestions to include common-root project: %v", suggestions)
	}
	if len(suggestions) > maxSuggestedProjects {
		t.Fatalf("suggestions length = %d, want <= %d", len(suggestions), maxSuggestedProjects)
	}
}

func TestDiscoverPathSuggestionsIncludesGrandparentChildren(t *testing.T) {
	base := t.TempDir()
	t.Setenv("HOME", base)
	cwd := filepath.Join(base, "team", "apps", "hun")
	if err := os.MkdirAll(cwd, 0o755); err != nil {
		t.Fatalf("mkdir cwd: %v", err)
	}
	if err := os.WriteFile(filepath.Join(cwd, "go.mod"), []byte("module hun"), 0o644); err != nil {
		t.Fatalf("write go.mod: %v", err)
	}

	grandSibling := filepath.Join(base, "team", "payments")
	if err := os.MkdirAll(grandSibling, 0o755); err != nil {
		t.Fatalf("mkdir grand sibling: %v", err)
	}
	if err := os.WriteFile(filepath.Join(grandSibling, "package.json"), []byte(`{"name":"payments"}`), 0o644); err != nil {
		t.Fatalf("write package.json: %v", err)
	}

	suggestions := discoverPathSuggestions(cwd)
	if !containsPath(suggestions, grandSibling) {
		t.Fatalf("expected suggestions to include grandparent child %q, got %v", grandSibling, suggestions)
	}
}

func TestProjectRelevanceScorePrefersCwd(t *testing.T) {
	base := t.TempDir()
	cwd := filepath.Join(base, "side-projects", "hun")
	if err := os.MkdirAll(cwd, 0o755); err != nil {
		t.Fatalf("mkdir cwd: %v", err)
	}
	sibling := filepath.Join(base, "side-projects", "other")
	if err := os.MkdirAll(sibling, 0o755); err != nil {
		t.Fatalf("mkdir sibling: %v", err)
	}
	if err := os.WriteFile(filepath.Join(sibling, "go.mod"), []byte("module other"), 0o644); err != nil {
		t.Fatalf("write sibling marker: %v", err)
	}

	cwdScore := projectRelevanceScore(cwd, cwd)
	siblingScore := projectRelevanceScore(sibling, cwd)
	if cwdScore <= siblingScore {
		t.Fatalf("expected cwd score (%d) > sibling score (%d)", cwdScore, siblingScore)
	}
}

func TestDiscoverFZFProjectCandidatesFiltersProjectLikeDirs(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	cwd := filepath.Join(home, "side-projects", "hun")
	if err := os.MkdirAll(cwd, 0o755); err != nil {
		t.Fatalf("mkdir cwd: %v", err)
	}
	if err := os.WriteFile(filepath.Join(cwd, "go.mod"), []byte("module hun"), 0o644); err != nil {
		t.Fatalf("write go.mod: %v", err)
	}

	good := filepath.Join(home, "side-projects", "api")
	if err := os.MkdirAll(good, 0o755); err != nil {
		t.Fatalf("mkdir good: %v", err)
	}
	if err := os.WriteFile(filepath.Join(good, "package.json"), []byte(`{"name":"api"}`), 0o644); err != nil {
		t.Fatalf("write package.json: %v", err)
	}

	nonProject := filepath.Join(home, "side-projects", "notes")
	if err := os.MkdirAll(nonProject, 0o755); err != nil {
		t.Fatalf("mkdir non-project: %v", err)
	}
	if err := os.WriteFile(filepath.Join(nonProject, "README.md"), []byte("notes"), 0o644); err != nil {
		t.Fatalf("write README: %v", err)
	}

	candidates := discoverFZFProjectCandidates(cwd)
	if len(candidates) == 0 {
		t.Fatalf("expected fuzzy candidates, got none")
	}
	if !containsPath(candidates, good) {
		t.Fatalf("expected fuzzy candidates to include project %q, got %v", good, candidates)
	}
	if containsPath(candidates, nonProject) {
		t.Fatalf("did not expect non-project path %q in fuzzy candidates: %v", nonProject, candidates)
	}
	if len(candidates) > maxFuzzyCandidates {
		t.Fatalf("fuzzy candidates length = %d, want <= %d", len(candidates), maxFuzzyCandidates)
	}
}

func TestOnboardProjectDirWithExistingConfig(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	projectDir := t.TempDir()
	cfg := "name: demo\nservices:\n  app:\n    cmd: echo ok\n"
	if err := os.WriteFile(filepath.Join(projectDir, ".hun.yml"), []byte(cfg), 0o644); err != nil {
		t.Fatalf("write config: %v", err)
	}

	name, err := onboardProjectDir(projectDir)
	if err != nil {
		t.Fatalf("onboardProjectDir: %v", err)
	}
	if name != "demo" {
		t.Fatalf("name = %q, want demo", name)
	}

	st, err := state.Load()
	if err != nil {
		t.Fatalf("state load: %v", err)
	}
	if got := st.Registry["demo"]; got != projectDir {
		t.Fatalf("registry[demo] = %q, want %q", got, projectDir)
	}
}

func containsPath(paths []string, target string) bool {
	for _, p := range paths {
		if p == target {
			return true
		}
	}
	return false
}

func TestOnboardProjectDirCreatesMinimalConfigWhenUndetected(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	projectDir := t.TempDir()
	name, err := onboardProjectDir(projectDir)
	if err != nil {
		t.Fatalf("onboardProjectDir: %v", err)
	}
	if name != filepath.Base(projectDir) {
		t.Fatalf("name = %q, want %q", name, filepath.Base(projectDir))
	}

	if _, err := os.Stat(filepath.Join(projectDir, ".hun.yml")); err != nil {
		t.Fatalf("expected .hun.yml to be created: %v", err)
	}
}

func TestOnboardProjectDirConflict(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	dirA := t.TempDir()
	dirB := t.TempDir()
	cfg := "name: demo\nservices:\n  app:\n    cmd: echo ok\n"
	if err := os.WriteFile(filepath.Join(dirA, ".hun.yml"), []byte(cfg), 0o644); err != nil {
		t.Fatalf("write config A: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dirB, ".hun.yml"), []byte(cfg), 0o644); err != nil {
		t.Fatalf("write config B: %v", err)
	}

	if _, err := onboardProjectDir(dirA); err != nil {
		t.Fatalf("onboard first dir: %v", err)
	}
	if _, err := onboardProjectDir(dirB); err == nil {
		t.Fatalf("expected conflict error")
	} else if !strings.Contains(err.Error(), "already registered at") {
		t.Fatalf("unexpected error: %v", err)
	}
}
