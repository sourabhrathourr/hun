package tui

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/sourabhrathourr/hun/internal/daemon"
)

func TestNewRestoresModeAndActiveProjectFromState(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	projectDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(projectDir, ".hun.yml"), []byte("name: proj-a\nservices:\n  app:\n    cmd: echo ok\n"), 0o644); err != nil {
		t.Fatalf("write project config: %v", err)
	}

	hunDir := filepath.Join(home, ".hun")
	if err := os.MkdirAll(hunDir, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	stateJSON := `{"mode":"multitask","active_project":"proj-a","projects":{"proj-a":{"status":"running"}},"registry":{"proj-a":"` + projectDir + `"}}`
	if err := os.WriteFile(filepath.Join(hunDir, "state.json"), []byte(stateJSON), 0o644); err != nil {
		t.Fatalf("write state: %v", err)
	}

	m := New(false)
	if m.mode != "multitask" {
		t.Fatalf("mode = %q, want multitask", m.mode)
	}
	if m.focusedProject != "proj-a" {
		t.Fatalf("focused project = %q, want proj-a", m.focusedProject)
	}
}

func TestApplyStatusReconcilesStaleFocusedProject(t *testing.T) {
	m := New(false)
	m.client = nil
	m.focusedProject = "old-project"

	status := statusUpdateMsg{
		"new-project": {
			"api": daemon.ServiceInfo{Running: true, Port: 8080, Ready: true},
		},
	}

	cmds := m.applyStatus(status)
	if m.focusedProject != "new-project" {
		t.Fatalf("focused project = %q, want new-project", m.focusedProject)
	}
	if m.topBar.focused != 0 {
		t.Fatalf("topbar focused = %d, want 0", m.topBar.focused)
	}
	if len(m.services.items) != 1 || m.services.items[0].name != "api" {
		t.Fatalf("unexpected services: %+v", m.services.items)
	}
	if len(cmds) == 0 {
		t.Fatal("expected follow-up commands for focus/log refresh")
	}
}

func TestPickerEnterSwitchesFocusImmediately(t *testing.T) {
	m := New(false)
	m.client = nil
	m.mode = "multitask"
	m.topBar.mode = "multitask"
	m.focusedProject = "proj1"
	m.topBar.projects = []projectTab{{name: "proj1", running: true}, {name: "proj2", running: true}}
	m.latestStatus = statusUpdateMsg{
		"proj1": {
			"svc1": daemon.ServiceInfo{Running: true, Port: 3000, Ready: true},
		},
		"proj2": {
			"svc2": daemon.ServiceInfo{Running: true, Port: 4000, Ready: true},
		},
	}
	m.picker = pickerModel{
		visible:  true,
		filtered: []pickerItem{{name: "proj2", running: true, svcs: 1}},
		selected: 0,
	}

	updated, _ := m.handlePickerKey(tea.KeyMsg{Type: tea.KeyEnter})
	m2 := updated.(Model)

	if m2.focusedProject != "proj2" {
		t.Fatalf("focused project = %q, want proj2", m2.focusedProject)
	}
	if m2.picker.visible {
		t.Fatal("picker should close on enter")
	}
	if len(m2.services.items) != 1 || m2.services.items[0].name != "svc2" {
		t.Fatalf("unexpected service list after picker focus: %+v", m2.services.items)
	}
}

