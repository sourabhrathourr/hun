package daemon

import (
	"fmt"
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
	processes   map[string]map[string]*Process // project → service → process
	projectCfgs map[string]*config.Project
	logs        *LogManager
	subscribers *SubscriberManager
	ports       *PortManager
	portSignals map[string]runtimePortSignal

	mu      sync.RWMutex
	stateMu sync.Mutex
	st      *state.State
}

type runtimePortSignal struct {
	port      int
	count     int
	lastSeen  time.Time
	confirmed bool
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
		if len(v.PortOverrides) > 0 {
			overrides := make(map[string]int, len(v.PortOverrides))
			for sn, sp := range v.PortOverrides {
				overrides[sn] = sp
			}
			v.PortOverrides = overrides
		}
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
		basePort := m.resolveBasePort(projectName, svcName, svcConfig.Port)
		actualPort := basePort + offset

		dir := projectPath
		if svcConfig.Cwd != "" {
			dir = filepath.Join(projectPath, svcConfig.Cwd)
		}

		serviceName := svcName
		restartPolicy := svcConfig.Restart
		proc := &Process{
			Name:         serviceName,
			Cmd:          svcConfig.Cmd,
			Dir:          dir,
			Env:          svcConfig.Env,
			Port:         actualPort,
			PortEnv:      svcConfig.PortEnv,
			ReadyPattern: svcConfig.Ready,
		}

		proc.onOutput = func(line string, isErr bool) {
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

		proc.onExit = func(err error, intentional bool) {
			status := "stopped"
			if !intentional && err != nil {
				status = "crashed"
			}
			m.updateServiceState(projectName, serviceName, 0, actualPort, status)
			if status == "crashed" && restartPolicy == "on_failure" {
				time.Sleep(time.Second)
				if restartErr := proc.Start(); restartErr == nil {
					m.updateServiceState(projectName, serviceName, proc.PID(), actualPort, "running")
				}
			}
		}

		readyCh := make(chan struct{}, 1)
		proc.onReady = func() {
			select {
			case readyCh <- struct{}{}:
			default:
			}
		}

		if err := proc.Start(); err != nil {
			return rollback(fmt.Errorf("starting service %s: %w", serviceName, err))
		}
		started[serviceName] = proc
		m.mu.Lock()
		m.processes[projectName][serviceName] = proc
		m.mu.Unlock()
		m.updateServiceState(projectName, serviceName, proc.PID(), actualPort, "running")

		if svcConfig.Ready != "" {
			select {
			case <-readyCh:
			case <-time.After(30 * time.Second):
			}
		} else {
			time.Sleep(time.Second)
		}
	}

	m.setProjectRunning(projectName, projectPath, offset, exclusive)
	return nil
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

	for _, proc := range procs {
		_ = proc.Stop()
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

	_ = proc.Stop()
	m.clearRuntimePortSignal(projectName, serviceName)
	if err := proc.Start(); err != nil {
		m.updateServiceState(projectName, serviceName, 0, proc.Port, "crashed")
		return err
	}
	m.updateServiceState(projectName, serviceName, proc.PID(), proc.Port, "running")
	return nil
}

// Status returns current status of all running projects and services.
func (m *Manager) Status() map[string]map[string]ServiceInfo {
	m.mu.RLock()
	defer m.mu.RUnlock()

	result := make(map[string]map[string]ServiceInfo)
	for proj, procs := range m.processes {
		result[proj] = make(map[string]ServiceInfo)
		for name, proc := range procs {
			result[proj][name] = ServiceInfo{
				PID:     proc.PID(),
				Port:    proc.Port,
				Running: proc.IsRunning(),
				Ready:   proc.IsReady(),
			}
		}
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
			if proc.Port > 0 {
				result[proj][name] = proc.Port
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
	PID     int  `json:"pid"`
	Port    int  `json:"port"`
	Running bool `json:"running"`
	Ready   bool `json:"ready"`
}

var runtimePortPatterns = []*regexp.Regexp{
	regexp.MustCompile(`https?://[^\s:]+:(\d{2,5})`),
	regexp.MustCompile(`\b(?:localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\]|::1):(\d{2,5})\b`),
	regexp.MustCompile(`\bport(?:\s+is|\s*=|\s+)?\s*(\d{2,5})\b`),
}

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

func (m *Manager) resolveBasePort(project, service string, configured int) int {
	m.stateMu.Lock()
	defer m.stateMu.Unlock()
	if m.st == nil {
		return configured
	}
	if ps, ok := m.st.Projects[project]; ok {
		if ps.PortOverrides != nil {
			if override := ps.PortOverrides[service]; override > 0 {
				return override
			}
		}
	}
	return configured
}

func (m *Manager) setPortOverride(project, service string, basePort int) {
	if basePort <= 0 {
		return
	}
	_ = m.mutateState(func(st *state.State) {
		ps := st.Projects[project]
		if ps.PortOverrides == nil {
			ps.PortOverrides = make(map[string]int)
		}
		ps.PortOverrides[service] = basePort
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
	current := proc.Port
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
	if current == 0 {
		threshold = 1
	}
	if signal.count < threshold || current == detected {
		m.mu.Unlock()
		return
	}
	proc.Port = detected
	procPID := proc.PID()
	m.portSignals[key] = runtimePortSignal{
		port:      detected,
		count:     signal.count,
		lastSeen:  now,
		confirmed: true,
	}
	m.mu.Unlock()

	offset := m.ports.GetOffset(project)
	basePort := detected - offset
	if basePort <= 0 {
		basePort = detected
	}

	m.updateServiceState(project, service, procPID, detected, "running")
	m.setPortOverride(project, service, basePort)

	note := LogLine{
		Timestamp: time.Now(),
		Service:   service,
		Project:   project,
		Text:      fmt.Sprintf("[hun] detected runtime port %d (base %d, offset %d)", detected, basePort, offset),
		IsErr:     false,
	}
	m.logs.WriteLog(note)
	m.subscribers.Broadcast(note)
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

func runHook(cmd, dir string) error {
	parts := strings.Fields(cmd)
	if len(parts) == 0 {
		return nil
	}
	c := exec.Command(parts[0], parts[1:]...)
	c.Dir = dir
	return c.Run()
}
