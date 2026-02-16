package cli

import (
	"encoding/json"
	"fmt"

	"github.com/hun-sh/hun/internal/client"
	"github.com/hun-sh/hun/internal/daemon"
	"github.com/spf13/cobra"
)

func init() {
	logsCmd.Flags().IntP("lines", "n", 500, "Number of lines to show")
	rootCmd.AddCommand(logsCmd)
}

var logsCmd = &cobra.Command{
	Use:   "logs <project>:<service>",
	Short: "Dump logs to stdout (pipe-friendly)",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		project, service := parseTarget(args[0])
		if service == "" {
			return fmt.Errorf("specify service: hun logs project:service")
		}

		lines, _ := cmd.Flags().GetInt("lines")

		c, err := client.New()
		if err != nil {
			return err
		}

		resp, err := c.Send(daemon.Request{
			Action:  "logs",
			Project: project,
			Service: service,
			Lines:   lines,
		})
		if err != nil {
			return err
		}
		if !resp.OK {
			return fmt.Errorf("%s", resp.Error)
		}

		var logLines []daemon.LogLine
		if err := json.Unmarshal(resp.Data, &logLines); err != nil {
			return err
		}

		for _, line := range logLines {
			ts := line.Timestamp.Format("15:04:05")
			fmt.Printf("[%s] %s\n", ts, line.Text)
		}

		return nil
	},
}
