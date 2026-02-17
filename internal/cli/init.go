package cli

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/sourabhrathourr/hun/internal/config"
	"github.com/sourabhrathourr/hun/internal/detect"
	"github.com/sourabhrathourr/hun/internal/state"
	"github.com/spf13/cobra"
)

func init() {
	initCmd.Flags().String("name", "", "Project name (defaults to directory name)")
	initCmd.Flags().String("profile", "", "Detection profile: local|compose|hybrid")
	initCmd.Flags().Bool("reconfigure", false, "Regenerate .hun.yml even if one already exists (creates .hun.yml.bak.<timestamp>)")
	initCmd.Flags().Bool("apply-port-overrides", false, "Apply runtime-detected port overrides from state to generated .hun.yml")
	rootCmd.AddCommand(initCmd)
}

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize current directory as a hun project",
	RunE: func(cmd *cobra.Command, args []string) error {
		dir, err := os.Getwd()
		if err != nil {
			return err
		}

		reconfigure, _ := cmd.Flags().GetBool("reconfigure")
		applyOverrides, _ := cmd.Flags().GetBool("apply-port-overrides")
		rawProfile, _ := cmd.Flags().GetString("profile")
		requestedProfile := strings.TrimSpace(rawProfile)
		if requestedProfile != "" {
			requestedProfile = detect.NormalizeProfile(requestedProfile)
			if requestedProfile == "" {
				return fmt.Errorf("invalid --profile %q (expected local|compose|hybrid)", rawProfile)
			}
		}

		var existing *config.Project
		if config.ProjectExists(dir) {
			proj, err := config.LoadProject(dir)
			if err != nil {
				return err
			}
			existing = proj
			if !reconfigure {
				fmt.Printf(".hun.yml already exists (project: %s)\n", proj.Name)
				return registerProject(proj.Name, dir)
			}
			fmt.Printf("Reconfiguring .hun.yml (project: %s)\n", proj.Name)
		}

		name, _ := cmd.Flags().GetString("name")
		if name == "" {
			if existing != nil && existing.Name != "" {
				name = existing.Name
			} else {
				name = filepath.Base(dir)
			}
		}

		analysis := detect.Analyze(dir)
		profile := requestedProfile
		if profile == "" {
			profile = detect.ProfileHybrid
			if len(analysis.Conflicts) > 0 && isInteractiveTerminal() {
				selected, err := promptProfileSelection(analysis.Conflicts)
				if err != nil {
					return err
				}
				profile = selected
			}
		}

		result := detect.Resolve(analysis, profile)
		var proj *config.Project

		if len(result.Services) > 0 {
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

			question := "Create .hun.yml with these services? [Y/n] "
			if reconfigure {
				question = "Rewrite .hun.yml with these services? [Y/n] "
			}
			if ok, err := confirmPrompt(question); err != nil {
				return err
			} else if !ok {
				fmt.Println("Aborted.")
				return nil
			}

			proj = detectedToProject(name, result)
		} else {
			fmt.Println("No project structure detected.")
			fmt.Println("Creating minimal .hun.yml...")
			proj = &config.Project{
				Name: name,
				Services: map[string]*config.Service{
					"app": {Cmd: "echo 'replace with your command'"},
				},
				Detect: config.DetectConfig{Version: "v2", Profile: result.Profile},
			}
		}

		if applyOverrides {
			if n, err := applyPortOverridesToProject(name, proj); err != nil {
				return err
			} else if n > 0 {
				fmt.Printf("%s Applied %d port override(s) from state\n", checkmark(), n)
			}
		}

		if reconfigure && existing != nil {
			backup, err := backupProjectConfig(dir)
			if err != nil {
				return err
			}
			fmt.Printf("%s Backed up existing config: %s\n", checkmark(), filepath.Base(backup))
		}

		if err := config.WriteProject(dir, proj); err != nil {
			return err
		}
		fmt.Printf("%s Created .hun.yml\n", checkmark())

		return registerProject(proj.Name, dir)
	},
}

