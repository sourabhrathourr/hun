package daemon

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/hun-sh/hun/internal/config"
	"github.com/hun-sh/hun/internal/state"
)

// Manager orchestrates processes for all running projects.
type Manager struct {
	processes    map[string]map[string]*Process // project → service → process
	logs         *LogManager
	subscribers  *SubscriberManager
	ports        *PortManager
	mu           sync.RWMutex
}

// NewManager creates a new process manager.
func NewManager() (*Manager, error) {
	logMgr, err := NewLogManager()
	if err != nil {
		return nil, err
	}
	return &Manager{
		processes:   make(map[string]map[string]*Process),
		logs:        logMgr,
		subscribers: NewSubscriberManager(),
		ports:       NewPortManager(),
	}, nil
}

// StartProject starts all services for a project.
func (m *Manager) StartProject(projectName string, projConfig *config.Project, projectPath string, exclusive bool) error {
	m.mu.Lock()
	if _, exists := m.processes[projectName]; exists {
		m.mu.Unlock()
		return fmt.Errorf("project %s already running", projectName)
	}
	m.processes[projectName] = make(map[string]*Process)
	m.mu.Unlock()

	// Run pre_start hook
	if projConfig.Hooks.PreStart != "" {
		if err := runHook(projConfig.Hooks.PreStart, projectPath); err != nil {
			return fmt.Errorf("pre_start hook failed: %w", err)
		}
	}

	// Assign port offset
	offset := m.ports.AssignOffset(projectName, exclusive)

	// Topological sort for dependency ordering
	order, err := topoSort(projConfig)
	if err != nil {
		return err
	}

	// Start services in order
	for _, svcName := range order {
		svcConfig := projConfig.Services[svcName]
		actualPort := svcConfig.Port + offset

		dir := projectPath
		if svcConfig.Cwd != "" {
			dir = filepath.Join(projectPath, svcConfig.Cwd)
		}

		proc := &Process{
			Name:         svcName,
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
				Service:   svcName,
				Project:   projectName,
				Text:      line,
				IsErr:     isErr,
			}
			m.logs.WriteLog(logLine)
			m.subscribers.Broadcast(logLine)
		}

		proc.onExit = func(err error) {
			status := "stopped"
			if err != nil {
				status = "crashed"
			}
			m.updateServiceState(projectName, svcName, 0, actualPort, status)

			// Auto-restart on failure if configured
			if status == "crashed" && svcConfig.Restart == "on_failure" {
				time.Sleep(time.Second)
				proc.Start()
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
			return fmt.Errorf("starting service %s: %w", svcName, err)
		}

		m.mu.Lock()
		m.processes[projectName][svcName] = proc
		m.mu.Unlock()

		m.updateServiceState(projectName, svcName, proc.PID(), actualPort, "running")

		// Wait for ready if pattern defined
		if svcConfig.Ready != "" {
			select {
			case <-readyCh:
			case <-time.After(30 * time.Second):
				// Warn but continue
			}
		} else {
			// No ready pattern: wait 1 second
			time.Sleep(time.Second)
		}
	}

	// Update project state
	st, err := state.Load()
	if err == nil {
		ps := st.Projects[projectName]
		ps.Status = "running"
		ps.Offset = offset
		ps.Path = projectPath
		ps.StartedAt = time.Now().UTC().Format(time.RFC3339)
		st.Projects[projectName] = ps
		st.Save()
	}

	return nil
}

// StopProject stops all services for a project.
func (m *Manager) StopProject(projectName string) error {
	m.mu.RLock()
	procs, exists := m.processes[projectName]
	if !exists {
		m.mu.RUnlock()
		return fmt.Errorf("project %s not running", projectName)
	}
	m.mu.RUnlock()

	// Stop in reverse dependency order
	for _, proc := range procs {
		proc.Stop()
	}

	// Run post_stop hook
	st, _ := state.Load()
	if st != nil {
		if path, ok := st.Registry[projectName]; ok {
			proj, err := config.LoadProject(path)
			if err == nil && proj.Hooks.PostStop != "" {
				runHook(proj.Hooks.PostStop, path)
			}
		}
	}

	m.ports.ReleaseOffset(projectName)

	m.mu.Lock()
	delete(m.processes, projectName)
	m.mu.Unlock()

	// Update state
	if st != nil {
		ps := st.Projects[projectName]
		ps.Status = "stopped"
		ps.Services = nil
		st.Projects[projectName] = ps
		st.Save()
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
		m.StopProject(name)
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

	proc.Stop()
	return proc.Start()
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

// Shutdown performs graceful shutdown of all processes.
func (m *Manager) Shutdown() {
	m.StopAll()
	m.logs.Close()
}

// ServiceInfo holds info about a running service.
type ServiceInfo struct {
	PID     int  `json:"pid"`
	Port    int  `json:"port"`
	Running bool `json:"running"`
	Ready   bool `json:"ready"`
}

func (m *Manager) updateServiceState(project, service string, pid, port int, status string) {
	st, err := state.Load()
	if err != nil {
		return
	}
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
	st.Save()
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
