package tui

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
	reflowtruncate "github.com/muesli/reflow/truncate"
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
	left := lipgloss.NewStyle().Bold(true).Foreground(colorFg).Render("hun")

	var badge string
	if m.mode == "focus" {
		badge = modeFocusBadge.Render("FOCUS")
	} else {
		badge = modeMultitaskBadge.Render("MULTI")
	}

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
	bar := left + "  " + badge + "  " + projList
	contentWidth := m.width - 2 // topBarStyle applies horizontal padding 1+1
	if contentWidth < 1 {
		contentWidth = 1
	}
	bar = reflowtruncate.StringWithTail(bar, uint(contentWidth), "…")
	return topBarStyle.Width(m.width).Render(bar)
}

func (m topBarModel) projectIndexAtX(x int) int {
	contentX := x - 1 // top bar style has horizontal padding of 1
	if contentX < 0 {
		return -1
	}

	left := lipgloss.NewStyle().Bold(true).Foreground(colorFg).Render("hun")
	badge := modeFocusBadge.Render("FOCUS")
	if m.mode != "focus" {
		badge = modeMultitaskBadge.Render("MULTI")
	}
	prefix := lipgloss.Width(left + "  " + badge + "  ")
	if contentX < prefix {
		return -1
	}

	cursor := prefix
	for i, project := range m.projects {
		tabWidth := len([]rune("● ")) + len([]rune(project.name))
		if contentX >= cursor && contentX < cursor+tabWidth {
			return i
		}
		cursor += tabWidth
		if i < len(m.projects)-1 {
			cursor += 4
		}
	}
	return -1
}
