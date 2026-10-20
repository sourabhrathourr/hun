package config

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

const profilesYAML = `# otto dev services
name: otto
services:
  postgres:
    cmd: docker compose up postgres
  redis:
    cmd: docker compose up redis
  backend:
    cmd: uv run app
    depends_on: [postgres, redis]
  frontend:
    cmd: npm run dev
  worker:
    cmd: uv run worker
    depends_on: [redis]
profiles:
  web: [frontend]
  app: [frontend, backend]
  full: all
`

func writeProjectFile(t *testing.T, contents string) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, ".hun.yml"), []byte(contents), 0o644); err != nil {
		t.Fatal(err)
	}
	return dir
}

func TestProfilesKeepFileOrder(t *testing.T) {
	proj, err := LoadProject(writeProjectFile(t, profilesYAML))
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, profile := range proj.Profiles {
		names = append(names, profile.Name)
	}
	if want := []string{"web", "app", "full"}; !reflect.DeepEqual(names, want) {
		t.Fatalf("profiles = %v, want %v", names, want)
	}
	if full, _ := proj.Profile("full"); !full.All {
		t.Fatalf("full should run every service")
	}
}

func TestResolveProfileAddsDependencies(t *testing.T) {
	proj, err := LoadProject(writeProjectFile(t, profilesYAML))
	if err != nil {
		t.Fatal(err)
	}
	cases := map[string][]string{
		"web":  {"frontend"},
		"app":  {"backend", "frontend", "postgres", "redis"},
		"full": {"backend", "frontend", "postgres", "redis", "worker"},
		"all":  {"backend", "frontend", "postgres", "redis", "worker"},
		"":     {"backend", "frontend", "postgres", "redis", "worker"},
	}
	for name, want := range cases {
		got, err := proj.ResolveProfile(name)
		if err != nil {
			t.Fatalf("ResolveProfile(%q): %v", name, err)
		}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("ResolveProfile(%q) = %v, want %v", name, got, want)
		}
	}
	if _, err := proj.ResolveProfile("missing"); err == nil {
		t.Fatalf("expected an error for an unknown profile")
	}
}

func TestInvalidProfilesAreRejected(t *testing.T) {
	base := "name: demo\nservices:\n  web:\n    cmd: npm run dev\n"
	cases := map[string]string{
		"unknown service": "profiles:\n  ui: [api]\n",
		"reserved name":   "profiles:\n  all: [web]\n",
		"empty list":      "profiles:\n  ui: []\n",
		"bad scalar":      "profiles:\n  ui: everything\n",
	}
	for name, profiles := range cases {
		if _, err := LoadProject(writeProjectFile(t, base+profiles)); err == nil {
			t.Fatalf("%s: expected LoadProject to fail", name)
		}
	}
}

func TestSaveProfileKeepsCommentsAndOrder(t *testing.T) {
	dir := writeProjectFile(t, profilesYAML)
	if err := SaveProfile(dir, "voice", []string{"backend", "worker"}); err != nil {
		t.Fatal(err)
	}
	if err := SaveProfile(dir, "web", []string{"frontend", "worker"}); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(dir, ".hun.yml"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), "# otto dev services") {
		t.Fatalf("comment was lost:\n%s", data)
	}
	proj, err := LoadProject(dir)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, profile := range proj.Profiles {
		names = append(names, profile.Name)
	}
	if want := []string{"web", "app", "full", "voice"}; !reflect.DeepEqual(names, want) {
		t.Fatalf("profiles = %v, want %v", names, want)
	}
	if web, _ := proj.Profile("web"); !reflect.DeepEqual(web.Services, []string{"frontend", "worker"}) {
		t.Fatalf("web = %v, want it replaced", web.Services)
	}

	if err := SaveProfile(dir, "broken", []string{"nope"}); err == nil {
		t.Fatalf("expected saving an unknown service to fail")
	}
	if _, err := LoadProject(dir); err != nil {
		t.Fatalf("a rejected save must leave the file loadable: %v", err)
	}
}

func TestSaveProfileAddsSectionWhenMissing(t *testing.T) {
	dir := writeProjectFile(t, "name: demo\nservices:\n  web:\n    cmd: npm run dev\n")
	if err := SaveProfile(dir, "ui", []string{"web"}); err != nil {
		t.Fatal(err)
	}
	proj, err := LoadProject(dir)
	if err != nil {
		t.Fatal(err)
	}
	if ui, ok := proj.Profile("ui"); !ok || !reflect.DeepEqual(ui.Services, []string{"web"}) {
		t.Fatalf("ui = %+v, %v", ui, ok)
	}
}

func TestRemovingAServiceUpdatesProfiles(t *testing.T) {
	proj, err := LoadProject(writeProjectFile(t, profilesYAML))
	if err != nil {
		t.Fatal(err)
	}
	updated, err := ProjectWithoutService(proj, "frontend")
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := updated.Profile("web"); ok {
		t.Fatalf("web only had frontend and should be dropped")
	}
	if app, _ := updated.Profile("app"); !reflect.DeepEqual(app.Services, []string{"backend"}) {
		t.Fatalf("app = %v, want [backend]", app.Services)
	}
	if web, _ := proj.Profile("web"); !reflect.DeepEqual(web.Services, []string{"frontend"}) {
		t.Fatalf("the original project must be left alone, web = %v", web.Services)
	}
}
