package daemon

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/sourabhrathourr/hun/internal/config"
)

// PortHolder describes whatever is listening on a port, for conflict messages
// and the app's "Stop it & run" action.
type PortHolder struct {
	Port      int    `json:"port"`
	PID       int    `json:"pid,omitempty"`
	Command   string `json:"command,omitempty"`
	Cwd       string `json:"cwd,omitempty"`
	Project   string `json:"project,omitempty"`
	Service   string `json:"service,omitempty"`
	Container string `json:"container,omitempty"`
	Managed   bool   `json:"managed,omitempty"` // started by this Hun daemon
}

// Describe renders the holder for humans, e.g. "node (pid 1234) in ~/demo".
func (h PortHolder) Describe() string {
	owner := ""
	if h.Project != "" && h.Service != "" {
		owner = h.Project + "/" + h.Service
	}
	switch {
	case h.Container != "":
		if owner != "" {
			return fmt.Sprintf("Docker container %s (%s)", h.Container, owner)
		}
		return "Docker container " + h.Container
	case h.PID > 0:
		desc := fmt.Sprintf("%s (pid %d)", nonEmpty(h.Command, "a process"), h.PID)
		if owner != "" {
			desc = owner + ": " + desc
		}
		if h.Cwd != "" && h.Cwd != "/" {
			desc += " in " + abbreviateHome(h.Cwd)
		}
		return desc
	default:
		return "another process"
	}
}

// PortConflictError reports a configured port held by something other than
// the service being started.
type PortConflictError struct {
	Project string
	Service string
	Holder  PortHolder
}

func (e *PortConflictError) Error() string {
	return fmt.Sprintf("port %d is held by %s", e.Holder.Port, e.Holder.Describe())
}

func (e *PortConflictError) Unwrap() error { return errPortUnavailable }

// externalService is a running instance of a configured service that this
// daemon did not start.
type externalService struct {
	Project   string
	Service   string
	Port      int
	PID       int // listener pid; 0 for containers
	RootPID   int // top of the process tree that belongs to the service
	Command   string
	Cwd       string
	Container ObservedContainer
	Docker    bool
}

func (e externalService) holder() PortHolder {
	h := PortHolder{
		Port:    e.Port,
		PID:     e.PID,
		Command: e.Command,
		Cwd:     e.Cwd,
		Project: e.Project,
		Service: e.Service,
	}
	if e.Docker {
		h.Container = e.Container.Name
	}
	return h
}

// SnapshotProcess is a dev process listening on a port that no registered
// service accounts for.
type SnapshotProcess struct {
	PID     int    `json:"pid"`
	Command string `json:"command"`
	Port    int    `json:"port"`
	Ports   []int  `json:"ports,omitempty"`
	Cwd     string `json:"cwd"`
	Project string `json:"project,omitempty"`
	// Worktree names the git worktree it runs in, if it's a linked
	// worktree (an agent's, say), so the app can say whose it is.
	Worktree *WorktreeRef `json:"worktree,omitempty"`
}

// WorktreeRef is a linked git worktree: its folder's name and the name of
// the repository it belongs to.
type WorktreeRef struct {
	Name string `json:"name"`
	Repo string `json:"repo"`
}

type attributionProject struct {
	Name   string
	Path   string
	Config *config.Project
}

type managedRef struct {
	Project string
	Service string
}

// Attribution maps an observation onto registered projects.
type Attribution struct {
	Services  map[string]map[string]externalService // project → service
	Holders   map[int]PortHolder                    // port → holder, every listener
	Unmanaged []SnapshotProcess
	obs       Observation
}

func (a Attribution) external(project, service string) (externalService, bool) {
	ext, ok := a.Services[project][service]
	return ext, ok
}

