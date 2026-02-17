package tui

import (
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

	hunDir := filepath.Join(home, ".hun")
	if err := os.MkdirAll(hunDir, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	stateJSON := `{"mode":"multitask","active_project":"proj-a","projects":{},"registry":{}}`
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
