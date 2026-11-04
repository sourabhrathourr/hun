package daemon

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/sourabhrathourr/hun/internal/config"
)

func ottoProject() attributionProject {
	return attributionProject{
		Name: "otto",
		Path: "/w/otto",
		Config: &config.Project{Name: "otto", Services: map[string]*config.Service{
			"backend":  {Cmd: "if [ -f h.yml ]; then docker compose -f docker-compose.yml -f h.yml up --build backend; else docker compose up backend; fi", Port: 8000},
			"api":      {Cmd: "docker compose -f a.yml up --build gateway"},
			"db":       {Cmd: "make db", Port: 5432},
			"frontend": {Cmd: "npm run dev --prefix frontend", Port: 3000},
			"worker":   {Cmd: "python worker.py", Cwd: "worker"},
		}},
	}
}

func TestAttributeComposeContainers(t *testing.T) {
	obs := Observation{Containers: []ObservedContainer{
		{ID: "c1", Name: "otto-backend-1", WorkingDir: "/w/otto", Service: "backend", Ports: []int{8000}},
		{ID: "c2", Name: "otto-gateway-1", WorkingDir: "/w/otto", Service: "gateway"},
		{ID: "c3", Name: "otto-postgres-1", WorkingDir: "/w/otto", Service: "postgres", Ports: []int{5432}},
		{ID: "c4", Name: "other-web-1", WorkingDir: "/w/other", Service: "web", Ports: []int{9000}},
	}}
	attr := attribute(obs, []attributionProject{ottoProject()}, nil, nil)

	cases := map[string]string{"backend": "c1", "api": "c2", "db": "c3"}
	for service, id := range cases {
		ext, ok := attr.external("otto", service)
		if !ok || !ext.Docker || ext.Container.ID != id {
			t.Errorf("otto/%s = %+v (found %v), want container %s", service, ext, ok, id)
		}
	}
	if len(attr.Services) != 1 {
		t.Errorf("unexpected projects attributed: %+v", attr.Services)
	}
}

func TestAttributeNativeListenerByPortAndRoot(t *testing.T) {
	obs := Observation{
		Listeners: []ObservedListener{{PID: 100, Command: "node", Port: 3000}},
		Processes: map[int]ObservedProcess{
			100: {PID: 100, PPID: 90, PGID: 80, Command: "node", Cwd: "/w/otto/frontend"},
			90:  {PID: 90, PPID: 80, PGID: 80, Command: "npm", Cwd: "/w/otto"},
			80:  {PID: 80, PPID: 70, PGID: 80, Command: "-zsh", Cwd: "/w/otto"},
		},
	}
	attr := attribute(obs, []attributionProject{ottoProject()}, nil, nil)
	ext, ok := attr.external("otto", "frontend")
	if !ok || ext.Docker || ext.PID != 100 || ext.Port != 3000 {
		t.Fatalf("frontend = %+v (found %v)", ext, ok)
	}
	if ext.RootPID != 90 {
		t.Fatalf("root pid = %d, want npm (90), never the shell", ext.RootPID)
	}
	if holder := attr.Holders[3000]; holder.Project != "otto" || holder.Service != "frontend" {
		t.Fatalf("holder = %+v", holder)
	}
}

func TestAttributeNativeListenerByServiceDir(t *testing.T) {
	obs := Observation{
		Listeners: []ObservedListener{{PID: 5, Command: "python", Port: 7777}},
		Processes: map[int]ObservedProcess{5: {PID: 5, PPID: 1, Cwd: "/w/otto/worker/jobs"}},
	}
	attr := attribute(obs, []attributionProject{ottoProject()}, nil, nil)
	if ext, ok := attr.external("otto", "worker"); !ok || ext.Port != 7777 {
		t.Fatalf("worker = %+v (found %v)", ext, ok)
	}
}

func TestAttributeNestedProjectsPreferDeepest(t *testing.T) {
	mono := attributionProject{Name: "mono", Path: "/w/mono", Config: &config.Project{Services: map[string]*config.Service{
		"api": {Cmd: "go run .", Port: 4000},
	}}}
	site := attributionProject{Name: "site", Path: "/w/mono/apps/site", Config: &config.Project{Services: map[string]*config.Service{
		"web": {Cmd: "npm run dev", Port: 4000},
	}}}
	obs := Observation{
		Listeners: []ObservedListener{{PID: 9, Command: "node", Port: 4000}},
		Processes: map[int]ObservedProcess{9: {PID: 9, PPID: 1, Cwd: "/w/mono/apps/site"}},
	}
	attr := attribute(obs, []attributionProject{mono, site}, nil, nil)
	if _, ok := attr.external("site", "web"); !ok {
		t.Fatalf("expected site/web, got %+v", attr.Services)
	}
	if _, ok := attr.external("mono", "api"); ok {
		t.Fatal("listener in nested project attributed to parent project")
	}
}

