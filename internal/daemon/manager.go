package daemon

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/sourabhrathourr/hun/internal/config"
	"github.com/sourabhrathourr/hun/internal/state"
)

// Manager orchestrates processes for all running projects.
type Manager struct {
	processes         map[string]map[string]*Process // project → service → process
	projectCfgs       map[string]*config.Project
	logs              *LogManager
	subscribers       *SubscriberManager
	ports             *PortManager
	portSignals       map[string]runtimePortSignal
	lastDiscoveryScan time.Time
	discoveryScanDirs []string
	discoveryWarnings []string
	iconCache         map[string]projectIconCacheEntry

	mu      sync.RWMutex
	stateMu sync.Mutex
	iconMu  sync.Mutex
	st      *state.State
}

type runtimePortSignal struct {
	port      int
	count     int
	lastSeen  time.Time
	confirmed bool
	verifying bool
	stopping  bool
}

// NewManager creates a new process manager.
func NewManager() (*Manager, error) {
	logMgr, err := NewLogManager()
	if err != nil {
		return nil, err
	}
	st, err := state.Load()
	if err != nil {
		return nil, err
	}
	return &Manager{
		processes:   make(map[string]map[string]*Process),
		projectCfgs: make(map[string]*config.Project),
		logs:        logMgr,
		subscribers: NewSubscriberManager(),
		ports:       NewPortManager(),
		portSignals: make(map[string]runtimePortSignal),
		iconCache:   make(map[string]projectIconCacheEntry),
		st:          st,
	}, nil
}

// RefreshRegistry merges on-disk registry changes into in-memory state.
func (m *Manager) RefreshRegistry() {
	onDisk, err := state.Load()
	if err != nil {
		return
	}
	m.stateMu.Lock()
	defer m.stateMu.Unlock()
	for name, path := range onDisk.Registry {
		m.st.Registry[name] = path
	}
	_ = m.st.Save()
}

func (m *Manager) ProjectPath(name string) (string, bool) {
	m.stateMu.Lock()
	defer m.stateMu.Unlock()
	path, ok := m.st.Registry[name]
	return path, ok
}

func (m *Manager) RegisterProjectPath(path string) (*config.Project, string, error) {
	abs, err := filepath.Abs(strings.TrimSpace(path))
	if err != nil {
		return nil, "", err
	}
	clean := filepath.Clean(abs)
	if !config.ProjectExists(clean) {
		return nil, "", fmt.Errorf("no .hun.yml found in %s", clean)
	}
	proj, err := config.LoadProject(clean)
	if err != nil {
		return nil, "", err
	}

	m.stateMu.Lock()
	defer m.stateMu.Unlock()
	if m.st == nil {
		st, err := state.Load()
		if err != nil {
			return nil, "", err
		}
		m.st = st
	}
	if m.st.Registry == nil {
		m.st.Registry = make(map[string]string)
	}
	if m.st.Projects == nil {
		m.st.Projects = make(map[string]state.ProjectState)
	}
	if existing, ok := m.st.Registry[proj.Name]; ok && filepath.Clean(existing) != clean {
		return nil, "", fmt.Errorf("project %q already registered at %s", proj.Name, existing)
	}

	m.st.Registry[proj.Name] = clean
	ps := m.st.Projects[proj.Name]
	if ps.Path == "" {
		ps.Path = clean
	}
	m.st.Projects[proj.Name] = ps
	m.lastDiscoveryScan = time.Time{}
	if err := m.st.Save(); err != nil {
		return nil, "", err
	}
	return proj, clean, nil
}

func (m *Manager) StateSnapshot() *state.State {
	m.stateMu.Lock()
	defer m.stateMu.Unlock()
	clone := &state.State{
		SchemaVersion: m.st.SchemaVersion,
		Mode:          m.st.Mode,
		ActiveProject: m.st.ActiveProject,
	}
	clone.Registry = make(map[string]string, len(m.st.Registry))
	for k, v := range m.st.Registry {
		clone.Registry[k] = v
	}
	clone.Projects = make(map[string]state.ProjectState, len(m.st.Projects))
	for k, v := range m.st.Projects {
		services := make(map[string]state.ServiceState, len(v.Services))
		for sn, sv := range v.Services {
			services[sn] = sv
		}
		v.Services = services
		clone.Projects[k] = v
	}
	return clone
}

