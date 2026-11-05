---
name: hun
description: Use whenever you need to start, stop, restart or check anything a project runs in development (dev servers, workers, databases, or a watcher that builds and relaunches an app) in a project that has a .hun.yml (always start them through Hun), when creating or starting work in a git worktree of such a project, or when setting up a project's .hun.yml or its profiles.
---

# Hun

Hun runs a project's dev services from a `.hun.yml` file and shows them, with their logs, in one place.

## Always start services through Hun

In a project with a `.hun.yml`, start everything it runs in development with `hun run`: dev servers, workers, databases, and watchers that build and relaunch an app, such as a macOS or mobile dev build. Read the services in `.hun.yml` before running anything yourself. Never start one yourself with `npm run dev`, `docker compose up`, `uvicorn`, `xcodebuild` and `open`, or similar. Hun then captures the logs and ports where the user can see them, and keeps ports from clashing with other projects. This applies whenever you need something running: to test a change, to reproduce a bug, or because the user asked you to start it.

If a service you need isn't in `.hun.yml`, add it there and start it with Hun. If the project has no `.hun.yml` yet, set one up first (see below), then start it with Hun.

The project name is the `name` in `.hun.yml`.

If your shell can't find `hun`, use the copy inside the app instead, for example `/Applications/hun.app/Contents/Resources/hun status`. Don't install anything or edit shell files to fix it.

- `hun status`: what's running, and on which ports. Check it first: the service may already be running.
- `hun run <project>`: start the project. Add `-p <profile>` to run a profile, or use `<project>:<service>` for one service.
- `hun restart <project>:<service>`, `hun stop <project>`, `hun stop <project>:<service>`.
- `hun logs <project>:<service>` prints recent output; `hun tail <project>:<service>` follows it.

If a port is taken, look at `hun status` instead of killing processes.

## Setting up a project

Keep it quick. Most projects need ten lines or so.

1. Find out how the project is started: the README, `package.json` scripts, `docker-compose.yml`, `Makefile` or `Procfile`. Stop looking once you know.
2. Write `.hun.yml` with one service for each thing that runs in development, using the commands the project already uses. If a `.hun.yml` exists, change only what's wrong or missing.
   - Name the project after its folder.
   - Give each Docker Compose service its own Hun service (`docker compose up postgres`, `docker compose up redis`), so dependencies stay precise.
   - If a command fixes its port, write it as `$PORT` (`--port $PORT`, or `npm run dev -- --port $PORT` for Vite) and set `port:` to the usual number. Hun sets `PORT` and can then move the service when that port is busy.
3. Run `hun validate .` and fix anything it reports.
4. Run `hun add . -y` to register the project (safe if it's already registered).
5. Tell the user what you set up in two or three lines.

Use sensible defaults instead of asking. Ask one question only if you can't tell how to start the app at all.

```yaml
name: shop

services:
  web:
    cmd: npm run dev
    cwd: ./web          # only when it isn't the project root
    port: 3000          # when it uses a known port
  api:
    cmd: uv run app
    cwd: ./api
    port: 8000
    depends_on: [db]
  db:
    cmd: docker compose up db
```

Add these only when they clearly help:

- `depends_on: [service]`: starts that service first. Workers usually depend on the database or queue they use.
- `ready: "text"`: the exact line the service prints once it's up, so services that depend on it wait. Leave it out if you don't know the line.
- `port_env: APP_PORT`: if the app reads its port from a variable other than `PORT`. Hun sets both.
- `env: { KEY: value }` and `restart: on_failure`. When a service calls another, write `${service.port}` instead of the number (`API_URL: http://localhost:${api.port}`): Hun fills in the port that service really runs on.

Don't put secrets in `.hun.yml`, add install or migration steps as services, or add services the project doesn't use.

## Profiles

A profile is a named set of services to run together, such as just the frontend, or the frontend and the API. Suggest profiles when a project has more than three or so services. Set them up whenever the user asks. Add only the profiles the user wants, or one obvious one, not every combination.

```yaml
profiles:
  web: [web]
  app: [web, api]       # db comes along: api depends on it
  everything: all
```

- List only the services someone works on. Their `depends_on` services start with them, so you don't list databases and the like.
- Name profiles after what the user is doing: `web`, `api`, `app`, `mobile`.
- `all` means every service; it can't be used as a profile name.
- Run one with `hun run <project> -p <profile>`. Hun remembers the last profile for each project and each worktree separately, and switching profiles only starts and stops the difference.
- If the user describes what they work on ("I usually just need the frontend and the API"), turn that straight into a profile.

After adding profiles, run `hun validate .` again.

## Worktrees

When you create a git worktree for a task, or start working in one, give it its own `.hun.yml` and run only what the task needs:

1. If the worktree has no `.hun.yml`, copy the main checkout's into the worktree's root, whether or not git ignores the file. Without its own copy, the worktree uses the main checkout's file, which works but runs every service.
2. Choose a profile for the task. Read the profiles in `.hun.yml` and reuse one that covers the services the task touches. If none fits, add a profile to the worktree's copy, named after the task, listing only those services. Then run `hun validate .`.
3. Run `hun add . -y` in the worktree. It prints the worktree's project name.
4. Start it with `hun run <name> -p <profile>`, always with `-p`. A new worktree has no profile yet, so without `-p` it runs everything. Hun then remembers the profile for this worktree only.

Change only the worktree's `.hun.yml`, never the main checkout's. The worktree's copy goes when the worktree is deleted. If `.hun.yml` is committed to the repository, git puts it in the worktree already: reuse a profile when one fits, and leave a profile you add out of your commits.