func TestOpenPickerUsesCompactHeight(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	projectA := t.TempDir()
	projectB := t.TempDir()
	if err := os.WriteFile(filepath.Join(projectA, ".hun.yml"), []byte("name: proj-a\nservices:\n  api:\n    cmd: echo ok\n"), 0o644); err != nil {
		t.Fatalf("write project a config: %v", err)
	}
	if err := os.WriteFile(filepath.Join(projectB, ".hun.yml"), []byte("name: proj-b\nservices:\n  web:\n    cmd: echo ok\n"), 0o644); err != nil {
		t.Fatalf("write project b config: %v", err)
	}

	hunDir := filepath.Join(home, ".hun")
	if err := os.MkdirAll(hunDir, 0o755); err != nil {
		t.Fatalf("mkdir hun dir: %v", err)
	}
	stateJSON := `{"mode":"focus","projects":{},"registry":{"proj-a":"` + projectA + `","proj-b":"` + projectB + `"}}`
	if err := os.WriteFile(filepath.Join(hunDir, "state.json"), []byte(stateJSON), 0o644); err != nil {
		t.Fatalf("write state: %v", err)
	}

	m := New(false)
	m.client = nil
	m.width = 140
	m.height = 42
	m.latestStatus = statusUpdateMsg{
		"proj-a": {"api": daemon.ServiceInfo{Running: true, Ready: true, Port: 3000}},
	}

	m.openPicker()

	if !m.picker.visible {
		t.Fatal("picker should be visible")
	}
	if m.picker.height <= 0 {
		t.Fatalf("picker height = %d, want > 0", m.picker.height)
	}
	if m.picker.height >= m.height-4 {
		t.Fatalf("picker height = %d, should be compact and less than %d", m.picker.height, m.height-4)
	}
	if m.picker.height > 24 {
		t.Fatalf("picker height = %d, expected compact bounded height", m.picker.height)
	}
}

func TestLogMsgUpdatesAllLogsView(t *testing.T) {
	m := New(false)
	m.client = nil
	m.focusedProject = "proj"
	m.logs.service = "all"
	m.services.items = []serviceItem{{name: "svc", running: true}}

	timestamp := time.Now()
	updated, _ := m.Update(logMsg(daemon.LogLine{Timestamp: timestamp, Project: "proj", Service: "svc", Text: "hello"}))
	m2 := updated.(Model)
	if len(m2.logs.lines) != 1 {
		t.Fatalf("expected 1 log line in all-logs view, got %d", len(m2.logs.lines))
	}
}

func TestViewHeightStableWithAndWithoutToast(t *testing.T) {
	m := New(false)
	m.client = nil
	m.width = 120
	m.height = 30
	m.updateLayout()
	m.latestStatus = statusUpdateMsg{
		"proj": {
			"svc": daemon.ServiceInfo{Running: true, Ready: true, Port: 3000},
		},
	}
	m.applyStatus(m.latestStatus)

	viewNoToast := m.View()
	if lipgloss.Height(viewNoToast) != m.height {
		t.Fatalf("view height without toast = %d, want %d", lipgloss.Height(viewNoToast), m.height)
	}

	m.toast = "Restarting svc..."
	viewWithToast := m.View()
	if lipgloss.Height(viewWithToast) != m.height {
		t.Fatalf("view height with toast = %d, want %d", lipgloss.Height(viewWithToast), m.height)
	}
}

func TestViewHeightStableInMultitaskSelectionMode(t *testing.T) {
	m := New(false)
	m.client = nil
	m.width = 120
	m.height = 30
	m.mode = "multitask"
	m.topBar.mode = "multitask"
	m.focusedProject = "project-with-a-very-long-name-1"
	m.topBar.projects = []projectTab{
		{name: "project-with-a-very-long-name-1", running: true},
		{name: "project-with-a-very-long-name-2", running: true},
		{name: "project-with-a-very-long-name-3", running: true},
	}
	m.updateLayout()
	m.latestStatus = statusUpdateMsg{
		"project-with-a-very-long-name-1": {
			"svc": daemon.ServiceInfo{Running: true, Ready: true, Port: 3000},
		},
	}
	m.applyStatus(m.latestStatus)
	m.activePane = paneLogs
	m.logs.selectionMode = true

	view := m.View()
	if lipgloss.Height(view) != m.height {
		t.Fatalf("view height in multitask+selection = %d, want %d", lipgloss.Height(view), m.height)
	}
}

