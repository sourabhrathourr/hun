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
	Use:   "run <project>[:<service>]",
	Short: "Start a project or one service alongside others (Multitask Mode with port offset)",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		project, service := parseTarget(args[0])

		c, err := client.New()
		if err != nil {
			return err
		}

		req := daemon.Request{
			Action:  "start",
			Project: project,
			Mode:    "parallel",
		}
		if service != "" {
			req.Action = "start_service"
			req.Service = service
		}
		resp, err := c.Send(req)
		if err != nil {
			return err
		}
		if !resp.OK {
			return fmt.Errorf("%s", resp.Error)
		}

		if service != "" {
			fmt.Printf("%s Started %s:%s in parallel\n", checkmark(), project, service)
		} else {
			fmt.Printf("%s Started %s in parallel\n", checkmark(), project)
		}
		return nil
	},
}
