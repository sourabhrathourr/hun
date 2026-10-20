package daemon

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"sort"
	"time"

	"github.com/sourabhrathourr/hun/internal/config"
)

// Request represents a JSON command from CLI/TUI.
type Request struct {
	Action  string `json:"action"`
	Project string `json:"project,omitempty"`
	Service string `json:"service,omitempty"`
	Path    string `json:"path,omitempty"`
	Branch  string `json:"branch,omitempty"`
	Mode    string `json:"mode,omitempty"` // "exclusive" or "parallel"
	Lines   int    `json:"lines,omitempty"`
	Note    string `json:"note,omitempty"`
	Origin  string `json:"origin,omitempty"`
	Stash   bool   `json:"stash,omitempty"`
	Port    int    `json:"port,omitempty"`
}

// Response is the JSON response from the daemon.
type Response struct {
	OK    bool            `json:"ok"`
	Error string          `json:"error,omitempty"`
	Data  json.RawMessage `json:"data,omitempty"`
	// Conflict identifies what holds a port when a start failed on it.
	Conflict *PortHolder `json:"conflict,omitempty"`
}

func successResponse(data interface{}) Response {
	raw, _ := json.Marshal(data)
	return Response{OK: true, Data: raw}
}

func errorResponse(msg string) Response {
	return Response{OK: false, Error: msg}
}

// errorResponseFrom keeps the port holder of a conflict so clients can offer
// to stop it.
func errorResponseFrom(err error) Response {
	resp := errorResponse(err.Error())
	var conflict *PortConflictError
	if errors.As(err, &conflict) {
		holder := conflict.Holder
		resp.Conflict = &holder
	}
	return resp
}

// HandleRequest routes an API request to the appropriate handler.
func (d *Daemon) HandleRequest(req Request) Response {
	if serializesGitMutation(req.Action) {
		d.gitMu.Lock()
		defer d.gitMu.Unlock()
	}
	if req.Action == "snapshot" || req.Action == "refresh" {
		if req.Origin == "hook" {
			return errorResponse("lifecycle commands cannot run recursively from Hun hooks")
		}
		return d.handleSnapshotRequest(req.Action == "refresh")
	}
	if serializesLifecycle(req.Action) {
		if req.Origin == "hook" {
			return errorResponse("lifecycle commands cannot run recursively from Hun hooks")
		}
		if !d.acquireLifecycle(30 * time.Second) {
			return errorResponse("lifecycle operation in progress")
		}
		defer d.lifecycleMu.Unlock()
	}
	switch req.Action {
	case "ping":
		return successResponse(map[string]interface{}{
			"status":     "pong",
			"protocol":   CurrentProtocolVersion,
			"version":    d.version,
			"commit":     d.commit,
			"pid":        os.Getpid(),
			"started_at": d.startedAt,
		})
	case "start":
		return d.handleStart(req)
	case "start_service":
		return d.handleStartService(req)
	case "stop":
		return d.handleStop(req)
	case "stop_service":
		return d.handleStopService(req)
	case "remove_service":
		return d.handleRemoveService(req)
	case "set_project_icon":
		return d.handleSetProjectIcon(req)
	case "clear_project_icon":
		return d.handleClearProjectIcon(req)
	case "restart":
		return d.handleRestart(req)
	case "status":
		return d.handleStatus()
	case "register_project", "add_project":
		return d.handleRegisterProject(req)
	case "remove_project":
		return d.handleRemoveProject(req)
	case "logs":
		return d.handleLogs(req)
	case "git_status":
		return d.handleGitStatus(req)
	case "git_branches":
		return d.handleGitBranches(req)
	case "git_create_branch":
		return d.handleGitCreateBranch(req)
	case "git_switch_branch":
		return d.handleGitSwitchBranch(req)
	case "git_fetch":
		return d.handleGitFetch(req)
	case "ports":
		return d.handlePorts()
	case "focus":
		return d.handleFocus(req)
	case "free_port":
		return d.handleFreePort(req)
	case "subscribe":
		// Handled at connection level, not here
		return errorResponse("subscribe must be handled at connection level")
	default:
		return errorResponse(fmt.Sprintf("unknown action: %s", req.Action))
	}
}

func serializesGitMutation(action string) bool {
	switch action {
	case "git_create_branch", "git_switch_branch", "git_fetch":
		return true
	default:
		return false
	}
}

