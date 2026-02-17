package detect

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestVoiceAIMonorepoDetectionUsesWorkspaceServices(t *testing.T) {
	dir := t.TempDir()

	mustWrite(t, filepath.Join(dir, "package.json"), `{
  "name": "voice-ai",
  "packageManager": "bun@1.2.0",
  "workspaces": ["apps/*"],
  "scripts": {
    "dev": "turbo run dev",
    "agent": "turbo run agent --filter=api"
  }
}`)
	mustWrite(t, filepath.Join(dir, "docker-compose.yml"), `services:
  mongodb:
    image: mongo:7
    ports:
      - "27017:27017"
`)
	mustWrite(t, filepath.Join(dir, "apps", "web", "package.json"), `{
  "name": "web",
  "scripts": {"dev": "vite"}
}`)
	mustWrite(t, filepath.Join(dir, "apps", "api", "package.json"), `{
  "name": "api",
  "scripts": {
    "dev": "uv run python run_server.py",
    "agent": "uv run python run_agent.py start"
  }
}`)
	mustWrite(t, filepath.Join(dir, "apps", "api", "config", "settings.py"), `API_PORT = int(os.getenv("API_PORT", "8000"))`)

	result := Run(dir, Options{Profile: ProfileHybrid})
	byName := toMap(result.Services)

	if _, ok := byName["voice-ai"]; ok {
		t.Fatalf("root orchestrator service should be suppressed when workspaces exist")
	}

	web, ok := byName["web"]
	if !ok {
		t.Fatalf("expected web service, got: %v", keys(byName))
	}
	if web.Cmd != "bun run dev" {
		t.Fatalf("web cmd = %q, want bun run dev", web.Cmd)
	}
	if web.Cwd != "./apps/web" {
		t.Fatalf("web cwd = %q, want ./apps/web", web.Cwd)
	}
	if web.Port != 5173 {
		t.Fatalf("web port = %d, want 5173", web.Port)
	}

	api, ok := byName["api"]
	if !ok {
		t.Fatalf("expected api service, got: %v", keys(byName))
	}
	if api.Port != 8000 {
		t.Fatalf("api port = %d, want 8000", api.Port)
	}

	if _, ok := byName["mongodb"]; !ok {
		t.Fatalf("expected mongodb compose service, got: %v", keys(byName))
	}
}

func TestProfileResolutionPrefersComposeOrLocalForConflicts(t *testing.T) {
	dir := t.TempDir()

	mustWrite(t, filepath.Join(dir, "package.json"), `{
  "name": "journal-app",
  "packageManager": "bun@1.2.0",
  "workspaces": ["apps/*"],
  "scripts": {
    "dev": "turbo run dev",
    "celery:worker": "cd apps/api && uv run celery -A celery_app worker --loglevel=info",
    "celery:beat": "cd apps/api && uv run celery -A celery_app beat --loglevel=info"
  }
}`)
	mustWrite(t, filepath.Join(dir, "apps", "web", "package.json"), `{
  "name": "web",
  "scripts": {"dev": "next dev"}
}`)
	mustWrite(t, filepath.Join(dir, "apps", "api", "package.json"), `{
  "name": "api",
  "scripts": {
    "dev": "uv run python run_server.py",
    "agent": "uv run python run_agent.py start"
  }
}`)
	mustWrite(t, filepath.Join(dir, "apps", "api", "config", "settings.py"), `API_PORT = int(os.getenv("API_PORT", "8000"))`)
	mustWrite(t, filepath.Join(dir, "docker-compose.yml"), `services:
  mongodb:
    image: mongo:7
    ports:
      - "127.0.0.1:27017:27017"
  api:
    image: my-api
    ports:
      - "8000:8000"
  agent:
    image: my-agent
  celery-worker:
    image: my-worker
  celery-beat:
    image: my-beat
`)

	local := toMap(Run(dir, Options{Profile: ProfileLocal}).Services)
	compose := toMap(Run(dir, Options{Profile: ProfileCompose}).Services)
	hybrid := toMap(Run(dir, Options{Profile: ProfileHybrid}).Services)

	if !strings.HasPrefix(local["api"].Cmd, "bun run") {
		t.Fatalf("local api should use local command, got %q", local["api"].Cmd)
	}
	if compose["api"].Cmd != "docker compose up api" {
		t.Fatalf("compose api should use compose command, got %q", compose["api"].Cmd)
	}
	if !strings.HasPrefix(hybrid["api"].Cmd, "bun run") {
		t.Fatalf("hybrid api should use local command, got %q", hybrid["api"].Cmd)
	}
	if hybrid["mongodb"].Cmd != "docker compose up mongodb" {
		t.Fatalf("hybrid mongodb should use compose command, got %q", hybrid["mongodb"].Cmd)
	}
}

func TestUnknownNodePortDoesNotDefaultTo3000(t *testing.T) {
	dir := t.TempDir()
	mustWrite(t, filepath.Join(dir, "package.json"), `{
  "name": "mystery",
  "scripts": {"dev": "node server.js"}
}`)

	result := Run(dir, Options{Profile: ProfileHybrid})
	if len(result.Services) != 1 {
		t.Fatalf("expected one service, got %d", len(result.Services))
	}
	if result.Services[0].Port != 0 {
		t.Fatalf("port = %d, want 0 for unknown script", result.Services[0].Port)
	}
}

func TestComposePortParsingHandlesIpHostContainer(t *testing.T) {
	dir := t.TempDir()
	mustWrite(t, filepath.Join(dir, "docker-compose.yml"), `services:
  rabbitmq:
    image: rabbitmq:3
    ports:
      - "127.0.0.1:15672:15672/tcp"
`)
	result := Run(dir, Options{Profile: ProfileHybrid})
	byName := toMap(result.Services)
	if byName["rabbitmq"].Port != 15672 {
		t.Fatalf("rabbitmq port = %d, want 15672", byName["rabbitmq"].Port)
	}
}

func mustWrite(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir %s: %v", path, err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}

func toMap(services []DetectedService) map[string]DetectedService {
	m := make(map[string]DetectedService, len(services))
	for _, svc := range services {
		m[svc.Name] = svc
	}
	return m
}

func keys(m map[string]DetectedService) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}
