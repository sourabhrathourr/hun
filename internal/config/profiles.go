package config

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"
)

// AllServicesProfile names the built-in profile that runs every service. A
// profile in .hun.yml can also use it as its value: `full: all`.
const AllServicesProfile = "all"

// Profile is a named set of services to run together. Services lists the
// services you intend to work on; their depends_on are added when the
// profile runs.
type Profile struct {
	Name     string
	All      bool
	Services []string
}

// Profiles keeps the order profiles are written in, so menus match the file.
type Profiles []Profile

func (p *Profiles) UnmarshalYAML(node *yaml.Node) error {
	if node.Kind != yaml.MappingNode {
		return fmt.Errorf("profiles must map profile names to service lists")
	}
	profiles := make(Profiles, 0, len(node.Content)/2)
	for i := 0; i+1 < len(node.Content); i += 2 {
		name := node.Content[i].Value
		value := node.Content[i+1]
		profile := Profile{Name: name}
		switch value.Kind {
		case yaml.ScalarNode:
			if strings.TrimSpace(value.Value) != AllServicesProfile {
				return fmt.Errorf("profile %q must be a list of services or %q", name, AllServicesProfile)
			}
			profile.All = true
		case yaml.SequenceNode:
			if err := value.Decode(&profile.Services); err != nil {
				return fmt.Errorf("profile %q: %w", name, err)
			}
		default:
			return fmt.Errorf("profile %q must be a list of services or %q", name, AllServicesProfile)
		}
		profiles = append(profiles, profile)
	}
	*p = profiles
	return nil
}

func (p Profiles) MarshalYAML() (interface{}, error) {
	node := &yaml.Node{Kind: yaml.MappingNode}
	for _, profile := range p {
		node.Content = append(node.Content,
			&yaml.Node{Kind: yaml.ScalarNode, Value: profile.Name},
			profileValueNode(profile),
		)
	}
	return node, nil
}

func profileValueNode(profile Profile) *yaml.Node {
	if profile.All {
		return &yaml.Node{Kind: yaml.ScalarNode, Value: AllServicesProfile}
	}
	value := &yaml.Node{Kind: yaml.SequenceNode, Style: yaml.FlowStyle}
	for _, service := range profile.Services {
		value.Content = append(value.Content, &yaml.Node{Kind: yaml.ScalarNode, Value: service})
	}
	return value
}

// Profile returns the profile named name.
func (p *Project) Profile(name string) (Profile, bool) {
	for _, profile := range p.Profiles {
		if profile.Name == name {
			return profile, true
		}
	}
	return Profile{}, false
}

// ProfileTargets returns the services a profile asks for, before their
// dependencies. The empty name and "all" mean every service.
func (p *Project) ProfileTargets(name string) ([]string, error) {
	if name == "" || name == AllServicesProfile {
		return sortedServiceNames(p), nil
	}
	profile, ok := p.Profile(name)
	if !ok {
		return nil, fmt.Errorf("profile %q not found in %s", name, p.Name)
	}
	if profile.All {
		return sortedServiceNames(p), nil
	}
	return append([]string(nil), profile.Services...), nil
}

// ResolveProfile returns every service a profile runs: its own services and
// everything they depend on, sorted by name.
func (p *Project) ResolveProfile(name string) ([]string, error) {
	targets, err := p.ProfileTargets(name)
	if err != nil {
		return nil, err
	}
	seen := make(map[string]bool)
	var visit func(service string)
	visit = func(service string) {
		if seen[service] {
			return
		}
		seen[service] = true
		if svc := p.Services[service]; svc != nil {
			for _, dep := range svc.DependsOn {
				visit(dep)
			}
		}
	}
	for _, target := range targets {
		visit(target)
	}
	resolved := make([]string, 0, len(seen))
	for service := range seen {
		resolved = append(resolved, service)
	}
	sort.Strings(resolved)
	return resolved, nil
}

func validateProfiles(proj *Project) error {
	seen := make(map[string]bool)
	for _, profile := range proj.Profiles {
		name := strings.TrimSpace(profile.Name)
		switch {
		case name == "":
			return fmt.Errorf("profile names cannot be empty")
		case name == AllServicesProfile:
			return fmt.Errorf("profile name %q is reserved for running every service", AllServicesProfile)
		case seen[name]:
			return fmt.Errorf("profile %q is defined twice", name)
		}
		seen[name] = true
		if profile.All {
			continue
		}
		if len(profile.Services) == 0 {
			return fmt.Errorf("profile %q lists no services", name)
		}
		for _, service := range profile.Services {
			if _, ok := proj.Services[service]; !ok {
				return fmt.Errorf("profile %q references unknown service %q", name, service)
			}
		}
	}
	return nil
}

// SaveProfile adds or replaces a profile in dir's .hun.yml. Only the
// profiles section changes; comments elsewhere in the file are kept.
func SaveProfile(dir, name string, services []string) error {
	name = strings.TrimSpace(name)
	path := filepath.Join(dir, ".hun.yml")
	data, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("reading %s: %w", path, err)
	}
	var doc yaml.Node
	if err := yaml.Unmarshal(data, &doc); err != nil {
		return fmt.Errorf("parsing %s: %w", path, err)
	}
	if len(doc.Content) == 0 || doc.Content[0].Kind != yaml.MappingNode {
		return fmt.Errorf("%s is not a mapping", path)
	}
	root := doc.Content[0]

	profiles := mappingValue(root, "profiles")
	if profiles == nil {
		profiles = &yaml.Node{Kind: yaml.MappingNode}
		root.Content = append(root.Content, &yaml.Node{Kind: yaml.ScalarNode, Value: "profiles"}, profiles)
	}
	value := profileValueNode(Profile{Name: name, Services: services})
	if existing := mappingValue(profiles, name); existing != nil {
		*existing = *value
	} else {
		profiles.Content = append(profiles.Content, &yaml.Node{Kind: yaml.ScalarNode, Value: name}, value)
	}

	var out bytes.Buffer
	encoder := yaml.NewEncoder(&out)
	encoder.SetIndent(detectIndent(data))
	if err := encoder.Encode(&doc); err != nil {
		return fmt.Errorf("encoding %s: %w", path, err)
	}
	_ = encoder.Close()

	// Refuse to write a file Hun could not load back.
	var check Project
	if err := yaml.Unmarshal(out.Bytes(), &check); err != nil {
		return fmt.Errorf("saving profile %q: %w", name, err)
	}
	if err := validateProject(&check); err != nil {
		return fmt.Errorf("saving profile %q: %w", name, err)
	}
	return os.WriteFile(path, out.Bytes(), 0o644)
}

func mappingValue(node *yaml.Node, key string) *yaml.Node {
	for i := 0; i+1 < len(node.Content); i += 2 {
		if node.Content[i].Value == key {
			return node.Content[i+1]
		}
	}
	return nil
}

// detectIndent keeps a file's own indentation when it is rewritten.
func detectIndent(data []byte) int {
	for _, line := range strings.Split(string(data), "\n") {
		trimmed := strings.TrimLeft(line, " ")
		if trimmed == "" || strings.HasPrefix(trimmed, "#") || len(trimmed) == len(line) {
			continue
		}
		if indent := len(line) - len(trimmed); indent >= 2 && indent <= 8 {
			return indent
		}
	}
	return 2
}

func sortedServiceNames(p *Project) []string {
	names := make([]string, 0, len(p.Services))
	for name := range p.Services {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}