func (d *Daemon) acquireLifecycle(timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for {
		if d.lifecycleMu.TryLock() {
			return true
		}
		if time.Now().After(deadline) {
			return false
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func serializesLifecycle(action string) bool {
	switch action {
	case "start", "start_service", "stop", "stop_service", "remove_service", "restart", "focus",
		"register_project", "add_project", "remove_project", "free_port":
		return true
	default:
		return false
	}
}

func (d *Daemon) handleStart(req Request) Response {
	if req.Project == "" {
		return errorResponse("project name required")
	}

	if _, err := d.manager.ReconcileDiscovery(true); err != nil {
		return errorResponse(fmt.Sprintf("refreshing project registry: %v", err))
	}
	path, ok := d.manager.ProjectPath(req.Project)
	if !ok {
		return errorResponse(fmt.Sprintf("project %q not in registry", req.Project))
	}

	proj, err := config.LoadProject(path)
	if err != nil {
		return errorResponse(fmt.Sprintf("loading project config: %v", err))
	}

	exclusive := req.Mode != "parallel"
	if exclusive {
		d.clearForFocus(req.Project, proj)
	}

	if d.manager.IsRunning(req.Project) {
		mode := "multitask"
		if exclusive {
			mode = "focus"
		}
		if err := d.manager.SetFocus(req.Project, mode); err != nil {
			return errorResponse(err.Error())
		}
		return successResponse(map[string]string{"status": "already_running"})
	}

	if err := d.manager.StartProject(req.Project, proj, path, exclusive); err != nil {
		return errorResponseFrom(err)
	}

	return successResponse(map[string]interface{}{
		"status": "started",
		"offset": d.manager.ports.GetOffset(req.Project),
	})
}

func (d *Daemon) handleStartService(req Request) Response {
	if req.Project == "" {
		return errorResponse("project name required")
	}
	if req.Service == "" {
		return errorResponse("service name required")
	}

	if _, err := d.manager.ReconcileDiscovery(true); err != nil {
		return errorResponse(fmt.Sprintf("refreshing project registry: %v", err))
	}
	path, ok := d.manager.ProjectPath(req.Project)
	if !ok {
		return errorResponse(fmt.Sprintf("project %q not in registry", req.Project))
	}
	proj, err := config.LoadProject(path)
	if err != nil {
		return errorResponse(fmt.Sprintf("loading project config: %v", err))
	}

	exclusive := req.Mode != "parallel"
	if exclusive {
		d.clearForFocus(req.Project, proj)
	}

	if err := d.manager.StartService(req.Project, req.Service, proj, path, exclusive); err != nil {
		return errorResponseFrom(err)
	}
	return successResponse(map[string]string{"status": "service_started"})
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

func (d *Daemon) handleRemoveService(req Request) Response {
	if req.Project == "" {
		return errorResponse("project name required")
	}
	if req.Service == "" {
		return errorResponse("service name required")
	}

	if _, err := d.manager.ReconcileDiscovery(true); err != nil {
		return errorResponse(fmt.Sprintf("refreshing project registry: %v", err))
	}
	path, ok := d.manager.ProjectPath(req.Project)
	if !ok {
		return errorResponse(fmt.Sprintf("project %q not in registry", req.Project))
	}
	proj, err := config.LoadProject(path)
	if err != nil {
		return errorResponse(fmt.Sprintf("loading project config: %v", err))
	}
	updated, err := config.ProjectWithoutService(proj, req.Service)
	if err != nil {
		return errorResponse(err.Error())
	}

	if d.manager.IsServiceRunning(req.Project, req.Service) {
		if err := d.manager.StopService(req.Project, req.Service); err != nil {
			return errorResponse(err.Error())
		}
	}
	if err := config.WriteProject(path, updated); err != nil {
		return errorResponse(err.Error())
	}
	d.manager.ForgetService(req.Project, req.Service, updated)
	return successResponse(map[string]string{"status": "service_removed"})
}

func (d *Daemon) handleSetProjectIcon(req Request) Response {
	if req.Project == "" {
		return errorResponse("project name required")
	}
	if req.Path == "" {
		return errorResponse("icon path required")
	}
	if _, err := d.manager.ReconcileDiscovery(true); err != nil {
		return errorResponse(fmt.Sprintf("refreshing project registry: %v", err))
	}
	path, err := d.manager.SetProjectIcon(req.Project, req.Path)
	if err != nil {
		return errorResponse(err.Error())
	}
	return successResponse(map[string]string{"status": "project_icon_set", "icon_path": path})
}

func (d *Daemon) handleClearProjectIcon(req Request) Response {
	if req.Project == "" {
		return errorResponse("project name required")
	}
	if _, err := d.manager.ReconcileDiscovery(true); err != nil {
		return errorResponse(fmt.Sprintf("refreshing project registry: %v", err))
	}
	if err := d.manager.ClearProjectIcon(req.Project); err != nil {
		return errorResponse(err.Error())
	}
	return successResponse(map[string]string{"status": "project_icon_cleared"})
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

		wasExclusive := d.manager.currentMode() == "focus"
		d.manager.StopProject(req.Project)
		time.Sleep(500 * time.Millisecond)
		if err := d.manager.StartProject(req.Project, proj, path, wasExclusive); err != nil {
			return errorResponseFrom(err)
		}
		return successResponse(map[string]string{"status": "restarted"})
	}

	if !d.manager.IsServiceRunning(req.Project, req.Service) {
		// Not running under Hun: stop any instance started elsewhere, then
		// start it here so Hun owns it and captures its logs.
		path, ok := d.manager.ProjectPath(req.Project)
		if !ok {
			return errorResponse("project not in registry")
		}
		proj, err := config.LoadProject(path)
		if err != nil {
			return errorResponse(err.Error())
		}
		if _, ok := d.manager.attribution(freshObservationAge).external(req.Project, req.Service); ok {
			if err := d.manager.StopService(req.Project, req.Service); err != nil {
				return errorResponse(err.Error())
			}
			if svc := proj.Services[req.Service]; svc != nil && svc.Port > 0 {
				waitForPortRelease([]int{svc.Port}, portReleaseTimeout)
			}
		}
		exclusive := d.manager.currentMode() == "focus"
		if err := d.manager.StartService(req.Project, req.Service, proj, path, exclusive); err != nil {
			return errorResponseFrom(err)
		}
		return successResponse(map[string]string{"status": "restarted"})
	}

	if err := d.manager.RestartService(req.Project, req.Service); err != nil {
		return errorResponseFrom(err)
	}
	return successResponse(map[string]string{"status": "restarted"})
}

// clearForFocus makes the machine look like target is the only project:
// other projects stop whether or not Hun started them, and target's
// configured ports get time to free up.
func (d *Daemon) clearForFocus(target string, proj *config.Project) {
	for name := range d.manager.Status() {
		if name != target {
			d.saveGitContext(name)
			_ = d.manager.StopProject(name)
		}
	}
	_ = d.manager.stopExternalsExcept(target)
	d.manager.waitForProjectPorts(target, proj, portReleaseTimeout)
}

func (d *Daemon) handleFreePort(req Request) Response {
	if req.Port <= 0 {
		return errorResponse("port required")
	}
	if err := d.manager.FreePort(req.Port); err != nil {
		return errorResponse(err.Error())
	}
	return successResponse(map[string]string{"status": "port_freed"})
}

func (d *Daemon) handleStatus() Response {
	return successResponse(d.manager.StatusWithExternal())
}

func (d *Daemon) handleSnapshot(force bool) Response {
	snapshot, err := d.manager.Snapshot(force)
	if err != nil {
		return errorResponse(err.Error())
	}
	return successResponse(snapshot)
}

// handleSnapshotRequest keeps the dashboard readable while startup recovery or
// another service transition owns the lifecycle lock. Discovery mutates the
// registry, so it still runs under that lock; the fallback only reads the
// already-loaded registry and current process state.
func (d *Daemon) handleSnapshotRequest(force bool) Response {
	if d.acquireLifecycle(100 * time.Millisecond) {
		defer d.lifecycleMu.Unlock()
		return d.handleSnapshot(force)
	}

	snapshot := d.manager.CachedSnapshot()
	snapshot.LifecycleBusy = true
	return successResponse(snapshot)
}

func (d *Daemon) handleRegisterProject(req Request) Response {
	if req.Path == "" {
		return errorResponse("project path required")
	}
	proj, key, path, err := d.manager.RegisterProjectPath(req.Path)
	if err != nil {
		return errorResponse(err.Error())
	}
	return successResponse(map[string]string{
		"status":  "registered",
		"project": key,
		"name":    proj.Name,
		"path":    path,
	})
}

func (d *Daemon) handleRemoveProject(req Request) Response {
	if req.Project == "" {
		return errorResponse("project name required")
	}
	d.saveGitContext(req.Project)
	if err := d.manager.RemoveProject(req.Project); err != nil {
		return errorResponse(err.Error())
	}
	return successResponse(map[string]string{"status": "project_removed"})
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
	if mode == "focus" {
		if err := d.transitionToFocus(req.Project); err != nil {
			return errorResponse(err.Error())
		}
		return successResponse(map[string]string{
			"status":  "ok",
			"project": d.manager.FocusSurvivor(req.Project),
		})
	}
	if err := d.manager.SetFocus(req.Project, mode); err != nil {
		return errorResponse(err.Error())
	}
	return successResponse(map[string]string{"status": "ok"})
}

func (d *Daemon) transitionToFocus(preferred string) error {
	survivor := d.manager.FocusSurvivor(preferred)
	var survivorPath string
	var survivorConfig *config.Project
	var runningServices []string
	originalPorts := make(map[string]int)
	needsBasePortRestart := false
	if survivor != "" {
		var ok bool
		survivorPath, ok = d.manager.ProjectPath(survivor)
		if !ok {
			return fmt.Errorf("focus survivor %q is not registered", survivor)
		}
		var err error
		survivorConfig, err = config.LoadProject(survivorPath)
		if err != nil {
			return fmt.Errorf("loading focus survivor config: %w", err)
		}
		for service, info := range d.manager.Status()[survivor] {
			if !info.Running {
				continue
			}
			runningServices = append(runningServices, service)
			originalPorts[service] = info.Port
			if svc := survivorConfig.Services[service]; svc != nil && svc.Port > 0 && info.Port != svc.Port {
				needsBasePortRestart = true
			}
		}
		sort.Strings(runningServices)
	}

	for _, name := range d.manager.RunningProjects() {
		if name == survivor {
			continue
		}
		d.saveGitContext(name)
		if err := d.manager.StopProject(name); err != nil {
			return fmt.Errorf("stopping %s for focus mode: %w", name, err)
		}
	}

	keep := survivor
	if keep == "" {
		keep = preferred
	}
	if keep != "" {
		if err := d.manager.stopExternalsExcept(keep); err != nil {
			return fmt.Errorf("stopping services outside %s for focus mode: %w", keep, err)
		}
	}

	if err := d.manager.SetFocusMode(survivor); err != nil {
		return err
	}
	if !needsBasePortRestart && d.manager.ports.GetOffset(survivor) != 0 {
		return d.manager.MoveProjectToBaseOffset(survivor)
	}
	if !needsBasePortRestart {
		return nil
	}
	for _, service := range runningServices {
		svc := survivorConfig.Services[service]
		if svc == nil || svc.Port <= 0 {
			continue
		}
		if err := ensureTCPPortAvailable(svc.Port); err != nil {
			return fmt.Errorf("cannot restore %s/%s to base port %d; it remains running on port %d: %w", survivor, service, svc.Port, originalPorts[service], err)
		}
	}
	if err := d.manager.StopProject(survivor); err != nil {
		return fmt.Errorf("stopping %s to restore base ports: %w", survivor, err)
	}
	for _, service := range runningServices {
		if err := d.manager.StartService(survivor, service, survivorConfig, survivorPath, true); err != nil {
			basePortErr := fmt.Errorf("restarting %s/%s on base ports: %w", survivor, service, err)
			if rollbackErr := d.restoreFocusSurvivor(survivor, survivorPath, survivorConfig, runningServices, originalPorts); rollbackErr != nil {
				return fmt.Errorf("%v; restoring previous service ports also failed: %w", basePortErr, rollbackErr)
			}
			return fmt.Errorf("%v; restored previous service ports", basePortErr)
		}
	}
	return nil
}

func (d *Daemon) restoreFocusSurvivor(project, path string, proj *config.Project, services []string, ports map[string]int) error {
	if d.manager.IsRunning(project) {
		if err := d.manager.StopProject(project); err != nil {
			return err
		}
	}
	for _, service := range services {
		if err := d.manager.startService(project, service, proj, path, true, ports); err != nil {
			return err
		}
	}
	return d.manager.SetFocusMode(project)
}
