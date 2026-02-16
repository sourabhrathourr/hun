# hun.sh

Seamless project context switching for developers.

hun.sh manages your development services, captures logs, and lets you switch between projects instantly. Unlike terminal multiplexers like tmux, hun operates at the **project level** — it understands what services a project needs, manages their lifecycle, and provides instant access to logs from anywhere.

> "One project at a time, by default. Multiple when you need it. Always in control."

## Install

**Homebrew (macOS & Linux):**

```sh
brew install hun-sh/tap/hun
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
# Initialize a project (auto-detects services)
cd ~/code/my-project
hun init

# Switch to it (starts all services)
hun switch my-project

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
    port_env: PORT
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
hun init                        # Initialize current directory
hun init --name <name>          # Initialize with explicit name
hun list                        # List all known projects
hun add <path>                  # Register an existing project
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
| `↑↓` | Select service |
| `tab` | Cycle between projects (multitask) |
| `r` | Restart selected service |
| `R` | Restart all services in project |
| `p` | Open project picker (fuzzy search) |
| `/` | Search / filter logs |
| `a` | Show combined logs from all services |
| `m` | Switch to Multitask Mode |
| `f` | Switch to Focus Mode |
| `s` | Stop focused project (multitask) |
| `c` | Enter copy mode |
| `q` | Quit TUI (services keep running) |

## Auto-Detection

`hun init` detects your project structure automatically:

- **Node.js** — `package.json` scripts, detects npm/yarn/pnpm/bun
- **Go** — `go.mod` + `main.go` or `cmd/` directory
- **Python** — `manage.py`, `app.py`, `main.py` with `requirements.txt` or `pyproject.toml`
- **Docker Compose** — services from `docker-compose.yml` / `compose.yml`
- **Monorepos** — scans `frontend/`, `backend/`, `server/`, `client/` subdirectories

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
# Build
make build

# Install to $GOPATH/bin
make install

# Run tests
make test

# Lint
make lint
```

## License

MIT
