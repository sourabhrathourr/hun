package cli

import (
	"fmt"

	"github.com/sourabhrathourr/hun/internal/client"
	"github.com/sourabhrathourr/hun/internal/daemon"
	"github.com/sourabhrathourr/hun/internal/state"
	"github.com/spf13/cobra"
)

func init() {
	switchCmd.Flags().StringP("message", "m", "", "Note to save for current project before switching")
	switchCmd.Flags().StringP("profile", "p", "", `Profile from .hun.yml to run, or "all" (default: the last one run)`)
	rootCmd.AddCommand(switchCmd)
}

var switchCmd = &cobra.Command{
	Use:   "switch <project>",
	Short: "Switch to a project (Focus Mode: stops current, starts target)",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		project := args[0]
		note, _ := cmd.Flags().GetString("message")
		profile, _ := cmd.Flags().GetString("profile")

		// Save note for current project if provided
		if note != "" {
			st, err := state.Load()
			if err == nil {
				target := st.ActiveProject
				if target == "" {
					for name, ps := range st.Projects {
						if ps.Status == "running" {
							target = name
							break
						}
					}
				}
				if target != "" {
					ps := st.Projects[target]
					ps.LastNote = note
					st.Projects[target] = ps
					_ = st.Save()
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
			Profile: profile,
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
