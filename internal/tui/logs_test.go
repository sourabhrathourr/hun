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

func TestLogsViewShowsStoppedServiceState(t *testing.T) {
	m := logsModel{
		service:       "api",
		serviceStatus: "stopped",
		width:         80,
		height:        12,
		lines: []daemon.LogLine{{
			Timestamp: time.Now(),
			Text:      "old log line that should not be rendered in stopped state",
		}},
	}

	view := m.View()
	if !strings.Contains(view, "Service is currently stopped") {
		t.Fatalf("expected stopped-state title in logs view, got %q", view)
	}
	if strings.Contains(view, "old log line") {
		t.Fatalf("expected log rows hidden while stopped, got %q", view)
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

func TestLogsWrapToggleBuildsMultipleRows(t *testing.T) {
	m := logsModel{
		service: "svc",
		width:   36,
		height:  12,
		lines: []daemon.LogLine{{
			Timestamp: time.Now(),
			Text:      "this is a very long line that should wrap into multiple rows when wrap mode is enabled",
		}},
	}

	rowsWithoutWrap := m.buildRenderedRows(m.filteredLines())
	if len(rowsWithoutWrap) != 1 {
		t.Fatalf("expected 1 row without wrap, got %d", len(rowsWithoutWrap))
	}

	m.toggleWrap()
	rowsWithWrap := m.buildRenderedRows(m.filteredLines())
	if len(rowsWithWrap) <= 1 {
		t.Fatalf("expected wrapped rows > 1, got %d", len(rowsWithWrap))
	}
}

func TestSelectionWithWrapMovesByRenderedRow(t *testing.T) {
	base := time.Now()
	m := logsModel{
		service:    "svc",
		width:      46,
		height:     12,
		autoScroll: false,
		wrap:       true,
		lines: []daemon.LogLine{
			{Timestamp: base, Text: "short one"},
			{Timestamp: base.Add(time.Second), Text: "this is a very long log line that wraps across multiple rendered rows"},
			{Timestamp: base.Add(2 * time.Second), Text: "short two"},
		},
	}
	m.jumpTop()
	m.startSelectionMode()
	m.moveCursor(1)

	if m.selectionAnchor != 0 || m.selectionEnd != 1 {
		t.Fatalf("expected row-based selection 0..1 after single down in wrap mode, got %d..%d", m.selectionAnchor, m.selectionEnd)
	}
	if m.cursorRow != 1 {
		t.Fatalf("expected cursorRow=1 after single down, got %d", m.cursorRow)
	}
}

func TestCopyPayloadDedupesWrappedRowsInSelection(t *testing.T) {
	base := time.Now()
	m := logsModel{
		service:    "svc",
		width:      46,
		height:     12,
		autoScroll: false,
		wrap:       true,
		lines: []daemon.LogLine{
			{Timestamp: base, Text: "first"},
			{Timestamp: base.Add(time.Second), Text: "this is a very long log line that wraps across multiple rendered rows"},
			{Timestamp: base.Add(2 * time.Second), Text: "third"},
		},
	}
	m.jumpTop()
	m.startSelectionMode()
	for i := 0; i < 3; i++ {
		m.moveCursor(1)
	}

	payload, count := m.copyPayload()
	if count != 2 {
		t.Fatalf("expected 2 copied lines (first + wrapped long), got %d payload=%q", count, payload)
	}
	if strings.Count(payload, "\n") != 1 {
		t.Fatalf("expected 2 newline-separated lines, got payload=%q", payload)
	}
}

func TestLogsAllViewCopyIncludesServiceName(t *testing.T) {
	m := logsModel{
		service: "all",
		width:   80,
		height:  10,
		lines: []daemon.LogLine{{
			Timestamp: time.Now(),
			Service:   "api",
			Text:      "hello",
		}},
	}
	payload, count := m.copyPayload()
	if count != 1 {
		t.Fatalf("copy count = %d, want 1", count)
	}
	if !strings.Contains(payload, "[api] hello") {
		t.Fatalf("copy payload should include service name, got %q", payload)
	}
}

func TestLogsUnreadLifecycleWithFollowPauseAndResume(t *testing.T) {
	base := time.Now()
	m := logsModel{
		service:    "svc",
		width:      80,
		height:     12,
		autoScroll: true,
	}
	m.setLines([]daemon.LogLine{{
		Timestamp: base,
		Text:      "line-1",
	}})
	if m.unread != 0 {
		t.Fatalf("unread = %d, want 0 in follow mode", m.unread)
	}

	m.moveCursor(-1)
	if m.autoScroll {
		t.Fatal("expected follow mode paused after manual cursor move")
	}

	m.setLines([]daemon.LogLine{
		{Timestamp: base, Text: "line-1"},
		{Timestamp: base.Add(time.Second), Text: "line-2"},
	})
	if m.unread == 0 {
		t.Fatal("expected unread > 0 when new lines arrive while paused")
	}

	m.jumpBottom()
	if !m.autoScroll {
		t.Fatal("expected follow mode resumed at bottom")
	}
	if m.unread != 0 {
		t.Fatalf("expected unread reset after jumpBottom, got %d", m.unread)
	}
}

func TestLogsSelectionBoundsClampOnFilterChanges(t *testing.T) {
	m := logsModel{
		service: "svc",
		width:   80,
		height:  10,
		lines: []daemon.LogLine{
			{Timestamp: time.Now(), Text: "alpha"},
			{Timestamp: time.Now(), Text: "beta"},
			{Timestamp: time.Now(), Text: "gamma"},
		},
		selectionMode:   true,
		selectionAnchor: 0,
		selectionEnd:    2,
		cursor:          2,
	}

	m.setSearch("beta")
	start, end, ok := m.selectionBounds(len(m.filteredLines()))
	if !ok {
		t.Fatal("expected selection to remain active after filter")
	}
	if start != 0 || end != 0 {
		t.Fatalf("selection bounds = %d..%d, want 0..0 after clamp", start, end)
	}
}

func TestMoveCursorToBottomResumesFollow(t *testing.T) {
	base := time.Now()
	m := logsModel{
		service: "svc",
		width:   80,
		height:  12,
		lines: []daemon.LogLine{
			{Timestamp: base, Text: "l1"},
			{Timestamp: base.Add(time.Second), Text: "l2"},
			{Timestamp: base.Add(2 * time.Second), Text: "l3"},
			{Timestamp: base.Add(3 * time.Second), Text: "l4"},
		},
		autoScroll: false,
		cursor:     1,
	}
	m.normalize()

	m.moveCursor(10)
	if !m.autoScroll {
		t.Fatal("expected follow to resume when moving back to bottom")
	}
	if m.unread != 0 {
		t.Fatalf("expected unread reset on follow resume, got %d", m.unread)
	}
}

func TestMoveCursorDownOnLastLineResumesLive(t *testing.T) {
	base := time.Now()
	m := logsModel{
		service: "svc",
		width:   42,
		height:  10,
		wrap:    true,
		lines: []daemon.LogLine{
			{Timestamp: base, Text: "line-1"},
			{Timestamp: base.Add(time.Second), Text: "this is a very long last line that wraps and still counts as the last log line"},
		},
		autoScroll: false,
	}
	m.normalize()

	rows := m.buildRenderedRows(m.filteredLines())
	first, _, ok := rowBoundsForLine(rows, len(m.lines)-1)
	if !ok {
		t.Fatal("expected rendered rows for last line")
	}

	// Simulate paused mode with cursor on last logical line.
	m.cursorRow = first
	m.cursor = len(m.lines) - 1
	m.autoScroll = false

	m.moveCursor(1)
	if !m.autoScroll {
		t.Fatal("expected down on last line to resume live mode")
	}
	if m.cursor != len(m.lines)-1 {
		t.Fatalf("cursor = %d, want %d (last line) when live resumes", m.cursor, len(m.lines)-1)
	}
}

func TestScrollRowsSelectionReachesLastLineAtBottom(t *testing.T) {
	base := time.Now()
	lines := make([]daemon.LogLine, 0, 80)
	for i := 0; i < 80; i++ {
		lines = append(lines, daemon.LogLine{
			Timestamp: base.Add(time.Duration(i) * time.Second),
			Text:      "line",
		})
	}

	m := logsModel{
		service:       "svc",
		width:         100,
		height:        10,
		autoScroll:    false,
		selectionMode: true,
		lines:         lines,
	}
	m.selectionAnchor = 0
	m.selectionEnd = 0
	m.cursor = 0
	m.normalize()

	for i := 0; i < 200; i++ {
		m.scrollRows(2)
	}

	last := len(m.filteredLines()) - 1
	if m.cursor != last {
		t.Fatalf("cursor = %d, want %d (last line) after scrolling to bottom in selection mode", m.cursor, last)
	}
	if m.selectionEnd != last {
		t.Fatalf("selectionEnd = %d, want %d (last line)", m.selectionEnd, last)
	}
}

func TestScrollRowsToBottomResumesLiveWhenNotSelecting(t *testing.T) {
	base := time.Now()
	lines := make([]daemon.LogLine, 0, 60)
	for i := 0; i < 60; i++ {
		lines = append(lines, daemon.LogLine{
			Timestamp: base.Add(time.Duration(i) * time.Second),
			Text:      "line",
		})
	}

	m := logsModel{
		service:    "svc",
		width:      100,
		height:     10,
		autoScroll: false,
		lines:      lines,
	}
	m.cursor = 0
	m.normalize()

	for i := 0; i < 200; i++ {
		m.scrollRows(2)
		if m.autoScroll {
			break
		}
	}

	if !m.autoScroll {
		t.Fatal("expected live mode to resume when wheel-scrolling to bottom outside selection mode")
	}
	last := len(m.filteredLines()) - 1
	if m.cursor != last {
		t.Fatalf("cursor = %d, want %d when live resumes at bottom", m.cursor, last)
	}
}

func TestLogsSelectionHighlightFillsFullRowWidth(t *testing.T) {
	m := logsModel{
		service:       "svc",
		width:         60,
		height:        10,
		autoScroll:    false,
		cursor:        0,
		selectionMode: true,
		lines: []daemon.LogLine{{
			Timestamp: time.Now(),
			Text:      "hello world",
		}},
	}
	m.selectionAnchor = 0
	m.selectionEnd = 0
	m.normalize()

	view := m.View()
	rows := strings.Split(view, "\n")
	if len(rows) < 3 {
		t.Fatalf("expected at least 3 rows in logs view, got %d", len(rows))
	}
	line := rows[2]
	if got := lipgloss.Width(line); got != m.width {
		t.Fatalf("highlighted row width = %d, want %d", got, m.width)
	}
	if !strings.Contains(line, "hello world") {
		t.Fatalf("expected highlighted row to contain log text, got %q", line)
	}
}

func TestLogsStatusTextUsesLiveLabel(t *testing.T) {
	live := logsModel{autoScroll: true}.statusText()
	if !strings.Contains(live, "LIVE") {
		t.Fatalf("expected LIVE status label, got %q", live)
	}
	if strings.Contains(live, "FOLLOW") {
		t.Fatalf("did not expect FOLLOW label, got %q", live)
	}

	paused := logsModel{autoScroll: false}.statusText()
	if !strings.Contains(paused, "PAUSED") {
		t.Fatalf("expected PAUSED status label, got %q", paused)
	}
	if strings.Contains(paused, "END=FOLLOW") {
		t.Fatalf("did not expect END=FOLLOW hint, got %q", paused)
	}
}

func TestStartSelectionModeResetsRangeToCursor(t *testing.T) {
	base := time.Now()
	m := logsModel{
		service:         "svc",
		width:           80,
		height:          10,
		autoScroll:      false,
		selectionMode:   true,
		selectionAnchor: 0,
		selectionEnd:    40,
		cursor:          12,
	}
	for i := 0; i < 50; i++ {
		m.lines = append(m.lines, daemon.LogLine{
			Timestamp: base.Add(time.Duration(i) * time.Second),
			Text:      "line",
		})
	}
	m.normalize()

	m.startSelectionMode()
	if !m.selectionMode {
		t.Fatal("expected selection mode enabled")
	}
	if m.selectionAnchor != m.cursor || m.selectionEnd != m.cursor {
		t.Fatalf("expected range reset to cursor=%d, got %d..%d", m.cursor, m.selectionAnchor, m.selectionEnd)
	}
}

func TestStartSelectionModePausesLive(t *testing.T) {
	m := logsModel{
		service:    "svc",
		width:      80,
		height:     10,
		autoScroll: true,
		lines: []daemon.LogLine{
			{Timestamp: time.Now(), Text: "line-1"},
			{Timestamp: time.Now().Add(time.Second), Text: "line-2"},
		},
	}
	m.setLines(m.lines)

	m.startSelectionMode()
	if m.autoScroll {
		t.Fatal("expected live paused when starting selection")
	}
	if !m.selectionMode {
		t.Fatal("expected selection mode enabled")
	}
}

func TestPrimedSelectionStaysSingleRowOnIncomingLogs(t *testing.T) {
	base := time.Now()
	m := logsModel{
		service:    "svc",
		width:      80,
		height:     10,
		autoScroll: false,
		lines: []daemon.LogLine{
			{Timestamp: base, Text: "line-1"},
			{Timestamp: base.Add(time.Second), Text: "line-2"},
			{Timestamp: base.Add(2 * time.Second), Text: "line-3"},
		},
	}
	m.jumpBottom()
	m.startSelectionMode()
	if !m.selectionPrimed {
		t.Fatal("expected primed selection after starting selection mode")
	}

	m.setLines([]daemon.LogLine{
		{Timestamp: base, Text: "line-1"},
		{Timestamp: base.Add(time.Second), Text: "line-2"},
		{Timestamp: base.Add(2 * time.Second), Text: "line-3"},
		{Timestamp: base.Add(3 * time.Second), Text: "line-4"},
	})

	if m.selectionAnchor != m.selectionEnd {
		t.Fatalf("expected single-row selection to remain after incoming logs, got %d..%d", m.selectionAnchor, m.selectionEnd)
	}
}

func TestLineStyleWithStateDoesNotMutateGlobalSeverityStyle(t *testing.T) {
	originalBg := logInfo.GetBackground()
	_ = lineStyleWithState(logInfo, true)
	afterBg := logInfo.GetBackground()

	if originalBg != afterBg {
		t.Fatalf("expected logInfo background to remain unchanged, before=%v after=%v", originalBg, afterBg)
	}
}
