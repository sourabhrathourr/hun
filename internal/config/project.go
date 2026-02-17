package config

import (
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

// LoadProject reads and validates a .hun.yml file from the given directory.
func LoadProject(dir string) (*Project, error) {
	path := filepath.Join(dir, ".hun.yml")
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading %s: %w", path, err)
	}

	var proj Project
	if err := yaml.Unmarshal(data, &proj); err != nil {
		return nil, fmt.Errorf("parsing %s: %w", path, err)
	}

	if err := validateProject(&proj); err != nil {
		return nil, fmt.Errorf("validating %s: %w", path, err)
	}

	return &proj, nil
}

// ProjectExists checks if a .hun.yml file exists in the given directory.
func ProjectExists(dir string) bool {
	path := filepath.Join(dir, ".hun.yml")
	_, err := os.Stat(path)
	return err == nil
}

// WriteProject writes a Project config to .hun.yml in the given directory.
func WriteProject(dir string, proj *Project) error {
	path := filepath.Join(dir, ".hun.yml")
	data, err := yaml.Marshal(proj)
	if err != nil {
		return fmt.Errorf("marshaling config: %w", err)
	}
	if err := os.WriteFile(path, data, 0644); err != nil {
		return fmt.Errorf("writing %s: %w", path, err)
	}
	return nil
}

func validateProject(proj *Project) error {
	if proj.Name == "" {
		return fmt.Errorf("project name is required")
	}
	if proj.Detect.Profile != "" {
		switch proj.Detect.Profile {
		case "local", "compose", "hybrid":
		default:
			return fmt.Errorf("detect.profile must be one of local|compose|hybrid")
		}
	}
	if len(proj.Services) == 0 {
		return fmt.Errorf("at least one service is required")
	}
	for name, svc := range proj.Services {
		if svc.Cmd == "" {
			return fmt.Errorf("service %q: cmd is required", name)
		}
		if svc.Restart != "" && svc.Restart != "on_failure" {
			return fmt.Errorf("service %q: restart must be \"on_failure\" or empty", name)
		}
		for _, dep := range svc.DependsOn {
			if _, ok := proj.Services[dep]; !ok {
				return fmt.Errorf("service %q: depends_on references unknown service %q", name, dep)
			}
		}
	}
	if err := validateNoCycles(proj); err != nil {
		return err
	}
	return nil
}

func validateNoCycles(proj *Project) error {
	visited := make(map[string]int) // 0=unvisited, 1=in-progress, 2=done
	var visit func(name string) error
	visit = func(name string) error {
		if visited[name] == 1 {
			return fmt.Errorf("dependency cycle detected involving service %q", name)
		}
		if visited[name] == 2 {
			return nil
		}
		visited[name] = 1
		for _, dep := range proj.Services[name].DependsOn {
			if err := visit(dep); err != nil {
				return err
			}
		}
		visited[name] = 2
		return nil
	}
	for name := range proj.Services {
		if err := visit(name); err != nil {
			return err
		}
	}
	return nil
}