// StartProject starts all services for a project.
func (m *Manager) StartProject(projectName string, projConfig *config.Project, projectPath string, exclusive bool) error {
	m.mu.Lock()
	if _, exists := m.processes[projectName]; exists {
		m.mu.Unlock()
		return fmt.Errorf("project %s already running", projectName)
	}
	// Register project immediately so status/tui can observe startup progress.
	m.processes[projectName] = make(map[string]*Process)
	m.projectCfgs[projectName] = projConfig
	m.mu.Unlock()

	if projConfig.Hooks.PreStart != "" {
		if err := runHook(projConfig.Hooks.PreStart, projectPath); err != nil {
			m.mu.Lock()
			delete(m.processes, projectName)
			delete(m.projectCfgs, projectName)
			m.mu.Unlock()
			return fmt.Errorf("pre_start hook failed: %w", err)
		}
	}

	m.logs.SetProjectConfig(projectName, projConfig.Logs)
	offset := m.ports.AssignOffset(projectName, exclusive)

	order, err := topoSort(projConfig)
	if err != nil {
		m.ports.ReleaseOffset(projectName)
		m.mu.Lock()
		delete(m.processes, projectName)
		delete(m.projectCfgs, projectName)
		m.mu.Unlock()
		return err
	}

	started := make(map[string]*Process)
	dependentCount := make(map[string]int)
	for _, svc := range projConfig.Services {
		for _, dep := range svc.DependsOn {
			dependentCount[dep]++
		}
	}
	rollback := func(startErr error) error {
		for _, proc := range started {
			_ = proc.Stop()
		}
		m.ports.ReleaseOffset(projectName)
		m.logs.CleanProject(projectName)
		m.clearRuntimePortSignals(projectName)
		m.mu.Lock()
		delete(m.processes, projectName)
		delete(m.projectCfgs, projectName)
		m.mu.Unlock()
		m.setProjectStopped(projectName)
		return startErr
	}

	for _, svcName := range order {
		svcConfig := projConfig.Services[svcName]
		actualPort := m.ports.ApplyOffset(projectName, svcConfig.Port)
		proc, err := m.startConfiguredService(projectName, svcName, svcConfig, projectPath, actualPort, dependentCount[svcName] > 0)
		if err != nil {
			return rollback(fmt.Errorf("starting service %s: %w", svcName, err))
		}
		started[svcName] = proc
	}

	m.setProjectRunning(projectName, projectPath, offset, exclusive)
	return nil
}

// StartService starts one service and any services it depends on.
func (m *Manager) StartService(projectName, serviceName string, projConfig *config.Project, projectPath string, exclusive bool) error {
	if projConfig.Services[serviceName] == nil {
		return fmt.Errorf("service %s not found in project %s", serviceName, projectName)
	}

	order, err := serviceStartOrder(projConfig, serviceName)
	if err != nil {
		return err
	}

	m.mu.Lock()
	newProject := false
	if _, exists := m.processes[projectName]; !exists {
		m.processes[projectName] = make(map[string]*Process)
		newProject = true
	}
	m.projectCfgs[projectName] = projConfig
	m.mu.Unlock()

	if newProject && projConfig.Hooks.PreStart != "" {
		if err := runHook(projConfig.Hooks.PreStart, projectPath); err != nil {
			m.mu.Lock()
			delete(m.processes, projectName)
			delete(m.projectCfgs, projectName)
			m.mu.Unlock()
			return fmt.Errorf("pre_start hook failed: %w", err)
		}
	}

	m.logs.SetProjectConfig(projectName, projConfig.Logs)
	offset := m.ports.AssignOffset(projectName, exclusive)
	started := make(map[string]*Process)
	rollback := func(startErr error) error {
		for _, proc := range started {
			_ = proc.Stop()
		}
		m.mu.Lock()
		if newProject {
			delete(m.processes, projectName)
			delete(m.projectCfgs, projectName)
		} else if procs := m.processes[projectName]; procs != nil {
			for name := range started {
				delete(procs, name)
			}
		}
		m.mu.Unlock()
		if newProject {
			m.ports.ReleaseOffset(projectName)
			m.setProjectStopped(projectName)
		}
		return startErr
	}

	for idx, svcName := range order {
		if m.IsServiceRunning(projectName, svcName) {
			continue
		}
		m.forgetProcess(projectName, svcName)

		svcConfig := projConfig.Services[svcName]
		actualPort := m.ports.ApplyOffset(projectName, svcConfig.Port)
		proc, err := m.startConfiguredService(projectName, svcName, svcConfig, projectPath, actualPort, idx < len(order)-1)
		if err != nil {
			return rollback(fmt.Errorf("starting service %s: %w", svcName, err))
		}
		started[svcName] = proc
	}

	m.setProjectRunning(projectName, projectPath, offset, exclusive)
	return nil
}