// attribute assigns every listener and compose container to a registered
// project/service when it can. managed maps the process-group ids of
// Hun-started services so they are never reported as external.
func attribute(obs Observation, projects []attributionProject, managed map[int]managedRef, scanRoots []string) Attribution {
	attr := Attribution{
		Services: make(map[string]map[string]externalService),
		Holders:  make(map[int]PortHolder),
		obs:      obs,
	}
	home := resolvedHome()
	add := func(ext externalService) {
		if attr.Services[ext.Project] == nil {
			attr.Services[ext.Project] = make(map[string]externalService)
		}
		if existing, ok := attr.Services[ext.Project][ext.Service]; ok {
			// Prefer the instance on the configured port.
			if cfg := serviceConfig(projects, ext.Project, ext.Service); cfg != nil && existing.Port == cfg.Port {
				return
			}
		}
		attr.Services[ext.Project][ext.Service] = ext
	}

	// Compose containers: labels name the working directory and service.
	containerByPort := make(map[int]ObservedContainer)
	for _, container := range obs.Containers {
		for _, port := range container.Ports {
			containerByPort[port] = container
		}
		project := projectForPath(projects, container.WorkingDir)
		if project == nil || project.Config == nil {
			continue
		}
		service := composeServiceMatch(project.Config, container)
		if service == "" {
			continue
		}
		port := 0
		if cfg := project.Config.Services[service]; cfg != nil && cfg.Port > 0 && containsInt(container.Ports, cfg.Port) {
			port = cfg.Port
		} else if len(container.Ports) > 0 {
			port = container.Ports[0]
		}
		add(externalService{
			Project:   project.Name,
			Service:   service,
			Port:      port,
			Container: container,
			Docker:    true,
		})
	}

	type unmanagedKey struct{ pid int }
	unmanaged := make(map[unmanagedKey]*SnapshotProcess)
	self := os.Getpid()

	for _, listener := range obs.Listeners {
		proc := obs.Processes[listener.PID]
		if ref, ok := managedOwner(obs, listener.PID, managed); ok {
			attr.Holders[listener.Port] = PortHolder{
				Port:    listener.Port,
				PID:     listener.PID,
				Command: listener.Command,
				Cwd:     proc.Cwd,
				Project: ref.Project,
				Service: ref.Service,
				Managed: true,
			}
			continue
		}
		if listener.PID == self {
			continue
		}

		if container, ok := containerByPort[listener.Port]; ok {
			holder := PortHolder{Port: listener.Port, Container: container.Name}
			if project := projectForPath(projects, container.WorkingDir); project != nil && project.Config != nil {
				holder.Project = project.Name
				holder.Service = composeServiceMatch(project.Config, container)
			}
			attr.Holders[listener.Port] = holder
			continue
		}

		cwd := proc.Cwd
		project := projectForPath(projects, cwd)
		holder := PortHolder{Port: listener.Port, PID: listener.PID, Command: listener.Command, Cwd: cwd}
		if project != nil && project.Config != nil {
			holder.Project = project.Name
			if service := nativeServiceMatch(project, cwd, listener.Port); service != "" {
				holder.Service = service
				add(externalService{
					Project: project.Name,
					Service: service,
					Port:    listener.Port,
					PID:     listener.PID,
					RootPID: serviceRoot(obs, listener.PID, project.Path),
					Command: listener.Command,
					Cwd:     cwd,
				})
				attr.Holders[listener.Port] = holder
				continue
			}
		}
		attr.Holders[listener.Port] = holder

		if cwd == "" || cwd == "/" || listener.Port >= ephemeralPortStart || isProcessBoundary(listener.Command) {
			// System services, OS-assigned ports and the agents/editors
			// themselves are not dev servers.
			continue
		}
		// A dev server is one the person (or their agent) started: from a
		// terminal or an agent, wherever it runs; or, if that terminal has
		// gone, from one of their own folders.
		if project == nil && !startedByPerson(obs, listener.PID) && !underAnyRoot(scanRoots, cwd) && !inUserFolder(home, cwd) {
			continue
		}
		key := unmanagedKey{listener.PID}
		if entry, ok := unmanaged[key]; ok {
			entry.Ports = append(entry.Ports, listener.Port)
			continue
		}
		entry := &SnapshotProcess{
			PID:     listener.PID,
			Command: listener.Command,
			Port:    listener.Port,
			Ports:   []int{listener.Port},
			Cwd:     cwd,
		}
		if project != nil {
			entry.Project = project.Name
		}
		entry.Worktree = worktreeOf(cwd)
		unmanaged[key] = entry
	}

	for _, entry := range unmanaged {
		attr.Unmanaged = append(attr.Unmanaged, *entry)
	}
	sort.Slice(attr.Unmanaged, func(i, j int) bool {
		return attr.Unmanaged[i].Port < attr.Unmanaged[j].Port
	})
	return attr
}

// managedOwner reports whether pid belongs to a process group Hun started.
func managedOwner(obs Observation, pid int, managed map[int]managedRef) (managedRef, bool) {
	if len(managed) == 0 {
		return managedRef{}, false
	}
	if proc, ok := obs.Processes[pid]; ok {
		if ref, ok := managed[proc.PGID]; ok {
			return ref, true
		}
	}
	current := pid
	for depth := 0; current > 1 && depth < maxAncestorDepth; depth++ {
		if ref, ok := managed[current]; ok {
			return ref, true
		}
		proc, ok := obs.Processes[current]
		if !ok {
			break
		}
		current = proc.PPID
	}
	return managedRef{}, false
}

