package tui

import (
	"context"
	"encoding/json"
	"sort"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/key"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/sourabhrathourr/hun/internal/client"
	"github.com/sourabhrathourr/hun/internal/config"
	"github.com/sourabhrathourr/hun/internal/daemon"
	"github.com/sourabhrathourr/hun/internal/state"
)

// Model is the main TUI model.
type Model struct {
	topBar    topBarModel
	services  servicesModel
	logs      logsModel
	statusBar statusBarModel
	picker    pickerModel

	client *client.Client
	mode   string // "focus" or "multitask"
	width  int
	height int

	focusedProject string
	latestStatus   statusUpdateMsg
	allLogs        map[string][]daemon.LogLine // "project:service" → lines
	logCutoff      map[string]time.Time        // "project:service" → show logs after this time

	logCh            chan daemon.LogLine
	subErrCh         chan error
	subCancel        context.CancelFunc
	subProject       string
	subService       string
	forceResubscribe bool

	searching bool
	searchBuf string

	focusPromptVisible  bool
	focusPromptProjects []string
	focusPromptSelected int

	toast      string
	toastTimer int

	err error
}

type tickMsg time.Time
type statusUpdateMsg map[string]map[string]daemon.ServiceInfo
type logMsg daemon.LogLine
type toastExpireMsg struct{ id int }
type subscriptionErrMsg struct{ err error }
type retrySubscribeMsg struct{}
type logsFetchedMsg struct {
	project string
	service string
	lines   []daemon.LogLine
}

// New creates a new TUI model.
func New(multi bool) Model {
	mode := "focus"
	focused := ""
	if st, err := state.Load(); err == nil {
		if st.Mode == "multitask" {
			mode = "multitask"
		}
		focused = st.ActiveProject
	}
	if multi {
		mode = "multitask"
	}

	c, _ := client.New()

	m := Model{
		client:         c,
		mode:           mode,
		focusedProject: focused,
		allLogs:        make(map[string][]daemon.LogLine),
		logCutoff:      make(map[string]time.Time),
		logCh:          make(chan daemon.LogLine, 2048),
		subErrCh:       make(chan error, 32),
		topBar:         topBarModel{mode: mode},
		logs:           logsModel{autoScroll: true},
	}
	return m
}

// Init implements tea.Model.
func (m Model) Init() tea.Cmd {
	return tea.Batch(
		m.fetchStatusCmd(),
		m.tickCmd(),
		m.waitForLogCmd(),
		m.waitForSubErrCmd(),
	)
}

// Update implements tea.Model.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.updateLayout()
		return m, nil

	case tea.KeyMsg:
		return m.handleKey(msg)

	case statusUpdateMsg:
		cmds := m.applyStatus(msg)
		if len(cmds) == 0 {
			return m, nil
		}
		return m, tea.Batch(cmds...)

	case logMsg:
		line := daemon.LogLine(msg)
		if !m.logPassesCutoff(line) {
			return m, m.waitForLogCmd()
		}
		key := projectServiceKey(line.Project, line.Service)
		m.allLogs[key] = append(m.allLogs[key], line)
		if len(m.allLogs[key]) > 10000 {
			m.allLogs[key] = m.allLogs[key][len(m.allLogs[key])-10000:]
		}

		if m.logs.service == "all" {
			m.refreshAllLogs()
		} else if m.focusedProject == line.Project && len(m.services.items) > 0 {
			sel := m.services.items[m.services.selected].name
			if sel == line.Service {
				m.logs.lines = m.allLogs[key]
			}
		}
		return m, m.waitForLogCmd()

	case logsFetchedMsg:
		key := projectServiceKey(msg.project, msg.service)
		lines := m.filterLinesForKey(key, msg.lines)
		m.allLogs[key] = lines
		if m.logs.service == "all" {
			m.refreshAllLogs()
		} else if m.focusedProject == msg.project && len(m.services.items) > 0 {
			svc := m.services.items[m.services.selected].name
			if svc == msg.service {
				m.logs.lines = lines
			}
		}
		return m, nil

	case subscriptionErrMsg:
		m.err = msg.err
		cmd := m.showToast("Log stream reconnecting...")
		m.forceResubscribe = true
		return m, tea.Batch(m.waitForSubErrCmd(), cmd, m.retrySubscribeCmd())

	case retrySubscribeMsg:
		m.ensureSubscription()
		return m, nil

	case tickMsg:
		return m, tea.Batch(m.fetchStatusCmd(), m.tickCmd())

	case toastExpireMsg:
		if msg.id == m.toastTimer {
			m.toast = ""
		}
		return m, nil

	case error:
		m.err = msg
		return m, nil
	}

	return m, nil
}

