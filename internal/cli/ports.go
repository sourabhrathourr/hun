package cli

import (
	"encoding/json"
	"fmt"
	"sort"

	"github.com/hun-sh/hun/internal/client"
	"github.com/hun-sh/hun/internal/daemon"
	"github.com/hun-sh/hun/internal/state"
	"github.com/spf13/cobra"
)

func init() {
	rootCmd.AddCommand(portsCmd)
}

var portsCmd = &cobra.Command{
	Use:   "ports",
	Short: "Show port map for all running services",
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := client.New()
		if err != nil {
			return err
		}

		resp, err := c.Send(daemon.Request{Action: "ports"})
		if err != nil {
			return err
		}
		if !resp.OK {
			return fmt.Errorf("%s", resp.Error)
		}

		var ports map[string]map[string]int
		if err := json.Unmarshal(resp.Data, &ports); err != nil {
			return err
		}

		if len(ports) == 0 {
			fmt.Println("No running services.")
			return nil
		}

		st, _ := state.Load()

		projects := make([]string, 0, len(ports))
		for name := range ports {
			projects = append(projects, name)
		}
		sort.Strings(projects)

		for _, proj := range projects {
			services := ports[proj]
			offset := ""
			if st != nil {
				if ps, ok := st.Projects[proj]; ok && ps.Offset > 0 {
					offset = fmt.Sprintf(" (+%d)", ps.Offset)
				}
			}
			fmt.Printf("%s%s\n", proj, offset)

			svcNames := make([]string, 0, len(services))
			for name := range services {
				svcNames = append(svcNames, name)
			}
			sort.Strings(svcNames)

			for _, svc := range svcNames {
				port := services[svc]
				fmt.Printf("  %-20s localhost:%d\n", svc, port)
			}
			fmt.Println()
		}

		return nil
	},
}
