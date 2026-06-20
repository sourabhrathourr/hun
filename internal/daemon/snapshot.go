package daemon

import (
	"fmt"
	"sort"
	"time"

	"github.com/sourabhrathourr/hun/internal/config"
	"github.com/sourabhrathourr/hun/internal/discovery"
	"github.com/sourabhrathourr/hun/internal/state"
)

const discoveryCacheTTL = 10 * time.Second

// Snapshot is the full daemon-backed model consumed by the macOS app.
type Snapshot struct {
	Protocol      int               `json:"protocol"`
	Mode          string            `json:"mode"`
	ActiveProject string            `json:"active_project,omitempty"`
	ScanDirs      []string          `json:"scan_dirs"`
	LastScanAt    time.Time         `json:"last_scan_at,omitempty"`
	Projects      []SnapshotProject `json:"projects"`
	Warnings      []string          `json:"warnings,omitempty"`
}

type SnapshotProject struct {
	ID          string            `json:"id"`
	Name        string            `json:"name"`
	Path        string            `json:"path"`
	IconPath    string            `json:"icon_path,omitempty"`
	IconCustom  bool              `json:"icon_custom,omitempty"`
	Status      string            `json:"status"`
	IsActive    bool              `json:"is_active"`
	Branch      string            `json:"branch,omitempty"`
	LastNote    string            `json:"last_note,omitempty"`
	StartedAt   string            `json:"started_at,omitempty"`
	Services    []SnapshotService `json:"services"`
	ConfigError string            `json:"config_error,omitempty"`
}

type SnapshotService struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Cmd     string `json:"cmd,omitempty"`
	PID     int    `json:"pid"`
	Port    int    `json:"port"`
	Status  string `json:"status"`
	Running bool   `json:"running"`
	Ready   bool   `json:"ready"`
}

func (m *Manager) Snapshot(forceDiscovery bool) (Snapshot, error) {
	result, err := m.ReconcileDiscovery(forceDiscovery)
	if err != nil {
		return Snapshot{}, err
	}

	st := m.StateSnapshot()
	status := m.Status()
	warnings := append([]string(nil), result.Warnings...)

	snapshot := Snapshot{
		Protocol:      CurrentProtocolVersion,
		Mode:          st.Mode,
		ActiveProject: st.ActiveProject,
		ScanDirs:      append([]string(nil), result.ScanDirs...),
		LastScanAt:    m.lastScanAt(),
		Warnings:      warnings,
	}
	if snapshot.Mode == "" {
		snapshot.Mode = "focus"
	}

	names := make([]string, 0, len(st.Registry))
	for name := range st.Registry {
		names = append(names, name)
	}
	sort.Strings(names)

	for _, name := range names {
		project := m.snapshotProject(name, st.Registry[name], st, status[name])
		snapshot.Projects = append(snapshot.Projects, project)
	}

	return snapshot, nil
}

func (m *Manager) ReconcileDiscovery(force bool) (discovery.Result, error) {
	now := time.Now()

	m.stateMu.Lock()
	if !force && !m.lastDiscoveryScan.IsZero() && now.Sub(m.lastDiscoveryScan) < discoveryCacheTTL {
		result := discovery.Result{
			ScanDirs: append([]string(nil), m.discoveryScanDirs...),
			Projects: make(map[string]string),
			Warnings: append([]string(nil), m.discoveryWarnings...),
		}
		m.stateMu.Unlock()
		return result, nil
	}

	onDisk, err := state.Load()
	if err == nil {
		for name, path := range onDisk.Registry {
			m.st.Registry[name] = path
		}
	}
	current := cloneRegistry(m.st.Registry)
	m.stateMu.Unlock()

	global, err := config.LoadGlobal()
	if err != nil {
		return discovery.Result{}, err
	}
	result, err := discovery.Scan(global, current)
	if err != nil {
		return result, err
	}

	removals := make([]string, 0)
	for name, path := range current {
		if path == "" || !config.ProjectExists(path) {
			removals = append(removals, name)
		}
	}
	sort.Strings(removals)

	for _, name := range removals {
		if m.IsRunning(name) {
			if err := m.StopProject(name); err != nil {
				result.Warnings = append(result.Warnings, fmt.Sprintf("stopping removed project %q: %v", name, err))
			}
		}
	}

	m.stateMu.Lock()
	dirty := false
	for _, name := range removals {
		delete(m.st.Registry, name)
		delete(m.st.Projects, name)
		if m.st.ActiveProject == name {
			m.st.ActiveProject = ""
		}
		dirty = true
	}

	names := make([]string, 0, len(result.Projects))
	for name := range result.Projects {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		path := result.Projects[name]
		currentPath, exists := m.st.Registry[name]
		if exists && currentPath != "" && config.ProjectExists(currentPath) {
			continue
		}
		m.st.Registry[name] = path
		dirty = true
	}

	if m.st.ActiveProject == "" {
		for name, ps := range m.st.Projects {
			if ps.Status == "running" {
				if _, ok := m.st.Registry[name]; ok {
					m.st.ActiveProject = name
					dirty = true
					break
				}
			}
		}
	}

	m.lastDiscoveryScan = now
	m.discoveryScanDirs = append([]string(nil), result.ScanDirs...)
	m.discoveryWarnings = append([]string(nil), result.Warnings...)
	if dirty {
		err = m.st.Save()
	}
	m.stateMu.Unlock()
	if err != nil {
		return result, err
	}
	return result, nil
}

