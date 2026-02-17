package detect

import (
	"os"
	"path/filepath"
)

// PythonDetector detects Python projects.
type PythonDetector struct{}

func (d *PythonDetector) Detect(dir string) []DetectedService {
	// Check for common Python project markers
	var cmd string
	var port int

	switch {
	case fileExists(filepath.Join(dir, "manage.py")):
		cmd = "python manage.py runserver"
		port = 8000
	case fileExists(filepath.Join(dir, "app.py")):
		cmd = "python app.py"
		port = 5000
	case fileExists(filepath.Join(dir, "main.py")):
		cmd = "python main.py"
		port = 8000
	default:
		return nil
	}

	// Check for virtual environment / dependency manager
	hasRequirements := fileExists(filepath.Join(dir, "requirements.txt"))
	hasPyproject := fileExists(filepath.Join(dir, "pyproject.toml"))

	if !hasRequirements && !hasPyproject {
		return nil
	}

	name := filepath.Base(dir)
	return []DetectedService{
		{
			Name:           name,
			LogicalName:    name,
			Cmd:            cmd,
			Port:           port,
			Ready:          "listening on",
			Runtime:        "python",
			Strategy:       "local",
			Class:          "app",
			Source:         filepath.ToSlash(dir),
			Confidence:     0.7,
			PortConfidence: 0.55,
		},
	}
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