func (m *Manager) startConfiguredService(projectName, serviceName string, svcConfig *config.Service, projectPath string, actualPort int, waitForReady bool) (*Process, error) {
	lease, err := acquirePortLease(actualPort)
	if err != nil {
		return nil, err
	}
	if err := ensureTCPPortAvailable(actualPort); err != nil {
		lease.release()
		return nil, err
	}

	dir := projectPath
	if svcConfig.Cwd != "" {
		dir = filepath.Join(projectPath, svcConfig.Cwd)
	}

	restartPolicy := svcConfig.Restart
	proc := &Process{
		Name:         serviceName,
		Cmd:          svcConfig.Cmd,
		Dir:          dir,
		Env:          svcConfig.Env,
		PortEnv:      svcConfig.PortEnv,
		ReadyPattern: svcConfig.Ready,
		observedPort: actualPort,
		launchPort:   actualPort,
	}
	proc.SetPortLease(lease)

	// Every start boundary represents a fresh in-memory log session.
	m.logs.ResetService(projectName, serviceName)

	emitServiceLine := func(line string, isErr bool) {
		logLine := LogLine{
			Timestamp: time.Now(),
			Service:   serviceName,
			Project:   projectName,
			Text:      line,
			IsErr:     isErr,
		}
		m.logs.WriteLog(logLine)
		m.subscribers.Broadcast(logLine)
		m.observeRuntimePort(projectName, serviceName, line)
	}

	if err := ensureDockerReadyForCommand(svcConfig.Cmd, func(line string) {
		emitServiceLine(line, false)
	}); err != nil {
		return nil, err
	}

	proc.onOutput = emitServiceLine

	proc.onExit = func(err error, intentional bool) {
		status := "stopped"
		restarted := false
		if !intentional && err != nil {
			status = "crashed"
		}
		m.updateServiceState(projectName, serviceName, 0, actualPort, status)
		if status == "crashed" && restartPolicy == "on_failure" {
			time.Sleep(time.Second)
			m.logs.ResetService(projectName, serviceName)
			launchPort := proc.ResetObservedPort()
			if portErr := ensureTCPPortAvailable(launchPort); portErr != nil {
				m.updateServiceState(projectName, serviceName, 0, launchPort, "crashed")
			} else if restartErr := proc.Start(); restartErr == nil {
				restarted = true
				m.updateServiceState(projectName, serviceName, proc.PID(), launchPort, "running")
				go m.monitorRuntimePort(projectName, serviceName, proc, proc.PID(), proc.StartedAt())
			}
		}
		if !restarted {
			proc.ReleasePortLease()
		}
	}

	readyCh := make(chan struct{}, 1)
	proc.onReady = func() {
		select {
		case readyCh <- struct{}{}:
		default:
		}
	}

	// Register before starting output scanners so fast startup lines can update
	// the same live process model consumed by status and the macOS sidebar.
	m.mu.Lock()
	m.processes[projectName][serviceName] = proc
	m.mu.Unlock()

	if err := proc.Start(); err != nil {
		proc.ReleasePortLease()
		m.mu.Lock()
		if m.processes[projectName][serviceName] == proc {
			delete(m.processes[projectName], serviceName)
		}
		m.mu.Unlock()
		return nil, err
	}
	m.updateServiceState(projectName, serviceName, proc.PID(), actualPort, "running")
	go m.monitorRuntimePort(projectName, serviceName, proc, proc.PID(), proc.StartedAt())

	if waitForReady && svcConfig.Ready != "" {
		select {
		case <-readyCh:
		case <-time.After(30 * time.Second):
		}
	}
	return proc, nil
}

