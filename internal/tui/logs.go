package tui

import (
	"fmt"
	"regexp"
	"sort"
	"strings"
	"unicode"

	"github.com/charmbracelet/lipgloss"
	"github.com/sourabhrathourr/hun/internal/daemon"
)

type logsModel struct {
	lines         []daemon.LogLine
	service       string
	serviceStatus string
	active        bool
	autoScroll    bool
	offset        int // row offset (not line index)
	height        int
	width         int
	search        string
	searching     bool
	wrap          bool
	unread        int

	cursor          int // index in filtered log lines (derived from cursorRow)
	cursorRow       int // index in rendered rows
	selectionMode   bool
	selectionAnchor int // index in rendered rows
	selectionEnd    int // index in rendered rows
	selectionPrimed bool
}

type renderedLogRow struct {
	lineIndex    int
	timestamp    string
	text         string
	severity     logSeverity
	continuation bool
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
	focusArrow := paneFocusInactive.Render("▸")
	titleStyle := serviceNormal
	if m.active {
		focusArrow = paneFocusActive.Render("▸")
		titleStyle = serviceSelected
	}
	title := focusArrow + " " + titleStyle.Render(m.service)
	status := m.statusText()
	header := title + "  " + descStyle.Render(status)

	if m.searching {
		header += "  " + searchLabelStyle.Render("/") + " " + searchBarStyle.Render(m.search+"\u2588")
	} else if m.search != "" {
		header += "  " + searchLabelStyle.Render("/"+m.search) + "  " + searchHintStyle.Render("[esc to clear]")
	}

	visible := m.visibleRows()
	filtered := m.filteredLines()
	rows := m.buildRenderedRows(filtered)

	if m.service != "" && m.service != "all" && m.serviceStatus == "stopped" {
		return m.renderStoppedState(header)
	}

	if len(rows) == 0 {
		lines := []string{header, "", logEmptyStyle.Render("No log output yet...")}
		return strings.Join(lines, "\n")
	}

	start := m.offset
	if m.autoScroll {
		start = len(rows) - visible
	}
	if start < 0 {
		start = 0
	}
	if maxStart := maxInt(0, len(rows)-visible); start > maxStart {
		start = maxStart
	}
	end := start + visible
	if end > len(rows) {
		end = len(rows)
	}

	selStart, selEnd, hasSelection := m.selectionBounds(len(rows))

	lines := []string{header, ""}
	for i := start; i < end; i++ {
		row := rows[i]
		isFocused := i == m.cursorRow
		isSelected := hasSelection && i >= selStart && i <= selEnd

		markerGlyph := "  "
		if isFocused {
			if row.continuation {
				markerGlyph = "│ "
			} else {
				markerGlyph = "▸ "
			}
		}

		markerStyle := lineStyleWithState(lipgloss.NewStyle(), isSelected)
		if isFocused {
			cursorStyle := paneFocusInactive
			if m.active {
				cursorStyle = serviceCursor
			}
			markerStyle = lineStyleWithState(cursorStyle, isSelected)
		}
		marker := markerStyle.Render(markerGlyph)

		ts := row.timestamp
		if row.continuation {
			ts = strings.Repeat(" ", len([]rune(ts)))
		}
		tsStyle := lineStyleWithState(logTimestamp, isSelected)
		sep := lineStyleWithState(lipgloss.NewStyle(), isSelected).Render(" ")
		textStyle := lineStyleWithState(styleForSeverity(row.severity), isSelected)
		rendered := marker + tsStyle.Render(ts) + sep + textStyle.Render(row.text)
		if isSelected {
			padWidth := m.width - lipgloss.Width(rendered)
			if padWidth > 0 {
				padStyle := lineStyleWithState(lipgloss.NewStyle(), isSelected)
				rendered += padStyle.Render(strings.Repeat(" ", padWidth))
			}
		}
		lines = append(lines, rendered)
	}

	return strings.Join(lines, "\n")
}

func (m logsModel) renderStoppedState(header string) string {
	panelWidth := m.width - 4
	if panelWidth < 28 {
		panelWidth = m.width
	}
	if panelWidth < 20 {
		panelWidth = 20
	}

	title := stoppedStateTitleStyle.Render("Service is currently stopped")
	body := descStyle.Render("No live logs for ") + serviceNormal.Render(m.service) + descStyle.Render(".")
	hint := descStyle.Render("Press ") + keyStyle.Render("r") + descStyle.Render(" to start it again.")

	panel := stoppedStateBoxStyle.Width(panelWidth).Render(
		lipgloss.JoinVertical(lipgloss.Left, title, "", body, hint),
	)
	return strings.Join([]string{
		header,
		"",
		lipgloss.PlaceHorizontal(m.width, lipgloss.Center, panel),
	}, "\n")
}