func TestRestartServiceClearsAndCutsOffOldLogs(t *testing.T) {
	m := New(false)
	m.client = nil
	m.focusedProject = "proj"
	m.services.items = []serviceItem{{name: "svc", running: true}}
	m.logs.service = "svc"
	key := projectServiceKey("proj", "svc")
	m.allLogs[key] = []daemon.LogLine{{
		Project:   "proj",
		Service:   "svc",
		Text:      "old cached",
		Timestamp: time.Now().Add(-2 * time.Second),
	}}

	updated, _ := m.handleKey(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("r")})
	m2 := updated.(Model)

	if _, ok := m2.logCutoff[key]; !ok {
		t.Fatalf("expected cutoff timestamp for %s after restart", key)
	}
	if len(m2.allLogs[key]) != 0 {
		t.Fatalf("expected cached logs cleared on restart, got %d lines", len(m2.allLogs[key]))
	}

	cutoff := m2.logCutoff[key]
	oldLine := daemon.LogLine{
		Project:   "proj",
		Service:   "svc",
		Text:      "old from fetch",
		Timestamp: cutoff.Add(-time.Second),
	}
	newLine := daemon.LogLine{
		Project:   "proj",
		Service:   "svc",
		Text:      "new line",
		Timestamp: cutoff.Add(time.Second),
	}
	updated2, _ := m2.Update(logsFetchedMsg{
		project: "proj",
		service: "svc",
		lines:   []daemon.LogLine{oldLine, newLine},
	})
	m3 := updated2.(Model)

	if len(m3.allLogs[key]) != 1 {
		t.Fatalf("expected only fresh logs after cutoff, got %d", len(m3.allLogs[key]))
	}
	if !strings.Contains(m3.allLogs[key][0].Text, "new") {
		t.Fatalf("unexpected log kept after cutoff: %q", m3.allLogs[key][0].Text)
	}
}

func TestLogsPaneNavigationDoesNotChangeServiceSelection(t *testing.T) {
	m := New(false)
	m.client = nil
	m.focusedProject = "proj"
	m.services.items = []serviceItem{
		{name: "svc-a", running: true},
		{name: "svc-b", running: true},
	}
	m.services.selected = 1
	m.logs.service = "svc-b"
	m.activePane = paneLogs
	m.logs.height = 12
	m.logs.width = 100
	m.logs.setLines([]daemon.LogLine{
		{Project: "proj", Service: "svc-b", Text: "line-1", Timestamp: time.Now().Add(-2 * time.Second)},
		{Project: "proj", Service: "svc-b", Text: "line-2", Timestamp: time.Now().Add(-time.Second)},
		{Project: "proj", Service: "svc-b", Text: "line-3", Timestamp: time.Now()},
	})

	updated, _ := m.handleKey(tea.KeyMsg{Type: tea.KeyUp})
	m2 := updated.(Model)

	if m2.services.selected != 1 {
		t.Fatalf("services.selected = %d, want 1", m2.services.selected)
	}
	if m2.logs.cursor >= 2 {
		t.Fatalf("expected logs cursor to move up, got %d", m2.logs.cursor)
	}
}

func TestLeftRightPaneSwitchKeepsTabProjectCycling(t *testing.T) {
	m := New(false)
	m.client = nil
	m.mode = "multitask"
	m.topBar.mode = "multitask"
	m.focusedProject = "proj1"
	m.topBar.projects = []projectTab{{name: "proj1", running: true}, {name: "proj2", running: true}}
	m.latestStatus = statusUpdateMsg{
		"proj1": {"svc1": daemon.ServiceInfo{Running: true, Ready: true, Port: 3000}},
		"proj2": {"svc2": daemon.ServiceInfo{Running: true, Ready: true, Port: 4000}},
	}

	updated, _ := m.handleKey(tea.KeyMsg{Type: tea.KeyRight})
	m2 := updated.(Model)
	if m2.activePane != paneLogs {
		t.Fatalf("activePane = %q, want %q", m2.activePane, paneLogs)
	}

	updated2, _ := m2.handleKey(tea.KeyMsg{Type: tea.KeyTab})
	m3 := updated2.(Model)
	if m3.focusedProject != "proj2" {
		t.Fatalf("focusedProject = %q, want proj2", m3.focusedProject)
	}
}

func TestEnterInServicesPaneMovesFocusToLogsForSelectedService(t *testing.T) {
	m := New(false)
	m.client = nil
	m.activePane = paneServices
	m.focusedProject = "proj"
	m.services.items = []serviceItem{
		{name: "svc-a", running: true},
		{name: "svc-b", running: true},
	}
	m.services.selected = 1
	m.logs.service = "all"

	updated, _ := m.handleKey(tea.KeyMsg{Type: tea.KeyEnter})
	m2 := updated.(Model)

	if m2.activePane != paneLogs {
		t.Fatalf("activePane = %q, want %q", m2.activePane, paneLogs)
	}
	if m2.logs.service != "svc-b" {
		t.Fatalf("logs.service = %q, want %q", m2.logs.service, "svc-b")
	}
}

