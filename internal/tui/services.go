package tui

import (
	"fmt"

	"github.com/charmbracelet/lipgloss"
)

type serviceItem struct {
	name    string
	port    int
	running bool
	ready   bool
	crashed bool
	stopped bool
}

type servicesModel struct {
	items    []serviceItem
	selected int
	height   int
	width    int
	active   bool
}

func (m servicesModel) View() string {
	titleStyle := serviceNormal
	focusArrow := paneFocusInactive.Render("▸")
	if m.active {
		focusArrow = paneFocusActive.Render("▸")
		titleStyle = serviceTitleStyle
	}
	title := focusArrow + " " + titleStyle.Render("Services") + " " + serviceTitleCount.Render(fmt.Sprintf("(%d)", len(m.items)))
	lines := []string{title, ""}

	for i, item := range m.items {
		dot := dotStopped
		if item.crashed {
			dot = dotCrashed
		} else if item.running {
			dot = dotRunning
		} else if item.stopped {
			dot = dotStopped
		}

		cursor := "  "
		style := serviceNormal
		if i == m.selected {
			cursorStyle := paneFocusInactive
			if m.active {
				cursorStyle = serviceCursor
			}
			cursor = cursorStyle.Render("\u25b8") + " "
			style = serviceSelected
		}

		port := ""
		if item.port > 0 {
			port = " " + portStyle.Render(fmt.Sprintf(":%d", item.port))
		}

		ready := ""
		if item.ready {
			ready = " " + readyCheck
		}

		line := fmt.Sprintf("%s%s %s%s%s", cursor, dot, style.Render(item.name), ready, port)
		lines = append(lines, line)
	}

	content := lipgloss.JoinVertical(lipgloss.Left, lines...)
	return serviceListStyle.Width(m.width).Height(m.height).Render(content)
}