func (m logsModel) statusText() string {
	live := "PAUSED"
	if m.autoScroll {
		live = "LIVE"
	}
	wrap := "TRUNC"
	if m.wrap {
		wrap = "WRAP"
	}
	parts := []string{live, wrap}
	if !m.autoScroll {
		if m.unread > 0 {
			parts = append(parts, fmt.Sprintf("+%d new", m.unread))
		}
	}
	if m.selectionMode {
		parts = append(parts, "SELECT")
	}
	return strings.Join(parts, "  ")
}

func (m logsModel) visibleRows() int {
	visible := m.height - 2 // header + spacer
	if visible < 1 {
		visible = 1
	}
	return visible
}

func (m logsModel) filteredLines() []daemon.LogLine {
	if m.search == "" {
		return m.lines
	}
	result := make([]daemon.LogLine, 0, len(m.lines))
	lower := strings.ToLower(m.search)
	for _, line := range m.lines {
		if strings.Contains(strings.ToLower(sanitizeLogText(line.Text)), lower) {
			result = append(result, line)
		}
	}
	return result
}

func (m logsModel) buildRenderedRows(filtered []daemon.LogLine) []renderedLogRow {
	if len(filtered) == 0 {
		return nil
	}

	tsWidth := len("[15:04:05]")
	maxTextWidth := m.width - 2 - tsWidth - 1 // marker + timestamp + spacing
	if maxTextWidth < 1 {
		maxTextWidth = 1
	}

	rows := make([]renderedLogRow, 0, len(filtered))
	for i, line := range filtered {
		text := sanitizeLogText(line.Text)
		if m.service == "all" {
			text = "[" + line.Service + "] " + text
		}
		sev := classifyLogSeverity(text, line.IsErr)
		wrapped := []string{text}
		if m.wrap {
			wrapped = wrapLogText(text, maxTextWidth)
		} else {
			wrapped = []string{truncateText(text, maxTextWidth)}
		}
		if len(wrapped) == 0 {
			wrapped = []string{""}
		}

		ts := fmt.Sprintf("[%s]", line.Timestamp.Format("15:04:05"))
		for j, chunk := range wrapped {
			rows = append(rows, renderedLogRow{
				lineIndex:    i,
				timestamp:    ts,
				text:         chunk,
				severity:     sev,
				continuation: j > 0,
			})
		}
	}
	return rows
}

func (m *logsModel) setLines(lines []daemon.LogLine) {
	oldLen := len(m.filteredLines())
	m.lines = lines
	filtered := m.filteredLines()
	newLen := len(filtered)
	rows := m.buildRenderedRows(filtered)

	if newLen == 0 {
		m.cursor = 0
		m.cursorRow = 0
		m.offset = 0
		m.unread = 0
		m.clearSelection()
		return
	}

	if m.autoScroll {
		m.cursor = newLen - 1
		m.cursorRow = len(rows) - 1
		m.unread = 0
	} else if newLen > oldLen {
		m.unread += newLen - oldLen
	}

	m.normalize()
}

func (m *logsModel) setSearch(search string) {
	m.search = search
	m.normalize()
}

func (m *logsModel) toggleWrap() {
	m.wrap = !m.wrap
	m.normalize()
}

func (m *logsModel) toggleLive() {
	if m.autoScroll {
		m.autoScroll = false
		m.normalize()
		return
	}
	m.jumpBottom()
}

func (m *logsModel) jumpTop() {
	rows := m.buildRenderedRows(m.filteredLines())
	if len(rows) == 0 {
		m.autoScroll = false
		m.offset = 0
		m.cursor = 0
		m.cursorRow = 0
		if m.selectionMode {
			m.selectionEnd = 0
		}
		return
	}
	m.autoScroll = false
	m.offset = 0
	m.cursorRow = 0
	m.cursor = rows[0].lineIndex
	if m.selectionMode {
		m.selectionEnd = m.cursorRow
		m.selectionPrimed = false
	}
	m.normalize()
}