// View implements tea.Model.
func (m Model) View() string {
	if m.width == 0 {
		return "Loading..."
	}

	var view string

	if len(m.services.items) == 0 && len(m.topBar.projects) == 0 {
		view = m.viewWelcome()
	} else {
		topBar := m.topBar.View()
		statusBar := m.statusBar.View()

		// top bar (1) + separators (2) + toast row (1) + status bar (2)
		middleHeight := m.height - 6
		if middleHeight < 1 {
			middleHeight = 1
		}
		sidebarWidth := 24
		if m.width < 60 {
			sidebarWidth = 16
		}

		m.services.width = sidebarWidth
		m.services.height = middleHeight

		logsWidth := m.width - sidebarWidth - 3
		m.logs.width = logsWidth
		m.logs.height = middleHeight

		sidebar := m.services.View()
		logView := m.logs.View()

		middle := lipgloss.JoinHorizontal(
			lipgloss.Top,
			sidebar,
			lipgloss.NewStyle().Foreground(colorBorder).Render(" │ "),
			logView,
		)

		sep := lipgloss.NewStyle().Foreground(colorBorder).Width(m.width).Render(
			"─" + repeat("─", m.width-1),
		)

		toastLine := m.renderToastLine()
		parts := []string{topBar, sep, middle, sep, toastLine, statusBar}
		view = lipgloss.JoinVertical(lipgloss.Left, parts...)
	}

	if m.picker.visible {
		view = placeOverlay(m.width, m.height, m.picker.View(), view)
	}
	if m.focusPromptVisible {
		view = placeOverlay(m.width, m.height, m.viewFocusPrompt(), view)
	}

	// Always paint a full-frame buffer to avoid stale artifacts from previous frames.
	return lipgloss.NewStyle().Width(m.width).Height(m.height).Render(view)
}

func (m Model) viewWelcome() string {
	title := welcomeTitleStyle.Render("Welcome to hun")
	subtitle := welcomeTextStyle.Render("Seamless dev project context switching")

	keys := welcomeKeyStyle.Render("p") + welcomeTextStyle.Render(" open picker") + "    " +
		welcomeKeyStyle.Render("q") + welcomeTextStyle.Render(" quit")

	hint := welcomeTextStyle.Render("or run ") + welcomeKeyStyle.Render("hun run <project>") + welcomeTextStyle.Render(" from your terminal")

	content := lipgloss.JoinVertical(lipgloss.Center,
		"",
		title,
		"",
		subtitle,
		"",
		keys,
		"",
		hint,
		"",
	)

	return lipgloss.NewStyle().
		Width(m.width).
		Height(m.height).
		Align(lipgloss.Center, lipgloss.Center).
		Render(content)
}

func (m Model) viewFocusPrompt() string {
	if len(m.focusPromptProjects) == 0 {
		return ""
	}
	lines := []string{
		pickerTitle.Render("switch to focus"),
		"",
		descStyle.Render("Keep which project?"),
		"",
	}
	for i, p := range m.focusPromptProjects {
		prefix := "  "
		style := pickerItemNormal
		if i == m.focusPromptSelected {
			prefix = serviceCursor.Render("▸") + " "
			style = pickerItemActive
		}
		lines = append(lines, prefix+style.Render(p))
	}
	lines = append(lines, "")
	lines = append(lines, descStyle.Render("Others will be stopped."))
	lines = append(lines, descStyle.Render("[enter] confirm  [esc] cancel"))
	return pickerStyle.Render(lipgloss.JoinVertical(lipgloss.Left, lines...))
}

func (m *Model) showToast(text string) tea.Cmd {
	m.toastTimer++
	m.toast = text
	id := m.toastTimer
	return tea.Tick(2500*time.Millisecond, func(t time.Time) tea.Msg {
		return toastExpireMsg{id: id}
	})
}

