package cli

import (
	"fmt"

	"github.com/hun-sh/hun/internal/client"
	"github.com/hun-sh/hun/internal/daemon"
	"github.com/spf13/cobra"
)

func init() {
	stopCmd.Flags().Bool("all", false, "Stop all running projects")
	rootCmd.AddCommand(stopCmd)
}

var stopCmd = &cobra.Command{
	Use:   "stop [project]",
	Short: "Stop a project or all running projects",
	RunE: func(cmd *cobra.Command, args []string) error {
		all, _ := cmd.Flags().GetBool("all")

		c, err := client.New()
		if err != nil {
			return err
		}

		project := ""
		if len(args) > 0 {
			project = args[0]
		}

		if !all && project == "" {
			return fmt.Errorf("specify a project name or use --all")
		}

		resp, err := c.Send(daemon.Request{
			Action:  "stop",
			Project: project,
		})
		if err != nil {
			return err
		}
		if !resp.OK {
			return fmt.Errorf("%s", resp.Error)
		}

		if all || project == "" {
			fmt.Println("All projects stopped.")
		} else {
			fmt.Printf("%s Stopped %s\n", checkmark(), project)
		}
		return nil
	},
}
