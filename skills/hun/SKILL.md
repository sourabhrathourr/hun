---
name: hun
description: Use when starting, stopping, restarting, or checking dev servers and services in a project that has a .hun.yml, and when creating, validating, or updating .hun.yml files, especially when inspecting a repository to decide local, Docker Compose, or hybrid service orchestration.
---

# Hun

Hun runs a project's dev services from `.hun.yml` and shows them, with their logs, in one place. Use this skill both to run services through Hun and to create or improve `.hun.yml`. Treat `.hun.yml` as an operational contract: infer carefully, ask when the run strategy is ambiguous, and validate before finishing.

## Running services

When the project has a `.hun.yml` and you need a dev server, backend, worker, or database running, go through Hun instead of starting it yourself. Hun captures the logs where the user is looking and keeps ports from colliding across projects.

- `hun status` shows what is running and on which ports, including services started outside Hun. Check it first, especially before assuming a port is free.
- `hun run <project>` starts the project's last-run profile (every service if none); `hun run <project> --profile <name>` runs a profile from `.hun.yml` (`--profile all` for everything); `hun run <project>:<service>` starts one service and its dependencies. Running a different profile while the project runs only stops and starts the difference.
- `hun restart <project>:<service>` restarts one service. If the service was started outside Hun, this stops that instance and runs it under Hun.
- `hun logs <project>:<service>` prints recent output; `hun tail <project>:<service>` follows it.
- `hun stop <project>` stops a project, whoever started its services; `hun stop <project>:<service>` stops one service.

Do not run `npm run dev`, `docker compose up`, `uvicorn`, and similar service commands directly for a Hun project unless the user asks you to. If a command fails because a port is in use, run `hun status` to see what holds it rather than killing processes yourself.

The project name is the `name` field in `.hun.yml`.

The rest of this skill covers creating and improving `.hun.yml`.

## Workflow

1. Inspect the repository before editing.
   - Confirm the project root and current `.hun.yml`, if present.
   - Scan a few levels deep, skipping heavy folders such as `.git`, `node_modules`, `.venv`, `vendor`, `dist`, `build`, `target`, and `Library`.
   - Look for `README*`, `package.json`, workspace files, `docker-compose.yml`, `compose.yaml`, `Dockerfile`, `Makefile`, `justfile`, `Taskfile.yml`, `Procfile`, `.env.example`, `pyproject.toml`, `requirements.txt`, `manage.py`, `go.mod`, `Cargo.toml`, and `.github/workflows/*`.

2. Determine the likely run strategy.
   - Prefer **hybrid** when app services have clear local commands and infra services have clear Docker Compose definitions.
   - Prefer **local** when the repo documents local commands for everything and does not require containerized infra.
   - Prefer **compose** when Docker Compose is clearly the intended development path or local commands are incomplete.
   - Treat databases, Redis, queues, search, object stores, and similar dependencies as infra; Docker is usually appropriate for these.
   - Treat frontend, backend, workers, schedulers, and app-specific processes as app services; local commands are usually better when explicit and reliable.

3. Ask focused questions before finalizing when multiple valid setups exist.
   - Ask at most three questions at a time.
   - Prefer questions about choices that affect commands, service ownership, or developer workflow.
   - Good questions: "Run app services locally, in Docker, or hybrid?", "Should Hun manage Postgres/Redis or assume they already run?", "Which worker/scheduler processes do you actually use in dev?"

4. Edit `.hun.yml`.
   - Preserve a good existing config when possible; improve only the incorrect or missing parts.
   - Do not invent services without repo evidence or user confirmation.
   - Use stable service names such as `frontend`, `backend`, `worker`, `scheduler`, `redis`, `postgres`, `db`.
   - Use relative `cwd` values from the project root.
   - Use `depends_on` only for services Hun manages in the same file.
   - Add `port` when the service binds a known port. Treat it as the preferred base port; Multitask fallback is chosen only when that port is occupied.
   - Hun always publishes a configured service's selected launch port as `PORT`. Add `port_env` only when the service reads a different named environment variable; it is an additional alias for `port`, never a separate source of truth.
   - Add `ready` strings only when the repo logs or common framework output make them likely.

5. Validate and report.
   - Run `hun validate .` after writing `.hun.yml`.
   - If `hun validate` is unavailable, run the closest available Hun command that loads the project config and report that limitation.
   - Summarize the chosen run strategy and any assumptions the user should confirm.

## `.hun.yml` Shape

```yaml
name: my-project

services:
  frontend:
    cmd: npm run dev
    cwd: ./frontend
    port: 3000
    ready: "Ready"

  backend:
    cmd: python manage.py runserver
    cwd: ./backend
    port: 8000
    depends_on:
      - postgres

  postgres:
    cmd: docker compose up postgres
    ready: "database system is ready"

profiles:
  web: [frontend]
  app: [frontend, backend]   # postgres comes along through depends_on

detect:
  version: v2
  profile: hybrid
```

Supported project fields:
- `name`
- `services`
- `profiles`: named sets of services to run together. Each is a list of services or `all`. List the services someone works on and let `depends_on` bring in their infrastructure. `all` is reserved as a name. Not related to `detect.profile`.
- `hooks.pre_start`
- `hooks.post_stop`
- `logs.max_size`
- `logs.max_files`
- `logs.retention`
- `detect.version`
- `detect.profile`: `local`, `compose`, or `hybrid`

Supported service fields:
- `cmd` required
- `cwd`
- `port`
- `port_env`
- `ready`
- `env`
- `depends_on`
- `restart`: only `on_failure`

## Guardrails

- Never put secrets directly in `.hun.yml`; reference environment variables or `.env` files instead.
- When both `port` and `port_env` are present, `port` wins as the base. Hun injects the selected launch port into `PORT` and into `port_env`; do not infer or document an environment value as a competing port.
- Do not rewrite unrelated files unless the user explicitly asks.
- Do not add a separate "add service" workflow; `.hun.yml` is the source of truth for service changes.
- Do not make Hun run package installation, migrations, or destructive setup automatically unless the repo already documents that as the dev startup command or the user confirms it.
