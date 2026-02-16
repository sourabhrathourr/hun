package cli

import (
	"fmt"

	"github.com/sourabhrathourr/hun/internal/client"
	"github.com/sourabhrathourr/hun/internal/daemon"
	"github.com/spf13/cobra"
)

func init() {
	rootCmd.AddCommand(tailCmd)
}

var tailCmd = &cobra.Command{
	Use:   "tail <project>:<service>",
	Short: "Stream logs in real-time (tail -f style)",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		project, service := parseTarget(args[0])
		if service == "" {
			return fmt.Errorf("specify service: hun tail project:service")
		}

		c, err := client.New()
		if err != nil {
			return err
		}

		fmt.Printf("Streaming logs for %s:%s (Ctrl+C to stop)\n\n", project, service)

		return c.Subscribe(project, service, func(line daemon.LogLine) {
			ts := line.Timestamp.Format("15:04:05")
			fmt.Printf("[%s] %s\n", ts, line.Text)
		})
	},
}
