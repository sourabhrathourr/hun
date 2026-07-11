package config

import (
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

// HunDir returns the configured Hun data directory, defaulting to ~/.hun, and creates it if needed.
func HunDir() (string, error) {
	dir := strings.TrimSpace(os.Getenv("HUN_HOME"))
	if dir == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		dir = filepath.Join(home, ".hun")
	}
	dir = filepath.Clean(dir)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return "", err
	}
	return dir, nil
}

// LoadGlobal reads ~/.hun/config.yml, returning defaults if it doesn't exist.
func LoadGlobal() (*Global, error) {
	dir, err := HunDir()
	if err != nil {
		return defaultGlobal(), nil
	}

	path := filepath.Join(dir, "config.yml")
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return defaultGlobal(), nil
		}
		return nil, err
	}

	g := defaultGlobal()
	if err := yaml.Unmarshal(data, g); err != nil {
		return nil, err
	}
	return g, nil
}

func defaultGlobal() *Global {
	return &Global{
		Defaults: GlobalDefaults{
			AutoCD:           true,
			ShowLogsOnSwitch: true,
		},
		Ports: PortsConfig{
			DefaultOffset: 1,
		},
	}
}

// UnsupportedGlobalSettings returns configured fields that are currently parsed but not applied.
func UnsupportedGlobalSettings(g *Global) []string {
	if g == nil {
		return nil
	}
	unsupported := make([]string, 0, 3)

	defaults := defaultGlobal()
	if g.Defaults.AutoCD != defaults.Defaults.AutoCD || g.Defaults.ShowLogsOnSwitch != defaults.Defaults.ShowLogsOnSwitch {
		unsupported = append(unsupported, "defaults")
	}
	if g.Hotkeys.Peek != "" || g.Hotkeys.Switch != "" {
		unsupported = append(unsupported, "hotkeys")
	}

	return unsupported
}
