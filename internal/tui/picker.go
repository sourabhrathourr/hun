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
	offset   int
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
		matched := make([]pickerItem, 0, len(m.items))
		for _, item := range m.items {
			if strings.Contains(strings.ToLower(item.name), lower) {
				matched = append(matched, item)
			}
		}
		m.filtered = m.buildFiltered(matched)
	}
	m.clampSelected()
	m.clampOffset()
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
	if len(m.filtered) == 0 {
		m.selected = 0
		return
	}
	if m.selected >= len(m.filtered) {
		m.selected = len(m.filtered) - 1
	}
	if m.selected < 0 {
		m.selected = 0
	}
}

func (m *pickerModel) maxRows() int {
	if m.height <= 0 {
		return len(m.filtered)
	}
	rows := m.height - 8
	if rows < 1 {
		rows = 1
	}
	return rows
}

func (m *pickerModel) clampOffset() {
	maxRows := m.maxRows()
	maxOffset := len(m.filtered) - maxRows
	if maxOffset < 0 {
		maxOffset = 0
	}
	if m.offset < 0 {
		m.offset = 0
	}
	if m.offset > maxOffset {
		m.offset = maxOffset
	}
	if len(m.filtered) == 0 {
		m.offset = 0
		return
	}
	if m.selected < m.offset {
		m.offset = m.selected
	}
	if m.selected >= m.offset+maxRows {
		m.offset = m.selected - maxRows + 1
	}
	if m.offset < 0 {
		m.offset = 0
	}
}

func (m *pickerModel) move(delta int) {
	if len(m.filtered) == 0 {
		return
	}
	m.selected += delta
	m.clampSelected()
	m.clampOffset()
}

func (m pickerModel) selectedItem() (pickerItem, bool) {
	if len(m.filtered) == 0 {
		return pickerItem{}, false
	}
	if m.selected < 0 || m.selected >= len(m.filtered) {
		return pickerItem{}, false
	}
	return m.filtered[m.selected], true
}

func (m pickerModel) indexAtVisibleRow(row int) int {
	if row < 0 {
		return -1
	}
	idx := m.offset + row
	if idx < 0 || idx >= len(m.filtered) {
		return -1
	}
	return idx
}

func (m pickerModel) View() string {
	if !m.visible {
		return ""
	}

	title := pickerTitle.Render("projects")
	input := pickerInput.Render("> " + m.input + "\u2588")

	lines := []string{title, "", input, ""}

	if len(m.filtered) == 0 {
		lines = append(lines, pickerEmpty.Render("No matching projects"))
	} else {
		maxRows := m.maxRows()
		start := m.offset
		if start < 0 {
			start = 0
		}
		if start > len(m.filtered) {
			start = len(m.filtered)
		}
		end := start + maxRows
		if end > len(m.filtered) {
			end = len(m.filtered)
		}

		for i := start; i < end; i++ {
			item := m.filtered[i]
			if i > 0 && item.running != m.filtered[i-1].running {
				lines = append(lines, descStyle.Render("  ──────────"))
			}

			cursor := "  "
			style := pickerItemNormal
			if i == m.selected {
				cursor = serviceCursor.Render("▸") + " "
				style = pickerItemActive
			}

			if item.running {
				dot := pickerItemRunning.Render("● ")
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
	style := pickerStyle
	if m.width > 0 {
		style = style.Width(m.width)
	}
	if m.height > 0 {
		style = style.Height(m.height)
	}
	return style.Render(content)
}
