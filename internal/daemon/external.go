package daemon

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"sync"
	"syscall"
	"time"

	"github.com/sourabhrathourr/hun/internal/config"
)

const (
	// freshObservationAge bounds how stale an observation may be when a
	// lifecycle action is about to act on it.
	freshObservationAge = 300 * time.Millisecond
	externalStopTimeout = 10 * time.Second
	portReleaseTimeout  = 10 * time.Second
	dockerStopTimeout   = 30 * time.Second
)

// errServiceRunningExternally marks a start request for a service that is
// already running outside Hun; callers treat it as success.
var errServiceRunningExternally = errors.New("service is already running outside hun")

var (
	stopDockerContainer = defaultStopDockerContainer
	waitForPortRelease  = defaultWaitForPortRelease
)

// attribution maps the machine's running processes and containers onto the
// registered projects, using an observation at most maxAge old.
func (m *Manager) attribution(maxAge time.Duration) Attribution {
	obs := m.observer.get(maxAge)
	return attribute(obs, m.attributionProjects(), m.managedRefs(), m.scanRoots())
}

// staleAttribution answers from the last observation and refreshes it in the
// background; the dashboard's frequent polls use it so they never wait on a
// machine scan.
func (m *Manager) staleAttribution() Attribution {
	return attribute(m.observer.getStale(observationMaxAge), m.attributionProjects(), m.managedRefs(), m.scanRoots())
}

func (m *Manager) attributionProjects() []attributionProject {
	st := m.StateSnapshot()
	names := make([]string, 0, len(st.Registry))
	for name := range st.Registry {
		names = append(names, name)
	}
	sort.Strings(names)

	projects := make([]attributionProject, 0, len(names))
	for _, name := range names {
		path := st.Registry[name]
		proj, err := config.LoadProject(path)
		if err != nil {
			continue
		}
		// Process working directories are reported with symlinks resolved
		// (/private/var vs /var), so compare against the resolved path.
		if resolved, err := filepath.EvalSymlinks(path); err == nil {
			path = resolved
		}
		projects = append(projects, attributionProject{Name: name, Path: path, Config: proj})
	}
	return projects
}

// managedRefs returns the process-group ids of every live Hun-started service.
func (m *Manager) managedRefs() map[int]managedRef {
	m.mu.RLock()
	defer m.mu.RUnlock()
	refs := make(map[int]managedRef)
	for project, procs := range m.processes {
		for service, proc := range procs {
			if pid := proc.PID(); pid > 0 && proc.IsRunning() {
				refs[pid] = managedRef{Project: project, Service: service}
			}
		}
	}
	return refs
}

func (m *Manager) scanRoots() []string {
	m.stateMu.Lock()
	defer m.stateMu.Unlock()
	roots := make([]string, 0, len(m.discoveryScanDirs))
	for _, dir := range m.discoveryScanDirs {
		if resolved, err := filepath.EvalSymlinks(dir); err == nil {
			dir = resolved
		}
		roots = append(roots, dir)
	}
	return roots
}

// stopExternal stops a service instance that this daemon did not start.
func (m *Manager) stopExternal(ext externalService) error {
	defer m.observer.invalidate()
	if ext.Docker {
		return stopDockerContainer(ext.Container.ID)
	}
	return stopProcessTree(ext.RootPID, ext.Port)
}

// stopProjectExternals stops external instances of project's services that
// are not also running under Hun. A non-nil only limits it to those services.
func (m *Manager) stopProjectExternals(project string, only map[string]bool) (int, error) {
	attr := m.attribution(freshObservationAge)
	var targets []externalService
	for service, ext := range attr.Services[project] {
		if only != nil && !only[service] {
			continue
		}
		if !m.IsServiceRunning(project, service) {
			targets = append(targets, ext)
		}
	}
	return len(targets), m.stopExternals(targets)
}

// stopExternalsExcept stops external services of every registered project
// other than keep. Focus mode uses it so the machine matches the focused
// project no matter who started the other projects' services.
func (m *Manager) stopExternalsExcept(keep string) error {
	attr := m.attribution(freshObservationAge)
	var targets []externalService
	for project, services := range attr.Services {
		if project == keep {
			continue
		}
		for service, ext := range services {
			if !m.IsServiceRunning(project, service) {
				targets = append(targets, ext)
			}
		}
	}
	return m.stopExternals(targets)
}

func (m *Manager) stopExternals(targets []externalService) error {
	var wg sync.WaitGroup
	errCh := make(chan error, len(targets))
	for _, ext := range targets {
		wg.Add(1)
		go func(ext externalService) {
			defer wg.Done()
			if err := m.stopExternal(ext); err != nil {
				errCh <- fmt.Errorf("stopping %s/%s: %w", ext.Project, ext.Service, err)
			}
		}(ext)
	}
	wg.Wait()
	close(errCh)
	for err := range errCh {
		return err
	}
	return nil
}