func (m Model) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	if m.focusPromptVisible {
		return m.handleFocusPromptKey(msg)
	}
	if m.picker.visible {
		return m.handlePickerKey(msg)
	}
	if m.searching {
		return m.handleSearchKey(msg)
	}

	switch {
	case key.Matches(msg, key.NewBinding(key.WithKeys("q", "ctrl+c"))):
		m.cancelSubscription()
		return m, tea.Quit

	case key.Matches(msg, key.NewBinding(key.WithKeys("up", "k"))):
		if m.services.selected > 0 {
			m.services.selected--
			cmd := m.refreshLogs()
			if cmd != nil {
				return m, cmd
			}
		}

	case key.Matches(msg, key.NewBinding(key.WithKeys("down", "j"))):
		if m.services.selected < len(m.services.items)-1 {
			m.services.selected++
			cmd := m.refreshLogs()
			if cmd != nil {
				return m, cmd
			}
		}

	case key.Matches(msg, key.NewBinding(key.WithKeys("tab"))):
		if m.mode == "multitask" && len(m.topBar.projects) > 1 {
			m.topBar.focused = (m.topBar.focused + 1) % len(m.topBar.projects)
			newProject := m.topBar.projects[m.topBar.focused].name
			m.focusedProject = newProject
			cmds := []tea.Cmd{m.focusCmd(newProject)}
			cmds = append(cmds, m.refreshServices()...)
			return m, tea.Batch(cmds...)
		}

	case key.Matches(msg, key.NewBinding(key.WithKeys("r"))):
		svcName := ""
		if len(m.services.items) > 0 {
			svcName = m.services.items[m.services.selected].name
			m.markFreshLogsForService(m.focusedProject, svcName, time.Now())
		}
		cmd := tea.Batch(m.restartServiceCmd(), m.showToast("Restarting "+svcName+"..."))
		return m, cmd

	case key.Matches(msg, key.NewBinding(key.WithKeys("R"))):
		m.markFreshLogsForProject(m.focusedProject, time.Now())
		cmd := tea.Batch(m.restartProjectCmd(), m.showToast("Restarting project..."))
		return m, cmd

	case key.Matches(msg, key.NewBinding(key.WithKeys("p"))):
		m.openPicker()

	case key.Matches(msg, key.NewBinding(key.WithKeys("m"))):
		if m.mode == "focus" {
			m.mode = "multitask"
			m.topBar.mode = "multitask"
			m.statusBar.mode = "multitask"
			cmd := tea.Batch(m.focusCmd(m.focusedProject), m.showToast("Switched to multitask mode"))
			return m, cmd
		}

	case key.Matches(msg, key.NewBinding(key.WithKeys("f"))):
		if m.mode == "multitask" {
			if len(m.topBar.projects) > 1 {
				m.focusPromptVisible = true
				m.focusPromptProjects = nil
				for _, tab := range m.topBar.projects {
					m.focusPromptProjects = append(m.focusPromptProjects, tab.name)
				}
				m.focusPromptSelected = 0
				return m, nil
			}
			m.mode = "focus"
			m.topBar.mode = "focus"
			m.statusBar.mode = "focus"
			return m, tea.Batch(m.focusCmd(m.focusedProject), m.showToast("Switched to focus mode"))
		}

	case key.Matches(msg, key.NewBinding(key.WithKeys("s"))):
		if m.focusedProject != "" {
			cmd := tea.Batch(m.stopFocusedProjectCmd(), m.showToast("Stopping "+m.focusedProject+"..."))
			return m, cmd
		}

	case key.Matches(msg, key.NewBinding(key.WithKeys("/"))):
		m.searching = true
		m.searchBuf = ""
		m.logs.searching = true

	case key.Matches(msg, key.NewBinding(key.WithKeys("a"))):
		m.logs.service = "all"
		m.refreshAllLogs()
		m.ensureSubscription()
	}

	return m, nil
}

