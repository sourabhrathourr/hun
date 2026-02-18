package cli

import (
	"fmt"

	"github.com/spf13/cobra"
)

var (
	versionStr = "dev"
	commitStr  = "none"
)

func SetVersionInfo(version, commit string) {
	versionStr = version
	commitStr = commit
	rootCmd.Version = versionStr
}

func init() {
	rootCmd.AddCommand(versionCmd)
	rootCmd.Version = versionStr
	rootCmd.SetVersionTemplate("hun.sh {{ .Version }}\n")
}

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print version information",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Printf("hun.sh %s (commit: %s)\n", versionStr, commitStr)
	},
}
