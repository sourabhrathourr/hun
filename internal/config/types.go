package config

// Project represents a .hun.yml project configuration.
type Project struct {
	Name     string              `yaml:"name"`
	Services map[string]*Service `yaml:"services"`
	Hooks    Hooks               `yaml:"hooks,omitempty"`
	Logs     LogsConfig          `yaml:"logs,omitempty"`
	Detect   DetectConfig        `yaml:"detect,omitempty"`
}

// Service represents a single service within a project.
type Service struct {
	Cmd       string            `yaml:"cmd"`
	Cwd       string            `yaml:"cwd,omitempty"`
	Port      int               `yaml:"port,omitempty"`
	PortEnv   string            `yaml:"port_env,omitempty"`
	Ready     string            `yaml:"ready,omitempty"`
	Env       map[string]string `yaml:"env,omitempty"`
	DependsOn []string          `yaml:"depends_on,omitempty"`
	Restart   string            `yaml:"restart,omitempty"` // "on_failure" or ""
}

// Hooks defines lifecycle hooks for a project.
type Hooks struct {
	PreStart string `yaml:"pre_start,omitempty"`
	PostStop string `yaml:"post_stop,omitempty"`
}

// LogsConfig controls log rotation settings.
type LogsConfig struct {
	MaxSize   string `yaml:"max_size,omitempty"`  // e.g. "10MB"
	MaxFiles  int    `yaml:"max_files,omitempty"` // e.g. 3
	Retention string `yaml:"retention,omitempty"` // e.g. "7d"
}

// DetectConfig stores metadata about auto-detection mode used to generate the file.
type DetectConfig struct {
	Version string `yaml:"version,omitempty"` // v2
	Profile string `yaml:"profile,omitempty"` // local, compose, hybrid
}

// Global represents ~/.hun/config.yml global configuration.
type Global struct {
	Defaults GlobalDefaults `yaml:"defaults,omitempty"`
	ScanDirs []string       `yaml:"scan_dirs,omitempty"`
	Ports    PortsConfig    `yaml:"ports,omitempty"`
	Hotkeys  HotkeysConfig  `yaml:"hotkeys,omitempty"`
}

// GlobalDefaults holds default behavior settings.
type GlobalDefaults struct {
	AutoCD           bool `yaml:"auto_cd"`
	ShowLogsOnSwitch bool `yaml:"show_logs_on_switch"`
}

// PortsConfig holds port management settings.
type PortsConfig struct {
	DefaultOffset int `yaml:"default_offset"`
}

// HotkeysConfig holds global hotkey bindings.
type HotkeysConfig struct {
	Peek   string `yaml:"peek,omitempty"`
	Switch string `yaml:"switch,omitempty"`
}
