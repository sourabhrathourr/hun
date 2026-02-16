package cli

import (
	"fmt"
	"strings"

	"github.com/hun-sh/hun/internal/client"
	"github.com/hun-sh/hun/internal/daemon"
	"github.com/spf13/cobra"
)

func init() {
	rootCmd.AddCommand(restartCmd)
}

var restartCmd = &cobra.Command{
	Use:   "restart <project>[:<service>]",
	Short: "Restart a project or specific service",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		target := args[0]
		project, service := parseTarget(target)

		c, err := client.New()
		if err != nil {
			return err
		}

		resp, err := c.Send(daemon.Request{
			Action:  "restart",
			Project: project,
			Service: service,
		})
		if err != nil {
			return err
		}
		if !resp.OK {
			return fmt.Errorf("%s", resp.Error)
		}

		if service != "" {
			fmt.Printf("%s Restarted %s:%s\n", checkmark(), project, service)
		} else {
			fmt.Printf("%s Restarted %s\n", checkmark(), project)
		}
		return nil
	},
}

func parseTarget(target string) (project, service string) {
	parts := strings.SplitN(target, ":", 2)
	project = parts[0]
	if len(parts) > 1 {
		service = parts[1]
	}
	return
}
