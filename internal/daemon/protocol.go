package daemon

const (
	// LegacyProtocolVersion is used by daemon builds that only replied to ping with a plain "pong" string.
	LegacyProtocolVersion = 1
	// CurrentProtocolVersion is the expected API protocol between CLI/TUI clients and daemon.
	CurrentProtocolVersion = 12
)

var (
	buildVersion = "dev"
	buildCommit  = "none"
)

// SetVersionInfo supplies build metadata before the daemon starts.
func SetVersionInfo(version, commit string) {
	buildVersion = version
	buildCommit = commit
}