func (m *logsModel) jumpBottom() {
	rows := m.buildRenderedRows(m.filteredLines())
	if len(rows) == 0 {
		m.autoScroll = true
		m.offset = 0
		m.cursor = 0
		m.cursorRow = 0
		m.unread = 0
		return
	}
	m.autoScroll = true
	m.cursorRow = len(rows) - 1
	m.cursor = rows[m.cursorRow].lineIndex
	if m.selectionMode {
		m.selectionEnd = m.cursorRow
	}
	m.unread = 0
	m.normalize()
}

func (m *logsModel) moveCursor(delta int) {
	filtered := m.filteredLines()
	rows := m.buildRenderedRows(filtered)
	if len(rows) == 0 {
		return
	}

	if m.cursorRow < 0 || m.cursorRow >= len(rows) {
		rowIdx := rowIndexForLine(rows, m.cursor, true)
		if rowIdx < 0 {
			rowIdx = len(rows) - 1
		}
		m.cursorRow = rowIdx
	}
	m.cursor = rows[m.cursorRow].lineIndex

	// Down at the bottom should keep/resume live mode instead of pausing.
	if delta > 0 && !m.selectionMode {
		atBottomRow := m.cursorRow == len(rows)-1
		atLastLine := m.cursor == len(filtered)-1
		if m.autoScroll || atBottomRow || atLastLine {
			m.jumpBottom()
			return
		}
	}

	if m.autoScroll {
		m.autoScroll = false
	}

	m.cursorRow += delta
	if m.cursorRow < 0 {
		m.cursorRow = 0
	}
	if m.cursorRow >= len(rows) {
		m.cursorRow = len(rows) - 1
	}
	m.cursor = rows[m.cursorRow].lineIndex

	if delta > 0 && !m.selectionMode && (m.cursorRow == len(rows)-1 || m.cursor == len(filtered)-1) {
		m.jumpBottom()
		return
	}
	if m.selectionMode {
		m.selectionEnd = m.cursorRow
		m.selectionPrimed = false
	}
	m.normalize()
}

func (m *logsModel) page(delta int) {
	step := m.visibleRows() / 2
	if step < 1 {
		step = 1
	}
	m.moveCursor(delta * step)
}

func (m *logsModel) scrollRows(delta int) {
	rows := m.buildRenderedRows(m.filteredLines())
	if len(rows) == 0 {
		return
	}

	if m.autoScroll {
		m.autoScroll = false
		m.offset = maxInt(0, len(rows)-m.visibleRows())
	}

	maxOffset := maxInt(0, len(rows)-m.visibleRows())
	m.offset += delta
	if m.offset < 0 {
		m.offset = 0
	}
	if m.offset > maxOffset {
		m.offset = maxOffset
	}

	if delta > 0 && m.offset == maxOffset && !m.selectionMode {
		m.jumpBottom()
		return
	}

	visible := m.visibleRows()
	targetRow := m.offset
	if delta > 0 {
		targetRow = m.offset + visible - 1
		if targetRow >= len(rows) {
			targetRow = len(rows) - 1
		}
	}
	if targetRow >= 0 && targetRow < len(rows) {
		m.cursorRow = targetRow
		m.cursor = rows[targetRow].lineIndex
		if m.selectionMode {
			m.selectionEnd = m.cursorRow
			m.selectionPrimed = false
		}
	}
	m.normalize()
}

func (m *logsModel) startSelectionMode() {
	rows := m.buildRenderedRows(m.filteredLines())
	if len(rows) == 0 {
		m.clearSelection()
		return
	}

	// Entering selection should pause live mode so range stays stable.
	// When entering from live/auto-scroll mode, always pin the cursor to the
	// actual last row from the current lines — not the stale cursorRow from the
	// last setLines call, which may be behind if logs arrived since then.
	if m.autoScroll {
		m.autoScroll = false
		m.cursorRow = len(rows) - 1
	}

	m.selectionMode = true
	if m.cursorRow < 0 || m.cursorRow >= len(rows) {
		rowIdx := rowIndexForLine(rows, m.cursor, true)
		if rowIdx < 0 {
			rowIdx = len(rows) - 1
		}
		m.cursorRow = rowIdx
	}
	m.cursor = rows[m.cursorRow].lineIndex
	m.selectionAnchor = m.cursorRow
	m.selectionEnd = m.cursorRow
	m.selectionPrimed = true
	m.normalize()
}

func (m *logsModel) clearSelection() {
	m.selectionMode = false
	m.selectionAnchor = 0
	m.selectionEnd = 0
	m.selectionPrimed = false
}

