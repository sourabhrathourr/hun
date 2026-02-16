package cli

import (
	"fmt"
	"sort"

	"github.com/sourabhrathourr/hun/internal/state"
	"github.com/spf13/cobra"
)

func init() {
	rootCmd.AddCommand(listCmd)
}

var listCmd = &cobra.Command{
	Use:   "list",
	Short: "List all known projects",
	RunE: func(cmd *cobra.Command, args []string) error {
		st, err := state.Load()
		if err != nil {
			return err
		}

		if len(st.Registry) == 0 {
			fmt.Println("No projects registered. Run 'hun init' in a project directory.")
			return nil
		}

		names := make([]string, 0, len(st.Registry))
		for name := range st.Registry {
			names = append(names, name)
		}
		sort.Strings(names)

		for _, name := range names {
			path := st.Registry[name]
			status := "stopped"
			if ps, ok := st.Projects[name]; ok && ps.Status == "running" {
				status = "running"
			}

			indicator := "  "
			if status == "running" {
				indicator = "\u25cf "
			}
			fmt.Printf("%s%-20s %s\n", indicator, name, path)
		}

		return nil
	},
}
