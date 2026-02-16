package cli

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/sourabhrathourr/hun/internal/config"
	"github.com/sourabhrathourr/hun/internal/detect"
	"github.com/sourabhrathourr/hun/internal/state"
	"github.com/spf13/cobra"
)

func init() {
	initCmd.Flags().String("name", "", "Project name (defaults to directory name)")
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

		if config.ProjectExists(dir) {
			proj, err := config.LoadProject(dir)
			if err != nil {
				return err
			}
			fmt.Printf(".hun.yml already exists (project: %s)\n", proj.Name)
			return registerProject(proj.Name, dir)
		}

		name, _ := cmd.Flags().GetString("name")
		if name == "" {
			name = filepath.Base(dir)
		}

		// Auto-detect project structure
		result := detect.Run(dir)
		var proj *config.Project

		if len(result.Services) > 0 {
			fmt.Println("Detected project structure:")
			fmt.Println()
			for _, svc := range result.Services {
				port := ""
				if svc.Port > 0 {
					port = fmt.Sprintf(" (port %d)", svc.Port)
				}
				fmt.Printf("  %s %s%s\n", checkmark(), svc.Name, port)
				fmt.Printf("    -> %s\n", svc.Cmd)
				fmt.Println()
			}

			fmt.Print("Create .hun.yml with these services? [Y/n] ")
			var answer string
			fmt.Scanln(&answer)
			if answer != "" && answer != "y" && answer != "Y" {
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
			}
		}

		if err := config.WriteProject(dir, proj); err != nil {
			return err
		}
		fmt.Printf("%s Created .hun.yml\n", checkmark())

		return registerProject(name, dir)
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

func checkmark() string {
	return "\u2713"
}
