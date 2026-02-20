package client

import (
	"encoding/json"
	"testing"

	"github.com/sourabhrathourr/hun/internal/daemon"
)

func TestParsePingProtocol(t *testing.T) {
	tests := []struct {
		name string
		raw  string
		want int
	}{
		{
			name: "current protocol payload",
			raw:  `{"status":"pong","protocol":2}`,
			want: 2,
		},
		{
			name: "legacy pong string",
			raw:  `"pong"`,
			want: daemon.LegacyProtocolVersion,
		},
		{
			name: "legacy payload without protocol",
			raw:  `{"status":"pong"}`,
			want: daemon.LegacyProtocolVersion,
		},
		{
			name: "unknown payload falls back legacy",
			raw:  `{"status":"ok"}`,
			want: daemon.LegacyProtocolVersion,
		},
		{
			name: "invalid json falls back legacy",
			raw:  `not-json`,
			want: daemon.LegacyProtocolVersion,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := parsePingProtocol(json.RawMessage(tc.raw))
			if got != tc.want {
				t.Fatalf("parsePingProtocol(%s) = %d, want %d", tc.raw, got, tc.want)
			}
		})
	}
}
