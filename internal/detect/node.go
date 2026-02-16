package detect

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// NodeDetector detects Node.js projects via package.json.
type NodeDetector struct{}

type packageJSON struct {
	Name    string            `json:"name"`
	Scripts map[string]string `json:"scripts"`
}

func (d *NodeDetector) Detect(dir string) []DetectedService {
	// Check root package.json
	rootServices := d.detectPackage(dir, "")

	// Check common subdirectories for monorepos
	for _, sub := range []string{"frontend", "client", "web", "app", "backend", "server", "api"} {
		subDir := filepath.Join(dir, sub)
		if info, err := os.Stat(subDir); err == nil && info.IsDir() {
			subServices := d.detectPackage(subDir, sub)
			rootServices = append(rootServices, subServices...)
		}
	}

	return rootServices
}

func (d *NodeDetector) detectPackage(dir, prefix string) []DetectedService {
	pkgPath := filepath.Join(dir, "package.json")
	data, err := os.ReadFile(pkgPath)
	if err != nil {
		return nil
	}

	var pkg packageJSON
	if err := json.Unmarshal(data, &pkg); err != nil {
		return nil
	}

	var services []DetectedService

	// Detect dev script
	devCmd := ""
	for _, script := range []string{"dev", "start:dev", "serve"} {
		if _, ok := pkg.Scripts[script]; ok {
			devCmd = script
			break
		}
	}

	if devCmd == "" {
		if _, ok := pkg.Scripts["start"]; ok {
			devCmd = "start"
		}
	}

	if devCmd == "" {
		return nil
	}

	runner := detectPackageManager(dir)
	name := inferServiceName(prefix, pkg.Name, dir)
	port := guessNodePort(pkg.Scripts[devCmd])

	svc := DetectedService{
		Name:    name,
		Cmd:     runner + " run " + devCmd,
		Port:    port,
		PortEnv: "PORT",
		Ready:   guessNodeReady(name),
	}
	if prefix != "" {
		svc.Cwd = "./" + prefix
	}

	services = append(services, svc)
	return services
}

func detectPackageManager(dir string) string {
	if _, err := os.Stat(filepath.Join(dir, "bun.lockb")); err == nil {
		return "bun"
	}
	if _, err := os.Stat(filepath.Join(dir, "pnpm-lock.yaml")); err == nil {
		return "pnpm"
	}
	if _, err := os.Stat(filepath.Join(dir, "yarn.lock")); err == nil {
		return "yarn"
	}
	return "npm"
}

func inferServiceName(prefix, pkgName, dir string) string {
	if prefix != "" {
		return prefix
	}
	if pkgName != "" {
		// Strip scope
		if idx := strings.LastIndex(pkgName, "/"); idx >= 0 {
			pkgName = pkgName[idx+1:]
		}
		return pkgName
	}
	return filepath.Base(dir)
}

func guessNodePort(script string) int {
	// Look for common port patterns in script content
	patterns := []string{"--port ", "-p ", "PORT="}
	for _, p := range patterns {
		if idx := strings.Index(script, p); idx >= 0 {
			rest := script[idx+len(p):]
			numStr := ""
			for _, c := range rest {
				if c >= '0' && c <= '9' {
					numStr += string(c)
				} else {
					break
				}
			}
			if port := parsePort(numStr); port > 0 {
				return port
			}
		}
	}
	return 3000 // default for Node.js
}

func guessNodeReady(name string) string {
	lower := strings.ToLower(name)
	switch {
	case strings.Contains(lower, "frontend") || strings.Contains(lower, "client") || strings.Contains(lower, "web"):
		return "compiled successfully"
	case strings.Contains(lower, "backend") || strings.Contains(lower, "server") || strings.Contains(lower, "api"):
		return "listening on"
	}
	return "ready"
}

func parsePort(s string) int {
	s = strings.TrimSpace(s)
	n, err := strconv.Atoi(s)
	if err != nil {
		return 0
	}
	if n > 0 && n < 65536 {
		return n
	}
	return 0
}
