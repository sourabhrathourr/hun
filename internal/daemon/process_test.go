package daemon

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestBuildServiceEnvironmentIncludesDeveloperToolPaths(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
	t.Setenv("PORT", "8888")
	t.Setenv("PNPM_HOME", "")
	t.Setenv("BUN_INSTALL", "")
	pnpmHome := filepath.Join(home, "Library", "pnpm")
	bunBin := filepath.Join(home, ".bun", "bin")
	nvmBin := filepath.Join(home, ".nvm", "versions", "node", "v24.14.0", "bin")
	for _, dir := range []string{pnpmHome, bunBin, nvmBin} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatalf("mkdir %s: %v", dir, err)
		}
	}

	env := buildServiceEnvironment(map[string]string{"CUSTOM": "1", "PORT": "9999"}, "PORT", 3000)
	path := envValue(env, "PATH")

	for _, want := range []string{pnpmHome, bunBin, nvmBin, "/usr/bin"} {
		if !pathContains(path, want) {
			t.Fatalf("PATH %q missing %q", path, want)
		}
	}
	if got := envValue(env, "PNPM_HOME"); got != pnpmHome {
		t.Fatalf("PNPM_HOME = %q, want %q", got, pnpmHome)
	}
	if got := envValue(env, "BUN_INSTALL"); got != filepath.Join(home, ".bun") {
		t.Fatalf("BUN_INSTALL = %q, want %q", got, filepath.Join(home, ".bun"))
	}
	if got := envValue(env, "CUSTOM"); got != "1" {
		t.Fatalf("CUSTOM = %q, want 1", got)
	}
	if got := envValue(env, "PORT"); got != "3000" {
		t.Fatalf("PORT = %q, want configured port 3000 to override inherited and service env", got)
	}
}

func TestBuildServiceEnvironmentAlwaysPublishesSelectedPort(t *testing.T) {
	t.Setenv("PORT", "8888")

	env := buildServiceEnvironment(map[string]string{
		"PORT":     "9999",
		"API_PORT": "7777",
	}, "API_PORT", 3001)

	if got := envValue(env, "PORT"); got != "3001" {
		t.Fatalf("PORT = %q, want selected port 3001", got)
	}
	if got := envValue(env, "API_PORT"); got != "3001" {
		t.Fatalf("API_PORT = %q, want selected port alias 3001", got)
	}
}

func TestProcessStartFindsCommandFromDeveloperPath(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
	toolDir := filepath.Join(home, "Library", "pnpm")
	if err := os.MkdirAll(toolDir, 0o755); err != nil {
		t.Fatalf("mkdir tool dir: %v", err)
	}
	toolPath := filepath.Join(toolDir, "pnpm")
	if err := os.WriteFile(toolPath, []byte("#!/bin/sh\necho tool-ok\n"), 0o755); err != nil {
		t.Fatalf("write tool: %v", err)
	}

	lines := make(chan string, 4)
	proc := &Process{
		Name: "web",
		Cmd:  "pnpm",
		Dir:  t.TempDir(),
	}
	proc.onOutput = func(line string, isErr bool) {
		lines <- line
	}

	if err := proc.Start(); err != nil {
		t.Fatalf("start process: %v", err)
	}
	defer proc.Stop()

	select {
	case line := <-lines:
		if line != "tool-ok" {
			t.Fatalf("output = %q, want tool-ok", line)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timeout waiting for process output")
	}
}

func TestProcessKeepsStdinOpenForInteractiveDevServers(t *testing.T) {
	proc := &Process{
		Name: "stdin-sensitive",
		Cmd:  "read line; echo unexpected-exit",
		Dir:  t.TempDir(),
	}

	if err := proc.Start(); err != nil {
		t.Fatalf("start process: %v", err)
	}
	defer proc.Stop()

	time.Sleep(150 * time.Millisecond)
	if !proc.IsRunning() {
		t.Fatal("expected process to keep running while waiting on stdin")
	}
}

func pathContains(path, dir string) bool {
	for _, part := range strings.Split(path, string(os.PathListSeparator)) {
		if part == dir {
			return true
		}
	}
	return false
}

func TestExpandPortRefs(t *testing.T) {
	ports := map[string]int{"backend": 8001, "db": 5433}
	portOf := func(service string) int { return ports[service] }
	got := expandPortRefs(map[string]string{
		"API_URL":   "http://localhost:${backend.port}/api",
		"DB":        "postgres://localhost:${db.port}/app?x=${db.port}",
		"SELF":      "http://localhost:${frontend.port}",
		"UNKNOWN":   "${nope.port}",
		"UNTOUCHED": "plain ${HOME}",
	}, "frontend", 3002, portOf)
	want := map[string]string{
		"API_URL":   "http://localhost:8001/api",
		"DB":        "postgres://localhost:5433/app?x=5433",
		"SELF":      "http://localhost:3002",
		"UNKNOWN":   "${nope.port}",
		"UNTOUCHED": "plain ${HOME}",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("expandPortRefs = %v, want %v", got, want)
	}
	if expandPortRefs(nil, "x", 1, portOf) != nil {
		t.Fatal("no env stays nil")
	}
}