func TestPaneToggleEasterEggUsesUpperE(t *testing.T) {
	m := New(false)
	m.client = nil
	m.activePane = paneServices

	updated, _ := m.handleKey(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("E")})
	m2 := updated.(Model)
	if m2.activePane != paneLogs {
		t.Fatalf("activePane after first E = %q, want %q", m2.activePane, paneLogs)
	}

	updated2, _ := m2.handleKey(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("E")})
	m3 := updated2.(Model)
	if m3.activePane != paneServices {
		t.Fatalf("activePane after second E = %q, want %q", m3.activePane, paneServices)
	}
}

func TestServicesPaneNavigationWrapsAtEdges(t *testing.T) {
	m := New(false)
	m.client = nil
	m.activePane = paneServices
	m.focusedProject = "proj"
	m.services.items = []serviceItem{
		{name: "svc-a", running: true},
		{name: "svc-b", running: true},
		{name: "svc-c", running: true},
	}

	m.services.selected = 2
	updated, _ := m.handleKey(tea.KeyMsg{Type: tea.KeyDown})
	m2 := updated.(Model)
	if m2.services.selected != 0 {
		t.Fatalf("services.selected after down at last = %d, want 0", m2.services.selected)
	}
	if m2.logs.service != "svc-a" {
		t.Fatalf("logs.service after wrap-down = %q, want %q", m2.logs.service, "svc-a")
	}

	m2.services.selected = 0
	updated2, _ := m2.handleKey(tea.KeyMsg{Type: tea.KeyUp})
	m3 := updated2.(Model)
	if m3.services.selected != 2 {
		t.Fatalf("services.selected after up at first = %d, want 2", m3.services.selected)
	}
	if m3.logs.service != "svc-c" {
		t.Fatalf("logs.service after wrap-up = %q, want %q", m3.logs.service, "svc-c")
	}
}

func TestMouseSelectsServiceAndScrollsLogs(t *testing.T) {
	m := New(false)
	m.client = nil
	m.width = 120
	m.height = 30
	m.updateLayout()
	m.focusedProject = "proj"
	m.latestStatus = statusUpdateMsg{
		"proj": {
			"svc-a": daemon.ServiceInfo{Running: true, Ready: true, Port: 3001},
			"svc-b": daemon.ServiceInfo{Running: true, Ready: true, Port: 3002},
		},
	}
	m.applyStatus(m.latestStatus)
	m.allLogs[projectServiceKey("proj", "svc-a")] = []daemon.LogLine{{Project: "proj", Service: "svc-a", Text: "a", Timestamp: time.Now()}}
	m.allLogs[projectServiceKey("proj", "svc-b")] = []daemon.LogLine{{Project: "proj", Service: "svc-b", Text: "b", Timestamp: time.Now()}}
	m.refreshLogs()

	layout := m.layoutInfo()
	serviceClickY := layout.middleY + 2 + 1 // title+gap, then second service row
	updated, _ := m.handleMouse(tea.MouseMsg{
		X:      1,
		Y:      serviceClickY,
		Button: tea.MouseButtonLeft,
		Action: tea.MouseActionPress,
	})
	m2 := updated.(Model)
	if m2.services.selected != 1 {
		t.Fatalf("services.selected = %d, want 1", m2.services.selected)
	}
	if m2.activePane != paneServices {
		t.Fatalf("activePane = %q, want %q", m2.activePane, paneServices)
	}

	m2.activePane = paneLogs
	m2.logs.height = 12
	m2.logs.width = 90
	lines := make([]daemon.LogLine, 0, 30)
	for i := 0; i < 30; i++ {
		lines = append(lines, daemon.LogLine{
			Project:   "proj",
			Service:   "svc-b",
			Text:      "line",
			Timestamp: time.Now().Add(time.Duration(i) * time.Millisecond),
		})
	}
	m2.logs.setLines(lines)
	m2.logs.jumpBottom()
	m2.logs.autoScroll = false
	beforeOffset := m2.logs.offset

	updated3, _ := m2.handleMouse(tea.MouseMsg{
		X:      layout.logsX + 1,
		Y:      layout.middleY + 4,
		Button: tea.MouseButtonWheelUp,
		Action: tea.MouseActionPress,
	})
	m3 := updated3.(Model)
	if m3.services.selected != 1 {
		t.Fatalf("services.selected changed during log wheel scroll: %d", m3.services.selected)
	}
	if m3.logs.offset >= beforeOffset {
		t.Fatalf("expected log offset to decrease on wheel up, before=%d after=%d", beforeOffset, m3.logs.offset)
	}
}

