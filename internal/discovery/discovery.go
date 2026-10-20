package discovery

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/sourabhrathourr/hun/internal/config"
	"github.com/sourabhrathourr/hun/internal/state"
)

// Result describes one scan over the configured roots.
type Result struct {
	ScanDirs []string
	Projects []FoundProject // sorted by path
	Warnings []string
}

// FoundProject is a folder with a valid .hun.yml.
type FoundProject struct {
	Name string // the name: field in .hun.yml
	Path string
}

// Changes reports how Reconcile changed the registry.
type Changes struct {
	Added   []string
	Removed []string          // folders that no longer exist
	Renamed map[string]string // old key → new key
}

// Dirty reports whether the registry changed.
func (c Changes) Dirty() bool {
	return len(c.Added) > 0 || len(c.Removed) > 0 || len(c.Renamed) > 0
}

var skippedDirs = map[string]bool{
	".git":         true,
	".hg":          true,
	".svn":         true,
	".venv":        true,
	".cache":       true,
	".next":        true,
	"Library":      true,
	"build":        true,
	"dist":         true,
	"node_modules": true,
	"target":       true,
	"vendor":       true,
}

// ReconcileState scans the configured roots and applies the result to st.
// Callers own persistence. Projects marked running in st keep their key.
func ReconcileState(st *state.State) (Result, bool, error) {
	global, err := config.LoadGlobal()
	if err != nil {
		return Result{}, false, err
	}
	result, err := Scan(global)
	if err != nil {
		return result, false, err
	}
	changes := Reconcile(st, result, func(key string) bool {
		return st.Projects[key].Status == "running"
	})
	return result, changes.Dirty(), nil
}

// Reconcile applies a scan to st, keyed by folder rather than by name:
//   - projects whose folder is gone are unregistered; a missing .hun.yml alone
//     (another branch, a regenerated file) keeps the project;
//   - a folder registered twice keeps one key;
//   - a project follows a changed `name:` once busy reports it is not running
//     and the new name is free;
//   - newly found folders are registered unless the user removed them.
func Reconcile(st *state.State, result Result, busy func(key string) bool) Changes {
	changes := Changes{Renamed: make(map[string]string)}

	keys := make([]string, 0, len(st.Registry))
	for key := range st.Registry {
		keys = append(keys, key)
	}
	sort.Strings(keys)

	byPath := make(map[string][]string)
	names := make(map[string]string)
	for _, key := range keys {
		path := st.Registry[key]
		if config.ProjectFolderGone(path) {
			st.ForgetProject(key)
			changes.Removed = append(changes.Removed, key)
			continue
		}
		canonical := canonicalPath(path)
		byPath[canonical] = append(byPath[canonical], key)
		if proj, err := config.LoadProject(path); err == nil {
			names[key] = proj.Name
		}
	}

	// Earlier versions registered a renamed project a second time.
	for _, dupes := range byPath {
		if len(dupes) < 2 {
			continue
		}
		keep := dupes[0]
		for _, key := range dupes {
			if busy(key) {
				keep = key
				break
			}
			if key == names[key] {
				keep = key
			}
		}
		for _, key := range dupes {
			if key != keep && !busy(key) {
				st.ForgetProject(key)
				changes.Removed = append(changes.Removed, key)
			}
		}
	}

	for _, key := range keys {
		name := names[key]
		if name == "" || name == key || busy(key) {
			continue
		}
		if _, exists := st.Registry[key]; !exists {
			continue
		}
		if st.RenameProject(key, name) {
			changes.Renamed[key] = name
		}
	}

	for _, found := range result.Projects {
		if _, ok := st.KeyForPath(found.Path); ok || st.IsIgnored(found.Path) {
			continue
		}
		changes.Added = append(changes.Added, st.RegisterPath(found.Name, found.Path))
	}

	if st.ActiveProject == "" {
		for _, key := range keys {
			if st.Projects[key].Status == "running" {
				if _, ok := st.Registry[key]; ok {
					st.ActiveProject = key
					break
				}
			}
		}
	}
	return changes
}

func canonicalPath(path string) string {
	if resolved, err := filepath.EvalSymlinks(path); err == nil {
		return resolved
	}
	return filepath.Clean(path)
}

// Scan finds valid .hun.yml files below the configured roots.
func Scan(global *config.Global) (Result, error) {
	roots := scanDirs(global)
	result := Result{ScanDirs: roots}

	seen := make(map[string]bool)
	for _, root := range roots {
		if err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
			if err != nil {
				result.Warnings = append(result.Warnings, fmt.Sprintf("skipping %s: %v", path, err))
				if entry != nil && entry.IsDir() {
					return filepath.SkipDir
				}
				return nil
			}

			if entry.IsDir() {
				if path == root {
					return nil
				}
				if shouldSkipDir(entry.Name()) {
					return filepath.SkipDir
				}
				return nil
			}

			if entry.Name() != ".hun.yml" {
				return nil
			}

			projectDir := filepath.Clean(filepath.Dir(path))
			if seen[projectDir] {
				return nil
			}
			seen[projectDir] = true
			proj, loadErr := config.LoadProject(projectDir)
			if loadErr != nil {
				result.Warnings = append(result.Warnings, fmt.Sprintf("skipping %s: %v", path, loadErr))
				return nil
			}
			result.Projects = append(result.Projects, FoundProject{Name: proj.Name, Path: projectDir})
			return nil
		}); err != nil {
			result.Warnings = append(result.Warnings, fmt.Sprintf("scanning %s: %v", root, err))
		}
	}

	sort.Slice(result.Projects, func(i, j int) bool {
		return result.Projects[i].Path < result.Projects[j].Path
	})
	return result, nil
}

// scanDirs returns the configured scan roots, or the default developer
// folders. Folders of individually added projects are never scanned: they
// are already registered, and scanning their parents would pull in
// unrelated projects (and walk folders such as ~/Desktop or ~ itself).
func scanDirs(global *config.Global) []string {
	seen := make(map[string]bool)
	dirs := make([]string, 0)
	add := func(path string) {
		expanded := expandHome(strings.TrimSpace(path))
		if expanded == "" {
			return
		}
		abs, err := filepath.Abs(expanded)
		if err != nil {
			return
		}
		clean := filepath.Clean(abs)
		if seen[clean] {
			return
		}
		if info, err := os.Stat(clean); err != nil || !info.IsDir() {
			return
		}
		seen[clean] = true
		dirs = append(dirs, clean)
	}

	if global != nil && len(global.ScanDirs) > 0 {
		for _, dir := range global.ScanDirs {
			add(dir)
		}
		return dirs
	}
	for _, dir := range []string{"~/side-projects", "~/projects", "~/dev", "~/work"} {
		add(dir)
	}
	return dirs
}

func expandHome(path string) string {
	if path == "~" {
		if home, err := os.UserHomeDir(); err == nil {
			return home
		}
		return path
	}
	if strings.HasPrefix(path, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			return filepath.Join(home, strings.TrimPrefix(path, "~/"))
		}
	}
	return path
}

func shouldSkipDir(name string) bool {
	if skippedDirs[name] {
		return true
	}
	return strings.HasPrefix(name, ".") && name != "."
}
