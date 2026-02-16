package detect

// DetectedService represents a service found by auto-detection.
type DetectedService struct {
	Name      string
	Cmd       string
	Cwd       string
	Port      int
	PortEnv   string
	Ready     string
	DependsOn []string
}

// Result holds all detected services for a directory.
type Result struct {
	Services []DetectedService
}

// Detector is an interface for project type detectors.
type Detector interface {
	Detect(dir string) []DetectedService
}

// Run executes all detectors against a directory and returns combined results.
func Run(dir string) Result {
	detectors := []Detector{
		&ComposeDetector{},
		&NodeDetector{},
		&GoDetector{},
		&PythonDetector{},
	}

	var result Result
	for _, d := range detectors {
		services := d.Detect(dir)
		result.Services = append(result.Services, services...)
	}
	return result
}
