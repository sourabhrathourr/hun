package cli

import (
	"github.com/hun-sh/hun/internal/daemon"
	"github.com/spf13/cobra"
)

func init() {
	daemonCmd.Hidden = true
	rootCmd.AddCommand(daemonCmd)
}

var daemonCmd = &cobra.Command{
	Use:   "daemon",
	Short: "Run the background daemon (internal)",
	RunE: func(cmd *cobra.Command, args []string) error {
		d, err := daemon.New()
		if err != nil {
			return err
		}
		return d.Run()
	},
}
