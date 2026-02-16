package cli

import (
	"encoding/json"
	"fmt"
	"sort"

	"github.com/sourabhrathourr/hun/internal/client"
	"github.com/sourabhrathourr/hun/internal/daemon"
	"github.com/spf13/cobra"
)

func init() {
	rootCmd.AddCommand(statusCmd)
}

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show running projects and services",
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := client.New()
		if err != nil {
			return err
		}

		resp, err := c.Send(daemon.Request{Action: "status"})
		if err != nil {
			return err
		}
		if !resp.OK {
			return fmt.Errorf("%s", resp.Error)
		}

		var status map[string]map[string]daemon.ServiceInfo
		if err := json.Unmarshal(resp.Data, &status); err != nil {
			return err
		}

		if len(status) == 0 {
			fmt.Println("No running projects.")
			return nil
		}

		projects := make([]string, 0, len(status))
		for name := range status {
			projects = append(projects, name)
		}
		sort.Strings(projects)

		for _, proj := range projects {
			services := status[proj]
			fmt.Printf("\u25cf %s\n", proj)

			svcNames := make([]string, 0, len(services))
			for name := range services {
				svcNames = append(svcNames, name)
			}
			sort.Strings(svcNames)

			for _, svc := range svcNames {
				info := services[svc]
				statusStr := "running"
				if !info.Running {
					statusStr = "stopped"
				}
				readyMark := " "
				if info.Ready {
					readyMark = "\u2713"
				}
				port := ""
				if info.Port > 0 {
					port = fmt.Sprintf(":%d", info.Port)
				}
				fmt.Printf("  %-20s %s %-6s %s\n", svc, readyMark, port, statusStr)
			}
			fmt.Println()
		}

		return nil
	},
}
