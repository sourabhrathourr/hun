package daemon

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"os/exec"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// Observation is a point-in-time view of what is running on the machine,
// independent of which tool started it.
type Observation struct {
	At         time.Time
	Listeners  []ObservedListener
	Processes  map[int]ObservedProcess
	Containers []ObservedContainer
}

// ObservedListener is one process listening on one TCP port.
type ObservedListener struct {
	PID     int
	Command string
	Port    int
}

// ObservedProcess is the process-table entry for a listener or one of its
// ancestors. Cwd is only populated for those processes.
type ObservedProcess struct {
	PID     int
	PPID    int
	PGID    int
	Command string
	Cwd     string
}

// ObservedContainer is a running Docker Compose container.
type ObservedContainer struct {
	ID             string
	Name           string
	ComposeProject string
	WorkingDir     string
	Service        string
	Ports          []int // published host ports
}

const (
	observationMaxAge    = 1500 * time.Millisecond
	observeDockerTimeout = 2 * time.Second
	maxAncestorDepth     = 12
)

var (
	listTCPListeners      = defaultListTCPListeners
	listProcessTable      = defaultListProcessTable
	lookupProcessCwds     = defaultLookupProcessCwds
	listComposeContainers = defaultListComposeContainers
)

type observer struct {
	mu         sync.Mutex // serializes scans so concurrent callers share one
	cacheM     sync.RWMutex
	last       Observation
	refreshing atomic.Bool
}

// getStale returns the last observation immediately and, when it is older
// than maxAge, rescans in the background so the next caller sees fresh data.
// It only blocks when nothing has been observed yet.
func (o *observer) getStale(maxAge time.Duration) Observation {
	last := o.cached()
	if last.At.IsZero() {
		return o.get(maxAge)
	}
	if time.Since(last.At) > maxAge && o.refreshing.CompareAndSwap(false, true) {
		go func() {
			defer o.refreshing.Store(false)
			o.get(maxAge)
		}()
	}
	return last
}

// get returns an observation no older than maxAge, scanning when needed.
func (o *observer) get(maxAge time.Duration) Observation {
	o.cacheM.RLock()
	last := o.last
	o.cacheM.RUnlock()
	if !last.At.IsZero() && time.Since(last.At) <= maxAge {
		return last
	}

	o.mu.Lock()
	defer o.mu.Unlock()
	o.cacheM.RLock()
	last = o.last
	o.cacheM.RUnlock()
	if !last.At.IsZero() && time.Since(last.At) <= maxAge {
		return last
	}

	obs := scanMachine()
	o.cacheM.Lock()
	o.last = obs
	o.cacheM.Unlock()
	return obs
}

// cached returns the last observation without scanning.
func (o *observer) cached() Observation {
	o.cacheM.RLock()
	defer o.cacheM.RUnlock()
	return o.last
}

func (o *observer) invalidate() {
	o.cacheM.Lock()
	o.last = Observation{}
	o.cacheM.Unlock()
}

// scanMachine collects listeners, their process ancestry and working
// directories, and compose containers. Every source degrades to empty on
// failure so a missing tool never breaks the snapshot.
func scanMachine() Observation {
	obs := Observation{At: time.Now(), Processes: make(map[int]ObservedProcess)}

	var wg sync.WaitGroup
	var listeners []ObservedListener
	var table map[int]ObservedProcess
	var containers []ObservedContainer
	wg.Add(3)
	go func() {
		defer wg.Done()
		listeners, _ = listTCPListeners()
	}()
	go func() {
		defer wg.Done()
		table, _ = listProcessTable()
	}()
	go func() {
		defer wg.Done()
		containers, _ = listComposeContainers()
	}()
	wg.Wait()

	obs.Listeners = listeners
	obs.Containers = containers

	// Keep listeners and their ancestors; those are the processes attribution
	// and stop-tree logic reason about.
	wanted := make(map[int]bool)
	for _, l := range listeners {
		pid := l.PID
		for depth := 0; pid > 1 && depth < maxAncestorDepth; depth++ {
			if wanted[pid] {
				break
			}
			wanted[pid] = true
			entry, ok := table[pid]
			if !ok {
				break
			}
			pid = entry.PPID
		}
	}
	for pid := range wanted {
		if entry, ok := table[pid]; ok {
			obs.Processes[pid] = entry
		} else {
			obs.Processes[pid] = ObservedProcess{PID: pid}
		}
	}
	for _, l := range listeners {
		entry := obs.Processes[l.PID]
		if entry.Command == "" {
			entry.Command = l.Command
			obs.Processes[l.PID] = entry
		}
	}

	pids := make([]int, 0, len(wanted))
	for pid := range wanted {
		pids = append(pids, pid)
	}
	if cwds, err := lookupProcessCwds(pids); err == nil {
		for pid, cwd := range cwds {
			entry := obs.Processes[pid]
			entry.Cwd = cwd
			obs.Processes[pid] = entry
		}
	}
	return obs
}

func defaultListTCPListeners() ([]ObservedListener, error) {
	lsof, err := lsofPath()
	if err != nil {
		return nil, err
	}
	output, err := exec.Command(lsof, "-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn").Output()
	if err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) && exitErr.ExitCode() == 1 {
			return nil, nil
		}
		return nil, fmt.Errorf("inspect listeners: %w", err)
	}
	return parseLsofListeners(string(output)), nil
}

