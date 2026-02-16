package detect

import (
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

// ComposeDetector detects Docker Compose services.
type ComposeDetector struct{}

type composeFile struct {
	Services map[string]composeService `yaml:"services"`
}

type composeService struct {
	Image string   `yaml:"image"`
	Ports []string `yaml:"ports"`
}

func (d *ComposeDetector) Detect(dir string) []DetectedService {
	names := []string{"docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"}
	var composePath string
	for _, name := range names {
		p := filepath.Join(dir, name)
		if _, err := os.Stat(p); err == nil {
			composePath = p
			break
		}
	}
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

	var services []DetectedService
	for name, svc := range cf.Services {
		port := parseComposePort(svc.Ports)
		ready := guessReadyPattern(svc.Image)
		services = append(services, DetectedService{
			Name:  name,
			Cmd:   "docker compose up " + name,
			Port:  port,
			Ready: ready,
		})
	}
	return services
}

func parseComposePort(ports []string) int {
	if len(ports) == 0 {
		return 0
	}
	// Format: "3000:3000" or "3000"
	p := ports[0]
	parts := strings.Split(p, ":")
	if len(parts) >= 2 {
		return parsePort(parts[0])
	}
	return parsePort(p)
}

func guessReadyPattern(image string) string {
	lower := strings.ToLower(image)
	switch {
	case strings.Contains(lower, "postgres"):
		return "database system is ready"
	case strings.Contains(lower, "mysql"):
		return "ready for connections"
	case strings.Contains(lower, "redis"):
		return "Ready to accept connections"
	case strings.Contains(lower, "mongo"):
		return "Waiting for connections"
	}
	return ""
}
