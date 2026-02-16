package cli

import (
	"fmt"
	"net"
	"os"
	"path/filepath"
	"time"

	"github.com/hun-sh/hun/internal/config"
	"github.com/hun-sh/hun/internal/state"
	"github.com/spf13/cobra"
)

func init() {
	rootCmd.AddCommand(doctorCmd)
}

var doctorCmd = &cobra.Command{
	Use:   "doctor",
	Short: "Diagnose common issues",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Printf("hun.sh doctor (version: %s)\n\n", versionStr)

		allOK := true

		// Check hun directory
		dir, err := config.HunDir()
		if err != nil {
			printCheck(false, "hun directory", err.Error())
			allOK = false
		} else {
			printCheck(true, "hun directory", dir)
		}

		// Check daemon socket
		sockPath := filepath.Join(dir, "daemon.sock")
		if _, err := os.Stat(sockPath); err != nil {
			printCheck(false, "daemon socket", "not found (daemon not running)")
			allOK = false
		} else {
			// Try to connect
			conn, err := net.DialTimeout("unix", sockPath, time.Second)
			if err != nil {
				printCheck(false, "daemon socket", "socket exists but daemon not responding")
				allOK = false
			} else {
				conn.Close()
				printCheck(true, "daemon", "running and responsive")
			}
		}

		// Check state file
		st, err := state.Load()
		if err != nil {
			printCheck(false, "state file", err.Error())
			allOK = false
		} else {
			printCheck(true, "state file", fmt.Sprintf("%d projects registered", len(st.Registry)))
		}

		// Validate registered project configs
		if st != nil {
			for name, path := range st.Registry {
				if _, err := os.Stat(path); err != nil {
					printCheck(false, fmt.Sprintf("project %s", name), fmt.Sprintf("path missing: %s", path))
					allOK = false
					continue
				}
				if !config.ProjectExists(path) {
					printCheck(false, fmt.Sprintf("project %s", name), "no .hun.yml found")
					allOK = false
					continue
				}
				if _, err := config.LoadProject(path); err != nil {
					printCheck(false, fmt.Sprintf("project %s", name), fmt.Sprintf("config error: %v", err))
					allOK = false
					continue
				}
				printCheck(true, fmt.Sprintf("project %s", name), "config valid")
			}
		}

		// Check logs directory
		logsDir := filepath.Join(dir, "logs")
		if _, err := os.Stat(logsDir); err != nil {
			printCheck(false, "logs directory", "not found")
		} else {
			printCheck(true, "logs directory", logsDir)
		}

		fmt.Println()
		if allOK {
			fmt.Println("All checks passed!")
		} else {
			fmt.Println("Some checks failed. See above for details.")
		}

		return nil
	},
}

func printCheck(ok bool, label, detail string) {
	mark := "\u2713"
	if !ok {
		mark = "\u2717"
	}
	fmt.Printf("  %s %-25s %s\n", mark, label, detail)
}
