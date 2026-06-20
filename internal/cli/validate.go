package cli

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/sourabhrathourr/hun/internal/config"
	"github.com/spf13/cobra"
)

func init() {
	rootCmd.AddCommand(validateCmd)
}

var validateCmd = &cobra.Command{
	Use:   "validate [path]",
	Short: "Validate a .hun.yml project config",
	Args:  cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		dir := "."
		if len(args) == 1 {
			dir = args[0]
		}
		abs, err := filepath.Abs(dir)
		if err != nil {
			return err
		}
		info, err := os.Stat(abs)
		if err != nil {
			return err
		}
		if !info.IsDir() {
			abs = filepath.Dir(abs)
		}

		project, err := config.LoadProject(abs)
		if err != nil {
			return err
		}
		fmt.Printf("%s .hun.yml valid (project: %s, services: %d)\n", checkmark(), project.Name, len(project.Services))
		return nil
	},
}
