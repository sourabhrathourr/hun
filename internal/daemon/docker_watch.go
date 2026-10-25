package daemon

import "time"

var (
	dockerWatchInterval = 10 * time.Second
	// How many checks in a row Docker must miss before its services are
	// stopped, so one slow answer under load does not stop anything.
	dockerDownAfterChecks = 2
)

type dockerServiceRef struct {
	project string
	service string
	proc    *Process
}

// watchDocker stops services that run through Docker once the Docker daemon
// stops answering. Their `docker compose` client can outlive a crashed
// engine, which would otherwise leave them showing as running.
func (m *Manager) watchDocker(interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	misses := 0
	for range ticker.C {
		misses = m.checkDockerServices(misses)
	}
}

// checkDockerServices runs one check and returns how many checks in a row
// Docker has now missed. Docker is only asked while one of its services runs.
func (m *Manager) checkDockerServices(misses int) int {
	services := m.runningDockerServices()
	if len(services) == 0 {
		return 0
	}
	if checkDockerDaemonWithTimeout() == nil {
		return 0
	}
	misses++
	if misses < dockerDownAfterChecks {
		return misses
	}
	for _, ref := range services {
		m.stopForDockerDown(ref)
	}
	return 0
}

func (m *Manager) runningDockerServices() []dockerServiceRef {
	m.mu.RLock()
	defer m.mu.RUnlock()
	var refs []dockerServiceRef
	for project, procs := range m.processes {
		for service, proc := range procs {
			if proc.IsRunning() && commandNeedsDocker(proc.Cmd) {
				refs = append(refs, dockerServiceRef{project: project, service: service, proc: proc})
			}
		}
	}
	return refs
}

func (m *Manager) stopForDockerDown(ref dockerServiceRef) {
	m.emitInternalServiceLine(ref.project, ref.service, "[hun] Docker stopped responding, so this service was stopped. Start Docker, then restart it.", true)
	_ = ref.proc.Stop()
	m.mu.RLock()
	current := m.processes[ref.project][ref.service]
	m.mu.RUnlock()
	if current == ref.proc {
		m.updateServiceState(ref.project, ref.service, 0, ref.proc.ObservedPort(), "crashed")
	}
}