func TestMouseDragSelectsLogRange(t *testing.T) {
	m := New(false)
	m.client = nil
	m.width = 120
	m.height = 30
	m.updateLayout()
	m.activePane = paneLogs
	m.focusedProject = "proj"
	m.logs.service = "svc"

	base := time.Now()
	lines := make([]daemon.LogLine, 0, 20)
	for i := 0; i < 20; i++ {
		lines = append(lines, daemon.LogLine{
			Project:   "proj",
			Service:   "svc",
			Text:      "line",
			Timestamp: base.Add(time.Duration(i) * time.Second),
		})
	}
	m.logs.setLines(lines)
	m.logs.jumpTop()

	layout := m.layoutInfo()
	x := layout.logsX + 4
	yStart := layout.middleY + 2 + 1
	yDrag := yStart + 4

	updated, _ := m.handleMouse(tea.MouseMsg{
		X:      x,
		Y:      yStart,
		Button: tea.MouseButtonLeft,
		Action: tea.MouseActionPress,
	})
	m2 := updated.(Model)
	if !m2.logs.selectionMode {
		t.Fatal("expected selection mode enabled on left click in logs")
	}
	if !m2.mouseLogSelecting {
		t.Fatal("expected mouse drag state enabled after left press in logs")
	}

	updated2, _ := m2.handleMouse(tea.MouseMsg{
		X:      x,
		Y:      yDrag,
		Button: tea.MouseButtonLeft,
		Action: tea.MouseActionMotion,
	})
	m3 := updated2.(Model)
	start, end, ok := m3.logs.selectionBounds(len(m3.logs.buildRenderedRows(m3.logs.filteredLines())))
	if !ok {
		t.Fatal("expected active selection after drag motion")
	}
	if end <= start {
		t.Fatalf("expected drag selection to extend range, got %d..%d", start, end)
	}

	updated3, _ := m3.handleMouse(tea.MouseMsg{
		X:      x,
		Y:      yDrag,
		Button: tea.MouseButtonNone,
		Action: tea.MouseActionRelease,
	})
	m4 := updated3.(Model)
	if m4.mouseLogSelecting {
		t.Fatal("expected mouse drag state cleared on release")
	}
}

func TestMouseTopbarClickFocusesProject(t *testing.T) {
	m := New(false)
	m.client = nil
	m.width = 120
	m.height = 30
	m.updateLayout()
	m.mode = "multitask"
	m.topBar.mode = "multitask"
	m.focusedProject = "proj1"
	m.topBar.projects = []projectTab{{name: "proj1", running: true}, {name: "proj2", running: true}}
	m.latestStatus = statusUpdateMsg{
		"proj1": {"svc1": daemon.ServiceInfo{Running: true, Ready: true, Port: 3000}},
		"proj2": {"svc2": daemon.ServiceInfo{Running: true, Ready: true, Port: 4000}},
	}

	clickX := -1
	for x := 0; x < m.width; x++ {
		if m.topBar.projectIndexAtX(x) == 1 {
			clickX = x
			break
		}
	}
	if clickX < 0 {
		t.Fatal("could not find clickable x-coordinate for second project tab")
	}

	updated, _ := m.handleMouse(tea.MouseMsg{
		X:      clickX,
		Y:      0,
		Button: tea.MouseButtonLeft,
		Action: tea.MouseActionPress,
	})
	m2 := updated.(Model)
	if m2.focusedProject != "proj2" {
		t.Fatalf("focusedProject = %q, want proj2", m2.focusedProject)
	}
}

