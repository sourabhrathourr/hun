package config

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// ProjectFile is the .hun.yml a folder uses: its own, or, for a git
// worktree without one, its main checkout's, so an agent's worktree runs
// like the project it came from. A worktree's own file always wins.
func ProjectFile(dir string) string {
	own := filepath.Join(dir, ".hun.yml")
	if _, err := os.Stat(own); err == nil {
		return own
	}
	if main, ok := MainCheckout(dir); ok {
		inherited := filepath.Join(main, ".hun.yml")
		if _, err := os.Stat(inherited); err == nil {
			return inherited
		}
	}
	return own
}

// MainCheckout returns the main checkout of the linked git worktree at dir:
// dir/.git is a file pointing into <main>/.git/worktrees/<name>.
func MainCheckout(dir string) (string, bool) {
	data, err := os.ReadFile(filepath.Join(dir, ".git"))
	if err != nil {
		return "", false
	}
	line := strings.TrimSpace(string(data))
	gitdir, ok := strings.CutPrefix(line, "gitdir:")
	if !ok {
		return "", false
	}
	gitdir = strings.TrimSpace(gitdir)
	if !filepath.IsAbs(gitdir) {
		gitdir = filepath.Join(dir, gitdir)
	}
	gitdir = filepath.Clean(gitdir)
	// <main>/.git/worktrees/<name>
	worktrees := filepath.Dir(gitdir)
	dotGit := filepath.Dir(worktrees)
	if filepath.Base(worktrees) != "worktrees" || filepath.Base(dotGit) != ".git" {
		return "", false
	}
	return filepath.Dir(dotGit), true
}

// Worktrees lists the linked worktrees of the git checkout at dir that are
// still on disk, from its .git/worktrees records.
func Worktrees(dir string) []string {
	entries, err := os.ReadDir(filepath.Join(dir, ".git", "worktrees"))
	if err != nil {
		return nil
	}
	var paths []string
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		data, err := os.ReadFile(filepath.Join(dir, ".git", "worktrees", entry.Name(), "gitdir"))
		if err != nil {
			continue
		}
		// gitdir holds the worktree's .git file path.
		path := filepath.Dir(filepath.Clean(strings.TrimSpace(string(data))))
		if info, err := os.Stat(path); err == nil && info.IsDir() {
			paths = append(paths, path)
		}
	}
	sort.Strings(paths)
	return paths
}
