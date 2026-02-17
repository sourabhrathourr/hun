package tui

import (
	"fmt"
	"regexp"
	"strings"
	"unicode"

	"github.com/charmbracelet/lipgloss"
	"github.com/sourabhrathourr/hun/internal/daemon"
)

type logsModel struct {
	lines      []daemon.LogLine
	service    string
	autoScroll bool
	offset     int
	height     int
	width      int
	search     string
	searching  bool
}

type logSeverity int

const (
	logSeverityNeutral logSeverity = iota
	logSeverityInfo
	logSeverityWarning
	logSeverityError
	logSeverityDebug
)

var (
	ansiCSIRegex            = regexp.MustCompile(`\x1b\[[0-9;?]*[ -/]*[@-~]`)
	ansiOSCRegex            = regexp.MustCompile(`\x1b\][^\a]*(?:\a|\x1b\\)`)
	jsonLevelRegex          = regexp.MustCompile(`(?i)"level"\s*:\s*"([a-z]+)"`)
	prefixLevelRegex        = regexp.MustCompile(`(?i)^\s*(?:\[[^\]]+\]\s*)?([a-z]+)\s*:`)
	keyValueLevelRegex      = regexp.MustCompile(`(?i)\b(?:level|lvl|severity)\s*[=:]\s*"?([a-z]+)"?`)
	processLevelRegex       = regexp.MustCompile(`(?i)\b(info|warn(?:ing)?|error|fatal|critical|debug|trace|verbose|panic)\/[a-z_][a-z0-9_:-]*\b`)
	infoTokenRegex          = regexp.MustCompile(`(?i)\binfo\b`)
	warningTokenRegex       = regexp.MustCompile(`(?i)\bwarn(?:ing)?\b`)
	errorTokenRegex         = regexp.MustCompile(`(?i)\b(error|fatal|panic|exception|traceback|critical|segfault|sigsegv)\b`)
	debugTokenRegex         = regexp.MustCompile(`(?i)\b(debug|trace|verbose)\b`)
	strongFailureTokenRegex = regexp.MustCompile(`(?i)\b(failed|failure|cannot|can't|unable|refused|timeout|timed out|permission denied|no such file)\b`)
	benignErrorContextRegex = regexp.MustCompile(`(?i)\b(no errors?|without errors?|0 errors?|error(s)?\s*[:=]\s*0)\b`)
	benignShutdownRegex     = regexp.MustCompile(`(?i)\b(polite quit request|warm shutdown|graceful shutdown|draining worker|shutting down worker|terminated by signal sigterm|received sigterm)\b`)
)

func (m logsModel) View() string {
	title := serviceSelected.Render(m.service)
	header := title

	// Search bar
	if m.searching {
		header += "  " + searchLabelStyle.Render("/") + " " + searchBarStyle.Render(m.search+"\u2588")
	} else if m.search != "" {
		header += "  " + searchLabelStyle.Render("/"+m.search) + "  " + searchHintStyle.Render("[esc to clear]")
	}

	visible := m.height - 2 // Reserve for header
	if visible < 1 {
		visible = 1
	}

	filtered := m.filteredLines()

	// Empty state
	if len(filtered) == 0 {
		var lines []string
		lines = append(lines, header)
		lines = append(lines, "")
		lines = append(lines, logEmptyStyle.Render("No log output yet..."))
		return strings.Join(lines, "\n")
	}

	start := m.offset
	if m.autoScroll {
		start = len(filtered) - visible
	}
	if start < 0 {
		start = 0
	}
	end := start + visible
	if end > len(filtered) {
		end = len(filtered)
	}

	var lines []string
	lines = append(lines, header)
	lines = append(lines, "")

	for i := start; i < end; i++ {
		line := filtered[i]
		ts := logTimestamp.Render(fmt.Sprintf("[%s]", line.Timestamp.Format("15:04:05")))
		text := sanitizeLogText(line.Text)
		sev := classifyLogSeverity(text, line.IsErr)
		maxTextWidth := m.width - lipgloss.Width(ts) - 1
		if maxTextWidth < 1 {
			maxTextWidth = 1
		}
		text = truncateText(text, maxTextWidth)
		text = styleForSeverity(sev).Render(text)
		lines = append(lines, ts+" "+text)
	}

	return strings.Join(lines, "\n")
}

func (m logsModel) filteredLines() []daemon.LogLine {
	if m.search == "" {
		return m.lines
	}
	var result []daemon.LogLine
	lower := strings.ToLower(m.search)
	for _, line := range m.lines {
		if strings.Contains(strings.ToLower(sanitizeLogText(line.Text)), lower) {
			result = append(result, line)
		}
	}
	return result
}

func sanitizeLogText(text string) string {
	if text == "" {
		return ""
	}
	// Strip terminal control sequences from service logs so they can't corrupt the TUI layout.
	text = ansiOSCRegex.ReplaceAllString(text, "")
	text = ansiCSIRegex.ReplaceAllString(text, "")

	var b strings.Builder
	b.Grow(len(text))
	for _, r := range text {
		switch r {
		case '\n', '\r':
			b.WriteRune(' ')
		case '\t':
			b.WriteString("    ")
		default:
			if unicode.IsControl(r) {
				continue
			}
			b.WriteRune(r)
		}
	}
	return strings.TrimSpace(b.String())
}

func styleForSeverity(sev logSeverity) lipgloss.Style {
	switch sev {
	case logSeverityError:
		return logError
	case logSeverityWarning:
		return logWarning
	case logSeverityInfo:
		return logInfo
	case logSeverityDebug:
		return logDebug
	default:
		return logText
	}
}

func classifyLogSeverity(text string, isErr bool) logSeverity {
	if text == "" {
		return logSeverityNeutral
	}
	lower := strings.ToLower(text)
	level := extractLevelHint(lower)
	switch level {
	case "error", "fatal", "critical", "panic":
		if benignShutdownRegex.MatchString(lower) {
			return logSeverityWarning
		}
		return logSeverityError
	case "warn", "warning":
		return logSeverityWarning
	case "info":
		return logSeverityInfo
	case "debug", "trace", "verbose":
		return logSeverityDebug
	}

	if benignShutdownRegex.MatchString(lower) {
		return logSeverityWarning
	}
	if warningTokenRegex.MatchString(lower) {
		return logSeverityWarning
	}
	if debugTokenRegex.MatchString(lower) {
		return logSeverityDebug
	}
	if errorTokenRegex.MatchString(lower) {
		if benignErrorContextRegex.MatchString(lower) {
			return logSeverityNeutral
		}
		return logSeverityError
	}
	if strongFailureTokenRegex.MatchString(lower) {
		return logSeverityError
	}
	if infoTokenRegex.MatchString(lower) {
		return logSeverityInfo
	}

	// stderr alone is not enough to classify as error.
	if isErr {
		return logSeverityNeutral
	}
	return logSeverityNeutral
}

func extractLevelHint(lower string) string {
	if m := jsonLevelRegex.FindStringSubmatch(lower); len(m) == 2 {
		return strings.TrimSpace(m[1])
	}
	if m := keyValueLevelRegex.FindStringSubmatch(lower); len(m) == 2 {
		return strings.TrimSpace(m[1])
	}
	if m := prefixLevelRegex.FindStringSubmatch(lower); len(m) == 2 {
		token := strings.TrimSpace(m[1])
		switch token {
		case "info", "warn", "warning", "error", "fatal", "critical", "debug", "trace", "verbose", "panic":
			return token
		}
	}
	if m := processLevelRegex.FindStringSubmatch(lower); len(m) == 2 {
		return strings.TrimSpace(m[1])
	}
	return ""
}