func TestApplyStatusStartedAtForcesFreshCutoff(t *testing.T) {
	m := New(false)
	m.client = nil
	startedAt := time.Now().Add(-2 * time.Second).UTC()
	status := statusUpdateMsg{
		"proj": {
			"svc": daemon.ServiceInfo{Running: true, Ready: true, Port: 3000, StartedAt: startedAt},
		},
	}
	m.focusedProject = "proj"
	m.applyStatus(status)

	key := projectServiceKey("proj", "svc")
	cutoff, ok := m.logCutoff[key]
	if !ok {
		t.Fatalf("expected cutoff for %s after started_at update", key)
	}
	if !cutoff.Equal(startedAt) {
		t.Fatalf("cutoff = %s, want %s", cutoff, startedAt)
	}

	oldLine := daemon.LogLine{
		Project:   "proj",
		Service:   "svc",
		Text:      "old",
		Timestamp: startedAt.Add(-time.Second),
	}
	newLine := daemon.LogLine{
		Project:   "proj",
		Service:   "svc",
		Text:      "new",
		Timestamp: startedAt,
	}
	updated, _ := m.Update(logsFetchedMsg{
		project: "proj",
		service: "svc",
		lines:   []daemon.LogLine{oldLine, newLine},
	})
	m2 := updated.(Model)
	if len(m2.allLogs[key]) != 1 {
		t.Fatalf("expected only fresh line at cutoff, got %d", len(m2.allLogs[key]))
	}
	if m2.allLogs[key][0].Text != "new" {
		t.Fatalf("unexpected line retained: %+v", m2.allLogs[key][0])
	}
}

func TestRefreshServicesUsesStatusFieldForCrashedVsStopped(t *testing.T) {
	m := New(false)
	m.client = nil
	m.focusedProject = "proj"

	status := statusUpdateMsg{
		"proj": {
			"svc-crashed": daemon.ServiceInfo{Running: false, Status: "crashed", PID: 1234},
			"svc-stopped": daemon.ServiceInfo{Running: false, Status: "stopped", PID: 1234},
		},
	}
	m.applyStatus(status)

	var crashed, stopped *serviceItem
	for i := range m.services.items {
		item := &m.services.items[i]
		switch item.name {
		case "svc-crashed":
			crashed = item
		case "svc-stopped":
			stopped = item
		}
	}
	if crashed == nil || stopped == nil {
		t.Fatalf("expected both services in items, got %+v", m.services.items)
	}
	if !crashed.crashed || crashed.stopped {
		t.Fatalf("expected svc-crashed to be crashed only, got %+v", *crashed)
	}
	if stopped.crashed || !stopped.stopped {
		t.Fatalf("expected svc-stopped to be stopped only, got %+v", *stopped)
	}
}

func TestKeyLInLogsPaneTogglesLiveMode(t *testing.T) {
	m := New(false)
	m.client = nil
	m.activePane = paneLogs
	m.logs.autoScroll = true

	updated, _ := m.handleKey(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("l")})
	m2 := updated.(Model)

	if m2.logs.autoScroll {
		t.Fatal("expected live mode to pause on l in logs pane")
	}
}

func TestKeyVInLogsPaneStartsSelectionAndDoesNotCopy(t *testing.T) {
	m := New(false)
	m.client = nil
	m.activePane = paneLogs
	m.logs.autoScroll = true
	m.logs.height = 12
	m.logs.width = 100
	m.logs.setLines([]daemon.LogLine{
		{Project: "proj", Service: "svc", Text: "line-1", Timestamp: time.Now().Add(-2 * time.Second)},
		{Project: "proj", Service: "svc", Text: "line-2", Timestamp: time.Now().Add(-time.Second)},
		{Project: "proj", Service: "svc", Text: "line-3", Timestamp: time.Now()},
	})

	updated, _ := m.handleKey(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("v")})
	m2 := updated.(Model)

	if !m2.logs.selectionMode {
		t.Fatal("expected selection mode enabled on v")
	}
	if m2.logs.autoScroll {
		t.Fatal("expected live mode paused when starting selection")
	}
	if m2.toast != "" {
		t.Fatalf("did not expect copy toast on v, got %q", m2.toast)
	}
	if m2.logs.selectionAnchor != m2.logs.selectionEnd {
		t.Fatalf("expected single-line initial selection, got %d..%d", m2.logs.selectionAnchor, m2.logs.selectionEnd)
	}
}