func TestAttributeSkipsManagedAndCollectsUnmanaged(t *testing.T) {
	setUserHome(t, "/Users/me")
	obs := Observation{
		Listeners: []ObservedListener{
			{PID: 200, Command: "node", Port: 3000},
			{PID: 300, Command: "vite", Port: 5173},
			{PID: 300, Command: "vite", Port: 24678},
			{PID: 400, Command: "ControlCe", Port: 7000},
			{PID: 500, Command: "node", Port: 4255},
			{PID: 600, Command: "codex", Port: 4300},
			{PID: 700, Command: "node", Port: 64791},
		},
		Processes: map[int]ObservedProcess{
			200: {PID: 200, PPID: 1, PGID: 200, Cwd: "/w/otto/frontend"},
			300: {PID: 300, PPID: 1, PGID: 300, Cwd: "/w/scratch"},
			400: {PID: 400, PPID: 1, PGID: 400, Cwd: "/"},
			500: {PID: 500, PPID: 1, PGID: 500, Cwd: "/Users/someone/elsewhere"},
			600: {PID: 600, PPID: 1, PGID: 600, Cwd: "/w/otto"},
			700: {PID: 700, PPID: 1, PGID: 700, Cwd: "/w/scratch"},
		},
	}
	managed := map[int]managedRef{200: {Project: "otto", Service: "frontend"}}
	attr := attribute(obs, []attributionProject{ottoProject()}, managed, []string{"/w"})

	if _, ok := attr.external("otto", "frontend"); ok {
		t.Fatal("hun-managed listener reported as external")
	}
	if holder := attr.Holders[3000]; !holder.Managed || holder.Service != "frontend" {
		t.Fatalf("managed holder = %+v", holder)
	}
	want := []SnapshotProcess{{PID: 300, Command: "vite", Port: 5173, Ports: []int{5173, 24678}, Cwd: "/w/scratch"}}
	if !reflect.DeepEqual(attr.Unmanaged, want) {
		t.Fatalf("unmanaged = %+v, want %+v", attr.Unmanaged, want)
	}
	if holder := attr.Holders[7000]; holder.PID != 400 {
		t.Fatalf("system listener should still be a known holder, got %+v", holder)
	}
}

func TestApplyObservedServicesMarksExternalAndConflicts(t *testing.T) {
	proj := ottoProject()
	obs := Observation{
		Listeners: []ObservedListener{
			{PID: 10, Command: "node", Port: 3000},
			{PID: 20, Command: "python3", Port: 5432},
		},
		Processes: map[int]ObservedProcess{
			10: {PID: 10, PPID: 1, Cwd: "/w/otto/frontend"},
			20: {PID: 20, PPID: 1, Cwd: "/tmp/demo"},
		},
	}
	attr := attribute(obs, []attributionProject{proj}, nil, nil)
	services := servicesFromConfig(proj.Config)
	if !applyObservedServices("otto", proj.Config, services, attr, true) {
		t.Fatal("expected an external service")
	}
	byID := map[string]SnapshotService{}
	for _, svc := range services {
		byID[svc.ID] = svc
	}
	if svc := byID["frontend"]; svc.Origin != "external" || !svc.Running || svc.PID != 10 || svc.Runtime != "process" {
		t.Fatalf("frontend = %+v", svc)
	}
	if svc := byID["db"]; svc.Running || svc.Conflict == nil || svc.Conflict.PID != 20 {
		t.Fatalf("db = %+v, want conflict held by pid 20", svc)
	}
	if svc := byID["backend"]; svc.Running || svc.Conflict != nil {
		t.Fatalf("backend = %+v", svc)
	}
}

func TestServiceRootStopsAtAgents(t *testing.T) {
	obs := Observation{Processes: map[int]ObservedProcess{
		3: {PID: 3, PPID: 2, Command: "next-server", Cwd: "/w/app"},
		2: {PID: 2, PPID: 1, Command: "/Users/x/.local/bin/claude", Cwd: "/w/app"},
	}}
	if root := serviceRoot(obs, 3, "/w/app"); root != 3 {
		t.Fatalf("root = %d, want 3", root)
	}
}

func TestCommandStartsComposeService(t *testing.T) {
	cmd := ottoProject().Config.Services["backend"].Cmd
	if !commandStartsComposeService(cmd, "backend") {
		t.Fatal("expected backend match")
	}
	if commandStartsComposeService(cmd, "redis") {
		t.Fatal("unexpected redis match")
	}
	if commandStartsComposeService("npm run up backend", "backend") {
		t.Fatal("non-docker command matched")
	}
}