func (m Model) handleFocusPromptKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch {
	case key.Matches(msg, key.NewBinding(key.WithKeys("esc"))):
		m.focusPromptVisible = false
		return m, nil
	case key.Matches(msg, key.NewBinding(key.WithKeys("up", "k"))):
		if m.focusPromptSelected > 0 {
			m.focusPromptSelected--
		}
		return m, nil
	case key.Matches(msg, key.NewBinding(key.WithKeys("down", "j"))):
		if m.focusPromptSelected < len(m.focusPromptProjects)-1 {
			m.focusPromptSelected++
		}
		return m, nil
	case key.Matches(msg, key.NewBinding(key.WithKeys("enter"))):
		if len(m.focusPromptProjects) == 0 {
			m.focusPromptVisible = false
			return m, nil
		}
		keep := m.focusPromptProjects[m.focusPromptSelected]
		m.focusPromptVisible = false
		m.mode = "focus"
		m.topBar.mode = "focus"
		m.statusBar.mode = "focus"
		m.focusedProject = keep
		for i, tab := range m.topBar.projects {
			if tab.name == keep {
				m.topBar.focused = i
				break
			}
		}

		cmds := []tea.Cmd{m.focusCmd(keep), m.showToast("Switched to focus mode")}
		for _, project := range m.focusPromptProjects {
			if project != keep {
				cmds = append(cmds, m.stopProjectCmd(project))
			}
		}
		cmds = append(cmds, m.refreshServices()...)
		return m, tea.Batch(cmds...)
	}
	return m, nil
}

func (m Model) handlePickerKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch {
	case key.Matches(msg, key.NewBinding(key.WithKeys("ctrl+c"))):
		m.cancelSubscription()
		return m, tea.Quit

	case key.Matches(msg, key.NewBinding(key.WithKeys("esc"))):
		m.picker.visible = false

	case key.Matches(msg, key.NewBinding(key.WithKeys("enter"))):
		if len(m.picker.filtered) > 0 && m.picker.selected < len(m.picker.filtered) {
			item := m.picker.filtered[m.picker.selected]
			m.picker.visible = false
			m.focusedProject = item.name
			for i, tab := range m.topBar.projects {
				if tab.name == item.name {
					m.topBar.focused = i
					break
				}
			}
			m.refreshServices()
			cmds := []tea.Cmd{m.startProject(item.name), m.focusCmd(item.name), m.showToast("Starting " + item.name + "...")}
			return m, tea.Batch(cmds...)
		}

	case key.Matches(msg, key.NewBinding(key.WithKeys("up"))):
		if m.picker.selected > 0 {
			m.picker.selected--
		}
	case key.Matches(msg, key.NewBinding(key.WithKeys("down"))):
		if m.picker.selected < len(m.picker.filtered)-1 {
			m.picker.selected++
		}

	case key.Matches(msg, key.NewBinding(key.WithKeys("backspace"))):
		if len(m.picker.input) > 0 {
			m.picker.input = m.picker.input[:len(m.picker.input)-1]
			m.picker.filter()
		}

	default:
		if len(msg.Runes) > 0 {
			m.picker.input += string(msg.Runes)
			m.picker.filter()
		}
	}

	return m, nil
}

func (m Model) handleSearchKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch {
	case key.Matches(msg, key.NewBinding(key.WithKeys("esc"))):
		m.searching = false
		m.logs.searching = false
		m.searchBuf = ""
		m.logs.search = ""

	case key.Matches(msg, key.NewBinding(key.WithKeys("enter"))):
		m.searching = false
		m.logs.searching = false
		m.logs.search = m.searchBuf

	case key.Matches(msg, key.NewBinding(key.WithKeys("backspace"))):
		if len(m.searchBuf) > 0 {
			m.searchBuf = m.searchBuf[:len(m.searchBuf)-1]
			m.logs.search = m.searchBuf
		}

	default:
		if len(msg.Runes) > 0 {
			m.searchBuf += string(msg.Runes)
			m.logs.search = m.searchBuf
		}
	}

	return m, nil
}

func (m *Model) updateLayout() {
	m.topBar.width = m.width
	m.statusBar.width = m.width
	m.statusBar.mode = m.mode
}

func (m *Model) applyStatus(status statusUpdateMsg) []tea.Cmd {
	m.latestStatus = status

	var tabs []projectTab
	for name, svcs := range status {
		running := false
		for _, info := range svcs {
			if info.Running {
				running = true
				break
			}
		}
		tabs = append(tabs, projectTab{name: name, running: running})
	}
	sort.Slice(tabs, func(i, j int) bool { return tabs[i].name < tabs[j].name })
	m.topBar.projects = tabs

	cmds := make([]tea.Cmd, 0)
	if len(tabs) == 0 {
		m.focusedProject = ""
		m.topBar.focused = 0
		m.services.items = nil
		m.logs.lines = nil
		m.cancelSubscription()
		return cmds
	}

	focusedIndex := -1
	for i, tab := range tabs {
		if tab.name == m.focusedProject {
			focusedIndex = i
			break
		}
	}
	if focusedIndex == -1 {
		m.focusedProject = tabs[0].name
		focusedIndex = 0
		cmds = append(cmds, m.focusCmd(m.focusedProject))
	}
	m.topBar.focused = focusedIndex

	cmds = append(cmds, m.refreshServices()...)
	return cmds
}