func (m *logsModel) setCursorFromVisibleRow(relativeRow int, extendSelection bool) {
	rows := m.buildRenderedRows(m.filteredLines())
	if len(rows) == 0 {
		return
	}

	visible := m.visibleRows()
	start := m.offset
	if m.autoScroll {
		start = len(rows) - visible
		if start < 0 {
			start = 0
		}
	}
	idx := start + relativeRow
	if idx < 0 {
		idx = 0
	}
	if idx >= len(rows) {
		idx = len(rows) - 1
	}
	if extendSelection {
		if !m.selectionMode {
			m.selectionMode = true
			if m.cursorRow >= 0 && m.cursorRow < len(rows) {
				m.selectionAnchor = m.cursorRow
			} else {
				m.selectionAnchor = idx
			}
		}
		m.selectionEnd = idx
		m.selectionPrimed = false
	} else {
		if m.selectionMode {
			m.selectionAnchor = idx
			m.selectionEnd = idx
			m.selectionPrimed = true
		}
	}

	m.autoScroll = false
	m.cursorRow = idx
	m.cursor = rows[idx].lineIndex
	if !m.selectionMode && !extendSelection && idx == len(rows)-1 {
		m.jumpBottom()
		return
	}
	m.normalize()
}

func (m *logsModel) startSelectionFromVisibleRow(relativeRow int) {
	rows := m.buildRenderedRows(m.filteredLines())
	if len(rows) == 0 {
		return
	}

	visible := m.visibleRows()
	start := m.offset
	if m.autoScroll {
		start = len(rows) - visible
		if start < 0 {
			start = 0
		}
	}
	idx := start + relativeRow
	if idx < 0 {
		idx = 0
	}
	if idx >= len(rows) {
		idx = len(rows) - 1
	}

	m.autoScroll = false
	m.selectionMode = true
	m.cursorRow = idx
	m.cursor = rows[idx].lineIndex
	m.selectionAnchor = idx
	m.selectionEnd = idx
	m.selectionPrimed = false
	m.normalize()
}

func (m logsModel) lineIndexAtVisibleRow(relativeRow int) int {
	rows := m.buildRenderedRows(m.filteredLines())
	if len(rows) == 0 {
		return -1
	}

	visible := m.visibleRows()
	start := m.offset
	if m.autoScroll {
		start = len(rows) - visible
		if start < 0 {
			start = 0
		}
	}
	idx := start + relativeRow
	if idx < 0 {
		idx = 0
	}
	if idx >= len(rows) {
		idx = len(rows) - 1
	}
	return rows[idx].lineIndex
}

func (m logsModel) copyPayload() (string, int) {
	filtered := m.filteredLines()
	if len(filtered) == 0 {
		return "", 0
	}
	rows := m.buildRenderedRows(filtered)
	if len(rows) == 0 {
		return "", 0
	}

	includeService := m.service == "all"
	lines := make([]string, 0, 8)

	if start, end, ok := m.selectionBounds(len(rows)); ok {
		lastLineIdx := -1
		for i := start; i <= end && i < len(rows); i++ {
			lineIdx := rows[i].lineIndex
			if lineIdx < 0 || lineIdx >= len(filtered) || lineIdx == lastLineIdx {
				continue
			}
			lines = append(lines, formatCopyLine(filtered[lineIdx], includeService))
			lastLineIdx = lineIdx
		}
		return strings.Join(lines, "\n"), len(lines)
	}

	idx := m.cursor
	if m.cursorRow >= 0 && m.cursorRow < len(rows) {
		idx = rows[m.cursorRow].lineIndex
	}
	if idx < 0 || idx >= len(filtered) {
		idx = rows[len(rows)-1].lineIndex
	}
	lines = append(lines, formatCopyLine(filtered[idx], includeService))
	return strings.Join(lines, "\n"), len(lines)
}

func formatCopyLine(line daemon.LogLine, includeService bool) string {
	ts := line.Timestamp.Format("15:04:05")
	text := sanitizeLogText(line.Text)
	if includeService {
		return fmt.Sprintf("[%s] [%s] %s", ts, line.Service, text)
	}
	return fmt.Sprintf("[%s] %s", ts, text)
}

func (m logsModel) selectionBounds(totalRows int) (start int, end int, ok bool) {
	if !m.selectionMode || totalRows == 0 {
		return 0, 0, false
	}
	a := m.selectionAnchor
	b := m.selectionEnd
	if a < 0 {
		a = 0
	}
	if b < 0 {
		b = 0
	}
	if a >= totalRows {
		a = totalRows - 1
	}
	if b >= totalRows {
		b = totalRows - 1
	}
	if a > b {
		a, b = b, a
	}
	return a, b, true
}

