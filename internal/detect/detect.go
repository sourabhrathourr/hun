package detect

import (
	"sort"
	"strings"
)

// DetectedService represents a service found by auto-detection.
type DetectedService struct {
	Name           string
	Cmd            string
	Cwd            string
	Port           int
	PortEnv        string
	Ready          string
	DependsOn      []string
	Runtime        string  // node, python, go, compose
	Source         string  // source file/path used for detection
	LogicalName    string  // canonical name used for profile conflict resolution
	Strategy       string  // local, compose
	Class          string  // app, infra
	Confidence     float64 // service detection confidence
	PortConfidence float64 // port inference confidence
}

// Result holds all detected services for a directory.
type Result struct {
	Services  []DetectedService
	Conflicts []Conflict
	Profile   string
}

// Conflict captures local/compose ambiguity for a logical service.
type Conflict struct {
	Name     string
	Variants []DetectedService
}

// Options controls detection resolution behavior.
type Options struct {
	Profile string // local, compose, hybrid
}

// Analysis is the raw pre-resolution output of all detectors.
type Analysis struct {
	Candidates []DetectedService
	Conflicts  []Conflict
}

// Detector is an interface for project type detectors.
type Detector interface {
	Detect(dir string) []DetectedService
}

const (
	ProfileLocal   = "local"
	ProfileCompose = "compose"
	ProfileHybrid  = "hybrid"
)

// NormalizeProfile validates and normalizes a profile string.
func NormalizeProfile(profile string) string {
	switch strings.ToLower(strings.TrimSpace(profile)) {
	case ProfileLocal:
		return ProfileLocal
	case ProfileCompose:
		return ProfileCompose
	case ProfileHybrid, "":
		return ProfileHybrid
	default:
		return ""
	}
}

// Analyze executes all detectors against a directory and returns unresolved candidates.
func Analyze(dir string) Analysis {
	detectors := []Detector{
		&ComposeDetector{},
		&NodeDetector{},
		&GoDetector{},
		&PythonDetector{},
	}

	var candidates []DetectedService
	for _, d := range detectors {
		candidates = append(candidates, d.Detect(dir)...)
	}

	sort.Slice(candidates, func(i, j int) bool {
		ai := candidates[i]
		aj := candidates[j]
		if ai.LogicalName != aj.LogicalName {
			return ai.LogicalName < aj.LogicalName
		}
		if ai.Strategy != aj.Strategy {
			return ai.Strategy < aj.Strategy
		}
		if ai.Source != aj.Source {
			return ai.Source < aj.Source
		}
		return ai.Name < aj.Name
	})

	return Analysis{
		Candidates: candidates,
		Conflicts:  detectConflicts(candidates),
	}
}

// Resolve applies the selected profile to candidate services and returns a deterministic set.
func Resolve(analysis Analysis, profile string) Result {
	normalized := NormalizeProfile(profile)
	if normalized == "" {
		normalized = ProfileHybrid
	}

	byLogical := make(map[string][]DetectedService)
	for _, svc := range analysis.Candidates {
		key := svc.LogicalName
		if key == "" {
			key = svc.Name
		}
		byLogical[key] = append(byLogical[key], svc)
	}

	keys := make([]string, 0, len(byLogical))
	for k := range byLogical {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	out := make([]DetectedService, 0, len(keys))
	for _, key := range keys {
		choice := chooseCandidate(byLogical[key], normalized)
		if choice.Name == "" && choice.Cmd == "" {
			continue
		}
		choice.Name = key
		choice.LogicalName = key
		out = append(out, choice)
	}

	sort.Slice(out, func(i, j int) bool {
		return out[i].Name < out[j].Name
	})

	return Result{
		Services:  out,
		Conflicts: analysis.Conflicts,
		Profile:   normalized,
	}
}

// Run executes all detectors and resolves services for the selected profile.
func Run(dir string, opts Options) Result {
	return Resolve(Analyze(dir), opts.Profile)
}

func detectConflicts(candidates []DetectedService) []Conflict {
	byLogical := make(map[string][]DetectedService)
	for _, svc := range candidates {
		key := svc.LogicalName
		if key == "" {
			key = svc.Name
		}
		byLogical[key] = append(byLogical[key], svc)
	}

	conflicts := make([]Conflict, 0)
	for key, variants := range byLogical {
		hasLocal := false
		hasCompose := false
		for _, v := range variants {
			switch v.Strategy {
			case "compose":
				hasCompose = true
			default:
				hasLocal = true
			}
		}
		if hasLocal && hasCompose {
			sorted := append([]DetectedService(nil), variants...)
			sortCandidates(sorted)
			conflicts = append(conflicts, Conflict{
				Name:     key,
				Variants: sorted,
			})
		}
	}
	sort.Slice(conflicts, func(i, j int) bool {
		return conflicts[i].Name < conflicts[j].Name
	})
	return conflicts
}

func chooseCandidate(variants []DetectedService, profile string) DetectedService {
	if len(variants) == 0 {
		return DetectedService{}
	}
	if len(variants) == 1 {
		return variants[0]
	}

	locals := make([]DetectedService, 0, len(variants))
	composes := make([]DetectedService, 0, len(variants))
	for _, v := range variants {
		if v.Strategy == "compose" {
			composes = append(composes, v)
		} else {
			locals = append(locals, v)
		}
	}

	if len(locals) == 0 {
		sortCandidates(composes)
		return composes[0]
	}
	if len(composes) == 0 {
		sortCandidates(locals)
		return locals[0]
	}

	sortCandidates(locals)
	sortCandidates(composes)

	switch profile {
	case ProfileCompose:
		return composes[0]
	case ProfileLocal:
		return locals[0]
	case ProfileHybrid:
		if isInfraConflict(composes) {
			return composes[0]
		}
		return locals[0]
	default:
		return locals[0]
	}
}

func sortCandidates(c []DetectedService) {
	sort.Slice(c, func(i, j int) bool {
		a := c[i]
		b := c[j]
		if a.Confidence != b.Confidence {
			return a.Confidence > b.Confidence
		}
		if a.PortConfidence != b.PortConfidence {
			return a.PortConfidence > b.PortConfidence
		}
		if a.Strategy != b.Strategy {
			return a.Strategy < b.Strategy
		}
		if a.Source != b.Source {
			return a.Source < b.Source
		}
		if a.Cwd != b.Cwd {
			return a.Cwd < b.Cwd
		}
		return a.Cmd < b.Cmd
	})
}

func isInfraConflict(composes []DetectedService) bool {
	for _, c := range composes {
		if c.Class == "infra" {
			return true
		}
	}
	return false
}