// StopProject stops all services for a project.
func (m *Manager) StopProject(projectName string) error {
	m.mu.RLock()
	procs, exists := m.processes[projectName]
	projCfg := m.projectCfgs[projectName]
	m.mu.RUnlock()
	if !exists {
		return fmt.Errorf("project %s not running", projectName)
	}

	procList := make([]*Process, 0, len(procs))
	for _, proc := range procs {
		procList = append(procList, proc)
	}

	var wg sync.WaitGroup
	errCh := make(chan error, len(procList))
	for _, proc := range procList {
		wg.Add(1)
		go func(p *Process) {
			defer wg.Done()
			if err := p.Stop(); err != nil {
				errCh <- err
			}
		}(proc)
	}
	wg.Wait()
	close(errCh)

	var stopErr error
	for err := range errCh {
		if stopErr == nil {
			stopErr = err
		}
	}
	if stopErr != nil {
		return stopErr
	}

	path := ""
	if p, ok := m.ProjectPath(projectName); ok {
		path = p
	}
	if projCfg != nil && projCfg.Hooks.PostStop != "" && path != "" {
		_ = runHook(projCfg.Hooks.PostStop, path)
	}

	m.ports.ReleaseOffset(projectName)
	m.logs.CleanProject(projectName)
	m.clearRuntimePortSignals(projectName)

	m.mu.Lock()
	delete(m.processes, projectName)
	delete(m.projectCfgs, projectName)
	nextActive := ""
	for name := range m.processes {
		nextActive = name
		break
	}
	m.mu.Unlock()

	m.setProjectStopped(projectName)
	if nextActive != "" {
		m.SetFocus(nextActive, m.currentMode())
	}
	return nil
}

// StopService stops a single service in a running project.
func (m *Manager) StopService(projectName, serviceName string) error {
	m.mu.RLock()
	procs, exists := m.processes[projectName]
	if !exists {
		m.mu.RUnlock()
		return fmt.Errorf("project %s not running", projectName)
	}
	proc, exists := procs[serviceName]
	if !exists {
		m.mu.RUnlock()
		return fmt.Errorf("service %s not found in project %s", serviceName, projectName)
	}
	port := proc.ObservedPort()
	m.mu.RUnlock()

	if err := proc.Stop(); err != nil {
		return err
	}

	m.clearRuntimePortSignal(projectName, serviceName)
	m.updateServiceState(projectName, serviceName, 0, port, "stopped")
	return nil
}

// StopAll stops all running projects.
func (m *Manager) StopAll() error {
	m.mu.RLock()
	names := make([]string, 0, len(m.processes))
	for name := range m.processes {
		names = append(names, name)
	}
	m.mu.RUnlock()

	for _, name := range names {
		_ = m.StopProject(name)
	}
	return nil
}

// RestartService restarts a single service within a project.
func (m *Manager) RestartService(projectName, serviceName string) error {
	m.mu.RLock()
	procs, exists := m.processes[projectName]
	if !exists {
		m.mu.RUnlock()
		return fmt.Errorf("project %s not running", projectName)
	}
	proc, exists := procs[serviceName]
	if !exists {
		m.mu.RUnlock()
		return fmt.Errorf("service %s not found in project %s", serviceName, projectName)
	}
	m.mu.RUnlock()

	if err := proc.Stop(); err != nil {
		return err
	}
	m.clearRuntimePortSignal(projectName, serviceName)
	m.logs.ResetService(projectName, serviceName)
	launchPort := proc.ResetObservedPort()
	lease, err := acquirePortLease(launchPort)
	if err != nil {
		m.updateServiceState(projectName, serviceName, 0, launchPort, "crashed")
		return err
	}
	proc.SetPortLease(lease)
	if err := ensureTCPPortAvailable(launchPort); err != nil {
		proc.ReleasePortLease()
		m.updateServiceState(projectName, serviceName, 0, launchPort, "crashed")
		return err
	}
	if err := proc.Start(); err != nil {
		proc.ReleasePortLease()
		m.updateServiceState(projectName, serviceName, 0, launchPort, "crashed")
		return err
	}
	m.updateServiceState(projectName, serviceName, proc.PID(), launchPort, "running")
	go m.monitorRuntimePort(projectName, serviceName, proc, proc.PID(), proc.StartedAt())
	return nil
}

