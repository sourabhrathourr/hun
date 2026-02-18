package cli

import (
	"fmt"

	"github.com/sourabhrathourr/hun/internal/config"
	"github.com/sourabhrathourr/hun/internal/detect"
)

// prepareProjectFromDetection runs service detection and returns a generated project config.
// If the user declines generation, aborted is true and err is nil.
func prepareProjectFromDetection(name, dir, requestedProfile string, reconfigure bool) (proj *config.Project, aborted bool, err error) {
	if requestedProfile != "" {
		normalized := detect.NormalizeProfile(requestedProfile)
		if normalized == "" {
			return nil, false, fmt.Errorf("invalid --profile %q (expected local|compose|hybrid)", requestedProfile)
		}
		requestedProfile = normalized
	}

	analysis := detect.Analyze(dir)
	profile := requestedProfile
	if profile == "" {
		profile = detect.ProfileHybrid
		if len(analysis.Conflicts) > 0 && isInteractiveTerminal() {
			selected, selectErr := promptProfileSelection(analysis.Conflicts)
			if selectErr != nil {
				return nil, false, selectErr
			}
			profile = selected
		}
	}

	result := detect.Resolve(analysis, profile)
	if len(result.Services) == 0 {
		fmt.Println("No project structure detected.")
		fmt.Println("Creating minimal .hun.yml...")
		return &config.Project{
			Name: name,
			Services: map[string]*config.Service{
				"app": {Cmd: "echo 'replace with your command'"},
			},
			Detect: config.DetectConfig{Version: "v2", Profile: result.Profile},
		}, false, nil
	}

	printDetectionSummary(result)

	question := "Create .hun.yml with these services? [Y/n] "
	if reconfigure {
		question = "Rewrite .hun.yml with these services? [Y/n] "
	}
	ok, confirmErr := confirmPrompt(question)
	if confirmErr != nil {
		return nil, false, confirmErr
	}
	if !ok {
		return nil, true, nil
	}

	return detectedToProject(name, result), false, nil
}

func printDetectionSummary(result detect.Result) {
	fmt.Println("Detected project structure:")
	fmt.Println()
	for _, svc := range result.Services {
		port := ""
		if svc.Port > 0 {
			port = fmt.Sprintf(" (port %d)", svc.Port)
		}
		meta := ""
		if svc.Strategy != "" {
			meta = fmt.Sprintf(" [%s]", svc.Strategy)
		}
		fmt.Printf("  %s %s%s%s\n", checkmark(), svc.Name, port, meta)
		fmt.Printf("    -> %s\n", svc.Cmd)
		fmt.Println()
	}

	if len(result.Conflicts) > 0 {
		fmt.Printf("Using profile: %s\n", result.Profile)
		fmt.Printf("Resolved %d compose/local conflicts.\n\n", len(result.Conflicts))
	}
}