func TestKeyUpperVInLogsPaneStartsSelection(t *testing.T) {
	m := New(false)
	m.client = nil
	m.activePane = paneLogs
	m.logs.height = 12
	m.logs.width = 100
	m.logs.setLines([]daemon.LogLine{
		{Project: "proj", Service: "svc", Text: "line-1", Timestamp: time.Now()},
		{Project: "proj", Service: "svc", Text: "line-2", Timestamp: time.Now().Add(time.Second)},
	})

	updated, _ := m.handleKey(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("V")})
	m2 := updated.(Model)
	if !m2.logs.selectionMode {
		t.Fatal("expected selection mode enabled on V")
	}
	if m2.logs.selectionAnchor != m2.logs.selectionEnd {
		t.Fatalf("expected single-line initial selection on V, got %d..%d", m2.logs.selectionAnchor, m2.logs.selectionEnd)
	}
}

func TestKeyCCopiesOnlyInLogsPane(t *testing.T) {
	m := New(false)
	m.client = nil
	m.activePane = paneServices
	m.logs.height = 12
	m.logs.width = 100
	m.logs.setLines([]daemon.LogLine{
		{Project: "proj", Service: "svc", Text: "line-1", Timestamp: time.Now()},
	})

	updated, _ := m.handleKey(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("c")})
	m2 := updated.(Model)
	if m2.toast != "" {
		t.Fatalf("did not expect copy toast outside logs pane, got %q", m2.toast)
	}
}

func TestKeyYInLogsPaneYanksWithYankToast(t *testing.T) {
	origOut := osc52Out
	origCommands := clipboardCommands
	origExec := clipboardExec
	t.Cleanup(func() {
		osc52Out = origOut
		clipboardCommands = origCommands
		clipboardExec = origExec
	})

	osc52Out = &bytes.Buffer{}
	clipboardCommands = func() []clipboardCommand {
		return []clipboardCommand{{name: "definitely-missing-binary"}}
	}

	m := New(false)
	m.client = nil
	m.activePane = paneLogs
	m.logs.height = 12
	m.logs.width = 100
	m.logs.setLines([]daemon.LogLine{
		{Project: "proj", Service: "svc", Text: "line-1", Timestamp: time.Now()},
	})

	updated, _ := m.handleKey(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("y")})
	m2 := updated.(Model)
	if m2.toast != "Yanked 1 line" {
		t.Fatalf("toast = %q, want %q", m2.toast, "Yanked 1 line")
	}
}

func TestKeyCClearsSelectionAfterCopy(t *testing.T) {
	origOut := osc52Out
	origCommands := clipboardCommands
	origExec := clipboardExec
	t.Cleanup(func() {
		osc52Out = origOut
		clipboardCommands = origCommands
		clipboardExec = origExec
	})

	osc52Out = &bytes.Buffer{}
	clipboardCommands = func() []clipboardCommand {
		return []clipboardCommand{{name: "definitely-missing-binary"}}
	}

	m := New(false)
	m.client = nil
	m.activePane = paneLogs
	m.logs.height = 12
	m.logs.width = 100
	m.logs.setLines([]daemon.LogLine{
		{Project: "proj", Service: "svc", Text: "line-1", Timestamp: time.Now().Add(-time.Second)},
		{Project: "proj", Service: "svc", Text: "line-2", Timestamp: time.Now()},
	})
	m.logs.startSelectionMode()
	m.logs.moveCursor(-1)
	if !m.logs.selectionMode {
		t.Fatal("expected selection mode enabled before copy")
	}

	updated, _ := m.handleKey(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("c")})
	m2 := updated.(Model)

	if m2.logs.selectionMode {
		t.Fatal("expected selection cleared after c copy")
	}
	if m2.toast != "Copied 2 lines" {
		t.Fatalf("toast = %q, want %q", m2.toast, "Copied 2 lines")
	}
}

