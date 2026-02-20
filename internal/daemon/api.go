package daemon

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/sourabhrathourr/hun/internal/config"
)

// Request represents a JSON command from CLI/TUI.
type Request struct {
	Action  string `json:"action"`
	Project string `json:"project,omitempty"`
	Service string `json:"service,omitempty"`
	Mode    string `json:"mode,omitempty"` // "exclusive" or "parallel"
	Lines   int    `json:"lines,omitempty"`
	Note    string `json:"note,omitempty"`
}

// Response is the JSON response from the daemon.
type Response struct {
	OK    bool            `json:"ok"`
	Error string          `json:"error,omitempty"`
	Data  json.RawMessage `json:"data,omitempty"`
}

func successResponse(data interface{}) Response {
	raw, _ := json.Marshal(data)
	return Response{OK: true, Data: raw}
}

func errorResponse(msg string) Response {
	return Response{OK: false, Error: msg}
}

// HandleRequest routes an API request to the appropriate handler.
func (d *Daemon) HandleRequest(req Request) Response {
	switch req.Action {
	case "ping":
		return successResponse(map[string]interface{}{
			"status":   "pong",
			"protocol": CurrentProtocolVersion,
		})
	case "start":
		return d.handleStart(req)
	case "stop":
		return d.handleStop(req)
	case "stop_service":
		return d.handleStopService(req)
	case "restart":
		return d.handleRestart(req)
	case "status":
		return d.handleStatus()
	case "logs":
		return d.handleLogs(req)
	case "ports":
		return d.handlePorts()
	case "focus":
		return d.handleFocus(req)
	case "subscribe":
		// Handled at connection level, not here
		return errorResponse("subscribe must be handled at connection level")
	default:
		return errorResponse(fmt.Sprintf("unknown action: %s", req.Action))
	}
}

func (d *Daemon) handleStart(req Request) Response {
	if req.Project == "" {
		return errorResponse("project name required")
	}

	d.manager.RefreshRegistry()
	path, ok := d.manager.ProjectPath(req.Project)
	if !ok {
		return errorResponse(fmt.Sprintf("project %q not in registry", req.Project))
	}

	proj, err := config.LoadProject(path)
	if err != nil {
		return errorResponse(fmt.Sprintf("loading project config: %v", err))
	}

	exclusive := req.Mode != "parallel"

	// In exclusive mode, stop all other running projects first
	if exclusive {
		status := d.manager.Status()
		for name := range status {
			if name != req.Project {
				// Save git branch before stopping
				d.saveGitContext(name)
				d.manager.StopProject(name)
			}
		}
	}

	if d.manager.IsRunning(req.Project) {
		return successResponse(map[string]string{"status": "already_running"})
	}

	if err := d.manager.StartProject(req.Project, proj, path, exclusive); err != nil {
		return errorResponse(err.Error())
	}

	return successResponse(map[string]interface{}{
		"status": "started",
		"offset": d.manager.ports.GetOffset(req.Project),
	})
}

func (d *Daemon) handleStop(req Request) Response {
	if req.Project == "" {
		// Stop all
		d.manager.StopAll()
		return successResponse(map[string]string{"status": "all_stopped"})
	}

	if req.Service != "" {
		if err := d.manager.StopService(req.Project, req.Service); err != nil {
			return errorResponse(err.Error())
		}
		return successResponse(map[string]string{"status": "service_stopped"})
	}

	d.saveGitContext(req.Project)

	if err := d.manager.StopProject(req.Project); err != nil {
		return errorResponse(err.Error())
	}

	return successResponse(map[string]string{"status": "stopped"})
}

func (d *Daemon) handleStopService(req Request) Response {
	if req.Project == "" {
		return errorResponse("project name required")
	}
	if req.Service == "" {
		return errorResponse("service name required")
	}
	if err := d.manager.StopService(req.Project, req.Service); err != nil {
		return errorResponse(err.Error())
	}
	return successResponse(map[string]string{"status": "service_stopped"})
}

func (d *Daemon) handleRestart(req Request) Response {
	if req.Project == "" {
		return errorResponse("project name required")
	}
	if req.Service == "" {
		// Restart entire project
		path, ok := d.manager.ProjectPath(req.Project)
		if !ok {
			return errorResponse("project not in registry")
		}
		proj, err := config.LoadProject(path)
		if err != nil {
			return errorResponse(err.Error())
		}

		wasExclusive := d.manager.ports.GetOffset(req.Project) == 0
		d.manager.StopProject(req.Project)
		time.Sleep(500 * time.Millisecond)
		if err := d.manager.StartProject(req.Project, proj, path, wasExclusive); err != nil {
			return errorResponse(err.Error())
		}
		return successResponse(map[string]string{"status": "restarted"})
	}

	if err := d.manager.RestartService(req.Project, req.Service); err != nil {
		return errorResponse(err.Error())
	}
	return successResponse(map[string]string{"status": "restarted"})
}

func (d *Daemon) handleStatus() Response {
	return successResponse(d.manager.Status())
}

func (d *Daemon) handleLogs(req Request) Response {
	lines := req.Lines
	if lines <= 0 {
		lines = 500
	}
	logLines := d.manager.GetLogs(req.Project, req.Service, lines)
	return successResponse(logLines)
}

func (d *Daemon) handlePorts() Response {
	return successResponse(d.manager.Ports())
}

func (d *Daemon) handleFocus(req Request) Response {
	mode := req.Mode
	switch mode {
	case "exclusive":
		mode = "focus"
	case "parallel":
		mode = "multitask"
	}

	if req.Project == "" && mode == "" {
		return errorResponse("project or mode required")
	}
	if err := d.manager.SetFocus(req.Project, mode); err != nil {
		return errorResponse(err.Error())
	}
	return successResponse(map[string]string{"status": "ok"})
}
