package cli

import (
	"fmt"

	"github.com/sourabhrathourr/hun/internal/state"
	"github.com/spf13/cobra"
)

func init() {
	rootCmd.AddCommand(removeCmd)
}

var removeCmd = &cobra.Command{
	Use:   "remove <project>",
	Short: "Unregister a project (doesn't delete files)",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		name := args[0]

		st, err := state.Load()
		if err != nil {
			return err
		}

		if !st.IsRegistered(name) {
			return fmt.Errorf("project %q not found in registry", name)
		}

		if ps, ok := st.Projects[name]; ok && ps.Status == "running" {
			return fmt.Errorf("project %q is currently running; stop it first with 'hun stop %s'", name, name)
		}

		st.Unregister(name)
		if err := st.Save(); err != nil {
			return err
		}
		fmt.Printf("%s Removed project: %s\n", checkmark(), name)
		return nil
	},
}
