package daemon

import (
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
	if !applyObservedServices("otto", proj.Config, services, attr) {
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