// Status returns current status of all running projects and services.
func (m *Manager) Status() map[string]map[string]ServiceInfo {
	m.mu.RLock()
	defer m.mu.RUnlock()
	stateStatuses := m.serviceStatusSnapshot()

	result := make(map[string]map[string]ServiceInfo)
	for proj, procs := range m.processes {
		result[proj] = make(map[string]ServiceInfo)
		for name, proc := range procs {
			running := proc.IsRunning()
			status := stateStatuses[proj][name]
			if status == "" {
				if running {
					status = "running"
				} else {
					status = "stopped"
				}
			}
			if running {
				status = "running"
			}
			result[proj][name] = ServiceInfo{
				PID:       proc.PID(),
				Port:      proc.ObservedPort(),
				Status:    status,
				Running:   running,
				Ready:     proc.IsReady(),
				StartedAt: proc.StartedAt(),
			}
		}
	}
	return result
}

func (m *Manager) serviceStatusSnapshot() map[string]map[string]string {
	m.stateMu.Lock()
	defer m.stateMu.Unlock()

	result := make(map[string]map[string]string)
	if m.st == nil {
		return result
	}
	for project, ps := range m.st.Projects {
		if len(ps.Services) == 0 {
			continue
		}
		services := make(map[string]string, len(ps.Services))
		for service, ss := range ps.Services {
			services[service] = ss.Status
		}
		result[project] = services
	}
	return result
}

// Ports returns port mapping for all running services.
func (m *Manager) Ports() map[string]map[string]int {
	m.mu.RLock()
	defer m.mu.RUnlock()

	result := make(map[string]map[string]int)
	for proj, procs := range m.processes {
		result[proj] = make(map[string]int)
		for name, proc := range procs {
			if port := proc.ObservedPort(); port > 0 {
				result[proj][name] = port
			}
		}
	}
	return result
}

// GetLogs returns buffered log lines for a service.
func (m *Manager) GetLogs(project, service string, lines int) []LogLine {
	return m.logs.GetLines(project, service, lines)
}

// Subscribe creates a new log subscriber.
func (m *Manager) Subscribe(project, service string) *Subscriber {
	return m.subscribers.Subscribe(project, service)
}

// Unsubscribe removes a subscriber.
func (m *Manager) Unsubscribe(id int) {
	m.subscribers.Unsubscribe(id)
}

// IsRunning checks if a project is running.
func (m *Manager) IsRunning(project string) bool {
	m.mu.RLock()
	defer m.mu.RUnlock()
	_, exists := m.processes[project]
	return exists
}

// IsServiceRunning checks if one service is currently running.
func (m *Manager) IsServiceRunning(project, service string) bool {
	m.mu.RLock()
	proc := m.processes[project][service]
	m.mu.RUnlock()
	return proc != nil && proc.IsRunning()
}

// ForgetService removes one service from in-memory process and persisted state.
func (m *Manager) ForgetService(project, service string, projConfig *config.Project) {
	m.clearRuntimePortSignal(project, service)

	releaseOffset := false
	m.mu.Lock()
	if procs := m.processes[project]; procs != nil {
		delete(procs, service)
		if len(procs) == 0 {
			delete(m.processes, project)
			delete(m.projectCfgs, project)
			releaseOffset = true
		} else if projConfig != nil {
			m.projectCfgs[project] = projConfig
		}
	}
	m.mu.Unlock()

	if releaseOffset {
		m.ports.ReleaseOffset(project)
		m.setProjectStopped(project)
		return
	}
	m.deleteServiceState(project, service)
}

func (m *Manager) forgetProcess(project, service string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if procs := m.processes[project]; procs != nil {
		delete(procs, service)
	}
}

// RunningProjects returns sorted running project names.
func (m *Manager) RunningProjects() []string {
	m.mu.RLock()
	defer m.mu.RUnlock()
	projects := make([]string, 0, len(m.processes))
	for name := range m.processes {
		projects = append(projects, name)
	}
	sort.Strings(projects)
	return projects
}

