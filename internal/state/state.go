package state

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"

	"github.com/sourabhrathourr/hun/internal/config"
)

const CurrentSchemaVersion = 2

// State represents the global hun state persisted at ~/.hun/state.json.
type State struct {
	SchemaVersion int                     `json:"schema_version,omitempty"`
	Mode          string                  `json:"mode"`
	ActiveProject string                  `json:"active_project,omitempty"`
	Projects      map[string]ProjectState `json:"projects"`
	Registry      map[string]string       `json:"registry"` // project key → path
	// Ignored lists folders the user removed, so discovery leaves them out.
	Ignored []string `json:"ignored,omitempty"`

	mu   sync.Mutex `json:"-"`
	path string     `json:"-"`
}

// ProjectState holds runtime state for a single project.
type ProjectState struct {
	Status    string                  `json:"status"`
	Offset    int                     `json:"offset"`
	Path      string                  `json:"path"`
	Services  map[string]ServiceState `json:"services"`
	GitBranch string                  `json:"git_branch"`
	LastNote  string                  `json:"last_note"`
	StartedAt string                  `json:"started_at"`
	IconPath  string                  `json:"icon_path,omitempty"`
	// Profile is the profile this project last ran; empty means every
	// service. It is kept while the project is stopped so Run repeats it.
	Profile string `json:"profile,omitempty"`
}

// ServiceState holds runtime state for a single service.
type ServiceState struct {
	PID    int    `json:"pid"`
	Port   int    `json:"port"`
	Status string `json:"status"`
}

// Load reads state from ~/.hun/state.json, returning empty state if not found.
func Load() (*State, error) {
	dir, err := config.HunDir()
	if err != nil {
		return nil, err
	}

	path := filepath.Join(dir, "state.json")
	s := &State{
		SchemaVersion: CurrentSchemaVersion,
		Mode:          "focus",
		Projects:      make(map[string]ProjectState),
		Registry:      make(map[string]string),
		path:          path,
	}

	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return s, nil
		}
		return nil, fmt.Errorf("reading state: %w", err)
	}

	if err := json.Unmarshal(data, s); err != nil {
		return nil, fmt.Errorf("parsing state: %w", err)
	}
	s.path = path

	if s.SchemaVersion == 0 {
		s.SchemaVersion = CurrentSchemaVersion
	}
	if s.Mode == "" {
		s.Mode = "focus"
	}
	if s.Projects == nil {
		s.Projects = make(map[string]ProjectState)
	}
	if s.Registry == nil {
		s.Registry = make(map[string]string)
	}
	if s.ActiveProject == "" {
		for name, ps := range s.Projects {
			if ps.Status == "running" {
				s.ActiveProject = name
				break
			}
		}
	}

	if pruneStaleRegistryEntries(s) {
		if err := s.Save(); err != nil {
			return nil, fmt.Errorf("syncing state registry: %w", err)
		}
	}
	return s, nil
}

// Save writes state to disk atomically.
func (s *State) Save() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.SchemaVersion = CurrentSchemaVersion
	if s.Mode == "" {
		s.Mode = "focus"
	}

	data, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return fmt.Errorf("marshaling state: %w", err)
	}

	tmpPath := s.path + ".tmp"
	if err := os.WriteFile(tmpPath, data, 0644); err != nil {
		return fmt.Errorf("writing state: %w", err)
	}
	if err := os.Rename(tmpPath, s.path); err != nil {
		return fmt.Errorf("renaming state: %w", err)
	}
	return nil
}

// Register adds a project name → path mapping.
func (s *State) Register(name, path string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.Registry[name] = path
}

// Unregister removes a project from the registry and projects.
func (s *State) Unregister(name string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.Registry, name)
	delete(s.Projects, name)
}

// IsRegistered checks if a project name is already in the registry.
func (s *State) IsRegistered(name string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, ok := s.Registry[name]
	return ok
}

func pruneStaleRegistryEntries(s *State) bool {
	if s == nil {
		return false
	}

	dirty := false
	for name, path := range s.Registry {
		if config.ProjectFolderGone(path) {
			delete(s.Registry, name)
			delete(s.Projects, name)
			if s.ActiveProject == name {
				s.ActiveProject = ""
			}
			dirty = true
		}
	}

	if s.ActiveProject != "" {
		if _, ok := s.Registry[s.ActiveProject]; !ok {
			s.ActiveProject = ""
			dirty = true
		}
	}

	if s.ActiveProject == "" {
		for name, ps := range s.Projects {
			if ps.Status == "running" {
				if _, ok := s.Registry[name]; ok {
					s.ActiveProject = name
					break
				}
			}
		}
	}

	return dirty
}

