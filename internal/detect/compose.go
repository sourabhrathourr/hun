package detect

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"
)

// ComposeDetector detects Docker Compose services.
type ComposeDetector struct{}

type composeFile struct {
	Services map[string]composeService `yaml:"services"`
}

type composeService struct {
	Image     string      `yaml:"image"`
	Ports     interface{} `yaml:"ports"`
	DependsOn interface{} `yaml:"depends_on"`
}

func (d *ComposeDetector) Detect(dir string) []DetectedService {
	composePath := findComposeFile(dir)
	if composePath == "" {
		return nil
	}

	data, err := os.ReadFile(composePath)
	if err != nil {
		return nil
	}

	var cf composeFile
	if err := yaml.Unmarshal(data, &cf); err != nil {
		return nil
	}

	names := make([]string, 0, len(cf.Services))
	for name := range cf.Services {
		names = append(names, name)
	}
	sort.Strings(names)

	services := make([]DetectedService, 0, len(names))
	for _, name := range names {
		svc := cf.Services[name]
		port := parseComposePort(svc.Ports)
		ready := guessReadyPattern(svc.Image)
		dependsOn := parseComposeDependsOn(svc.DependsOn)
		class := "app"
		if isInfraComposeService(name, svc.Image) {
			class = "infra"
		}
		services = append(services, DetectedService{
			Name:           name,
			LogicalName:    name,
			Cmd:            "docker compose up " + name,
			Port:           port,
			PortEnv:        "",
			Ready:          ready,
			DependsOn:      dependsOn,
			Runtime:        "compose",
			Strategy:       "compose",
			Class:          class,
			Source:         filepath.ToSlash(composePath),
			Confidence:     0.9,
			PortConfidence: composePortConfidence(port),
		})
	}

	return services
}

func findComposeFile(dir string) string {
	for _, name := range []string{"docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"} {
		p := filepath.Join(dir, name)
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return ""
}

func composePortConfidence(port int) float64 {
	if port <= 0 {
		return 0
	}
	return 0.95
}

func parseComposeDependsOn(raw interface{}) []string {
	switch v := raw.(type) {
	case []interface{}:
		deps := make([]string, 0, len(v))
		for _, item := range v {
			s, ok := item.(string)
			if !ok || strings.TrimSpace(s) == "" {
				continue
			}
			deps = append(deps, strings.TrimSpace(s))
		}
		sort.Strings(deps)
		return deps
	case map[string]interface{}:
		deps := make([]string, 0, len(v))
		for name := range v {
			deps = append(deps, strings.TrimSpace(name))
		}
		sort.Strings(deps)
		return deps
	default:
		return nil
	}
}

func parseComposePort(raw interface{}) int {
	ports, ok := raw.([]interface{})
	if !ok || len(ports) == 0 {
		return 0
	}
	for _, entry := range ports {
		switch v := entry.(type) {
		case string:
			if p := parseComposePortString(v); p > 0 {
				return p
			}
		case map[string]interface{}:
			if p := parseComposePortMap(v); p > 0 {
				return p
			}
		}
	}
	return 0
}

func parseComposePortMap(m map[string]interface{}) int {
	if pub, ok := m["published"]; ok {
		s := fmt.Sprintf("%v", pub)
		if p := parsePort(s); p > 0 {
			return p
		}
	}
	if host, ok := m["host_port"]; ok {
		s := fmt.Sprintf("%v", host)
		if p := parsePort(s); p > 0 {
			return p
		}
	}
	if target, ok := m["target"]; ok {
		s := fmt.Sprintf("%v", target)
		if p := parsePort(s); p > 0 {
			return p
		}
	}
	return 0
}

func parseComposePortString(raw string) int {
	s := strings.TrimSpace(raw)
	s = strings.Trim(s, `"'`)
	if idx := strings.Index(s, "/"); idx >= 0 {
		s = s[:idx]
	}
	if s == "" {
		return 0
	}
	if p := parsePort(s); p > 0 {
		return p
	}

	parts := strings.Split(s, ":")
	if len(parts) == 2 {
		return parsePort(parts[0])
	}
	if len(parts) >= 3 {
		hostIdx := len(parts) - 2
		if hostIdx >= 0 {
			if p := parsePort(parts[hostIdx]); p > 0 {
				return p
			}
		}
	}

	return 0
}

func isInfraComposeService(name, image string) bool {
	check := strings.ToLower(name + " " + image)
	for _, token := range []string{
		"postgres", "mongo", "mysql", "mariadb", "redis", "rabbitmq", "kafka", "nats", "elasticsearch", "opensearch",
		"db", "cache", "broker", "mq",
	} {
		if strings.Contains(check, token) {
			return true
		}
	}
	return false
}

func guessReadyPattern(image string) string {
	lower := strings.ToLower(image)
	switch {
	case strings.Contains(lower, "postgres"):
		return "database system is ready"
	case strings.Contains(lower, "mysql") || strings.Contains(lower, "mariadb"):
		return "ready for connections"
	case strings.Contains(lower, "redis"):
		return "Ready to accept connections"
	case strings.Contains(lower, "mongo"):
		return "Waiting for connections"
	}
	return ""
}