func TestParseObservationSources(t *testing.T) {
	listeners := parseLsofListeners("p40\ncnode\nf13\nn*:3000\nf14\nn[::1]:3000\np77\nccom.docker.backend\nf80\nn*:5432\n")
	want := []ObservedListener{{PID: 40, Command: "node", Port: 3000}, {PID: 77, Command: "com.docker.backend", Port: 5432}}
	if !reflect.DeepEqual(listeners, want) {
		t.Fatalf("listeners = %+v", listeners)
	}

	table := parsePSTable("  1     0     1 /sbin/launchd\n 812   1   812 /Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin)\n")
	if table[812].Command != "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin)" || table[812].PPID != 1 {
		t.Fatalf("ps table = %+v", table)
	}
	if !isProcessBoundary(table[812].Command) {
		t.Fatal("editor helper should be a boundary")
	}

	containers := parseDockerPS("abc\totto-backend-1\t0.0.0.0:8000->8000/tcp, [::]:8000->8000/tcp\totto\t/w/otto\tbackend\n")
	if len(containers) != 1 || !reflect.DeepEqual(containers[0].Ports, []int{8000}) || containers[0].Service != "backend" {
		t.Fatalf("containers = %+v", containers)
	}
}

func setUserHome(t *testing.T, home string) {
	t.Helper()
	previous := userHomeDir
	userHomeDir = func() (string, error) { return home, nil }
	t.Cleanup(func() { userHomeDir = previous })
}

// Servers started from any of the person's own folders show under "Running
// elsewhere", not just those in the project folders Hun scans; the home
// folder itself, ~/Library, hidden folders and other people's folders don't.
func TestAttributeShowsServersFromAnyUserFolder(t *testing.T) {
	setUserHome(t, "/Users/me")
	obs := Observation{
		Listeners: []ObservedListener{
			{PID: 100, Command: "node", Port: 4790},
			{PID: 200, Command: "node", Port: 4791},
			{PID: 300, Command: "node", Port: 4792},
			{PID: 400, Command: "node", Port: 4793},
			{PID: 500, Command: "node", Port: 4794},
			{PID: 600, Command: "python", Port: 4795},
		},
		Processes: map[int]ObservedProcess{
			100: {PID: 100, PPID: 1, PGID: 100, Cwd: "/Users/me/tools/reviewer"},
			200: {PID: 200, PPID: 1, PGID: 200, Cwd: "/Users/me"},
			300: {PID: 300, PPID: 1, PGID: 300, Cwd: "/Users/me/Library/Application Support/Some App"},
			400: {PID: 400, PPID: 1, PGID: 400, Cwd: "/Users/me/.ollama"},
			500: {PID: 500, PPID: 1, PGID: 500, Cwd: "/Users/someone/tools"},
			600: {PID: 600, PPID: 1, PGID: 600, Cwd: "/Users/me/Downloads/demo"},
		},
	}
	attr := attribute(obs, nil, nil, []string{"/Users/me/side-projects"})

	var got []int
	for _, entry := range attr.Unmanaged {
		got = append(got, entry.Port)
	}
	if want := []int{4790, 4795}; !reflect.DeepEqual(got, want) {
		t.Fatalf("unmanaged ports = %v, want %v", got, want)
	}
}

func TestInUserFolder(t *testing.T) {
	cases := map[string]bool{
		"/Users/me/tools/reviewer": true,
		"/Users/me/x":              true,
		"/Users/me":                false,
		"/Users/me/":               false,
		"/Users/me/Library/Caches": false,
		"/Users/me/.config/thing":  false,
		"/Users/meet/tools":        false,
		"/Users":                   false,
		"/":                        false,
		"":                         false,
	}
	for dir, want := range cases {
		if got := inUserFolder("/Users/me", dir); got != want {
			t.Errorf("inUserFolder(%q) = %v, want %v", dir, got, want)
		}
	}
	if inUserFolder("", "/Users/me/tools") {
		t.Error("no home should match nothing")
	}
}

