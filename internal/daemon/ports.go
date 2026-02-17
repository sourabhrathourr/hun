package daemon

import (
	"sync"

	"github.com/sourabhrathourr/hun/internal/config"
)

// PortManager tracks port offsets for parallel running projects.
type PortManager struct {
	offsets map[string]int // project → offset
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

// AssignOffset assigns the lowest available offset to a project.
// Offset 0 means base ports (exclusive mode).
func (pm *PortManager) AssignOffset(project string, exclusive bool) int {
	pm.mu.Lock()
	defer pm.mu.Unlock()

	if existing, ok := pm.offsets[project]; ok {
		return existing
	}

	if exclusive {
		pm.offsets[project] = 0
		return 0
	}

	// Find lowest available offset
	used := make(map[int]bool)
	for _, offset := range pm.offsets {
		used[offset] = true
	}

	offset := 0
	for used[offset] {
		offset += pm.step
	}

	pm.offsets[project] = offset
	return offset
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

// ApplyOffset returns the actual port given base port and project offset.
func (pm *PortManager) ApplyOffset(project string, basePort int) int {
	if basePort == 0 {
		return 0
	}
	return basePort + pm.GetOffset(project)
}
