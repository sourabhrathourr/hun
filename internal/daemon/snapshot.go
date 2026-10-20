package daemon

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
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
	LifecycleBusy bool              `json:"lifecycle_busy,omitempty"`
	// Unmanaged lists dev processes listening on ports that no registered
	// service accounts for.
	Unmanaged []SnapshotProcess `json:"unmanaged,omitempty"`
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
	// Profiles are the named service sets in .hun.yml, in file order.
	// Profile is the one Run uses: the last one run, empty for every service.
	Profiles []SnapshotProfile `json:"profiles,omitempty"`
	Profile  string            `json:"profile,omitempty"`
}

type SnapshotProfile struct {
	Name string `json:"name"`
	// Services are the ones the profile lists; Resolved adds what they
	// depend on, which is everything the profile runs.
	Services []string `json:"services"`
	Resolved []string `json:"resolved"`
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
	// Origin is "hun" when this daemon runs the service and "external" when
	// it was started elsewhere (a terminal, an agent, Docker Desktop).
	Origin    string `json:"origin,omitempty"`
	Runtime   string `json:"runtime,omitempty"` // "process" or "docker"
	Container string `json:"container,omitempty"`
	// Conflict names what holds the configured port of a stopped service.
	Conflict *PortHolder `json:"conflict,omitempty"`
}

func (m *Manager) Snapshot(forceDiscovery bool) (Snapshot, error) {
	result, err := m.ReconcileDiscovery(forceDiscovery)
	if err != nil {
		return Snapshot{}, err
	}

	return m.buildSnapshot(result, m.lastScanAt(), forceDiscovery), nil
}

// CachedSnapshot returns the last known registry without running discovery.
// It is safe to call while lifecycle recovery is in progress because it only
// reads state protected by the manager's own locks.
func (m *Manager) CachedSnapshot() Snapshot {
	m.stateMu.Lock()
	result := discovery.Result{
		ScanDirs: append([]string(nil), m.discoveryScanDirs...),
		Warnings: append([]string(nil), m.discoveryWarnings...),
	}
	lastScanAt := m.lastDiscoveryScan
	m.stateMu.Unlock()

	return m.buildSnapshot(result, lastScanAt, false)
}

// buildSnapshot assembles the dashboard model. Only a forced refresh waits
// for a fresh machine scan; regular polls use the last one so they return in
// milliseconds.
func (m *Manager) buildSnapshot(result discovery.Result, lastScanAt time.Time, freshObservation bool) Snapshot {
	st := m.StateSnapshot()
	status := m.Status()
	attr := m.staleAttribution()
	if freshObservation {
		attr = m.attribution(observationMaxAge)
	}

	snapshot := Snapshot{
		Protocol:      CurrentProtocolVersion,
		Mode:          st.Mode,
		ActiveProject: st.ActiveProject,
		ScanDirs:      append([]string(nil), result.ScanDirs...),
		LastScanAt:    lastScanAt,
		Warnings:      append([]string(nil), result.Warnings...),
		Unmanaged:     attr.Unmanaged,
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
		project := m.snapshotProject(name, st.Registry[name], st, status[name], attr)
		snapshot.Projects = append(snapshot.Projects, project)
	}

	return snapshot
}

