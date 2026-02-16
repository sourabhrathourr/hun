package tui

import (
	"fmt"
	"strings"
)

type pickerModel struct {
	visible  bool
	items    []pickerItem
	filtered []pickerItem
	selected int
	input    string
	width    int
	height   int
}

type pickerItem struct {
	name    string
	running bool
	svcs    int
}

func (m *pickerModel) filter() {
	if m.input == "" {
		m.filtered = m.items
		return
	}

	lower := strings.ToLower(m.input)
	m.filtered = nil
	for _, item := range m.items {
		if strings.Contains(strings.ToLower(item.name), lower) {
			m.filtered = append(m.filtered, item)
		}
	}
	if m.selected >= len(m.filtered) {
		m.selected = len(m.filtered) - 1
	}
	if m.selected < 0 {
		m.selected = 0
	}
}

func (m pickerModel) View() string {
	if !m.visible {
		return ""
	}

	title := pickerTitle.Render("projects")
	input := pickerInput.Render("> " + m.input + "_")

	var lines []string
	lines = append(lines, title)
	lines = append(lines, "")
	lines = append(lines, input)
	lines = append(lines, "")

	// Running projects first
	hasRunning := false
	for i, item := range m.filtered {
		if !item.running {
			continue
		}
		hasRunning = true
		cursor := "  "
		style := pickerItemNormal
		if i == m.selected {
			cursor = "\u25b8 "
			style = pickerItemActive
		}
		dot := pickerItemRunning.Render("\u25cf ")
		svcs := descStyle.Render(fmt.Sprintf("%d svcs", item.svcs))
		lines = append(lines, cursor+dot+style.Render(item.name)+"    "+svcs)
	}

	if hasRunning {
		lines = append(lines, descStyle.Render("  \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500"))
	}

	// Stopped projects
	for i, item := range m.filtered {
		if item.running {
			continue
		}
		cursor := "  "
		style := pickerItemNormal
		if i == m.selected {
			cursor = "\u25b8 "
			style = pickerItemActive
		}
		lines = append(lines, cursor+style.Render(item.name))
	}

	lines = append(lines, "")
	lines = append(lines, descStyle.Render("[enter] start/focus  [esc] cancel"))

	content := strings.Join(lines, "\n")
	return pickerStyle.Render(content)
}
