package cli

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/sourabhrathourr/hun/internal/config"
	"github.com/sourabhrathourr/hun/internal/state"
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
				proj, err := config.LoadProject(path)
				if err != nil {
					printCheck(false, fmt.Sprintf("project %s", name), fmt.Sprintf("config error: %v", err))
					allOK = false
					continue
				}
				printCheck(true, fmt.Sprintf("project %s", name), "config valid")

				if ps, ok := st.Projects[name]; ok && len(ps.PortOverrides) > 0 {
					mismatches := make([]string, 0)
					for svc, override := range ps.PortOverrides {
						cfgSvc, exists := proj.Services[svc]
						if !exists || override <= 0 {
							continue
						}
						if cfgSvc.Port != override {
							mismatches = append(mismatches, fmt.Sprintf("%s(%d→%d)", svc, cfgSvc.Port, override))
						}
					}
					if len(mismatches) > 0 {
						printCheck(false, fmt.Sprintf("project %s ports", name), fmt.Sprintf("runtime overrides differ: %s (run 'hun init --reconfigure --apply-port-overrides' in %s)", strings.Join(mismatches, ", "), path))
						allOK = false
					}
				}
			}
		}

		// Check logs directory
		logsDir := filepath.Join(dir, "logs")
		if _, err := os.Stat(logsDir); err != nil {
			printCheck(false, "logs directory", "not found")
		} else {
			printCheck(true, "logs directory", logsDir)
		}

		// Check unsupported global config fields and active port offset behavior.
		globalCfg, err := config.LoadGlobal()
		if err != nil {
			printCheck(false, "global config", fmt.Sprintf("read error: %v", err))
			allOK = false
		} else {
			unsupported := config.UnsupportedGlobalSettings(globalCfg)
			if len(unsupported) > 0 {
				printCheck(false, "global config", fmt.Sprintf("unsupported keys configured: %s", strings.Join(unsupported, ", ")))
				allOK = false
			} else {
				printCheck(true, "global config", fmt.Sprintf("ports.default_offset=%d", globalCfg.Ports.DefaultOffset))
			}
		}

		// Non-blocking version check with timeout.
		latest, err := fetchLatestReleaseTag(2 * time.Second)
		if err != nil {
			printCheck(false, "version check", fmt.Sprintf("skipped: %v", err))
		} else {
			current := strings.TrimSpace(versionStr)
			if current == "" || current == "dev" {
				printCheck(true, "version check", fmt.Sprintf("development build (latest: %s)", latest))
			} else if normalizeVersion(current) != normalizeVersion(latest) {
				printCheck(false, "version check", fmt.Sprintf("update available: %s -> %s", current, latest))
			} else {
				printCheck(true, "version check", fmt.Sprintf("up to date (%s)", current))
			}
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

func fetchLatestReleaseTag(timeout time.Duration) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://api.github.com/repos/sourabhrathourr/hun/releases/latest", nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "hun-doctor")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("http %d", resp.StatusCode)
	}

	var payload struct {
		Tag string `json:"tag_name"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return "", err
	}
	if strings.TrimSpace(payload.Tag) == "" {
		return "", fmt.Errorf("missing tag_name in response")
	}
	return payload.Tag, nil
}

func normalizeVersion(v string) string {
	v = strings.TrimSpace(v)
	v = strings.TrimPrefix(v, "v")
	return v
}