// composeServiceMatch maps a container to a Hun service by name, by the
// compose service named in the service command, or by published port.
func composeServiceMatch(proj *config.Project, container ObservedContainer) string {
	if container.Service == "" {
		return ""
	}
	if svc := proj.Services[container.Service]; svc != nil {
		return container.Service
	}
	names := sortedServiceNames(proj)
	for _, name := range names {
		if commandStartsComposeService(proj.Services[name].Cmd, container.Service) {
			return name
		}
	}
	for _, name := range names {
		if port := proj.Services[name].Port; port > 0 && containsInt(container.Ports, port) {
			return name
		}
	}
	return ""
}

// commandStartsComposeService reports whether cmd runs `docker compose ... up
// ... <service>` (or docker-compose).
func commandStartsComposeService(cmd, service string) bool {
	if !commandNeedsDocker(cmd) {
		return false
	}
	normalized := strings.NewReplacer(";", " ; ", "&&", " && ", "||", " || ").Replace(cmd)
	afterUp := false
	for _, token := range strings.Fields(normalized) {
		switch token {
		case ";", "&&", "||", "fi", "then", "else":
			afterUp = false
			continue
		case "up":
			afterUp = true
			continue
		}
		if afterUp && strings.Trim(token, `"'`) == service {
			return true
		}
	}
	return false
}

// nativeServiceMatch maps a listener to a service by configured port, or by
// the single service whose directory most specifically contains cwd.
func nativeServiceMatch(project *attributionProject, cwd string, port int) string {
	names := sortedServiceNames(project.Config)
	for _, name := range names {
		if svc := project.Config.Services[name]; svc.Port > 0 && svc.Port == port {
			return name
		}
	}

	best := ""
	bestLen := -1
	ambiguous := false
	for _, name := range names {
		svc := project.Config.Services[name]
		if svc.Port > 0 || commandNeedsDocker(svc.Cmd) {
			// A service with a known port would have matched above.
			continue
		}
		dir := project.Path
		if svc.Cwd != "" {
			dir = filepath.Join(project.Path, svc.Cwd)
		}
		if !pathWithin(dir, cwd) {
			continue
		}
		switch {
		case len(dir) > bestLen:
			best, bestLen, ambiguous = name, len(dir), false
		case len(dir) == bestLen:
			ambiguous = true
		}
	}
	if ambiguous {
		return ""
	}
	return best
}

// serviceRoot climbs from pid to the top of the process tree that belongs to
// the service: ancestors that still run inside dir, stopping before shells,
// terminals and agents so stopping a service never takes those down.
func serviceRoot(obs Observation, pid int, dir string) int {
	root := pid
	current := pid
	for depth := 0; depth < maxAncestorDepth; depth++ {
		proc, ok := obs.Processes[current]
		if !ok || proc.PPID <= 1 {
			break
		}
		parent, ok := obs.Processes[proc.PPID]
		if !ok || isProcessBoundary(parent.Command) || !pathWithin(dir, parent.Cwd) {
			break
		}
		root = parent.PID
		current = parent.PID
	}
	return root
}

// ephemeralPortStart is where macOS hands out OS-assigned ports.
const ephemeralPortStart = 49152

var boundaryCommands = map[string]bool{
	"zsh": true, "bash": true, "fish": true, "login": true, "tmux": true, "screen": true,
	"launchd": true, "claude": true, "codex": true, "cursor": true, "code": true,
	"terminal": true, "iterm2": true, "ghostty": true, "wezterm-gui": true, "alacritty": true,
	"kitty": true, "warp": true, "cmux": true, "hun": true,
}

func isProcessBoundary(command string) bool {
	name := strings.ToLower(filepath.Base(strings.TrimPrefix(command, "-")))
	if boundaryCommands[name] {
		return true
	}
	return strings.HasPrefix(name, "code helper") || strings.HasPrefix(name, "cursor helper")
}

func projectForPath(projects []attributionProject, path string) *attributionProject {
	if path == "" {
		return nil
	}
	var best *attributionProject
	for i := range projects {
		project := &projects[i]
		if project.Path == "" || !pathWithin(project.Path, path) || inNestedWorktree(project.Path, path) {
			continue
		}
		if best == nil || len(project.Path) > len(best.Path) {
			best = project
		}
	}
	return best
}

func serviceConfig(projects []attributionProject, project, service string) *config.Service {
	for _, p := range projects {
		if p.Name == project && p.Config != nil {
			return p.Config.Services[service]
		}
	}
	return nil
}

// startedByPerson reports whether pid was started from a terminal or by an
// agent: a shell, terminal, multiplexer, agent or editor among its
// ancestors. Apps and system services descend from launchd alone.
func startedByPerson(obs Observation, pid int) bool {
	current := pid
	for depth := 0; current > 1 && depth < maxAncestorDepth; depth++ {
		proc, ok := obs.Processes[current]
		if !ok || proc.PPID <= 1 {
			return false
		}
		parent, ok := obs.Processes[proc.PPID]
		if !ok {
			return false
		}
		name := strings.ToLower(filepath.Base(strings.TrimPrefix(parent.Command, "-")))
		if name != "launchd" && name != "hun" && isProcessBoundary(parent.Command) {
			return true
		}
		current = parent.PID
	}
	return false
}