func (m *Manager) ReconcileDiscovery(force bool) (discovery.Result, error) {
	now := time.Now()

	m.stateMu.Lock()
	if !force && !m.lastDiscoveryScan.IsZero() && now.Sub(m.lastDiscoveryScan) < discoveryCacheTTL {
		result := discovery.Result{
			ScanDirs: append([]string(nil), m.discoveryScanDirs...),
			Warnings: append([]string(nil), m.discoveryWarnings...),
		}
		m.stateMu.Unlock()
		return result, nil
	}
	current := cloneRegistry(m.st.Registry)
	m.stateMu.Unlock()

	global, err := config.LoadGlobal()
	if err != nil {
		return discovery.Result{}, err
	}
	result, err := discovery.Scan(global)
	if err != nil {
		return result, err
	}

	// Stop running projects whose folder was deleted before unregistering them.
	names := make([]string, 0, len(current))
	for name := range current {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		if config.ProjectFolderGone(current[name]) && m.IsRunning(name) {
			if err := m.StopProject(name); err != nil {
				result.Warnings = append(result.Warnings, fmt.Sprintf("stopping removed project %q: %v", name, err))
			}
		}
	}

	// Running projects keep their key until they stop. Collect them before
	// taking stateMu: Status() takes mu before stateMu.
	running := make(map[string]bool)
	m.mu.RLock()
	for name := range m.processes {
		running[name] = true
	}
	m.mu.RUnlock()

	m.stateMu.Lock()
	changes := discovery.Reconcile(m.st, result, func(key string) bool { return running[key] })
	m.lastDiscoveryScan = now
	m.discoveryScanDirs = append([]string(nil), result.ScanDirs...)
	m.discoveryWarnings = append([]string(nil), result.Warnings...)
	if changes.Dirty() {
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

func (m *Manager) snapshotProject(name, path string, st *state.State, live map[string]ServiceInfo, attr Attribution) SnapshotProject {
	projectState := st.Projects[name]
	// Read the branch live so it reflects local checkouts without needing a
	// restart; fall back to the last persisted value if the working tree
	// can't be read.
	branch := currentGitBranch(path)
	if branch == "" {
		branch = projectState.GitBranch
	}
	project := SnapshotProject{
		ID:         name,
		Name:       name,
		Path:       path,
		IconPath:   m.projectIconPath(path, projectState.IconPath),
		IconCustom: projectState.IconPath != "",
		Status:     "stopped",
		IsActive:   st.ActiveProject == name,
		Branch:     branch,
		LastNote:   projectState.LastNote,
		StartedAt:  projectState.StartedAt,
	}
	if projectState.Status != "" {
		project.Status = projectState.Status
	}

	proj, err := m.cachedProjectConfig(path)
	if err != nil {
		proj = nil
		project.ConfigError = err.Error()
		if !config.ProjectExists(path) {
			project.ConfigError = "No .hun.yml in this folder. It may be on another branch."
		}
	} else {
		project.Name = proj.Name
		project.Services = servicesFromConfig(proj)
		project.Profiles = profilesFromConfig(proj)
		if _, ok := proj.Profile(projectState.Profile); ok {
			project.Profile = projectState.Profile
		}
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
			Origin:  "hun",
		}
		if idx, ok := byID[serviceName]; ok {
			svc.Cmd = project.Services[idx].Cmd
			project.Services[idx] = svc
		} else {
			project.Services = append(project.Services, svc)
		}
	}

	// In Multitask a taken port isn't a problem: Hun starts the service on
	// the next free one. Only Focus needs the configured port.
	needsConfiguredPorts := st.Mode != "multitask"
	externalRunning := applyObservedServices(name, proj, project.Services, attr, needsConfiguredPorts)

	sort.Slice(project.Services, func(i, j int) bool {
		return project.Services[i].Name < project.Services[j].Name
	})

	if len(live) > 0 || externalRunning {
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

// applyObservedServices marks services running outside Hun and, when
// reportConflicts is set, records what holds the configured port of services
// that are not running. It reports whether any service runs externally.
func applyObservedServices(project string, proj *config.Project, services []SnapshotService, attr Attribution, reportConflicts bool) bool {
	externalRunning := false
	for i := range services {
		svc := &services[i]
		if svc.Running {
			continue
		}
		if ext, ok := attr.external(project, svc.ID); ok {
			svc.PID = ext.PID
			svc.Port = ext.Port
			svc.Status = "running"
			svc.Running = true
			svc.Ready = true
			svc.Origin = "external"
			svc.Runtime = "process"
			if ext.Docker {
				svc.Runtime = "docker"
				svc.Container = ext.Container.Name
			}
			externalRunning = true
			continue
		}
		if !reportConflicts || proj == nil || proj.Services[svc.ID] == nil {
			continue
		}
		port := proj.Services[svc.ID].Port
		if port <= 0 {
			continue
		}
		if holder, ok := attr.Holders[port]; ok && !holder.Managed && !(holder.Project == project && holder.Service == svc.ID) {
			conflict := holder
			svc.Conflict = &conflict
		}
	}
	return externalRunning
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

// currentGitBranch resolves the current branch by reading .git/HEAD directly.
// This avoids spawning git on every snapshot and handles linked worktrees
// (where .git is a file pointing at the real git dir). Returns "" if the
// branch can't be determined (e.g. not a repo) so the caller can fall back.
func currentGitBranch(path string) string {
	gitPath := filepath.Join(path, ".git")
	info, err := os.Stat(gitPath)
	if err != nil {
		return ""
	}

	headPath := filepath.Join(gitPath, "HEAD")
	if !info.IsDir() {
		data, err := os.ReadFile(gitPath)
		if err != nil {
			return ""
		}
		const prefix = "gitdir:"
		line := strings.TrimSpace(string(data))
		if !strings.HasPrefix(line, prefix) {
			return ""
		}
		gitDir := strings.TrimSpace(strings.TrimPrefix(line, prefix))
		if !filepath.IsAbs(gitDir) {
			gitDir = filepath.Join(path, gitDir)
		}
		headPath = filepath.Join(gitDir, "HEAD")
	}

	data, err := os.ReadFile(headPath)
	if err != nil {
		return ""
	}
	head := strings.TrimSpace(string(data))
	const refPrefix = "ref: refs/heads/"
	if strings.HasPrefix(head, refPrefix) {
		return strings.TrimPrefix(head, refPrefix)
	}
	// Detached HEAD: show a short commit hash.
	if len(head) >= 7 && !strings.Contains(head, " ") {
		return head[:7]
	}
	return ""
}

func cloneRegistry(registry map[string]string) map[string]string {
	clone := make(map[string]string, len(registry))
	for name, path := range registry {
		clone[name] = path
	}
	return clone
}

func profilesFromConfig(proj *config.Project) []SnapshotProfile {
	profiles := make([]SnapshotProfile, 0, len(proj.Profiles))
	for _, profile := range proj.Profiles {
		targets, _ := proj.ProfileTargets(profile.Name)
		resolved, _ := proj.ResolveProfile(profile.Name)
		profiles = append(profiles, SnapshotProfile{
			Name:     profile.Name,
			Services: targets,
			Resolved: resolved,
		})
	}
	return profiles
}

type projectConfigCacheEntry struct {
	modTime time.Time
	size    int64
	project *config.Project
	err     error
}

// cachedProjectConfig loads a project's .hun.yml for snapshots, which run
// every couple of seconds. The parsed config is reused until the file's
// modification time or size changes. Callers must not modify the result.
func (m *Manager) cachedProjectConfig(path string) (*config.Project, error) {
	info, statErr := os.Stat(filepath.Join(path, ".hun.yml"))
	if statErr != nil {
		return config.LoadProject(path)
	}
	m.configMu.Lock()
	entry, ok := m.configCache[path]
	m.configMu.Unlock()
	if ok && entry.modTime.Equal(info.ModTime()) && entry.size == info.Size() {
		return entry.project, entry.err
	}
	proj, err := config.LoadProject(path)
	m.configMu.Lock()
	if m.configCache == nil {
		m.configCache = make(map[string]projectConfigCacheEntry)
	}
	m.configCache[path] = projectConfigCacheEntry{modTime: info.ModTime(), size: info.Size(), project: proj, err: err}
	m.configMu.Unlock()
	return proj, err
}
