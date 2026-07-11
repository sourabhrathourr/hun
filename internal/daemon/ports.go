package daemon

import (
	"fmt"
	"sync"

	"github.com/sourabhrathourr/hun/internal/config"
)

// PortManager selects ports independently for each service. Project offsets are
// retained only as compatibility metadata for persisted state and older clients.
type PortManager struct {
	offsets map[string]int // project → largest live service offset (metadata only)
	step    int
	mu      sync.Mutex
}

// NewPortManager creates a new port manager.
func NewPortManager() *PortManager {
	step := 1
	if g, err := config.LoadGlobal(); err == nil && g.Ports.DefaultOffset > 0 {
		step = g.Ports.DefaultOffset
	}
	return &PortManager{
		offsets: make(map[string]int),
		step:    step,
	}
}

// EnsureProject initializes compatibility metadata for a project. Port
// selection never depends on metadata assigned to other projects.
func (pm *PortManager) EnsureProject(project string) int {
	pm.mu.Lock()
	defer pm.mu.Unlock()

	if existing, ok := pm.offsets[project]; ok {
		return existing
	}
	pm.offsets[project] = 0
	return 0
}

// ReleaseOffset frees the offset for a project.
func (pm *PortManager) ReleaseOffset(project string) {
	pm.mu.Lock()
	defer pm.mu.Unlock()
	delete(pm.offsets, project)
}

// GetOffset returns the current offset for a project.
func (pm *PortManager) GetOffset(project string) int {
	pm.mu.Lock()
	defer pm.mu.Unlock()
	return pm.offsets[project]
}

// SetOffset force-sets an offset for recovery flows.
func (pm *PortManager) SetOffset(project string, offset int) {
	pm.mu.Lock()
	defer pm.mu.Unlock()
	pm.offsets[project] = offset
}

// RecordOffset updates compatibility metadata after a service port is selected.
func (pm *PortManager) RecordOffset(project string, offset int) {
	if offset < 0 {
		return
	}
	pm.mu.Lock()
	defer pm.mu.Unlock()
	if offset > pm.offsets[project] {
		pm.offsets[project] = offset
	}
}

// ReserveAvailablePort reserves the configured base port, or in multitask mode
// the first available port reached by the configured offset step.
func (pm *PortManager) ReserveAvailablePort(basePort int, allowFallback bool) (int, *portLease, error) {
	if basePort <= 0 {
		return 0, nil, nil
	}

	for candidate := basePort; candidate <= 65535; {
		lease, err := acquirePortLease(candidate)
		if err != nil {
			if allowFallback && isPortUnavailable(err) {
				next := candidate + pm.step
				if next <= candidate || next > 65535 {
					break
				}
				candidate = next
				continue
			}
			return 0, nil, err
		}
		if err := ensureTCPPortAvailable(candidate); err != nil {
			lease.release()
			if allowFallback && isPortUnavailable(err) {
				next := candidate + pm.step
				if next <= candidate || next > 65535 {
					break
				}
				candidate = next
				continue
			}
			return 0, nil, err
		}
		return candidate, lease, nil
	}

	return 0, nil, fmt.Errorf("no available port at or above configured port %d", basePort)
}

// ReserveExactPort reserves one specific port without searching for a fallback.
func (pm *PortManager) ReserveExactPort(port int) (int, *portLease, error) {
	return pm.ReserveAvailablePort(port, false)
}