func (m *Manager) lastScanAt() time.Time {
	m.stateMu.Lock()
	defer m.stateMu.Unlock()
	return m.lastDiscoveryScan
}

func (m *Manager) snapshotProject(name, path string, st *state.State, live map[string]ServiceInfo) SnapshotProject {
	projectState := st.Projects[name]
	project := SnapshotProject{
		ID:         name,
		Name:       name,
		Path:       path,
		IconPath:   m.projectIconPath(path, projectState.IconPath),
		IconCustom: projectState.IconPath != "",
		Status:     "stopped",
		IsActive:   st.ActiveProject == name,
		Branch:     projectState.GitBranch,
		LastNote:   projectState.LastNote,
		StartedAt:  projectState.StartedAt,
	}
	if projectState.Status != "" {
		project.Status = projectState.Status
	}

	proj, err := config.LoadProject(path)
	if err != nil {
		project.ConfigError = err.Error()
	} else {
		project.Name = proj.Name
		project.Services = servicesFromConfig(proj)
	}

	byID := make(map[string]int, len(project.Services))
	for i, service := range project.Services {
		byID[service.ID] = i
	}

	for serviceName, info := range live {
		svc := SnapshotService{
			ID:      serviceName,
			Name:    serviceName,
			PID:     info.PID,
			Port:    info.Port,
			Status:  normalizeServiceStatus(info),
			Running: info.Running,
			Ready:   info.Ready,
		}
		if idx, ok := byID[serviceName]; ok {
			svc.Cmd = project.Services[idx].Cmd
			project.Services[idx] = svc
		} else {
			project.Services = append(project.Services, svc)
		}
	}

	sort.Slice(project.Services, func(i, j int) bool {
		return project.Services[i].Name < project.Services[j].Name
	})

	if len(live) > 0 {
		project.Status = "running"
	}
	for _, service := range project.Services {
		if service.Status == "crashed" {
			project.Status = "crashed"
			break
		}
	}
	return project
}

func servicesFromConfig(proj *config.Project) []SnapshotService {
	names := make([]string, 0, len(proj.Services))
	for name := range proj.Services {
		names = append(names, name)
	}
	sort.Strings(names)

	services := make([]SnapshotService, 0, len(names))
	for _, name := range names {
		svc := proj.Services[name]
		item := SnapshotService{
			ID:     name,
			Name:   name,
			Status: "stopped",
		}
		if svc != nil {
			item.Cmd = svc.Cmd
			item.Port = svc.Port
		}
		services = append(services, item)
	}
	return services
}

func normalizeServiceStatus(info ServiceInfo) string {
	if info.Status != "" {
		return info.Status
	}
	if info.Running {
		return "running"
	}
	return "stopped"
}

func cloneRegistry(registry map[string]string) map[string]string {
	clone := make(map[string]string, len(registry))
	for name, path := range registry {
		clone[name] = path
	}
	return clone
}
