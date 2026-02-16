package tui

import "github.com/charmbracelet/lipgloss"

var (
	// Colors — neutral + green palette
	colorPrimary   = lipgloss.Color("#04B575")
	colorSecondary = lipgloss.Color("#888888")
	colorSuccess   = lipgloss.Color("#04B575")
	colorDanger    = lipgloss.Color("#E55561")
	colorWarning   = lipgloss.Color("#E2B714")
	colorMuted     = lipgloss.Color("#888888")
	colorDim       = lipgloss.Color("#555555")
	colorBg        = lipgloss.Color("#101010")
	colorPanelBg   = lipgloss.Color("#1C1C1C")
	colorFg        = lipgloss.Color("#E0E0E0")
	colorBorder    = lipgloss.Color("#333333")
	colorHighlight = lipgloss.Color("#04B575")

	// Dot indicators
	dotRunning = lipgloss.NewStyle().Foreground(colorSuccess).Render("\u25cf")
	dotCrashed = lipgloss.NewStyle().Foreground(colorDanger).Render("\u25cf")
	dotStopped = lipgloss.NewStyle().Foreground(colorDim).Render("\u25cb")

	// Top bar
	topBarStyle = lipgloss.NewStyle().
			Padding(0, 1).
			Bold(true)

	topBarProjectActive = lipgloss.NewStyle().
				Foreground(colorFg).
				Bold(true)

	topBarProjectInactive = lipgloss.NewStyle().
				Foreground(colorMuted)

	// Mode badges
	modeFocusBadge = lipgloss.NewStyle().
			Background(colorSuccess).
			Foreground(lipgloss.Color("#101010")).
			Padding(0, 1).
			Bold(true)

	modeMultitaskBadge = lipgloss.NewStyle().
				Background(colorWarning).
				Foreground(lipgloss.Color("#101010")).
				Padding(0, 1).
				Bold(true)

	// Service list
	serviceListStyle = lipgloss.NewStyle().
				Padding(0, 1)

	serviceTitleStyle = lipgloss.NewStyle().
				Foreground(colorHighlight).
				Bold(true)

	serviceTitleCount = lipgloss.NewStyle().
				Foreground(colorMuted)

	serviceSelected = lipgloss.NewStyle().
			Foreground(colorHighlight).
			Bold(true)

	serviceNormal = lipgloss.NewStyle().
			Foreground(colorFg)

	serviceCursor = lipgloss.NewStyle().
			Foreground(colorHighlight)

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

	logEmptyStyle = lipgloss.NewStyle().
			Foreground(colorDim)

	// Search bar
	searchLabelStyle = lipgloss.NewStyle().
				Foreground(colorHighlight).
				Bold(true)

	searchBarStyle = lipgloss.NewStyle().
			Bold(true)

	searchHintStyle = lipgloss.NewStyle().
			Foreground(colorDim)

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
			Border(lipgloss.RoundedBorder()).
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

	pickerEmpty = lipgloss.NewStyle().
			Foreground(colorDim)

	// Toast
	toastStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(colorHighlight).
			Padding(0, 1)

	toastErrorStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(colorDanger).
			Padding(0, 1)

	// Welcome / empty state
	welcomeTitleStyle = lipgloss.NewStyle().
				Foreground(colorHighlight).
				Bold(true)

	welcomeTextStyle = lipgloss.NewStyle().
				Foreground(colorMuted)

	welcomeKeyStyle = lipgloss.NewStyle().
			Foreground(colorHighlight).
			Bold(true)
)