// SetFocus updates active project and mode without process restarts.
func (m *Manager) SetFocus(project, mode string) error {
	if mode != "focus" && mode != "multitask" && mode != "" {
		return fmt.Errorf("invalid mode %q", mode)
	}
	return m.mutateState(func(st *state.State) {
		if project != "" {
			st.ActiveProject = project
		}
		if mode != "" {
			st.Mode = mode
		}
	})
}

// SetGitBranch persists the last observed git branch for a project.
func (m *Manager) SetGitBranch(project, branch string) {
	_ = m.mutateState(func(st *state.State) {
		ps := st.Projects[project]
		ps.GitBranch = branch
		st.Projects[project] = ps
	})
}

// Shutdown performs graceful shutdown of all processes.
func (m *Manager) Shutdown() {
	_ = m.StopAll()
	m.logs.Close()
}

// ServiceInfo holds info about a running service.
type ServiceInfo struct {
	PID       int       `json:"pid"`
	Port      int       `json:"port"`
	Status    string    `json:"status,omitempty"`
	Running   bool      `json:"running"`
	Ready     bool      `json:"ready"`
	StartedAt time.Time `json:"started_at,omitempty"`
}

var runtimePortPatterns = []*regexp.Regexp{
	regexp.MustCompile(`https?://[^\s:]+:(\d{2,5})`),
	regexp.MustCompile(`\b(?:localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\]|::1):(\d{2,5})\b`),
	regexp.MustCompile(`\bport(?:\s+is|\s*=|\s+)?\s*(\d{2,5})\b`),
}

var listeningAddressPattern = regexp.MustCompile(`(?i)\b(?:uvicorn running on|listening on|server (?:is )?(?:running|listening)(?: at| on)?|local:)\b`)

func (m *Manager) updateServiceState(project, service string, pid, port int, status string) {
	_ = m.mutateState(func(st *state.State) {
		ps := st.Projects[project]
		if ps.Services == nil {
			ps.Services = make(map[string]state.ServiceState)
		}
		ps.Services[service] = state.ServiceState{
			PID:    pid,
			Port:   port,
			Status: status,
		}
		st.Projects[project] = ps
	})
}

func (m *Manager) deleteServiceState(project, service string) {
	_ = m.mutateState(func(st *state.State) {
		ps := st.Projects[project]
		if ps.Services != nil {
			delete(ps.Services, service)
			if len(ps.Services) == 0 {
				ps.Services = nil
			}
		}
		st.Projects[project] = ps
	})
}

func (m *Manager) observeRuntimePort(project, service, line string) {
	if strings.Contains(line, "[hun] detected runtime port") {
		return
	}
	detected := extractRuntimePort(line)
	if detected <= 0 {
		return
	}

	key := project + ":" + service
	now := time.Now()

	m.mu.Lock()
	procs := m.processes[project]
	proc := procs[service]
	if proc == nil {
		m.mu.Unlock()
		return
	}
	current := proc.ObservedPort()
	launchPort := proc.LaunchPort()
	signal := m.portSignals[key]
	if signal.port == detected && now.Sub(signal.lastSeen) <= 10*time.Second {
		signal.count++
	} else {
		signal.port = detected
		signal.count = 1
	}
	signal.lastSeen = now
	m.portSignals[key] = signal

	threshold := 2
	if current == 0 || listeningAddressPattern.MatchString(line) {
		threshold = 1
	}
	if signal.count < threshold || (current == detected && (signal.confirmed || launchPort == detected)) {
		m.mu.Unlock()
		return
	}
	if signal.verifying {
		m.mu.Unlock()
		return
	}
	signal.verifying = true
	m.portSignals[key] = signal
	procPID := proc.PID()
	m.mu.Unlock()

	listeningPorts, inspectErr := processGroupListeningTCPPorts(procPID)

	m.mu.Lock()
	currentProc := m.processes[project][service]
	signal = m.portSignals[key]
	signal.verifying = false
	m.portSignals[key] = signal
	if inspectErr != nil || !listeningPorts[detected] || currentProc != proc || (launchPort > 0 && listeningPorts[launchPort]) {
		m.mu.Unlock()
		return
	}
	m.mu.Unlock()
	m.applyVerifiedRuntimePort(project, service, proc, detected)
}