func (m *Model) refreshServices() []tea.Cmd {
	status := m.latestStatus
	if status == nil {
		return nil
	}

	svcs, ok := status[m.focusedProject]
	if !ok {
		if len(m.topBar.projects) > 0 {
			m.focusedProject = m.topBar.projects[0].name
			m.topBar.focused = 0
			svcs = status[m.focusedProject]
		} else {
			m.services.items = nil
			m.logs.lines = nil
			m.cancelSubscription()
			return nil
		}
	}

	items := make([]serviceItem, 0, len(svcs))
	for name, info := range svcs {
		items = append(items, serviceItem{
			name:    name,
			port:    info.Port,
			running: info.Running,
			ready:   info.Ready,
			crashed: !info.Running && info.PID > 0,
		})
	}
	sort.Slice(items, func(i, j int) bool { return items[i].name < items[j].name })
	m.services.items = items

	if m.services.selected >= len(items) {
		m.services.selected = len(items) - 1
	}
	if m.services.selected < 0 {
		m.services.selected = 0
	}

	cmds := make([]tea.Cmd, 0, 1)
	if m.logs.service == "all" {
		m.refreshAllLogs()
		m.ensureSubscription()
	} else {
		if cmd := m.refreshLogs(); cmd != nil {
			cmds = append(cmds, cmd)
		}
	}
	return cmds
}

func (m *Model) refreshLogs() tea.Cmd {
	if len(m.services.items) == 0 {
		m.logs.lines = nil
		m.logs.service = ""
		m.cancelSubscription()
		return nil
	}

	svc := m.services.items[m.services.selected]
	m.logs.service = svc.name

	key := projectServiceKey(m.focusedProject, svc.name)
	m.logs.lines = m.allLogs[key]
	m.ensureSubscription()

	if len(m.logs.lines) == 0 {
		return m.fetchLogsCmd(m.focusedProject, svc.name)
	}
	return nil
}

func (m *Model) refreshAllLogs() {
	all := make([]daemon.LogLine, 0)
	prefix := m.focusedProject + ":"
	for key, lines := range m.allLogs {
		if strings.HasPrefix(key, prefix) {
			all = append(all, lines...)
		}
	}
	sort.Slice(all, func(i, j int) bool {
		return all[i].Timestamp.Before(all[j].Timestamp)
	})
	m.logs.lines = all
}

func (m *Model) ensureSubscription() {
	targetProject := ""
	targetService := ""

	if m.focusedProject != "" {
		targetProject = m.focusedProject
		if m.logs.service == "all" {
			targetService = ""
		} else if len(m.services.items) > 0 && m.services.selected >= 0 && m.services.selected < len(m.services.items) {
			targetService = m.services.items[m.services.selected].name
		} else {
			targetProject = ""
		}
	}

	if targetProject == "" || m.client == nil {
		m.cancelSubscription()
		return
	}
	if !m.forceResubscribe && m.subCancel != nil && m.subProject == targetProject && m.subService == targetService {
		return
	}

	m.cancelSubscription()
	m.forceResubscribe = false

	ctx, cancel := context.WithCancel(context.Background())
	m.subCancel = cancel
	m.subProject = targetProject
	m.subService = targetService

	go func(c *client.Client, project, service string, logCh chan daemon.LogLine, errCh chan error, ctx context.Context) {
		err := c.SubscribeWithContext(ctx, project, service, func(line daemon.LogLine) {
			select {
			case logCh <- line:
			default:
			}
		})
		if err != nil && ctx.Err() == nil {
			select {
			case errCh <- err:
			default:
			}
		}
	}(m.client, targetProject, targetService, m.logCh, m.subErrCh, ctx)
}

