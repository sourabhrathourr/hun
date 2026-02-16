package tui

import (
	"encoding/json"
	"sort"
	"time"

	"github.com/charmbracelet/bubbles/key"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/hun-sh/hun/internal/client"
	"github.com/hun-sh/hun/internal/daemon"
	"github.com/hun-sh/hun/internal/state"
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
	allLogs        map[string][]daemon.LogLine // "project:service" → lines

	searching bool
	searchBuf string

	err error
}

type tickMsg time.Time
type statusUpdateMsg map[string]map[string]daemon.ServiceInfo
type logMsg daemon.LogLine

// New creates a new TUI model.
func New(multi bool) Model {
	mode := "focus"
	if multi {
		mode = "multitask"
	}

	c, _ := client.New()

	m := Model{
		client:  c,
		mode:    mode,
		allLogs: make(map[string][]daemon.LogLine),
		topBar:  topBarModel{mode: mode},
		logs:    logsModel{autoScroll: true},
	}
	return m
}

// Init implements tea.Model.
func (m Model) Init() tea.Cmd {
	return tea.Batch(
		m.fetchStatusCmd(),
		m.tickCmd(),
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
		m.applyStatus(msg)
		return m, nil

	case logMsg:
		line := daemon.LogLine(msg)
		key := line.Project + ":" + line.Service
		m.allLogs[key] = append(m.allLogs[key], line)
		// Trim to 10000
		if len(m.allLogs[key]) > 10000 {
			m.allLogs[key] = m.allLogs[key][len(m.allLogs[key])-10000:]
		}
		m.refreshLogs()
		return m, nil

	case tickMsg:
		return m, tea.Batch(m.fetchStatusCmd(), m.tickCmd())

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

	topBar := m.topBar.View()
	statusBar := m.statusBar.View()

	// Calculate middle area height
	middleHeight := m.height - 4 // top bar + separator + status bar lines

	sidebarWidth := 24
	if m.width < 60 {
		sidebarWidth = 16
	}

	m.services.width = sidebarWidth
	m.services.height = middleHeight

	logsWidth := m.width - sidebarWidth - 3 // border
	m.logs.width = logsWidth
	m.logs.height = middleHeight

	sidebar := m.services.View()
	logView := m.logs.View()

	middle := lipgloss.JoinHorizontal(
		lipgloss.Top,
		sidebar,
		lipgloss.NewStyle().Foreground(colorBorder).Render(" \u2502 "),
		logView,
	)

	sep := lipgloss.NewStyle().Foreground(colorBorder).Width(m.width).Render(
		"\u2500" + repeat("\u2500", m.width-1),
	)

	view := lipgloss.JoinVertical(lipgloss.Left,
		topBar,
		sep,
		middle,
		sep,
		statusBar,
	)

	// Overlay picker if visible
	if m.picker.visible {
		overlay := m.picker.View()
		view = placeOverlay(m.width, m.height, overlay, view)
	}

	return view
}

func (m Model) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	// Picker mode
	if m.picker.visible {
		return m.handlePickerKey(msg)
	}

	// Search mode
	if m.searching {
		return m.handleSearchKey(msg)
	}

	switch {
	case key.Matches(msg, key.NewBinding(key.WithKeys("q", "ctrl+c"))):
		return m, tea.Quit

	case key.Matches(msg, key.NewBinding(key.WithKeys("up", "k"))):
		if m.services.selected > 0 {
			m.services.selected--
			m.refreshLogs()
		}
	case key.Matches(msg, key.NewBinding(key.WithKeys("down", "j"))):
		if m.services.selected < len(m.services.items)-1 {
			m.services.selected++
			m.refreshLogs()
		}

	case key.Matches(msg, key.NewBinding(key.WithKeys("tab"))):
		if m.mode == "multitask" && len(m.topBar.projects) > 1 {
			m.topBar.focused = (m.topBar.focused + 1) % len(m.topBar.projects)
			m.focusedProject = m.topBar.projects[m.topBar.focused].name
			m.refreshServices()
		}

	case key.Matches(msg, key.NewBinding(key.WithKeys("r"))):
		return m, m.restartServiceCmd()

	case key.Matches(msg, key.NewBinding(key.WithKeys("R"))):
		return m, m.restartProjectCmd()

	case key.Matches(msg, key.NewBinding(key.WithKeys("p"))):
		m.openPicker()

	case key.Matches(msg, key.NewBinding(key.WithKeys("m"))):
		if m.mode == "focus" {
			m.mode = "multitask"
			m.topBar.mode = "multitask"
			m.statusBar.mode = "multitask"
		}

	case key.Matches(msg, key.NewBinding(key.WithKeys("f"))):
		if m.mode == "multitask" {
			m.mode = "focus"
			m.topBar.mode = "focus"
			m.statusBar.mode = "focus"
		}

	case key.Matches(msg, key.NewBinding(key.WithKeys("s"))):
		if m.mode == "multitask" && m.focusedProject != "" {
			return m, m.stopFocusedProjectCmd()
		}

	case key.Matches(msg, key.NewBinding(key.WithKeys("/"))):
		m.searching = true
		m.searchBuf = ""

	case key.Matches(msg, key.NewBinding(key.WithKeys("a"))):
		// Show all logs combined
		m.logs.service = "all"
		m.refreshAllLogs()
	}

	return m, nil
}

