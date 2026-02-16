package tui

import "github.com/charmbracelet/lipgloss"

var (
	// Colors
	colorPrimary   = lipgloss.Color("#FF6B35")
	colorSecondary = lipgloss.Color("#6C757D")
	colorSuccess   = lipgloss.Color("#28A745")
	colorDanger    = lipgloss.Color("#DC3545")
	colorMuted     = lipgloss.Color("#6C757D")
	colorBg        = lipgloss.Color("#1A1A2E")
	colorFg        = lipgloss.Color("#E0E0E0")
	colorBorder    = lipgloss.Color("#333355")
	colorHighlight = lipgloss.Color("#FF6B35")

	// Dot indicators
	dotRunning = lipgloss.NewStyle().Foreground(colorSuccess).Render("\u25cf")
	dotCrashed = lipgloss.NewStyle().Foreground(colorDanger).Render("\u25cf")
	dotStopped = lipgloss.NewStyle().Foreground(colorMuted).Render("\u25cb")

	// Top bar
	topBarStyle = lipgloss.NewStyle().
			Padding(0, 1).
			Bold(true)

	topBarProjectActive = lipgloss.NewStyle().
				Foreground(colorFg).
				Bold(true)

	topBarProjectInactive = lipgloss.NewStyle().
				Foreground(colorMuted)

	modeStyle = lipgloss.NewStyle().
			Foreground(colorSecondary)

	// Service list
	serviceListStyle = lipgloss.NewStyle().
				Padding(0, 1)

	serviceSelected = lipgloss.NewStyle().
			Foreground(colorHighlight).
			Bold(true)

	serviceNormal = lipgloss.NewStyle().
			Foreground(colorFg)

	portStyle = lipgloss.NewStyle().
			Foreground(colorMuted)

	readyCheck = lipgloss.NewStyle().
			Foreground(colorSuccess).Render("\u2713")

	// Log viewer
	logTimestamp = lipgloss.NewStyle().
			Foreground(colorMuted)

	logText = lipgloss.NewStyle().
		Foreground(colorFg)

	logError = lipgloss.NewStyle().
			Foreground(colorDanger)

	// Status bar
	statusBarStyle = lipgloss.NewStyle().
			Padding(0, 1).
			Foreground(colorMuted)

	keyStyle = lipgloss.NewStyle().
			Foreground(colorHighlight).
			Bold(true)

	descStyle = lipgloss.NewStyle().
			Foreground(colorMuted)

	// Borders
	borderStyle = lipgloss.NewStyle().
			Border(lipgloss.NormalBorder()).
			BorderForeground(colorBorder)

	// Picker
	pickerStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(colorHighlight).
			Padding(1, 2)

	pickerTitle = lipgloss.NewStyle().
			Foreground(colorHighlight).
			Bold(true)

	pickerInput = lipgloss.NewStyle().
			Foreground(colorFg)

	pickerItemActive = lipgloss.NewStyle().
			Foreground(colorHighlight).
			Bold(true)

	pickerItemNormal = lipgloss.NewStyle().
			Foreground(colorFg)

	pickerItemRunning = lipgloss.NewStyle().
			Foreground(colorSuccess)
)