func (m *Model) cancelSubscription() {
	if m.subCancel != nil {
		m.subCancel()
	}
	m.subCancel = nil
	m.subProject = ""
	m.subService = ""
}

func (m *Model) openPicker() {
	st, err := state.Load()
	if err != nil {
		return
	}

	status := m.latestStatus
	if status == nil {
		status = statusUpdateMsg{}
	}

	items := make([]pickerItem, 0, len(st.Registry))
	for name := range st.Registry {
		running := false
		svcs := 0
		if projStatus, ok := status[name]; ok {
			svcs = len(projStatus)
			for _, info := range projStatus {
				if info.Running {
					running = true
					break
				}
			}
		}
		if svcs == 0 {
			if path, ok := st.Registry[name]; ok {
				if proj, err := loadProjectConfig(path); err == nil {
					svcs = len(proj.Services)
				}
			}
		}
		items = append(items, pickerItem{name: name, running: running, svcs: svcs})
	}

	sort.Slice(items, func(i, j int) bool {
		if items[i].running != items[j].running {
			return items[i].running
		}
		return items[i].name < items[j].name
	})

	m.picker = pickerModel{
		visible:  true,
		items:    items,
		filtered: items,
		width:    m.pickerWidth(),
		height:   m.height - 4,
	}
}

func (m *Model) pickerWidth() int {
	// Keep picker comfortably wide and centered for long project names.
	width := 56
	if m.width > 0 {
		width = m.width / 2
	}
	if width < 48 {
		width = 48
	}
	if m.width > 0 {
		maxWidth := m.width - 8
		if maxWidth < 32 {
			maxWidth = 32
		}
		if width > maxWidth {
			width = maxWidth
		}
	}
	if width > 76 {
		width = 76
	}
	return width
}

// Commands

func (m Model) fetchStatusCmd() tea.Cmd {
	return func() tea.Msg {
		if m.client == nil {
			return nil
		}
		resp, err := m.client.Send(daemon.Request{Action: "status"})
		if err != nil {
			return err
		}
		if !resp.OK {
			return nil
		}
		var status statusUpdateMsg
		_ = json.Unmarshal(resp.Data, &status)
		return status
	}
}

func (m Model) fetchLogsCmd(project, service string) tea.Cmd {
	return func() tea.Msg {
		if m.client == nil || project == "" || service == "" {
			return nil
		}
		resp, err := m.client.Send(daemon.Request{
			Action:  "logs",
			Project: project,
			Service: service,
			Lines:   500,
		})
		if err != nil || !resp.OK {
			return nil
		}
		var lines []daemon.LogLine
		_ = json.Unmarshal(resp.Data, &lines)
		return logsFetchedMsg{project: project, service: service, lines: lines}
	}
}

func (m Model) tickCmd() tea.Cmd {
	return tea.Tick(2*time.Second, func(t time.Time) tea.Msg {
		return tickMsg(t)
	})
}

func (m Model) waitForLogCmd() tea.Cmd {
	return func() tea.Msg {
		line := <-m.logCh
		return logMsg(line)
	}
}

func (m Model) waitForSubErrCmd() tea.Cmd {
	return func() tea.Msg {
		err := <-m.subErrCh
		return subscriptionErrMsg{err: err}
	}
}

func (m Model) retrySubscribeCmd() tea.Cmd {
	return tea.Tick(1*time.Second, func(t time.Time) tea.Msg {
		return retrySubscribeMsg{}
	})
}

func (m Model) restartServiceCmd() tea.Cmd {
	return func() tea.Msg {
		if len(m.services.items) == 0 || m.client == nil {
			return nil
		}
		svc := m.services.items[m.services.selected]
		_, _ = m.client.Send(daemon.Request{
			Action:  "restart",
			Project: m.focusedProject,
			Service: svc.name,
		})
		return nil
	}
}

func (m Model) restartProjectCmd() tea.Cmd {
	return func() tea.Msg {
		if m.focusedProject == "" || m.client == nil {
			return nil
		}
		_, _ = m.client.Send(daemon.Request{
			Action:  "restart",
			Project: m.focusedProject,
		})
		return nil
	}
}

func (m Model) stopFocusedProjectCmd() tea.Cmd {
	return m.stopProjectCmd(m.focusedProject)
}

