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
}

type servicesModel struct {
	items    []serviceItem
	selected int
	height   int
	width    int
}

func (m servicesModel) View() string {
	title := lipgloss.NewStyle().Bold(true).Foreground(colorFg).Render("Services")
	lines := []string{title, ""}

	for i, item := range m.items {
		cursor := "  "
		style := serviceNormal
		if i == m.selected {
			cursor = "\u25b8 "
			style = serviceSelected
		}

		dot := dotStopped
		if item.crashed {
			dot = dotCrashed
		} else if item.running {
			dot = dotRunning
		}

		port := ""
		if item.port > 0 {
			port = portStyle.Render(fmt.Sprintf(":%d", item.port))
		}

		ready := " "
		if item.ready {
			ready = readyCheck
		}

		line := fmt.Sprintf("%s%s %s %s %s", cursor, style.Render(item.name), port, ready, dot)
		lines = append(lines, line)
	}

	content := lipgloss.JoinVertical(lipgloss.Left, lines...)
	return serviceListStyle.Width(m.width).Height(m.height).Render(content)
}
