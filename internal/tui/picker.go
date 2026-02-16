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
		m.filtered = m.buildFiltered(m.items)
	} else {
		lower := strings.ToLower(m.input)
		var matched []pickerItem
		for _, item := range m.items {
			if strings.Contains(strings.ToLower(item.name), lower) {
				matched = append(matched, item)
			}
		}
		m.filtered = m.buildFiltered(matched)
	}
	m.clampSelected()
}

// buildFiltered returns items sorted: running first, then stopped.
func (m *pickerModel) buildFiltered(items []pickerItem) []pickerItem {
	var running, stopped []pickerItem
	for _, item := range items {
		if item.running {
			running = append(running, item)
		} else {
			stopped = append(stopped, item)
		}
	}
	return append(running, stopped...)
}

func (m *pickerModel) clampSelected() {
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
	input := pickerInput.Render("> " + m.input + "\u2588")

	var lines []string
	lines = append(lines, title)
	lines = append(lines, "")
	lines = append(lines, input)
	lines = append(lines, "")

	if len(m.filtered) == 0 {
		lines = append(lines, pickerEmpty.Render("No matching projects"))
	} else {
		// Single pass through filtered (running first, then stopped)
		passedRunning := false
		for i, item := range m.filtered {
			// Insert separator when transitioning from running to stopped
			if !item.running && !passedRunning {
				// Check if there were any running items before
				if i > 0 {
					lines = append(lines, descStyle.Render("  \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500"))
				}
				passedRunning = true
			}

			cursor := "  "
			style := pickerItemNormal
			if i == m.selected {
				cursor = serviceCursor.Render("\u25b8") + " "
				style = pickerItemActive
			}

			if item.running {
				dot := pickerItemRunning.Render("\u25cf ")
				svcs := descStyle.Render(fmt.Sprintf("%d svcs", item.svcs))
				lines = append(lines, cursor+dot+style.Render(item.name)+"    "+svcs)
			} else {
				lines = append(lines, cursor+style.Render(item.name))
			}
		}
	}

	lines = append(lines, "")
	lines = append(lines, descStyle.Render("[enter] start/focus  [esc] cancel"))

	content := strings.Join(lines, "\n")
	return pickerStyle.Render(content)
}
