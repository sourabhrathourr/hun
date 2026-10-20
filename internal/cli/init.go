package cli

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/sourabhrathourr/hun/internal/client"
	"github.com/sourabhrathourr/hun/internal/config"
	"github.com/sourabhrathourr/hun/internal/daemon"
	"github.com/sourabhrathourr/hun/internal/detect"
	"github.com/sourabhrathourr/hun/internal/state"
	"github.com/spf13/cobra"
)

func init() {
	initCmd.Flags().String("name", "", "Project name (defaults to directory name)")
	initCmd.Flags().String("profile", "", "Detection profile: local|compose|hybrid")
	initCmd.Flags().BoolP("yes", "y", false, "Accept detected configuration without prompting")
	initCmd.Flags().Bool("no-register", false, "Create or update .hun.yml without registering the project")
	initCmd.Flags().Bool("reconfigure", false, "Regenerate .hun.yml even if one already exists (creates .hun.yml.bak.<timestamp>)")
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
		autoApprove, _ := cmd.Flags().GetBool("yes")
		noRegister, _ := cmd.Flags().GetBool("no-register")
		rawProfile, _ := cmd.Flags().GetString("profile")
		requestedProfile := strings.TrimSpace(rawProfile)

		var existing *config.Project
		if config.ProjectExists(dir) {
			proj, err := config.LoadProject(dir)
			if err != nil {
				return err
			}
			existing = proj
			if !reconfigure {
				if isInteractiveTerminal() {
					question := fmt.Sprintf(".hun.yml already exists (project: %s). Override it? [y/N] ", proj.Name)
					override, err := confirmPromptWithDefault(question, false)
					if err != nil {
						return err
					}
					if !override {
						fmt.Println("Keeping existing .hun.yml")
						if noRegister {
							return nil
						}
						return registerProject(proj.Name, dir)
					}
					reconfigure = true
					fmt.Printf("Reconfiguring .hun.yml (project: %s)\n", proj.Name)
				} else {
					fmt.Printf(".hun.yml already exists (project: %s)\n", proj.Name)
					if noRegister {
						return nil
					}
					return registerProject(proj.Name, dir)
				}
			} else {
				fmt.Printf("Reconfiguring .hun.yml (project: %s)\n", proj.Name)
			}
		}

		name, _ := cmd.Flags().GetString("name")
		if name == "" {
			if existing != nil && existing.Name != "" {
				name = existing.Name
			} else {
				name = filepath.Base(dir)
			}
		}

		proj, aborted, err := prepareProjectFromDetection(name, dir, requestedProfile, reconfigure, autoApprove)
		if err != nil {
			return err
		}
		if aborted {
			fmt.Println("Aborted.")
			return nil
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
		if noRegister {
			return nil
		}

		return registerProject(proj.Name, dir)
	},
}

// registerProject registers dir and reports the key it got. A running
// daemon owns state.json, so the change goes through it; otherwise the file
// is edited directly.
func registerProject(name, dir string) error {
	key, err := registerProjectPath(name, dir)
	if err != nil {
		return err
	}
	if key != name {
		fmt.Printf("%s Registered project: %s (another folder already uses %q)\n", checkmark(), key, name)
	} else {
		fmt.Printf("%s Registered project: %s\n", checkmark(), key)
	}
	return nil
}

// daemonOwnsState reports whether a running daemon owns state.json, in which
// case the CLI must not rewrite the registry behind its back.
func daemonOwnsState() bool {
	c, err := client.New()
	return err == nil && c.Running()
}

func registerProjectPath(name, dir string) (string, error) {
	if c, err := client.New(); err == nil && c.Running() {
		resp, err := c.Send(daemon.Request{Action: "register_project", Path: dir})
		if err != nil {
			return "", err
		}
		if !resp.OK {
			return "", fmt.Errorf("%s", resp.Error)
		}
		var payload struct {
			Project string `json:"project"`
		}
		if err := json.Unmarshal(resp.Data, &payload); err != nil {
			return "", err
		}
		return payload.Project, nil
	}

	st, err := state.Load()
	if err != nil {
		return "", err
	}
	key := st.RegisterPath(name, dir)
	if err := st.Save(); err != nil {
		return "", err
	}
	return key, nil
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
		portEnv := svc.PortEnv
		if portEnv == "PORT" {
			portEnv = ""
		}
		s := &config.Service{
			Cmd:       svc.Cmd,
			Port:      svc.Port,
			PortEnv:   portEnv,
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
	return confirmPromptWithDefault(question, true)
}

func confirmPromptWithDefault(question string, defaultYes bool) (bool, error) {
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
	return parseConfirmPromptAnswer(answer, defaultYes), nil
}

func parseConfirmPromptAnswer(answer string, defaultYes bool) bool {
	normalized := strings.TrimSpace(strings.ToLower(answer))
	if normalized == "" {
		return defaultYes
	}
	if normalized == "y" || normalized == "yes" {
		return true
	}
	if normalized == "n" || normalized == "no" {
		return false
	}
	return defaultYes
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

func checkmark() string {
	return "\u2713"
}
