package cli

import (
	"fmt"

	"github.com/hun-sh/hun/internal/client"
	"github.com/hun-sh/hun/internal/daemon"
	"github.com/hun-sh/hun/internal/state"
	"github.com/spf13/cobra"
)

func init() {
	switchCmd.Flags().StringP("message", "m", "", "Note to save for current project before switching")
	rootCmd.AddCommand(switchCmd)
}

var switchCmd = &cobra.Command{
	Use:   "switch <project>",
	Short: "Switch to a project (Focus Mode: stops current, starts target)",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		project := args[0]
		note, _ := cmd.Flags().GetString("message")

		// Save note for current project if provided
		if note != "" {
			st, err := state.Load()
			if err == nil {
				for name, ps := range st.Projects {
					if ps.Status == "running" {
						ps.LastNote = note
						st.Projects[name] = ps
						st.Save()
						break
					}
				}
			}
		}

		c, err := client.New()
		if err != nil {
			return err
		}

		resp, err := c.Send(daemon.Request{
			Action:  "start",
			Project: project,
			Mode:    "exclusive",
		})
		if err != nil {
			return err
		}
		if !resp.OK {
			return fmt.Errorf("%s", resp.Error)
		}

		// Show previous session info
		st, _ := state.Load()
		if st != nil {
			if ps, ok := st.Projects[project]; ok {
				if ps.GitBranch != "" || ps.LastNote != "" {
					fmt.Println("Previous session:")
					if ps.GitBranch != "" {
						fmt.Printf("  Branch: %s\n", ps.GitBranch)
					}
					if ps.LastNote != "" {
						fmt.Printf("  Note: %s\n", ps.LastNote)
					}
					fmt.Println()
				}
			}
		}

		fmt.Printf("%s Switched to %s\n", checkmark(), project)
		return nil
	},
}
