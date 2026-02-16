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
	title := serviceTitleStyle.Render("Services") + " " + serviceTitleCount.Render(fmt.Sprintf("(%d)", len(m.items)))
	lines := []string{title, ""}

	for i, item := range m.items {
		dot := dotStopped
		if item.crashed {
			dot = dotCrashed
		} else if item.running {
			dot = dotRunning
		}

		cursor := "  "
		style := serviceNormal
		if i == m.selected {
			cursor = serviceCursor.Render("\u25b8") + " "
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
