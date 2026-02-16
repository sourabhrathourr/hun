package state

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"

	"github.com/hun-sh/hun/internal/config"
)

// State represents the global hun state persisted at ~/.hun/state.json.
type State struct {
	Mode     string                  `json:"mode"`
	Projects map[string]ProjectState `json:"projects"`
	Registry map[string]string       `json:"registry"` // name → path

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
		Mode:     "focus",
		Projects: make(map[string]ProjectState),
		Registry: make(map[string]string),
		path:     path,
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

	if s.Projects == nil {
		s.Projects = make(map[string]ProjectState)
	}
	if s.Registry == nil {
		s.Registry = make(map[string]string)
	}
	return s, nil
}

// Save writes state to disk atomically.
func (s *State) Save() error {
	s.mu.Lock()
	defer s.mu.Unlock()

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
