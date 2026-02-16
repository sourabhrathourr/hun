package tui

import (
	"fmt"
	"strings"

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
}

func (m logsModel) View() string {
	title := serviceSelected.Render(m.service)
	header := title
	if m.search != "" {
		header += "  " + descStyle.Render("/" + m.search)
	}

	visible := m.height - 2 // Reserve for header
	if visible < 1 {
		visible = 1
	}

	filtered := m.filteredLines()

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
		text := line.Text
		if line.IsErr {
			text = logError.Render(text)
		} else {
			text = logText.Render(text)
		}
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
		if strings.Contains(strings.ToLower(line.Text), lower) {
			result = append(result, line)
		}
	}
	return result
}
