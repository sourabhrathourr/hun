package cli

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/sourabhrathourr/hun/internal/client"
	"github.com/sourabhrathourr/hun/internal/tui"
	"github.com/spf13/cobra"
)

var multiFlag bool

var rootCmd = &cobra.Command{
	Use:   "hun",
	Short: "Seamless project context switching for developers",
	Long:  "hun.sh manages your development services, captures logs, and lets you switch between projects instantly.",
	RunE: func(cmd *cobra.Command, args []string) error {
		// If no subcommand, launch TUI
		c, err := client.New()
		if err != nil {
			return err
		}
		if err := c.EnsureDaemon(); err != nil {
			fmt.Fprintf(os.Stderr, "Warning: could not start daemon: %v\n", err)
		}

		m := tui.New(multiFlag)
		p := tea.NewProgram(m, tea.WithAltScreen())
		_, err = p.Run()
		return err
	},
}

func init() {
	rootCmd.Flags().BoolVar(&multiFlag, "multi", false, "Open TUI in Multitask Mode")
}

func Execute() error {
	return rootCmd.Execute()
}
