package daemon

import (
	"sync"
)

// PortManager tracks port offsets for parallel running projects.
type PortManager struct {
	offsets map[string]int // project → offset
	mu      sync.Mutex
}

// NewPortManager creates a new port manager.
func NewPortManager() *PortManager {
	return &PortManager{
		offsets: make(map[string]int),
	}
}

// AssignOffset assigns the lowest available offset to a project.
// Offset 0 means base ports (exclusive mode).
func (pm *PortManager) AssignOffset(project string, exclusive bool) int {
	pm.mu.Lock()
	defer pm.mu.Unlock()

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
		offset++
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

// ApplyOffset returns the actual port given base port and project offset.
func (pm *PortManager) ApplyOffset(project string, basePort int) int {
	if basePort == 0 {
		return 0
	}
	return basePort + pm.GetOffset(project)
}