func (m *Manager) monitorRuntimePort(project, service string, proc *Process, pid int, startedAt time.Time) {
	if pid <= 0 {
		return
	}
	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()

	for range ticker.C {
		if !proc.IsRunning() || proc.PID() != pid || proc.StartedAt() != startedAt {
			return
		}
		ports, err := processGroupListeningTCPPorts(pid)
		if err != nil {
			if errors.Is(err, errPortInspectionUnavailable) {
				m.emitInternalServiceLine(project, service, "[hun] runtime port verification is unavailable; showing the configured port", true)
				return
			}
			continue
		}
		launchPort := proc.LaunchPort()
		if launchPort > 0 && ports[launchPort] {
			return
		}
		if launchPort > 0 && len(ports) > 1 && proc.IsReady() && time.Since(startedAt) >= 2*time.Second {
			m.rejectMissingConfiguredPort(project, service, proc, launchPort, ports)
			return
		}
		if len(ports) != 1 {
			continue
		}
		var detected int
		for port := range ports {
			detected = port
		}
		if launchPort == 0 || time.Since(startedAt) >= 2*time.Second {
			m.applyVerifiedRuntimePort(project, service, proc, detected)
			return
		}
	}
}

func (m *Manager) rejectMissingConfiguredPort(project, service string, proc *Process, configuredPort int, ports map[int]bool) {
	key := project + ":" + service
	m.mu.Lock()
	if m.processes[project][service] != proc {
		m.mu.Unlock()
		return
	}
	signal := m.portSignals[key]
	if signal.stopping {
		m.mu.Unlock()
		return
	}
	signal.stopping = true
	m.portSignals[key] = signal
	m.mu.Unlock()

	observed := make([]int, 0, len(ports))
	for port := range ports {
		observed = append(observed, port)
	}
	sort.Ints(observed)
	detail := "none"
	if len(observed) > 0 {
		values := make([]string, 0, len(observed))
		for _, port := range observed {
			values = append(values, strconv.Itoa(port))
		}
		detail = strings.Join(values, ", ")
	}
	m.emitInternalServiceLine(project, service, fmt.Sprintf("[hun] configured port %d is not owned by the service; verified listeners: %s; stopping service", configuredPort, detail), true)
	go func() {
		_ = proc.Stop()
		m.mu.RLock()
		currentProc := m.processes[project][service]
		m.mu.RUnlock()
		if currentProc == proc {
			m.updateServiceState(project, service, 0, proc.ObservedPort(), "crashed")
		}
	}()
}

func (m *Manager) applyVerifiedRuntimePort(project, service string, proc *Process, detected int) {
	key := project + ":" + service

	m.mu.Lock()
	if m.processes[project][service] != proc {
		m.mu.Unlock()
		return
	}
	signal := m.portSignals[key]
	current := proc.ObservedPort()
	launchPort := proc.LaunchPort()
	if current == detected && signal.confirmed {
		m.mu.Unlock()
		return
	}
	proc.SetObservedPort(detected)
	signal.port = detected
	signal.lastSeen = time.Now()
	signal.confirmed = true
	shouldStop := launchPort > 0 && detected != launchPort && !signal.stopping
	if shouldStop {
		signal.stopping = true
	}
	m.portSignals[key] = signal
	procPID := proc.PID()
	m.mu.Unlock()

	offset := m.ports.GetOffset(project)
	basePort := detected - offset
	if basePort <= 0 {
		basePort = detected
	}

	m.updateServiceState(project, service, procPID, detected, "running")

	m.emitInternalServiceLine(project, service, fmt.Sprintf("[hun] detected runtime port %d (base %d, offset %d)", detected, basePort, offset), false)

	if shouldStop {
		m.emitInternalServiceLine(project, service, fmt.Sprintf("[hun] configured port %d but service bound %d; stopping service", launchPort, detected), true)
		go func() {
			_ = proc.Stop()
			m.mu.RLock()
			currentProc := m.processes[project][service]
			m.mu.RUnlock()
			if currentProc == proc {
				m.updateServiceState(project, service, 0, detected, "crashed")
			}
		}()
	}
}

func (m *Manager) emitInternalServiceLine(project, service, line string, isErr bool) {
	entry := LogLine{
		Timestamp: time.Now(),
		Service:   service,
		Project:   project,
		Text:      line,
		IsErr:     isErr,
	}
	m.logs.WriteLog(entry)
	m.subscribers.Broadcast(entry)
}