// userHomeDir is swapped in tests.
var userHomeDir = os.UserHomeDir

// resolvedHome is the home folder with symlinks resolved, as process
// working directories are reported; empty if unknown.
func resolvedHome() string {
	home, err := userHomeDir()
	if err != nil || home == "" {
		return ""
	}
	if resolved, err := filepath.EvalSymlinks(home); err == nil {
		home = resolved
	}
	return filepath.Clean(home)
}

// inUserFolder reports whether dir is one of the person's own folders,
// where a server they started from a terminal or an agent runs: inside
// their home folder, but not the home folder itself, ~/Library (apps' own
// helpers) or a hidden folder.
func inUserFolder(home, dir string) bool {
	if home == "" || dir == "" {
		return false
	}
	rel, err := filepath.Rel(home, filepath.Clean(dir))
	if err != nil || rel == "." || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return false
	}
	first := strings.SplitN(rel, string(filepath.Separator), 2)[0]
	return first != "Library" && !strings.HasPrefix(first, ".")
}

// isLinkedWorktree and gitdirOf are swapped in tests.
var (
	isLinkedWorktree = defaultIsLinkedWorktree
	gitdirOf         = defaultGitdirOf
)

// worktreeOf finds the linked git worktree dir is in, if any: the nearest
// folder up from dir with a .git, if that .git points into a repository's
// worktrees.
func worktreeOf(dir string) *WorktreeRef {
	for current, depth := filepath.Clean(dir), 0; depth < 32; current, depth = filepath.Dir(current), depth+1 {
		gitdir, isFile, found := gitdirOf(current)
		if found {
			if !isFile {
				return nil
			}
			slashed := filepath.ToSlash(gitdir)
			at := strings.LastIndex(slashed, "/.git/worktrees/")
			if at <= 0 {
				return nil
			}
			return &WorktreeRef{Name: filepath.Base(current), Repo: filepath.Base(filepath.FromSlash(slashed[:at]))}
		}
		if current == filepath.Dir(current) {
			return nil
		}
	}
	return nil
}

// defaultGitdirOf reports whether dir has a .git, and if it's a file (a
// linked worktree or a submodule), where it points.
func defaultGitdirOf(dir string) (gitdir string, isFile, found bool) {
	path := filepath.Join(dir, ".git")
	info, err := os.Stat(path)
	if err != nil {
		return "", false, false
	}
	if info.IsDir() {
		return "", false, true
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return "", true, true
	}
	return strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(string(data)), "gitdir:")), true, true
}

// inNestedWorktree reports whether path is inside a separate git worktree
// within the project folder, such as an agent's worktree in
// .claude/worktrees: a different checkout, so not the project itself.
func inNestedWorktree(projectPath, path string) bool {
	projectPath = filepath.Clean(projectPath)
	for dir := filepath.Clean(path); dir != projectPath && pathWithin(projectPath, dir); dir = filepath.Dir(dir) {
		if isLinkedWorktree(dir) {
			return true
		}
	}
	return false
}

// defaultIsLinkedWorktree reports whether dir is the top of a linked git
// worktree: its .git is a file pointing into a repository's worktrees
// (a submodule's points into modules, and stays part of its project).
func defaultIsLinkedWorktree(dir string) bool {
	data, err := os.ReadFile(filepath.Join(dir, ".git"))
	if err != nil {
		return false
	}
	line := strings.TrimSpace(string(data))
	return strings.HasPrefix(line, "gitdir:") && strings.Contains(filepath.ToSlash(line), "/worktrees/")
}

func underAnyRoot(roots []string, path string) bool {
	for _, root := range roots {
		if root != "" && pathWithin(root, path) {
			return true
		}
	}
	return false
}

// pathWithin reports whether path equals dir or is nested inside it.
func pathWithin(dir, path string) bool {
	if dir == "" || path == "" {
		return false
	}
	dir = filepath.Clean(dir)
	path = filepath.Clean(path)
	return path == dir || strings.HasPrefix(path, dir+string(filepath.Separator))
}

func sortedServiceNames(proj *config.Project) []string {
	names := make([]string, 0, len(proj.Services))
	for name, svc := range proj.Services {
		if svc != nil {
			names = append(names, name)
		}
	}
	sort.Strings(names)
	return names
}

func containsInt(values []int, value int) bool {
	for _, v := range values {
		if v == value {
			return true
		}
	}
	return false
}

func abbreviateHome(path string) string {
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return path
	}
	if pathWithin(home, path) {
		return "~" + strings.TrimPrefix(path, home)
	}
	return path
}

func nonEmpty(value, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}
