package cli

import (
	"fmt"
	"path/filepath"

	"github.com/sourabhrathourr/hun/internal/config"
	"github.com/sourabhrathourr/hun/internal/state"
	"github.com/spf13/cobra"
)

func init() {
	addCmd.Flags().BoolP("yes", "y", false, "Register without prompting")
	rootCmd.AddCommand(addCmd)
}

var addCmd = &cobra.Command{
	Use:   "add <path>",
	Short: "Register an existing project",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		dir, err := filepath.Abs(args[0])
		if err != nil {
			return err
		}

		if !config.ProjectExists(dir) {
			return fmt.Errorf("no .hun.yml found in %s (run 'hun init' there first)", dir)
		}

		proj, err := config.LoadProject(dir)
		if err != nil {
			return err
		}

		st, err := state.Load()
		if err != nil {
			return err
		}

		if st.IsRegistered(proj.Name) {
			existingPath := st.Registry[proj.Name]
			if existingPath == dir {
				fmt.Printf("Project %s already registered.\n", proj.Name)
				return nil
			}
			return fmt.Errorf("project name %q already taken by %s", proj.Name, existingPath)
		}

		autoApprove, _ := cmd.Flags().GetBool("yes")
		if !autoApprove && isInteractiveTerminal() {
			fmt.Printf("Project: %s\n", proj.Name)
			fmt.Printf("Path:    %s\n", dir)
			fmt.Printf("Services: %d\n", len(proj.Services))
			ok, confirmErr := confirmPrompt("Register this project with hun? [Y/n] ")
			if confirmErr != nil {
				return confirmErr
			}
			if !ok {
				fmt.Println("Aborted.")
				return nil
			}
		}

		st.Register(proj.Name, dir)
		if err := st.Save(); err != nil {
			return err
		}
		fmt.Printf("%s Registered project: %s (%s)\n", checkmark(), proj.Name, dir)
		return nil
	},
}
