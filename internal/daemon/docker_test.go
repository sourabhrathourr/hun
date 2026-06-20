package daemon

import (
	"context"
	"errors"
	"runtime"
	"strings"
	"testing"
	"time"
)

func TestCommandNeedsDocker(t *testing.T) {
	tests := []struct {
		name    string
		command string
		want    bool
	}{
		{name: "docker compose", command: "docker compose up postgres", want: true},
		{name: "docker compose legacy binary", command: "docker-compose up postgres", want: true},
		{name: "env prefixed docker", command: "DOCKER_BUILDKIT=1 docker build .", want: true},
		{name: "sudo docker", command: "sudo -E docker ps", want: true},
		{name: "after shell boundary", command: "cd infra && docker compose up db", want: true},
		{name: "argument only", command: "echo docker", want: false},
		{name: "make target", command: "make docker-up", want: false},
		{name: "plain local command", command: "npm run dev", want: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := commandNeedsDocker(tt.command); got != tt.want {
				t.Fatalf("commandNeedsDocker(%q) = %v, want %v", tt.command, got, tt.want)
			}
		})
	}
}

func TestEnsureDockerReadyForCommandIgnoresNonDockerCommands(t *testing.T) {
	restore := replaceDockerHooks(t)
	defer restore()

	checkDockerDaemon = func(context.Context) error {
		t.Fatal("non-Docker commands should not check Docker daemon")
		return nil
	}

	if err := ensureDockerReadyForCommand("echo docker", nil); err != nil {
		t.Fatalf("ensureDockerReadyForCommand returned error: %v", err)
	}
}

func TestEnsureDockerReadyForCommandOpensDockerDesktopOnMac(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("Docker Desktop auto-start is macOS-specific")
	}
	restore := replaceDockerHooks(t)
	defer restore()

	checks := 0
	checkDockerDaemon = func(context.Context) error {
		checks++
		if checks < 3 {
			return errors.New("daemon down")
		}
		return nil
	}

	launches := 0
	launchDockerApp = func() error {
		launches++
		return nil
	}
	sleepBeforeRecheck = func(time.Duration) {}
	dockerReadyTimeout = time.Second
	dockerReadyPollInterval = time.Millisecond

	var emitted []string
	err := ensureDockerReadyForCommand("docker compose up postgres", func(line string) {
		emitted = append(emitted, line)
	})
	if err != nil {
		t.Fatalf("ensureDockerReadyForCommand returned error: %v", err)
	}
	if checks != 3 {
		t.Fatalf("docker checks = %d, want 3", checks)
	}
	if launches != 1 {
		t.Fatalf("Docker launches = %d, want 1", launches)
	}
	if strings.Join(emitted, "\n") != "Docker daemon is not running; opening Docker Desktop...\nDocker daemon is ready." {
		t.Fatalf("emitted lines = %q", emitted)
	}
}

func replaceDockerHooks(t *testing.T) func() {
	t.Helper()
	oldCheck := checkDockerDaemon
	oldLaunch := launchDockerApp
	oldSleep := sleepBeforeRecheck
	oldTimeout := dockerReadyTimeout
	oldPoll := dockerReadyPollInterval

	return func() {
		checkDockerDaemon = oldCheck
		launchDockerApp = oldLaunch
		sleepBeforeRecheck = oldSleep
		dockerReadyTimeout = oldTimeout
		dockerReadyPollInterval = oldPoll
	}
}