func (m *logsModel) normalize() {
	filtered := m.filteredLines()
	if len(filtered) == 0 {
		m.cursor = 0
		m.cursorRow = 0
		m.offset = 0
		m.unread = 0
		m.clearSelection()
		return
	}

	rows := m.buildRenderedRows(filtered)
	if len(rows) == 0 {
		m.cursor = 0
		m.cursorRow = 0
		m.offset = 0
		m.unread = 0
		m.clearSelection()
		return
	}

	if m.cursorRow < 0 || m.cursorRow >= len(rows) {
		rowIdx := rowIndexForLine(rows, m.cursor, true)
		if rowIdx < 0 {
			rowIdx = len(rows) - 1
		}
		m.cursorRow = rowIdx
	}
	m.cursor = rows[m.cursorRow].lineIndex

	visible := m.visibleRows()
	maxOffset := maxInt(0, len(rows)-visible)

	if m.autoScroll {
		m.offset = maxOffset
		m.cursorRow = len(rows) - 1
		m.cursor = rows[m.cursorRow].lineIndex
		m.unread = 0
	} else {
		if m.offset < 0 {
			m.offset = 0
		}
		if m.offset > maxOffset {
			m.offset = maxOffset
		}

		if m.cursorRow < m.offset {
			m.offset = m.cursorRow
		}
		if m.cursorRow >= m.offset+visible {
			m.offset = m.cursorRow - visible + 1
			if m.offset < 0 {
				m.offset = 0
			}
		}
	}

	if m.selectionMode {
		if m.selectionPrimed {
			m.selectionAnchor = m.cursorRow
			m.selectionEnd = m.cursorRow
		}
		if m.selectionAnchor < 0 {
			m.selectionAnchor = 0
		}
		if m.selectionAnchor >= len(rows) {
			m.selectionAnchor = len(rows) - 1
		}
		if m.selectionEnd < 0 {
			m.selectionEnd = 0
		}
		if m.selectionEnd >= len(rows) {
			m.selectionEnd = len(rows) - 1
		}
	}
}

func rowIndexForLine(rows []renderedLogRow, lineIdx int, preferLast bool) int {
	first := -1
	last := -1
	for i, row := range rows {
		if row.lineIndex != lineIdx {
			continue
		}
		if first == -1 {
			first = i
		}
		last = i
	}
	if first == -1 {
		return -1
	}
	if preferLast {
		return last
	}
	return first
}

func lineStyleWithState(style lipgloss.Style, selected bool) lipgloss.Style {
	// Lip Gloss style setters mutate the underlying rules map. Always copy before
	// applying per-row state so global palette styles don't get contaminated.
	s := style.Copy()
	if selected {
		return s.Background(lipgloss.Color("#173026"))
	}
	return s
}

func rowBoundsForLine(rows []renderedLogRow, lineIdx int) (first int, last int, ok bool) {
	first = -1
	last = -1
	for i, row := range rows {
		if row.lineIndex != lineIdx {
			continue
		}
		if first == -1 {
			first = i
		}
		last = i
	}
	if first == -1 {
		return 0, 0, false
	}
	return first, last, true
}

func wrapLogText(text string, width int) []string {
	if width <= 0 {
		return []string{""}
	}
	if text == "" {
		return []string{""}
	}

	words := strings.Fields(text)
	if len(words) == 0 {
		return []string{""}
	}

	lines := make([]string, 0, len(words))
	current := ""

	flush := func() {
		if current != "" {
			lines = append(lines, current)
			current = ""
		}
	}

	for _, word := range words {
		for len([]rune(word)) > width {
			part := string([]rune(word)[:width])
			word = string([]rune(word)[width:])
			if current == "" {
				lines = append(lines, part)
			} else {
				flush()
				lines = append(lines, part)
			}
		}

		if current == "" {
			current = word
			continue
		}
		candidate := current + " " + word
		if len([]rune(candidate)) <= width {
			current = candidate
			continue
		}
		flush()
		current = word
	}
	flush()

	if len(lines) == 0 {
		return []string{""}
	}
	return lines
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
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

func (m *logsModel) sortLinesChronologically() {
	sort.Slice(m.lines, func(i, j int) bool {
		return m.lines[i].Timestamp.Before(m.lines[j].Timestamp)
	})
	m.normalize()
}
