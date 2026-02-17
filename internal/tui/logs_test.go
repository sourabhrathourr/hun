package tui

import (
	"strings"
	"testing"
	"time"

	"github.com/charmbracelet/lipgloss"
	"github.com/sourabhrathourr/hun/internal/daemon"
)

func TestLogsViewSanitizesControlSequencesAndClampsWidth(t *testing.T) {
	longRaw := "prefix\x1b[2J\x1b[H\r" + strings.Repeat("A", 300)

	m := logsModel{
		service: "agent",
		width:   80,
		height:  12,
		lines: []daemon.LogLine{{
			Timestamp: time.Now(),
			Text:      longRaw,
			IsErr:     false,
		}},
	}

	view := m.View()
	if strings.Contains(view, "\x1b[2J") || strings.Contains(view, "\x1b[H") {
		t.Fatalf("expected control sequences stripped from logs view")
	}
	if strings.Contains(view, "\r") {
		t.Fatalf("expected carriage return removed from logs view")
	}

	for _, line := range strings.Split(view, "\n") {
		if lipgloss.Width(line) > m.width {
			t.Fatalf("line width %d exceeds model width %d: %q", lipgloss.Width(line), m.width, line)
		}
	}
}

func TestSanitizeLogText(t *testing.T) {
	got := sanitizeLogText("hello\x1b[31m\rworld\x00\t!")
	if got != "hello world    !" {
		t.Fatalf("sanitizeLogText() = %q, want %q", got, "hello world    !")
	}
}

func TestClassifyLogSeverity(t *testing.T) {
	tests := []struct {
		name  string
		text  string
		isErr bool
		want  logSeverity
	}{
		{
			name:  "warning line from stderr stays warning",
			text:  "WARNING:agent:Patched ToolContext.parse_function_tools for compatibility",
			isErr: true,
			want:  logSeverityWarning,
		},
		{
			name:  "json info from stderr stays info",
			text:  `{"message":"starting worker","level":"INFO","name":"livekit.agents"}`,
			isErr: true,
			want:  logSeverityInfo,
		},
		{
			name:  "process level format is parsed",
			text:  "INFO/MainProcess] Connected to amqp://localhost:5672//",
			isErr: true,
			want:  logSeverityInfo,
		},
		{
			name:  "benign sigterm shutdown is warning",
			text:  "ERROR: Script was terminated by signal SIGTERM (Polite quit request)",
			isErr: true,
			want:  logSeverityWarning,
		},
		{
			name:  "strong failure is error",
			text:  "FATAL: unable to bind port: permission denied",
			isErr: true,
			want:  logSeverityError,
		},
		{
			name:  "stderr with no signal is neutral",
			text:  "stream chunk completed",
			isErr: true,
			want:  logSeverityNeutral,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := classifyLogSeverity(tc.text, tc.isErr); got != tc.want {
				t.Fatalf("classifyLogSeverity() = %v, want %v", got, tc.want)
			}
		})
	}
}
