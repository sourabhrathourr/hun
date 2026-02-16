package config

import (
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

// HunDir returns the path to ~/.hun/, creating it if needed.
func HunDir() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	dir := filepath.Join(home, ".hun")
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
