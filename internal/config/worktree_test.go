package config

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

// makeWorktree lays out a main checkout at main with a linked worktree at
// wt, the way `git worktree add` records them.
func makeWorktree(t *testing.T, main, wt, name string) {
	t.Helper()
	record := filepath.Join(main, ".git", "worktrees", name)
	if err := os.MkdirAll(record, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(wt, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(record, "gitdir"), []byte(filepath.Join(wt, ".git")+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(wt, ".git"), []byte("gitdir: "+record+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
}

func writeConfig(t *testing.T, dir, contents string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, ".hun.yml"), []byte(contents), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestWorktreeUsesMainCheckoutConfigUnlessItHasItsOwn(t *testing.T) {
	root := t.TempDir()
	main := filepath.Join(root, "otto")
	wt := filepath.Join(main, ".claude", "worktrees", "ott-1650")
	own := filepath.Join(main, ".claude", "worktrees", "ott-1651")
	makeWorktree(t, main, wt, "ott-1650")
	makeWorktree(t, main, own, "ott-1651")
	writeConfig(t, main, "name: otto\nservices:\n  web:\n    cmd: npm run dev\n    port: 3000\n")
	writeConfig(t, own, "name: otto-own\nservices:\n  web:\n    cmd: npm run dev\n    port: 3100\n")

	if got, ok := MainCheckout(wt); !ok || got != main {
		t.Fatalf("MainCheckout = %q, %v; want %q", got, ok, main)
	}
	if _, ok := MainCheckout(main); ok {
		t.Fatal("the main checkout is not a worktree")
	}
	if got := ProjectFile(wt); got != filepath.Join(main, ".hun.yml") {
		t.Fatalf("ProjectFile(worktree) = %q, want the main checkout's", got)
	}
	if !ProjectExists(wt) {
		t.Fatal("a worktree with an inherited .hun.yml has a project")
	}
	proj, err := LoadProject(wt)
	if err != nil || proj.Name != "otto" {
		t.Fatalf("LoadProject(worktree) = %+v, %v", proj, err)
	}
	proj, err = LoadProject(own)
	if err != nil || proj.Name != "otto-own" {
		t.Fatalf("a worktree's own .hun.yml should win, got %+v, %v", proj, err)
	}
	if got, want := Worktrees(main), []string{wt, own}; !reflect.DeepEqual(got, want) {
		t.Fatalf("Worktrees = %v, want %v", got, want)
	}

	// Gone worktrees aren't listed.
	if err := os.RemoveAll(own); err != nil {
		t.Fatal(err)
	}
	if got, want := Worktrees(main), []string{wt}; !reflect.DeepEqual(got, want) {
		t.Fatalf("Worktrees after removal = %v, want %v", got, want)
	}
}

func TestPlainFolderKeepsItsOwnConfigPath(t *testing.T) {
	dir := t.TempDir()
	if got := ProjectFile(dir); got != filepath.Join(dir, ".hun.yml") {
		t.Fatalf("ProjectFile = %q", got)
	}
	if ProjectExists(dir) {
		t.Fatal("no .hun.yml, no project")
	}
}
