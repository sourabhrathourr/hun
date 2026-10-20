package cli

import (
	"fmt"

	"github.com/sourabhrathourr/hun/internal/client"
	"github.com/sourabhrathourr/hun/internal/daemon"
	"github.com/spf13/cobra"
)

func init() {
	stopCmd.Flags().Bool("all", false, "Stop all running projects")
	rootCmd.AddCommand(stopCmd)
}

var stopCmd = &cobra.Command{
	Use:   "stop [project][:<service>]",
	Short: "Stop a project, one of its services, or all running projects",
	RunE: func(cmd *cobra.Command, args []string) error {
		all, _ := cmd.Flags().GetBool("all")

		c, err := client.New()
		if err != nil {
			return err
		}

		project, service := "", ""
		if len(args) > 0 {
			project, service = parseTarget(args[0])
		}

		if !all && project == "" {
			return fmt.Errorf("specify a project name or use --all")
		}

		req := daemon.Request{Action: "stop", Project: project}
		if service != "" {
			req.Action = "stop_service"
			req.Service = service
		}
		resp, err := c.Send(req)
		if err != nil {
			return err
		}
		if !resp.OK {
			return fmt.Errorf("%s", resp.Error)
		}

		if all || project == "" {
			fmt.Println("All projects stopped.")
		} else if service != "" {
			fmt.Printf("%s Stopped %s:%s\n", checkmark(), project, service)
		} else {
			fmt.Printf("%s Stopped %s\n", checkmark(), project)
		}
		return nil
	},
}