func (m Model) stopProjectCmd(project string) tea.Cmd {
	return func() tea.Msg {
		if project == "" || m.client == nil {
			return nil
		}
		_, _ = m.client.Send(daemon.Request{Action: "stop", Project: project})
		return nil
	}
}

func (m Model) startProject(name string) tea.Cmd {
	return func() tea.Msg {
		if m.client == nil {
			return nil
		}
		mode := "exclusive"
		if m.mode == "multitask" {
			mode = "parallel"
		}
		_, _ = m.client.Send(daemon.Request{
			Action:  "start",
			Project: name,
			Mode:    mode,
		})
		return nil
	}
}

func (m Model) focusCmd(project string) tea.Cmd {
	return func() tea.Msg {
		if m.client == nil {
			return nil
		}
		_, _ = m.client.Send(daemon.Request{
			Action:  "focus",
			Project: project,
			Mode:    m.mode,
		})
		return nil
	}
}

// Helpers

func (m Model) renderToastLine() string {
	if m.width <= 0 {
		return ""
	}
	if m.toast == "" {
		return lipgloss.NewStyle().Width(m.width).Render("")
	}
	maxWidth := m.width - 4
	if maxWidth < 1 {
		maxWidth = 1
	}
	toastText := truncateText(m.toast, maxWidth)
	return lipgloss.NewStyle().Width(m.width).Render(toastStyle.Render(toastText))
}

func (m *Model) markFreshLogsForService(project, service string, cutoff time.Time) {
	if project == "" || service == "" {
		return
	}
	key := projectServiceKey(project, service)
	m.logCutoff[key] = cutoff
	delete(m.allLogs, key)
	if m.focusedProject == project {
		if m.logs.service == service {
			m.logs.lines = nil
		}
		if m.logs.service == "all" {
			m.refreshAllLogs()
		}
	}
}

func (m *Model) markFreshLogsForProject(project string, cutoff time.Time) {
	if project == "" {
		return
	}
	prefix := project + ":"
	for key := range m.allLogs {
		if strings.HasPrefix(key, prefix) {
			m.logCutoff[key] = cutoff
			delete(m.allLogs, key)
		}
	}
	if status, ok := m.latestStatus[project]; ok {
		for svc := range status {
			key := projectServiceKey(project, svc)
			m.logCutoff[key] = cutoff
			delete(m.allLogs, key)
		}
	}
	if m.focusedProject == project {
		if m.logs.service == "all" {
			m.refreshAllLogs()
		} else {
			m.logs.lines = nil
		}
	}
}

func (m *Model) logPassesCutoff(line daemon.LogLine) bool {
	key := projectServiceKey(line.Project, line.Service)
	cutoff, ok := m.logCutoff[key]
	if !ok {
		return true
	}
	return line.Timestamp.After(cutoff)
}

func (m *Model) filterLinesForKey(key string, lines []daemon.LogLine) []daemon.LogLine {
	cutoff, ok := m.logCutoff[key]
	if !ok || len(lines) == 0 {
		return lines
	}
	filtered := make([]daemon.LogLine, 0, len(lines))
	for _, line := range lines {
		if line.Timestamp.After(cutoff) {
			filtered = append(filtered, line)
		}
	}
	return filtered
}

func projectServiceKey(project, service string) string {
	return project + ":" + service
}

func truncateText(text string, maxWidth int) string {
	if maxWidth <= 0 {
		return ""
	}
	if len([]rune(text)) <= maxWidth {
		return text
	}
	if maxWidth == 1 {
		return "…"
	}
	return string([]rune(text)[:maxWidth-1]) + "…"
}

func repeat(s string, n int) string {
	result := ""
	for i := 0; i < n; i++ {
		result += s
	}
	return result
}

func placeOverlay(width, height int, overlay, background string) string {
	_ = background
	overlayStyle := lipgloss.NewStyle().
		Width(width).
		Height(height).
		Align(lipgloss.Center, lipgloss.Center)
	return overlayStyle.Render(overlay)
}

func loadProjectConfig(path string) (*projectConfigInfo, error) {
	proj, err := config.LoadProject(path)
	if err != nil {
		return nil, err
	}
	services := make(map[string]interface{}, len(proj.Services))
	for name := range proj.Services {
		services[name] = struct{}{}
	}
	return &projectConfigInfo{Services: services}, nil
}

type projectConfigInfo struct {
	Services map[string]interface{}
}