// A server started from a terminal or an agent is a dev server wherever it
// runs, even in a hidden folder (an agent's worktree in ~/.codex) or /tmp;
// one an app started (from launchd) isn't.
func TestAttributeShowsServersStartedFromTerminalsAndAgents(t *testing.T) {
	setUserHome(t, "/Users/me")
	obs := Observation{
		Listeners: []ObservedListener{
			{PID: 100, Command: "node", Port: 5173},
			{PID: 200, Command: "python3", Port: 8000},
			{PID: 300, Command: "Helper", Port: 7265},
			{PID: 400, Command: "node", Port: 3001},
		},
		Processes: map[int]ObservedProcess{
			100: {PID: 100, PPID: 101, Cwd: "/Users/me/.codex/worktrees/a1b2/app"},
			101: {PID: 101, PPID: 102, Command: "/bin/zsh", Cwd: "/Users/me/.codex/worktrees/a1b2/app"},
			102: {PID: 102, PPID: 1, Command: "codex", Cwd: "/Users/me"},
			200: {PID: 200, PPID: 201, Cwd: "/private/tmp/demo"},
			201: {PID: 201, PPID: 1, Command: "-zsh", Cwd: "/private/tmp/demo"},
			300: {PID: 300, PPID: 1, Command: "Helper", Cwd: "/Users/me/.someapp"},
			400: {PID: 400, PPID: 401, Cwd: "/Users/me/.config/thing"},
			401: {PID: 401, PPID: 1, Command: "hun", Cwd: "/"},
		},
	}
	attr := attribute(obs, nil, nil, nil)

	var got []int
	for _, entry := range attr.Unmanaged {
		got = append(got, entry.Port)
	}
	if want := []int{5173, 8000}; !reflect.DeepEqual(got, want) {
		t.Fatalf("unmanaged ports = %v, want %v", got, want)
	}
}

// A server in an agent's worktree inside the project folder is that
// worktree's, not the project's: it must not show the project as running.
func TestAttributeKeepsNestedWorktreesApartFromTheirProject(t *testing.T) {
	setUserHome(t, "/Users/me")
	previous := isLinkedWorktree
	isLinkedWorktree = func(dir string) bool { return dir == "/w/otto/.claude/worktrees/ott-1" }
	t.Cleanup(func() { isLinkedWorktree = previous })

	obs := Observation{
		Listeners: []ObservedListener{{PID: 100, Command: "node", Port: 3000}},
		Processes: map[int]ObservedProcess{
			100: {PID: 100, PPID: 1, Cwd: "/w/otto/.claude/worktrees/ott-1/frontend"},
		},
	}
	attr := attribute(obs, []attributionProject{ottoProject()}, nil, []string{"/w"})

	if ext, ok := attr.external("otto", "frontend"); ok {
		t.Fatalf("worktree server attributed to otto: %+v", ext)
	}
	if holder := attr.Holders[3000]; holder.Project != "" {
		t.Fatalf("holder = %+v, want no project", holder)
	}
	if len(attr.Unmanaged) != 1 || attr.Unmanaged[0].Project != "" || attr.Unmanaged[0].Cwd != "/w/otto/.claude/worktrees/ott-1/frontend" {
		t.Fatalf("unmanaged = %+v, want the worktree server on its own", attr.Unmanaged)
	}
}

func TestDefaultIsLinkedWorktree(t *testing.T) {
	dir := t.TempDir()
	write := func(name, content string) string {
		path := filepath.Join(dir, name)
		if err := os.MkdirAll(path, 0o755); err != nil {
			t.Fatal(err)
		}
		if content != "" {
			if err := os.WriteFile(filepath.Join(path, ".git"), []byte(content), 0o644); err != nil {
				t.Fatal(err)
			}
		}
		return path
	}
	worktree := write("wt", "gitdir: /w/otto/.git/worktrees/ott-1\n")
	submodule := write("sub", "gitdir: ../.git/modules/sub\n")
	plain := write("plain", "")
	if !defaultIsLinkedWorktree(worktree) {
		t.Error("worktree not recognised")
	}
	if defaultIsLinkedWorktree(submodule) || defaultIsLinkedWorktree(plain) {
		t.Error("submodule or plain folder taken for a worktree")
	}
}

func TestWorktreeOf(t *testing.T) {
	root := t.TempDir()
	mk := func(rel string) string {
		path := filepath.Join(root, rel)
		if err := os.MkdirAll(path, 0o755); err != nil {
			t.Fatal(err)
		}
		return path
	}
	mk("otto/.git/worktrees/ott-1650")
	wt := mk("otto/.claude/worktrees/ott-1650/frontend")
	if err := os.WriteFile(filepath.Join(root, "otto/.claude/worktrees/ott-1650/.git"), []byte("gitdir: "+filepath.Join(root, "otto/.git/worktrees/ott-1650")+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	main := mk("otto/frontend")
	plain := mk("loose/app")

	if got := worktreeOf(wt); got == nil || *got != (WorktreeRef{Name: "ott-1650", Repo: "otto"}) {
		t.Fatalf("worktree = %+v, want ott-1650 of otto", got)
	}
	if got := worktreeOf(main); got != nil {
		t.Fatalf("main checkout reported as a worktree: %+v", got)
	}
	if got := worktreeOf(plain); got != nil {
		t.Fatalf("plain folder reported as a worktree: %+v", got)
	}
}