func (m *Manager) clearRuntimePortSignals(project string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	prefix := project + ":"
	for key := range m.portSignals {
		if strings.HasPrefix(key, prefix) {
			delete(m.portSignals, key)
		}
	}
}

func (m *Manager) clearRuntimePortSignal(project, service string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.portSignals, project+":"+service)
}

func extractRuntimePort(line string) int {
	for _, re := range runtimePortPatterns {
		matches := re.FindAllStringSubmatch(line, -1)
		for _, m := range matches {
			if len(m) != 2 {
				continue
			}
			if p := parseRuntimePort(m[1]); p > 0 {
				return p
			}
		}
	}
	return 0
}

func parseRuntimePort(raw string) int {
	n, err := strconv.Atoi(strings.TrimSpace(raw))
	if err != nil {
		return 0
	}
	if n <= 0 || n > 65535 {
		return 0
	}
	return n
}

func (m *Manager) setProjectRunning(project, path string, offset int, exclusive bool) {
	_ = m.mutateState(func(st *state.State) {
		ps := st.Projects[project]
		ps.Status = "running"
		ps.Offset = offset
		ps.Path = path
		ps.StartedAt = time.Now().UTC().Format(time.RFC3339)
		if ps.Services == nil {
			ps.Services = make(map[string]state.ServiceState)
		}
		st.Projects[project] = ps
		st.ActiveProject = project
		if exclusive {
			st.Mode = "focus"
		} else {
			st.Mode = "multitask"
		}
	})
}

func (m *Manager) setProjectStopped(project string) {
	_ = m.mutateState(func(st *state.State) {
		ps := st.Projects[project]
		ps.Status = "stopped"
		ps.Services = nil
		st.Projects[project] = ps
		if st.ActiveProject == project {
			st.ActiveProject = ""
		}
	})
}

func (m *Manager) currentMode() string {
	m.stateMu.Lock()
	defer m.stateMu.Unlock()
	if m.st.Mode == "" {
		return "focus"
	}
	return m.st.Mode
}

func (m *Manager) mutateState(fn func(st *state.State)) error {
	m.stateMu.Lock()
	defer m.stateMu.Unlock()
	if m.st == nil {
		st, err := state.Load()
		if err != nil {
			return err
		}
		m.st = st
	}
	fn(m.st)
	return m.st.Save()
}

// topoSort returns services in dependency order.
func topoSort(proj *config.Project) ([]string, error) {
	visited := make(map[string]bool)
	temp := make(map[string]bool)
	var order []string

	var visit func(name string) error
	visit = func(name string) error {
		if temp[name] {
			return fmt.Errorf("dependency cycle at service %s", name)
		}
		if visited[name] {
			return nil
		}
		temp[name] = true
		svc := proj.Services[name]
		if svc != nil {
			for _, dep := range svc.DependsOn {
				if err := visit(dep); err != nil {
					return err
				}
			}
		}
		temp[name] = false
		visited[name] = true
		order = append(order, name)
		return nil
	}

	for name := range proj.Services {
		if err := visit(name); err != nil {
			return nil, err
		}
	}
	return order, nil
}

func serviceStartOrder(proj *config.Project, target string) ([]string, error) {
	needed := make(map[string]bool)
	var collect func(name string) error
	collect = func(name string) error {
		if needed[name] {
			return nil
		}
		svc := proj.Services[name]
		if svc == nil {
			return fmt.Errorf("service %s not found", name)
		}
		needed[name] = true
		for _, dep := range svc.DependsOn {
			if err := collect(dep); err != nil {
				return err
			}
		}
		return nil
	}
	if err := collect(target); err != nil {
		return nil, err
	}

	all, err := topoSort(proj)
	if err != nil {
		return nil, err
	}
	order := make([]string, 0, len(needed))
	for _, name := range all {
		if needed[name] {
			order = append(order, name)
		}
	}
	return order, nil
}

func runHook(cmd, dir string) error {
	if strings.TrimSpace(cmd) == "" {
		return nil
	}
	shell := getenvDefault("SHELL", "/bin/sh")
	c := exec.Command(shell, "-c", cmd)
	c.Dir = dir
	c.Env = buildServiceEnvironment(nil, "", 0)
	return c.Run()
}

func getenvDefault(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}
