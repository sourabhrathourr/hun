package daemon

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/sourabhrathourr/hun/internal/config"
)

func TestHandleRequestStopServiceStopsOnlyTargetService(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	proj := &config.Project{
		Name: "api-stop-service",
		Services: map[string]*config.Service{
			"a": {Cmd: "sleep 5"},
			"b": {Cmd: "sleep 5"},
		},
	}
	if err := m.StartProject("api-stop-service", proj, t.TempDir(), false); err != nil {
		t.Fatalf("start project: %v", err)
	}

	waitForServiceRunning(t, m, "api-stop-service", "a")
	waitForServiceRunning(t, m, "api-stop-service", "b")

	d := &Daemon{manager: m}
	resp := d.HandleRequest(Request{
		Action:  "stop_service",
		Project: "api-stop-service",
		Service: "a",
	})
	if !resp.OK {
		t.Fatalf("stop_service response error: %s", resp.Error)
	}

	waitForServiceStopped(t, m, "api-stop-service", "a")

	status := m.Status()
	a := status["api-stop-service"]["a"]
	b := status["api-stop-service"]["b"]
	if a.Running {
		t.Fatalf("expected service a stopped, got %+v", a)
	}
	if !b.Running {
		t.Fatalf("expected service b still running, got %+v", b)
	}
}

func TestHandleRequestStopServiceRequiresProjectAndService(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer m.Shutdown()

	d := &Daemon{manager: m}

	resp := d.HandleRequest(Request{Action: "stop_service", Service: "api"})
	if resp.OK || resp.Error == "" {
		t.Fatalf("expected missing project error, got %+v", resp)
	}

	resp = d.HandleRequest(Request{Action: "stop_service", Project: "proj"})
	if resp.OK || resp.Error == "" {
		t.Fatalf("expected missing service error, got %+v", resp)
	}
}

func TestHandleRequestPingReturnsProtocol(t *testing.T) {
	d := &Daemon{}
	resp := d.HandleRequest(Request{Action: "ping"})
	if !resp.OK {
		t.Fatalf("ping response error: %s", resp.Error)
	}
	var payload struct {
		Status   string `json:"status"`
		Protocol int    `json:"protocol"`
	}
	if err := json.Unmarshal(resp.Data, &payload); err != nil {
		t.Fatalf("unmarshal ping payload: %v", err)
	}
	if payload.Status != "pong" {
		t.Fatalf("ping status = %q, want %q", payload.Status, "pong")
	}
	if payload.Protocol != CurrentProtocolVersion {
		t.Fatalf("ping protocol = %d, want %d", payload.Protocol, CurrentProtocolVersion)
	}
}

func waitForServiceRunning(t *testing.T, m *Manager, project, service string) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		status := m.Status()
		if status[project][service].Running {
			return
		}
		time.Sleep(25 * time.Millisecond)
	}
	t.Fatalf("service %s/%s did not reach running state", project, service)
}

func waitForServiceStopped(t *testing.T, m *Manager, project, service string) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		status := m.Status()
		if !status[project][service].Running {
			return
		}
		time.Sleep(25 * time.Millisecond)
	}
	t.Fatalf("service %s/%s did not stop", project, service)
}
