package daemon

const (
	// LegacyProtocolVersion is used by daemon builds that only replied to ping with a plain "pong" string.
	LegacyProtocolVersion = 1
	// CurrentProtocolVersion is the expected API protocol between CLI/TUI clients and daemon.
	CurrentProtocolVersion = 2
)
