package cli

import (
	"fmt"
	"path/filepath"

	"github.com/hun-sh/hun/internal/config"
	"github.com/hun-sh/hun/internal/state"
	"github.com/spf13/cobra"
)

func init() {
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

		st.Register(proj.Name, dir)
		if err := st.Save(); err != nil {
			return err
		}
		fmt.Printf("%s Registered project: %s (%s)\n", checkmark(), proj.Name, dir)
		return nil
	},
}