// parseLsofListeners parses `lsof -F pcn` output into one entry per pid/port.
func parseLsofListeners(output string) []ObservedListener {
	var listeners []ObservedListener
	seen := make(map[[2]int]bool)
	pid := 0
	command := ""
	for _, line := range strings.Split(output, "\n") {
		if len(line) < 2 {
			continue
		}
		switch line[0] {
		case 'p':
			pid, _ = strconv.Atoi(line[1:])
			command = ""
		case 'c':
			command = line[1:]
		case 'n':
			port := parseLsofEndpointPort(line[1:])
			if pid <= 0 || port <= 0 {
				continue
			}
			key := [2]int{pid, port}
			if seen[key] {
				continue
			}
			seen[key] = true
			listeners = append(listeners, ObservedListener{PID: pid, Command: command, Port: port})
		}
	}
	sort.Slice(listeners, func(i, j int) bool {
		if listeners[i].Port != listeners[j].Port {
			return listeners[i].Port < listeners[j].Port
		}
		return listeners[i].PID < listeners[j].PID
	})
	return listeners
}

// parseLsofEndpointPort extracts the port from an lsof name like
// "*:3000", "127.0.0.1:8000" or "[::1]:5432".
func parseLsofEndpointPort(endpoint string) int {
	colon := strings.LastIndex(endpoint, ":")
	if colon < 0 {
		return 0
	}
	rawPort := endpoint[colon+1:]
	if end := strings.IndexFunc(rawPort, func(r rune) bool { return r < '0' || r > '9' }); end >= 0 {
		rawPort = rawPort[:end]
	}
	port, err := strconv.Atoi(rawPort)
	if err != nil || port <= 0 || port > 65535 {
		return 0
	}
	return port
}

func defaultListProcessTable() (map[int]ObservedProcess, error) {
	output, err := exec.Command("ps", "-axo", "pid=,ppid=,pgid=,comm=").Output()
	if err != nil {
		return nil, fmt.Errorf("list processes: %w", err)
	}
	return parsePSTable(string(output)), nil
}

func parsePSTable(output string) map[int]ObservedProcess {
	table := make(map[int]ObservedProcess)
	scanner := bufio.NewScanner(strings.NewReader(output))
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) < 4 {
			continue
		}
		pid, err1 := strconv.Atoi(fields[0])
		ppid, err2 := strconv.Atoi(fields[1])
		pgid, err3 := strconv.Atoi(fields[2])
		if err1 != nil || err2 != nil || err3 != nil {
			continue
		}
		table[pid] = ObservedProcess{
			PID:     pid,
			PPID:    ppid,
			PGID:    pgid,
			Command: strings.Join(fields[3:], " "),
		}
	}
	return table
}

func defaultLookupProcessCwds(pids []int) (map[int]string, error) {
	cwds := make(map[int]string)
	if len(pids) == 0 {
		return cwds, nil
	}
	lsof, err := lsofPath()
	if err != nil {
		return nil, err
	}
	list := make([]string, 0, len(pids))
	for _, pid := range pids {
		list = append(list, strconv.Itoa(pid))
	}
	output, err := exec.Command(lsof, "-a", "-p", strings.Join(list, ","), "-d", "cwd", "-F", "pn").Output()
	if err != nil {
		var exitErr *exec.ExitError
		if !errors.As(err, &exitErr) || len(output) == 0 {
			return cwds, nil
		}
	}
	pid := 0
	for _, line := range strings.Split(string(output), "\n") {
		if len(line) < 2 {
			continue
		}
		switch line[0] {
		case 'p':
			pid, _ = strconv.Atoi(line[1:])
		case 'n':
			if pid > 0 {
				cwds[pid] = line[1:]
			}
		}
	}
	return cwds, nil
}

var publishedPortPattern = regexp.MustCompile(`:(\d+)->`)

func defaultListComposeContainers() ([]ObservedContainer, error) {
	dockerPath, err := findDockerExecutable()
	if err != nil {
		return nil, nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), observeDockerTimeout)
	defer cancel()
	format := strings.Join([]string{
		"{{.ID}}",
		"{{.Names}}",
		"{{.Ports}}",
		`{{.Label "com.docker.compose.project"}}`,
		`{{.Label "com.docker.compose.project.working_dir"}}`,
		`{{.Label "com.docker.compose.service"}}`,
	}, "\t")
	cmd := exec.CommandContext(ctx, dockerPath, "ps", "--filter", "label=com.docker.compose.project", "--format", format)
	cmd.Env = withDeveloperEnvironment(cmd.Environ())
	output, err := cmd.Output()
	if err != nil {
		// Docker not running is the normal case; report nothing.
		return nil, nil
	}
	return parseDockerPS(string(output)), nil
}

func parseDockerPS(output string) []ObservedContainer {
	var containers []ObservedContainer
	for _, line := range strings.Split(output, "\n") {
		fields := strings.Split(line, "\t")
		if len(fields) < 6 || fields[0] == "" {
			continue
		}
		container := ObservedContainer{
			ID:             fields[0],
			Name:           fields[1],
			ComposeProject: fields[3],
			WorkingDir:     fields[4],
			Service:        fields[5],
		}
		seen := make(map[int]bool)
		for _, match := range publishedPortPattern.FindAllStringSubmatch(fields[2], -1) {
			port, err := strconv.Atoi(match[1])
			if err == nil && port > 0 && !seen[port] {
				seen[port] = true
				container.Ports = append(container.Ports, port)
			}
		}
		sort.Ints(container.Ports)
		containers = append(containers, container)
	}
	return containers
}
