# hun.sh

![hun.sh banner](https://res.cloudinary.com/djvbs5a8x/image/upload/v1771356053/hun-og_2x_xoflgq.png)

Seamless project context switching for developers.

hun.sh manages your development services, captures logs, and lets you switch between projects instantly. Unlike terminal multiplexers like tmux, hun operates at the **project level** — it understands what services a project needs, manages their lifecycle, and provides instant access to logs from anywhere.

> "One project at a time, by default. Multiple when you need it. Always in control."

## Install

**Homebrew (macOS & Linux):**

```sh
# one-time
brew tap hundotsh/tap

# install/update
brew install hun
```

**Go install:**

```sh
go install github.com/sourabhrathourr/hun@latest
```

**Direct download:**

```sh
curl -fsSL https://hun.sh/install.sh | sh
```

## Quick Start

```sh
# First-time setup (interactive, TUI-first)
hun onboard

# Open the TUI
hun
```

## How It Works

hun.sh runs a lightweight background daemon that manages all your services. The CLI and TUI communicate with it over a Unix socket. Services run in process groups for clean termination. Logs are captured in a ring buffer for instant access and written to disk with rotation.

```
CLI / TUI  ──>  Daemon  ──>  Services
                  │
                  ├── Log Capture (ring buffer + disk)
                  ├── Port Allocation
                  └── State Persistence
```

## Two Modes

| Mode | Philosophy | Behavior |
|------|-----------|----------|
| **Focus** (default) | One project at a time | `hun switch` stops current, starts target |
| **Multitask** | Orchestrate multiple | `hun run` starts alongside others with port offset |

## Configuration

Create a `.hun.yml` in your project root (or let `hun init` generate one):

```yaml
name: my-project

services:
  frontend:
    cmd: npm run dev
    cwd: ./frontend
    port: 3000
    ready: "compiled successfully"

  backend:
    cmd: python main.py
    cwd: ./backend
    port: 8000
    port_env: API_PORT
    env:
      DATABASE_URL: postgres://localhost:5432/mydb
    depends_on:
      - db

  db:
    cmd: docker compose up postgres
    ready: "database system is ready"

hooks:
  pre_start: ./scripts/setup.sh
  post_stop: ./scripts/cleanup.sh

logs:
  max_size: 10MB
  max_files: 3
  retention: 7d
```

`port` is the preferred base port. In Multitask mode, hun keeps it unchanged
when it is free and searches upward by the configured offset step only when
that individual service port is occupied. Hun always injects the selected port
as `PORT`, overriding inherited or service-level values. When `port_env` names
a different variable, hun injects the same selected port there as an additional
alias. Runtime detection verifies live listeners against the launched process
group. Focus mode rejects a different verified listener; Multitask mode safely
adopts it so frameworks with their own fallback behavior can keep running. A
per-port lease prevents concurrent hun services or instances from selecting
the same port while an application is still starting.

## Commands

### Process Management

```sh
hun switch <project>            # Focus mode: stop all, start one
hun switch <project> -m "note"  # Save a note before switching
hun run <project>               # Multitask: start alongside others (port offset)
hun stop <project>              # Stop specific project
hun stop --all                  # Stop all running projects
hun restart <project>:<service> # Restart one service
```

### Project Management

```sh
hun onboard [path]              # Interactive first-time setup
hun init                        # Initialize current directory
hun init --name <name>          # Initialize with explicit name
hun init --yes                  # Accept detected config without prompting
hun init --no-register          # Write .hun.yml without adding it to state
hun validate [path]             # Validate a .hun.yml config
hun list                        # List all known projects
hun add <path>                  # Register an existing project (prompts in a terminal)
hun remove <project>            # Unregister (doesn't delete files)
```

### Info & Logs

```sh
hun status                      # List running projects + services
hun ports                       # Show port map for all running services
hun logs <project>:<service>    # Dump logs to stdout (pipe-friendly)
hun tail <project>:<service>    # Stream logs (tail -f style)
hun open <service>              # Open service URL in browser
hun doctor                      # Diagnose common issues
```

### TUI

```sh
hun                             # Open TUI in Focus Mode
hun --multi                     # Open TUI in Multitask Mode
```

**TUI Keybindings:**

| Key | Action |
|-----|--------|
| `←→` | Switch pane (Services / Logs) |
| `↑↓` / `j` `k` | Move in active pane (service list or logs) |
| `tab` | Cycle between projects (multitask) |
| `u` / `d` | Fast log scroll (`pgup` / `pgdown` also works) |
| `home` / `end` (`g` / `G`) | Jump to top/bottom logs |
| `l` (Logs pane) | Toggle live log mode |
| `w` | Toggle log wrapping |
| `v` | Start/reset line-range selection at cursor |
| `c` | Copy current line or selected range |
| `y` | Yank current line or selected range |
| `r` | Restart selected service |
| `R` | Restart all services in project |
| `x` | Stop selected service |
| `p` | Open project picker (fuzzy search) |
| `/` | Search / filter logs |
| `a` | Show combined logs from all services |
| `m` | Switch to Multitask Mode |
| `f` | Switch to Focus Mode |
| `s` | Stop focused project |
| `q` | Quit TUI (services keep running) |

Mouse support:
- Click project tabs, services, and logs to focus/select.
- Shift+click in logs extends range selection.
- Scroll wheel works in services, picker, and logs.

## Auto-Detection

`hun init` detects your project structure automatically:

- **Node.js** — `package.json` scripts, detects npm/yarn/pnpm/bun
- **Go** — `go.mod` + `main.go` or `cmd/` directory
- **Python** — `manage.py`, `app.py`, `main.py` with `requirements.txt` or `pyproject.toml`
- **Docker Compose** — services from `docker-compose.yml` / `compose.yml`
- **Monorepos** — scans `frontend/`, `backend/`, `server/`, `client/` subdirectories

In an interactive terminal, `hun init` shows the detected services and asks before writing `.hun.yml`. Non-interactive callers must pass `--yes` to accept the generated config.

## File Locations

| Path | Purpose |
|------|---------|
| `~/.hun/` | Global hun.sh directory |
| `~/.hun/config.yml` | Global configuration |
| `~/.hun/state.json` | Active projects and saved states |
| `~/.hun/daemon.sock` | Unix socket for CLI-daemon communication |
| `~/.hun/logs/<project>/` | Stored log files per project |
| `<project>/.hun.yml` | Project-specific configuration |

## Development

```sh
# Build the CLI
make build

# Install the CLI to $GOPATH/bin
make install

# Run tests
make test

# Lint
make lint

# Rebuild and relaunch the macOS app whenever its source changes
make dev-macos
```

For UI-only macOS changes, Xcode's SwiftUI Canvas is faster: open
`ContentView.swift` or `MenuBarView.swift`, show the Canvas with
Option-Command-Return, and start the existing preview once. Xcode refreshes it
as you edit. Use `make dev-macos` when you need to exercise the complete app,
daemon connection, menu-bar item, or window behavior.

## Release

Run releases from a clean, up-to-date `main` branch. The release command owns
the Xcode marketing version, numeric build number, changelog metadata, release
commit, and Git tag. Pushing the tag triggers the GitHub Actions release
workflow.

```sh
# Preview the version, build, changelog, commit range, and actions.
# This changes nothing.
./scripts/release.sh --dry-run

# Repeat that plan, ask for confirmation, validate it, and start the release.
./scripts/release.sh
```

For the first release, the command uses the version already in Xcode. After
that, it derives the next patch and build number from the latest published
release while preserving a newer unreleased marketing version already in the
project. Optional overrides:

```sh
./scripts/release.sh minor --dry-run
./scripts/release.sh major --dry-run
./scripts/release.sh 1.0.0 --dry-run
```

The tag pipeline publishes the signed, notarized Apple-silicon DMG and Sparkle
appcast. Standalone CLI archives and the Homebrew formula are opt-in: set the
GitHub repository variable `PUBLISH_STANDALONE_CLI=true` only for releases that
should publish them. The macOS app always embeds its own matching Hun runtime,
regardless of that variable. Hun does not use Changesets; the release command
and GitHub Actions enforce the version contract directly.

## License

MIT