func registerProject(name, dir string) error {
	st, err := state.Load()
	if err != nil {
		return err
	}

	if st.IsRegistered(name) {
		existingPath := st.Registry[name]
		if existingPath != dir {
			return fmt.Errorf("project %q already registered at %s", name, existingPath)
		}
		fmt.Printf("Project %s already registered.\n", name)
		return nil
	}

	st.Register(name, dir)
	if err := st.Save(); err != nil {
		return err
	}
	fmt.Printf("%s Registered project: %s\n", checkmark(), name)
	return nil
}

func detectedToProject(name string, result detect.Result) *config.Project {
	proj := &config.Project{
		Name:     name,
		Services: make(map[string]*config.Service),
		Detect: config.DetectConfig{
			Version: "v2",
			Profile: result.Profile,
		},
	}
	for _, svc := range result.Services {
		s := &config.Service{
			Cmd:       svc.Cmd,
			Port:      svc.Port,
			PortEnv:   svc.PortEnv,
			Ready:     svc.Ready,
			DependsOn: svc.DependsOn,
		}
		if svc.Cwd != "" {
			s.Cwd = svc.Cwd
		}
		proj.Services[svc.Name] = s
	}
	return proj
}

func confirmPrompt(question string) (bool, error) {
	fmt.Print(question)
	reader := bufio.NewReader(os.Stdin)
	answer, err := reader.ReadString('\n')
	if err != nil {
		if strings.Contains(err.Error(), "EOF") {
			answer = ""
		} else {
			return false, err
		}
	}
	answer = strings.TrimSpace(strings.ToLower(answer))
	if answer == "" || answer == "y" || answer == "yes" {
		return true, nil
	}
	return false, nil
}

func promptProfileSelection(conflicts []detect.Conflict) (string, error) {
	fmt.Println("Compose and local variants detected for the following services:")
	for _, c := range conflicts {
		fmt.Printf("  - %s\n", c.Name)
	}
	fmt.Println()
	fmt.Println("Select detection profile:")
	fmt.Println("  1) local   - prefer local commands for overlapping services")
	fmt.Println("  2) compose - prefer docker compose services for overlaps")
	fmt.Println("  3) hybrid  - local app services + compose infra services (default)")
	fmt.Print("Profile [1/2/3]: ")

	reader := bufio.NewReader(os.Stdin)
	answer, err := reader.ReadString('\n')
	if err != nil && !strings.Contains(err.Error(), "EOF") {
		return "", err
	}
	answer = strings.TrimSpace(answer)
	switch answer {
	case "1", "local":
		return detect.ProfileLocal, nil
	case "2", "compose":
		return detect.ProfileCompose, nil
	case "", "3", "hybrid":
		return detect.ProfileHybrid, nil
	default:
		fmt.Println("Invalid selection, using hybrid.")
		return detect.ProfileHybrid, nil
	}
}

func isInteractiveTerminal() bool {
	stdinInfo, err := os.Stdin.Stat()
	if err != nil {
		return false
	}
	stdoutInfo, err := os.Stdout.Stat()
	if err != nil {
		return false
	}
	return (stdinInfo.Mode()&os.ModeCharDevice) != 0 && (stdoutInfo.Mode()&os.ModeCharDevice) != 0
}

func backupProjectConfig(dir string) (string, error) {
	src := filepath.Join(dir, ".hun.yml")
	data, err := os.ReadFile(src)
	if err != nil {
		return "", fmt.Errorf("read existing .hun.yml: %w", err)
	}
	backup := filepath.Join(dir, fmt.Sprintf(".hun.yml.bak.%s", time.Now().UTC().Format("20060102-150405")))
	if err := os.WriteFile(backup, data, 0o644); err != nil {
		return "", fmt.Errorf("write backup: %w", err)
	}
	return backup, nil
}

func applyPortOverridesToProject(projectName string, proj *config.Project) (int, error) {
	st, err := state.Load()
	if err != nil {
		return 0, fmt.Errorf("loading state for overrides: %w", err)
	}
	ps, ok := st.Projects[projectName]
	if !ok || len(ps.PortOverrides) == 0 {
		return 0, nil
	}

	applied := 0
	for svc, basePort := range ps.PortOverrides {
		if basePort <= 0 {
			continue
		}
		cfg, ok := proj.Services[svc]
		if !ok {
			continue
		}
		if cfg.Port != basePort {
			cfg.Port = basePort
			applied++
		}
	}
	return applied, nil
}

func checkmark() string {
	return "\u2713"
}