// KeyForPath returns the key a folder is registered under.
func (s *State) KeyForPath(path string) (string, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.keyForPathLocked(path)
}

func (s *State) keyForPathLocked(path string) (string, bool) {
	keys := make([]string, 0, len(s.Registry))
	for key := range s.Registry {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		if SamePath(s.Registry[key], path) {
			return key, true
		}
	}
	return "", false
}

// RegisterPath registers a folder and returns its key. A folder that is
// already registered keeps its key. Otherwise the key is name, or a variant
// derived from the folder when another folder already uses name, so clones,
// worktrees and same-named folders can all be added. Registering a folder also
// undoes an earlier removal of it.
func (s *State) RegisterPath(name, path string) string {
	s.mu.Lock()
	defer s.mu.Unlock()
	path = filepath.Clean(path)
	s.unignoreLocked(path)
	if key, ok := s.keyForPathLocked(path); ok {
		return key
	}
	key := UniqueKey(name, path, func(candidate string) bool {
		_, taken := s.Registry[candidate]
		return taken
	})
	s.Registry[key] = path
	ps := s.Projects[key]
	if ps.Path == "" {
		ps.Path = path
	}
	s.Projects[key] = ps
	return key
}

// RemoveProject unregisters key and remembers its folder so discovery does
// not add it back. It returns the folder.
func (s *State) RemoveProject(key string) (string, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	path, ok := s.Registry[key]
	if !ok {
		return "", false
	}
	s.dropLocked(key)
	s.unignoreLocked(path)
	s.Ignored = append(s.Ignored, filepath.Clean(path))
	sort.Strings(s.Ignored)
	return path, true
}

// ForgetProject unregisters key without remembering its folder, for
// projects whose folder is gone or that duplicate another registration.
func (s *State) ForgetProject(key string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.dropLocked(key)
}

// RenameProject moves a registration and its saved state to newKey.
func (s *State) RenameProject(oldKey, newKey string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	path, ok := s.Registry[oldKey]
	if !ok || oldKey == newKey {
		return false
	}
	if _, taken := s.Registry[newKey]; taken {
		return false
	}
	delete(s.Registry, oldKey)
	s.Registry[newKey] = path
	if ps, ok := s.Projects[oldKey]; ok {
		delete(s.Projects, oldKey)
		s.Projects[newKey] = ps
	}
	if s.ActiveProject == oldKey {
		s.ActiveProject = newKey
	}
	return true
}

// IsIgnored reports whether the user removed this folder from Hun.
func (s *State) IsIgnored(path string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, ignored := range s.Ignored {
		if SamePath(ignored, path) {
			return true
		}
	}
	return false
}

func (s *State) unignoreLocked(path string) {
	kept := s.Ignored[:0]
	for _, ignored := range s.Ignored {
		if !SamePath(ignored, path) {
			kept = append(kept, ignored)
		}
	}
	s.Ignored = kept
}

func (s *State) dropLocked(key string) {
	delete(s.Registry, key)
	delete(s.Projects, key)
	if s.ActiveProject == key {
		s.ActiveProject = ""
	}
}

// UniqueKey picks a project key for a folder: name when it is free, then the
// folder's own name, then "<parent>-<name>", then numbered variants.
func UniqueKey(name, path string, taken func(string) bool) string {
	name = sanitizeKey(name)
	if name == "" {
		name = sanitizeKey(filepath.Base(path))
	}
	base := sanitizeKey(filepath.Base(path))
	parent := sanitizeKey(filepath.Base(filepath.Dir(path)))
	candidates := []string{name}
	if base != "" && base != name {
		candidates = append(candidates, base)
	}
	if parent != "" && parent != "." && parent != string(filepath.Separator) {
		candidates = append(candidates, parent+"-"+name)
	}
	for _, candidate := range candidates {
		if candidate != "" && !taken(candidate) {
			return candidate
		}
	}
	for i := 2; ; i++ {
		candidate := name + "-" + strconv.Itoa(i)
		if !taken(candidate) {
			return candidate
		}
	}
}

// sanitizeKey keeps keys usable in `hun run <project>:<service>`.
func sanitizeKey(name string) string {
	name = strings.TrimSpace(name)
	return strings.NewReplacer(":", "-", "/", "-").Replace(name)
}

// SamePath reports whether two paths name the same folder, resolving
// symlinks such as /var → /private/var.
func SamePath(a, b string) bool {
	if a == "" || b == "" {
		return false
	}
	a, b = filepath.Clean(a), filepath.Clean(b)
	if a == b {
		return true
	}
	ra, errA := filepath.EvalSymlinks(a)
	rb, errB := filepath.EvalSymlinks(b)
	return errA == nil && errB == nil && ra == rb
}
