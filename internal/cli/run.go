package cli

import (
	"fmt"

	"github.com/sourabhrathourr/hun/internal/client"
	"github.com/sourabhrathourr/hun/internal/daemon"
	"github.com/spf13/cobra"
)

func init() {
	runCmd.Flags().StringP("profile", "p", "", `Profile from .hun.yml to run, or "all" (default: the last one run)`)
	rootCmd.AddCommand(runCmd)
}

var runCmd = &cobra.Command{
	Use:   "run <project>[:<service>]",
	Short: "Start a project or one service alongside others (Multitask Mode with port offset)",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		project, service := parseTarget(args[0])
		profile, _ := cmd.Flags().GetString("profile")
		if profile != "" && service != "" {
			return fmt.Errorf("--profile runs a set of services; drop :%s or the flag", service)
		}

		c, err := client.New()
		if err != nil {
			return err
		}

		req := daemon.Request{
			Action:  "start",
			Project: project,
			Mode:    "parallel",
			Profile: profile,
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
		} else if profile != "" {
			fmt.Printf("%s Running %s · %s in parallel\n", checkmark(), project, profile)
		} else {
			fmt.Printf("%s Started %s in parallel\n", checkmark(), project)
		}
		return nil
	},
}