func (m Model) handlePickerKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch {
	case key.Matches(msg, key.NewBinding(key.WithKeys("esc"))):
		m.picker.visible = false

	case key.Matches(msg, key.NewBinding(key.WithKeys("enter"))):
		if len(m.picker.filtered) > 0 && m.picker.selected < len(m.picker.filtered) {
			item := m.picker.filtered[m.picker.selected]
			m.picker.visible = false
			return m, m.startProject(item.name)
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
	case key.Matches(msg, key.NewBinding(key.WithKeys("esc", "enter"))):
		m.searching = false
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

func (m *Model) applyStatus(status statusUpdateMsg) {
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

	// Set focused project
	if m.focusedProject == "" && len(tabs) > 0 {
		m.focusedProject = tabs[0].name
		m.topBar.focused = 0
	}

	m.refreshServices()
}

func (m *Model) refreshServices() {
	status := m.fetchStatusSync()
	if status == nil {
		return
	}
	svcs, ok := status[m.focusedProject]
	if !ok {
		m.services.items = nil
		return
	}

	var items []serviceItem
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

	m.refreshLogs()
}

func (m *Model) refreshLogs() {
	if len(m.services.items) == 0 {
		m.logs.lines = nil
		m.logs.service = ""
		return
	}
	svc := m.services.items[m.services.selected]
	m.logs.service = svc.name

	key := m.focusedProject + ":" + svc.name
	m.logs.lines = m.allLogs[key]

	// Fetch from daemon if empty
	if len(m.logs.lines) == 0 && m.client != nil {
		resp, err := m.client.Send(daemon.Request{
			Action:  "logs",
			Project: m.focusedProject,
			Service: svc.name,
			Lines:   500,
		})
		if err == nil && resp.OK {
			var lines []daemon.LogLine
			json.Unmarshal(resp.Data, &lines)
			m.allLogs[key] = lines
			m.logs.lines = lines
		}
	}
}

func (m *Model) refreshAllLogs() {
	var all []daemon.LogLine
	for key, lines := range m.allLogs {
		prefix := m.focusedProject + ":"
		if len(key) > len(prefix) && key[:len(prefix)] == prefix {
			all = append(all, lines...)
		}
	}
	sort.Slice(all, func(i, j int) bool {
		return all[i].Timestamp.Before(all[j].Timestamp)
	})
	m.logs.lines = all
}

func (m *Model) openPicker() {
	st, err := state.Load()
	if err != nil {
		return
	}

	status := m.fetchStatusSync()

	var items []pickerItem
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

		// Count services from config
		if svcs == 0 {
			if path, ok := st.Registry[name]; ok {
				if proj, err := loadProjectConfig(path); err == nil {
					svcs = len(proj.Services)
				}
			}
		}

		items = append(items, pickerItem{name: name, running: running, svcs: svcs})
	}

	// Sort: running first, then alphabetical
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
		width:    30,
		height:   m.height - 4,
	}
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
		json.Unmarshal(resp.Data, &status)
		return status
	}
}

func (m Model) fetchStatusSync() map[string]map[string]daemon.ServiceInfo {
	if m.client == nil {
		return nil
	}
	resp, err := m.client.Send(daemon.Request{Action: "status"})
	if err != nil || !resp.OK {
		return nil
	}
	var status map[string]map[string]daemon.ServiceInfo
	json.Unmarshal(resp.Data, &status)
	return status
}

func (m Model) tickCmd() tea.Cmd {
	return tea.Tick(2*time.Second, func(t time.Time) tea.Msg {
		return tickMsg(t)
	})
}

func (m Model) restartServiceCmd() tea.Cmd {
	return func() tea.Msg {
		if len(m.services.items) == 0 || m.client == nil {
			return nil
		}
		svc := m.services.items[m.services.selected]
		m.client.Send(daemon.Request{
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
		m.client.Send(daemon.Request{
			Action:  "restart",
			Project: m.focusedProject,
		})
		return nil
	}
}

func (m Model) stopFocusedProjectCmd() tea.Cmd {
	return func() tea.Msg {
		if m.focusedProject == "" || m.client == nil {
			return nil
		}
		m.client.Send(daemon.Request{
			Action:  "stop",
			Project: m.focusedProject,
		})
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
		m.client.Send(daemon.Request{
			Action:  "start",
			Project: name,
			Mode:    mode,
		})
		return nil
	}
}

// Helpers

func repeat(s string, n int) string {
	result := ""
	for i := 0; i < n; i++ {
		result += s
	}
	return result
}

func placeOverlay(width, height int, overlay, background string) string {
	// Simple center overlay
	overlayStyle := lipgloss.NewStyle().
		Width(width).
		Height(height).
		Align(lipgloss.Center, lipgloss.Center)
	return overlayStyle.Render(overlay)
}

func loadProjectConfig(path string) (*projectConfigInfo, error) {
	// Light wrapper to avoid import cycle
	// Just count services from the YAML
	return &projectConfigInfo{Services: nil}, nil
}

type projectConfigInfo struct {
	Services map[string]interface{}
}
