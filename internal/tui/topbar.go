package tui

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
)

type topBarModel struct {
	mode     string // "focus" or "multitask"
	projects []projectTab
	focused  int
	width    int
}

type projectTab struct {
	name    string
	running bool
}

func (m topBarModel) View() string {
	left := lipgloss.NewStyle().Bold(true).Render("hun")
	modeLabel := modeStyle.Render(" \u2500\u2500 " + m.mode + " ")

	var tabs []string
	for i, p := range m.projects {
		dot := dotStopped
		if p.running {
			dot = dotRunning
		}

		style := topBarProjectInactive
		if i == m.focused {
			dot = lipgloss.NewStyle().Foreground(colorPrimary).Render("\u25cf")
			style = topBarProjectActive
		}

		tab := dot + " " + style.Render(p.name)
		tabs = append(tabs, tab)
	}

	projList := strings.Join(tabs, "    ")
	bar := left + modeLabel + projList
	return topBarStyle.Width(m.width).Render(bar)
}
