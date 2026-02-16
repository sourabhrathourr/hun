package cli

import (
	"fmt"

	"github.com/sourabhrathourr/hun/internal/client"
	"github.com/sourabhrathourr/hun/internal/daemon"
	"github.com/spf13/cobra"
)

func init() {
	rootCmd.AddCommand(runCmd)
}

var runCmd = &cobra.Command{
	Use:   "run <project>",
	Short: "Start a project alongside others (Multitask Mode with port offset)",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		project := args[0]

		c, err := client.New()
		if err != nil {
			return err
		}

		resp, err := c.Send(daemon.Request{
			Action:  "start",
			Project: project,
			Mode:    "parallel",
		})
		if err != nil {
			return err
		}
		if !resp.OK {
			return fmt.Errorf("%s", resp.Error)
		}

		fmt.Printf("%s Started %s in parallel\n", checkmark(), project)
		return nil
	},
}
