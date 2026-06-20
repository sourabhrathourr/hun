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

// Result describes one reconciliation pass over configured scan roots.
type Result struct {
	ScanDirs []string
	Projects map[string]string // project name -> project directory
	Warnings []string
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

// ReconcileState discovers valid .hun.yml projects and mutates st's registry.
// Callers own persistence and any runtime side effects such as stopping removed
// projects before saving.
func ReconcileState(st *state.State) (Result, bool, error) {
	global, err := config.LoadGlobal()
	if err != nil {
		return Result{}, false, err
	}
	result, err := Scan(global, st.Registry)
	if err != nil {
		return result, false, err
	}

	dirty := false
	for name, path := range st.Registry {
		if path == "" || !config.ProjectExists(path) {
			delete(st.Registry, name)
			delete(st.Projects, name)
			if st.ActiveProject == name {
				st.ActiveProject = ""
			}
			dirty = true
		}
	}

	names := make([]string, 0, len(result.Projects))
	for name := range result.Projects {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		path := result.Projects[name]
		if current, ok := st.Registry[name]; ok && current != "" && config.ProjectExists(current) {
			continue
		}
		st.Registry[name] = path
		dirty = true
	}

	if st.ActiveProject == "" {
		for name, ps := range st.Projects {
			if ps.Status == "running" {
				if _, ok := st.Registry[name]; ok {
					st.ActiveProject = name
					break
				}
			}
		}
	}

	return result, dirty, nil
}

// Scan finds valid .hun.yml files below configured roots.
func Scan(global *config.Global, registry map[string]string) (Result, error) {
	roots := scanDirs(global, registry)
	result := Result{
		ScanDirs: roots,
		Projects: make(map[string]string),
	}

	candidates := make(map[string][]string)
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

			projectDir := filepath.Dir(path)
			proj, loadErr := config.LoadProject(projectDir)
			if loadErr != nil {
				result.Warnings = append(result.Warnings, fmt.Sprintf("skipping %s: %v", path, loadErr))
				return nil
			}
			candidates[proj.Name] = append(candidates[proj.Name], projectDir)
			return nil
		}); err != nil {
			result.Warnings = append(result.Warnings, fmt.Sprintf("scanning %s: %v", root, err))
		}
	}

	names := make([]string, 0, len(candidates))
	for name := range candidates {
		names = append(names, name)
	}
	sort.Strings(names)

	for _, name := range names {
		paths := uniqueSortedPaths(candidates[name])
		if len(paths) == 0 {
			continue
		}

		chosen := paths[0]
		if current, ok := registry[name]; ok && containsPath(paths, current) {
			chosen = current
		}
		result.Projects[name] = chosen

		for _, path := range paths {
			if path == chosen {
				continue
			}
			result.Warnings = append(result.Warnings, fmt.Sprintf("project %q also found at %s; using %s", name, path, chosen))
		}
	}

	return result, nil
}

func scanDirs(global *config.Global, registry map[string]string) []string {
	seen := make(map[string]bool)
	add := func(path string, requireExists bool, dirs *[]string) {
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
		if requireExists {
			info, err := os.Stat(clean)
			if err != nil || !info.IsDir() {
				return
			}
		}
		seen[clean] = true
		*dirs = append(*dirs, clean)
	}

	dirs := make([]string, 0)
	if global != nil && len(global.ScanDirs) > 0 {
		for _, dir := range global.ScanDirs {
			add(dir, true, &dirs)
		}
		return dirs
	}

	for _, dir := range []string{"~/side-projects", "~/projects", "~/dev", "~/work"} {
		add(dir, true, &dirs)
	}

	registryPaths := make([]string, 0, len(registry))
	for _, path := range registry {
		if path != "" {
			registryPaths = append(registryPaths, path)
		}
	}
	sort.Strings(registryPaths)
	for _, path := range registryPaths {
		add(filepath.Dir(path), true, &dirs)
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

func uniqueSortedPaths(paths []string) []string {
	seen := make(map[string]bool, len(paths))
	out := make([]string, 0, len(paths))
	for _, path := range paths {
		clean := filepath.Clean(path)
		if seen[clean] {
			continue
		}
		seen[clean] = true
		out = append(out, clean)
	}
	sort.Strings(out)
	return out
}

func containsPath(paths []string, target string) bool {
	clean := filepath.Clean(target)
	for _, path := range paths {
		if filepath.Clean(path) == clean {
			return true
		}
	}
	return false
}
