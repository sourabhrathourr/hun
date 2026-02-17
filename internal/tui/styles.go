package tui

import "github.com/charmbracelet/lipgloss"

var (
	// Colors — neutral + green palette
	colorPrimary      = lipgloss.Color("#04B575")
	colorSecondary    = lipgloss.Color("#888888")
	colorSuccess      = lipgloss.Color("#04B575")
	colorDanger       = lipgloss.Color("#D86A72")
	colorWarning      = lipgloss.Color("#D9B86A")
	colorMuted        = lipgloss.Color("#888888")
	colorDim          = lipgloss.Color("#555555")
	colorBg           = lipgloss.Color("#101010")
	colorPanelBg      = lipgloss.Color("#1C1C1C")
	colorFg           = lipgloss.Color("#C8C0B6")
	colorBorder       = lipgloss.Color("#333333")
	colorHighlight    = lipgloss.Color("#04B575")
	colorLogTimestamp = lipgloss.Color("#7A7268")
	colorLogText      = lipgloss.Color("#B8B0A6")
	colorLogInfo      = lipgloss.Color("#C2B8AA")
	colorLogDebug     = lipgloss.Color("#8A8178")
	colorLogWarning   = lipgloss.Color("#D8BA72")
	colorLogError     = lipgloss.Color("#D88178")

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
			Foreground(colorLogTimestamp)

	logText = lipgloss.NewStyle().
		Foreground(colorLogText)

	logInfo = lipgloss.NewStyle().
		Foreground(colorLogInfo)

	logDebug = lipgloss.NewStyle().
			Foreground(colorLogDebug)

	logWarning = lipgloss.NewStyle().
			Foreground(colorLogWarning)

	logError = lipgloss.NewStyle().
			Foreground(colorLogError)

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
			Foreground(colorFg).
			Background(lipgloss.Color("#1A1A1A")).
			Padding(0, 1)

	toastErrorStyle = lipgloss.NewStyle().
			Foreground(colorDanger).
			Background(lipgloss.Color("#1A1A1A")).
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
