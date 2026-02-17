package detect

import (
	"os"
	"path/filepath"
	"strings"
)

// GoDetector detects Go projects via go.mod.
type GoDetector struct{}

func (d *GoDetector) Detect(dir string) []DetectedService {
	modPath := filepath.Join(dir, "go.mod")
	if _, err := os.Stat(modPath); err != nil {
		return nil
	}

	// Check for main.go or cmd/ directory
	mainCmd := ""
	if _, err := os.Stat(filepath.Join(dir, "main.go")); err == nil {
		mainCmd = "go run ."
	} else if entries, err := os.ReadDir(filepath.Join(dir, "cmd")); err == nil {
		for _, e := range entries {
			if e.IsDir() {
				mainCmd = "go run ./cmd/" + e.Name()
				break
			}
		}
	}

	if mainCmd == "" {
		return nil
	}

	name := filepath.Base(dir)
	data, _ := os.ReadFile(modPath)
	if lines := strings.Split(string(data), "\n"); len(lines) > 0 {
		modLine := strings.TrimPrefix(lines[0], "module ")
		modLine = strings.TrimSpace(modLine)
		if parts := strings.Split(modLine, "/"); len(parts) > 0 {
			name = parts[len(parts)-1]
		}
	}

	return []DetectedService{
		{
			Name:           name,
			LogicalName:    name,
			Cmd:            mainCmd,
			Port:           8080,
			Ready:          "listening on",
			Runtime:        "go",
			Strategy:       "local",
			Class:          "app",
			Source:         filepath.ToSlash(modPath),
			Confidence:     0.7,
			PortConfidence: 0.35,
		},
	}
}
