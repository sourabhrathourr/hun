package cli

import (
	"fmt"

	"github.com/sourabhrathourr/hun/internal/client"
	"github.com/sourabhrathourr/hun/internal/daemon"
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

		// A running daemon owns state.json; it also stops the project first.
		if c, err := client.New(); err == nil && c.Running() {
			resp, err := c.Send(daemon.Request{Action: "remove_project", Project: name})
			if err != nil {
				return err
			}
			if !resp.OK {
				return fmt.Errorf("%s", resp.Error)
			}
			fmt.Printf("%s Removed project: %s\n", checkmark(), name)
			return nil
		}

		st, err := state.Load()
		if err != nil {
			return err
		}
		if _, ok := st.RemoveProject(name); !ok {
			return fmt.Errorf("project %q not found in registry", name)
		}
		if err := st.Save(); err != nil {
			return err
		}
		fmt.Printf("%s Removed project: %s\n", checkmark(), name)
		return nil
	},
}
