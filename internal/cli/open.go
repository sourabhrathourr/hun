package cli

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"runtime"
	"sort"

	"github.com/sourabhrathourr/hun/internal/client"
	"github.com/sourabhrathourr/hun/internal/daemon"
	"github.com/spf13/cobra"
)

func init() {
	rootCmd.AddCommand(openCmd)
}

var openCmd = &cobra.Command{
	Use:   "open [service]",
	Short: "Open a service URL in the browser",
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

		// Find matching service
		target := ""
		if len(args) > 0 {
			target = args[0]
		}

		for proj, services := range ports {
			svcNames := make([]string, 0, len(services))
			for name := range services {
				svcNames = append(svcNames, name)
			}
			sort.Strings(svcNames)

			for _, svc := range svcNames {
				port := services[svc]
				if target == "" || svc == target {
					url := fmt.Sprintf("http://localhost:%d", port)
					fmt.Printf("Opening %s:%s at %s\n", proj, svc, url)
					return openBrowser(url)
				}
			}
		}

		if target != "" {
			return fmt.Errorf("service %q not found or has no port", target)
		}
		return fmt.Errorf("no running services with ports")
	},
}

func openBrowser(url string) error {
	switch runtime.GOOS {
	case "darwin":
		return exec.Command("open", url).Start()
	case "linux":
		return exec.Command("xdg-open", url).Start()
	default:
		return fmt.Errorf("unsupported platform")
	}
}