func TestKeyYClearsSelectionAfterYank(t *testing.T) {
	origOut := osc52Out
	origCommands := clipboardCommands
	origExec := clipboardExec
	t.Cleanup(func() {
		osc52Out = origOut
		clipboardCommands = origCommands
		clipboardExec = origExec
	})

	osc52Out = &bytes.Buffer{}
	clipboardCommands = func() []clipboardCommand {
		return []clipboardCommand{{name: "definitely-missing-binary"}}
	}

	m := New(false)
	m.client = nil
	m.activePane = paneLogs
	m.logs.height = 12
	m.logs.width = 100
	m.logs.setLines([]daemon.LogLine{
		{Project: "proj", Service: "svc", Text: "line-1", Timestamp: time.Now().Add(-time.Second)},
		{Project: "proj", Service: "svc", Text: "line-2", Timestamp: time.Now()},
	})
	m.logs.startSelectionMode()
	m.logs.moveCursor(-1)
	if !m.logs.selectionMode {
		t.Fatal("expected selection mode enabled before yank")
	}

	updated, _ := m.handleKey(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("y")})
	m2 := updated.(Model)

	if m2.logs.selectionMode {
		t.Fatal("expected selection cleared after y yank")
	}
	if m2.toast != "Yanked 2 lines" {
		t.Fatalf("toast = %q, want %q", m2.toast, "Yanked 2 lines")
	}
}

func TestKeyXStopsSelectedService(t *testing.T) {
	m := New(false)
	m.client = nil
	m.focusedProject = "proj"
	m.activePane = paneLogs
	m.services.items = []serviceItem{
		{name: "api", running: true, ready: true},
	}
	m.services.selected = 0
	m.logs.service = "api"
	m.logs.serviceStatus = "running"

	updated, _ := m.handleKey(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("x")})
	m2 := updated.(Model)

	if m2.toast != "Stopping api..." {
		t.Fatalf("toast = %q, want %q", m2.toast, "Stopping api...")
	}
	if m2.services.items[0].running {
		t.Fatal("expected selected service optimistically marked stopped")
	}
	if !m2.services.items[0].stopped {
		t.Fatal("expected selected service marked as stopped")
	}
	if m2.logs.serviceStatus != "stopped" {
		t.Fatalf("logs.serviceStatus = %q, want %q", m2.logs.serviceStatus, "stopped")
	}
}

func TestKeySStopsProject(t *testing.T) {
	m := New(false)
	m.client = nil
	m.focusedProject = "proj"

	updated, _ := m.handleKey(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("s")})
	m2 := updated.(Model)

	if m2.toast != "Stopping proj..." {
		t.Fatalf("toast = %q, want %q", m2.toast, "Stopping proj...")
	}
}

func TestKeySImmediatelyAfterXIsGuarded(t *testing.T) {
	m := New(false)
	m.client = nil
	m.focusedProject = "proj"
	m.services.items = []serviceItem{
		{name: "api", running: true, ready: true},
	}
	m.services.selected = 0
	m.logs.service = "api"
	m.logs.serviceStatus = "running"

	updated, _ := m.handleKey(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("x")})
	m2 := updated.(Model)
	if m2.toast != "Stopping api..." {
		t.Fatalf("toast after x = %q, want %q", m2.toast, "Stopping api...")
	}

	updated2, _ := m2.handleKey(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("s")})
	m3 := updated2.(Model)
	if m3.toast == "Stopping proj..." {
		t.Fatal("expected project stop to be guarded immediately after service stop")
	}
}

func TestKeyFInLogsPaneOpensFocusPromptInMultitask(t *testing.T) {
	m := New(false)
	m.client = nil
	m.mode = "multitask"
	m.topBar.mode = "multitask"
	m.activePane = paneLogs
	m.logs.autoScroll = true
	m.topBar.projects = []projectTab{{name: "proj", running: true}, {name: "proj2", running: true}}

	updated, _ := m.handleKey(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("f")})
	m2 := updated.(Model)

	if !m2.logs.autoScroll {
		t.Fatal("did not expect live mode to change on f in logs pane")
	}
	if !m2.focusPromptVisible {
		t.Fatal("expected focus prompt when pressing f in multitask mode")
	}
	if m2.mode != "multitask" {
		t.Fatalf("mode changed unexpectedly: %q", m2.mode)
	}
}