// FreePort stops whatever holds port so a service can use it. It refuses to
// stop processes that do not run from a folder (system services).
func (m *Manager) FreePort(port int) error {
	if port <= 0 {
		return errors.New("port required")
	}
	attr := m.attribution(freshObservationAge)
	holder, ok := attr.Holders[port]
	if !ok {
		if ensureTCPPortAvailable(port) == nil {
			return nil
		}
		return fmt.Errorf("couldn't identify what holds port %d", port)
	}

	var err error
	switch {
	case holder.Managed:
		err = m.StopService(holder.Project, holder.Service)
	case holder.Container != "":
		id := holder.Container
		for _, container := range attr.obs.Containers {
			if container.Name == holder.Container {
				id = container.ID
			}
		}
		err = stopDockerContainer(id)
	case holder.PID > 0:
		if holder.PID == os.Getpid() {
			return fmt.Errorf("port %d is held by the Hun daemon", port)
		}
		if holder.Cwd == "" || holder.Cwd == "/" {
			return fmt.Errorf("won't stop %s: it isn't running from a project folder", holder.Describe())
		}
		dir := holder.Cwd
		if holder.Project != "" {
			if path, ok := m.ProjectPath(holder.Project); ok {
				if resolved, rerr := filepath.EvalSymlinks(path); rerr == nil {
					path = resolved
				}
				dir = path
			}
		}
		err = stopProcessTree(serviceRoot(attr.obs, holder.PID, dir), port)
	default:
		return fmt.Errorf("couldn't identify what holds port %d", port)
	}
	m.observer.invalidate()
	if err != nil {
		return err
	}
	if !waitForPortRelease([]int{port}, portReleaseTimeout) {
		return fmt.Errorf("port %d is still in use after stopping %s", port, holder.Describe())
	}
	return nil
}

// waitForProjectPorts waits until each configured port of project is free or
// held by the project itself, e.g. after focus mode stopped other projects.
func (m *Manager) waitForProjectPorts(project string, proj *config.Project, timeout time.Duration) {
	if proj == nil {
		return
	}
	var ports []int
	for _, svc := range proj.Services {
		if svc != nil && svc.Port > 0 {
			ports = append(ports, svc.Port)
		}
	}
	deadline := time.Now().Add(timeout)
	for {
		pending := ports[:0:0]
		for _, port := range ports {
			if ensureTCPPortAvailable(port) != nil {
				pending = append(pending, port)
			}
		}
		if len(pending) == 0 {
			return
		}
		// Keep waiting only on holders that are going away: other projects
		// being stopped, or listeners already gone from the scan. Unrelated
		// processes won't let go, so the start reports them right away.
		attr := m.attribution(freshObservationAge)
		releasing := false
		for _, port := range pending {
			holder, ok := attr.Holders[port]
			if !ok || (holder.Project != "" && holder.Project != project) {
				releasing = true
				break
			}
		}
		if !releasing || time.Now().After(deadline) {
			return
		}
		time.Sleep(250 * time.Millisecond)
	}
}

// stopProcessTree stops root and all its descendants: SIGTERM, a grace
// period, then SIGKILL for anything left.
func stopProcessTree(root, port int) error {
	if root <= 1 || root == os.Getpid() {
		return fmt.Errorf("refusing to stop pid %d", root)
	}
	table, err := listProcessTable()
	if err != nil {
		table = nil
	}
	pids := processTree(table, root)
	for _, pid := range pids {
		_ = syscall.Kill(pid, syscall.SIGTERM)
	}
	if waitForPIDsExit(pids, externalStopTimeout) {
		return nil
	}
	for _, pid := range pids {
		_ = syscall.Kill(pid, syscall.SIGKILL)
	}
	if waitForPIDsExit(pids, 2*time.Second) {
		return nil
	}
	if port > 0 && ensureTCPPortAvailable(port) == nil {
		return nil
	}
	return fmt.Errorf("process %d did not exit", root)
}

// processTree returns root followed by all of its descendants.
func processTree(table map[int]ObservedProcess, root int) []int {
	children := make(map[int][]int)
	for pid, proc := range table {
		children[proc.PPID] = append(children[proc.PPID], pid)
	}
	pids := []int{root}
	seen := map[int]bool{root: true}
	for i := 0; i < len(pids); i++ {
		for _, child := range children[pids[i]] {
			if !seen[child] {
				seen[child] = true
				pids = append(pids, child)
			}
		}
	}
	return pids
}

func waitForPIDsExit(pids []int, timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for {
		alive := false
		for _, pid := range pids {
			if syscall.Kill(pid, 0) == nil {
				alive = true
				break
			}
		}
		if !alive {
			return true
		}
		if time.Now().After(deadline) {
			return false
		}
		time.Sleep(100 * time.Millisecond)
	}
}

func defaultWaitForPortRelease(ports []int, timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for {
		free := true
		for _, port := range ports {
			if ensureTCPPortAvailable(port) != nil {
				free = false
				break
			}
		}
		if free {
			return true
		}
		if time.Now().After(deadline) {
			return false
		}
		time.Sleep(200 * time.Millisecond)
	}
}

func defaultStopDockerContainer(id string) error {
	dockerPath, err := findDockerExecutable()
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), dockerStopTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, dockerPath, "stop", "--time", "10", id)
	cmd.Env = withDeveloperEnvironment(os.Environ())
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("docker stop %s: %v: %s", id, err, string(output))
	}
	return nil
}

// reserveServicePort reserves a service's configured port. When the port is
// taken in focus mode by a leftover instance of another registered project,
// that instance is stopped; any other holder is reported by identity.
func (m *Manager) reserveServicePort(project, service string, basePort int, allowFallback bool) (int, *portLease, error) {
	port, lease, err := m.ports.ReserveAvailablePort(basePort, allowFallback)
	if err == nil || basePort <= 0 || !isPortUnavailable(err) {
		return port, lease, err
	}
	attr := m.attribution(freshObservationAge)
	holder, ok := attr.Holders[basePort]
	if !ok {
		return port, lease, err
	}
	if !allowFallback && holder.Project != "" && holder.Project != project && !holder.Managed {
		if ext, found := attr.external(holder.Project, holder.Service); found {
			if stopErr := m.stopExternal(ext); stopErr == nil && waitForPortRelease([]int{basePort}, portReleaseTimeout) {
				return m.ports.ReserveAvailablePort(basePort, false)
			}
		}
	}
	return 0, nil, &PortConflictError{Project: project, Service: service, Holder: holder}
}
