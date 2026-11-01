// A small simulation of Hun's daemon for the landing-page window: projects,
// services with dependency waves, port assignment and a log feed. It is a
// plain store (subscribe/getSnapshot) so React reads it with
// useSyncExternalStore and every timer lives here, not in components.

export type ServiceStatus = "running" | "stopped" | "starting";
export type ProjectStatus = "running" | "stopped" | "starting";
export type Mode = "focus" | "multitask";
export type Scope = "service" | "combined";
export type Pending = "start" | "stop" | "restart" | null;
export type LogLevel = "info" | "warning" | "error";

type Kind = "next" | "uvicorn" | "worker" | "postgres" | "go";

export interface SimService {
  id: string;
  name: string;
  command: string;
  /** The configured port; 0 for none. */
  desiredPort: number;
  /** The port it holds while it runs. */
  port: number;
  pid: number;
  status: ServiceStatus;
  kind: Kind;
  deps: string[];
}

export interface SimProject {
  id: string;
  name: string;
  path: string;
  branch: string;
  pkg: string;
  services: SimService[];
  selectedServiceId: string;
  pending: Pending;
}

export interface LogLine {
  seq: number;
  service: string;
  time: string;
  message: string;
  level: LogLevel;
}

export interface SimState {
  projects: SimProject[];
  logs: Record<string, LogLine[]>;
  selectedProjectId: string;
  mode: Mode;
  modePending: boolean;
  scope: Scope;
  search: string;
  sidebarSearch: string;
}

const MAX_LINES = 400;

// MARK: - Seed data

function svc(
  id: string,
  command: string,
  port: number,
  pid: number,
  kind: Kind,
  deps: string[] = [],
  running = true,
): SimService {
  return {
    id,
    name: id,
    command,
    desiredPort: port,
    port,
    pid: running ? pid : 0,
    status: running ? "running" : "stopped",
    kind,
    deps,
  };
}

let seq = 0;
function L(service: string, time: string, message: string, level: LogLevel = "info"): LogLine {
  seq += 1;
  return { seq, service, time, message, level };
}

function seedProjects(): SimProject[] {
  return [
    {
      id: "blog",
      name: "blog",
      path: "~/code/blog",
      branch: "main",
      pkg: "blog@0.6.2",
      selectedServiceId: "web",
      pending: null,
      services: [svc("web", "npm run dev", 3000, 0, "next", [], false)],
    },
    {
      id: "docs",
      name: "docs",
      path: "~/code/docs",
      branch: "main",
      pkg: "docs@2.3.0",
      selectedServiceId: "site",
      pending: null,
      services: [svc("site", "npm run dev", 3001, 47962, "next")],
    },
    {
      id: "mobile-api",
      name: "mobile-api",
      path: "~/code/mobile-api",
      branch: "develop",
      pkg: "",
      selectedServiceId: "api",
      pending: null,
      services: [
        svc("api", "go run ./cmd/api", 8080, 0, "go", ["db"], false),
        svc("db", "docker compose up db", 5433, 0, "postgres", [], false),
      ],
    },
    {
      id: "orbit",
      name: "orbit",
      path: "~/code/orbit",
      branch: "main",
      pkg: "orbit-app@1.4.0",
      selectedServiceId: "app",
      pending: null,
      services: [
        svc("app", "npm run dev", 3000, 48211, "next", ["server"]),
        svc("postgres", "docker compose up postgres", 5432, 48177, "postgres"),
        svc("server", "uv run server", 8000, 48190, "uvicorn", ["postgres"]),
        svc("worker", "uv run worker", 0, 48195, "worker", ["postgres"]),
      ],
    },
  ];
}

function seedLogs(): Record<string, LogLine[]> {
  seq = 0;
  const orbit: LogLine[] = [
    L("postgres", "14:41:58.402", "Container orbit-postgres-1  Running"),
    L("postgres", "14:41:58.411", "Attaching to postgres-1"),
    L("postgres", "14:41:58.902", "postgres-1  | LOG:  database system is ready to accept connections"),
    L("server", "14:42:01.220", "INFO:     Started server process [48190]"),
    L("server", "14:42:01.221", "INFO:     Waiting for application startup."),
    L("server", "14:42:01.388", "INFO:     Application startup complete."),
    L("server", "14:42:01.389", "INFO:     Uvicorn running on http://127.0.0.1:8000"),
    L("worker", "14:42:01.540", "worker ready · queue=default concurrency=4"),
    L("app", "14:42:04.118", "> orbit-app@1.4.0 dev"),
    L("app", "14:42:04.119", "> next dev --port 3000"),
    L("app", "14:42:05.602", "   ▲ Next.js 15.2.4"),
    L("app", "14:42:05.603", "   - Local:        http://localhost:3000"),
    L("app", "14:42:05.931", " ✓ Starting..."),
    L("app", "14:42:07.284", " ✓ Ready in 1681ms"),
    L("app", "14:44:21.502", " ○ Compiling / ..."),
    L("app", "14:44:23.017", " ✓ Compiled / in 1.5s (812 modules)"),
    L("app", "14:44:23.240", " GET / 200 in 1738ms"),
    L("app", "14:44:30.884", " ○ Compiling /dashboard ..."),
    L("app", "14:44:31.902", " ✓ Compiled /dashboard in 1018ms (904 modules)"),
    L("app", "14:44:32.115", " GET /dashboard 200 in 1131ms"),
    L("server", "14:44:32.398", 'INFO:     127.0.0.1:52144 - "GET /projects HTTP/1.1" 200 OK'),
    L("app", "14:44:32.406", " GET /api/projects 200 in 42ms"),
    L("app", "14:45:02.771", " GET /dashboard 200 in 38ms"),
    L("server", "14:45:03.004", 'INFO:     127.0.0.1:52144 - "POST /tasks HTTP/1.1" 201 Created'),
    L("app", "14:45:03.012", " POST /api/tasks 201 in 64ms"),
    L("app", "14:45:09.448", " GET /projects/42 200 in 51ms"),
    L("server", "14:45:12.861", 'INFO:     127.0.0.1:52151 - "GET /projects/42 HTTP/1.1" 200 OK'),
    L("app", "14:45:12.903", " GET /api/projects/42 200 in 88ms"),
    L("server", "14:45:21.214", 'INFO:     127.0.0.1:52151 - "POST /invites HTTP/1.1" 200 OK'),
    L("app", "14:45:21.336", " POST /api/invites 200 in 214ms"),
    L("worker", "14:45:21.402", "job invite.email.sent done in 182ms"),
    L("app", "14:45:21.590", " GET /projects/42/tasks 200 in 47ms"),
    L("app", "14:46:02.118", " ○ Compiling /projects/[id] ..."),
    L("app", "14:46:03.007", " ✓ Compiled /projects/[id] in 889ms (931 modules)"),
    L("app", "14:46:03.214", " GET /projects/7 200 in 1096ms"),
    L("server", "14:46:03.469", 'INFO:     127.0.0.1:52160 - "GET /projects/7 HTTP/1.1" 200 OK'),
    L("app", "14:46:03.488", " GET /api/projects/7 200 in 31ms"),
    L("worker", "14:46:03.611", "job activity.logged done in 12ms"),
    L("app", "14:46:40.751", " GET / 200 in 29ms"),
  ];
  const docs: LogLine[] = [
    L("site", "14:38:12.540", "> docs@2.3.0 dev"),
    L("site", "14:38:12.541", "> next dev --port 3001"),
    L("site", "14:38:13.880", "   ▲ Next.js 15.2.4"),
    L("site", "14:38:13.881", "   - Local:        http://localhost:3001"),
    L("site", "14:38:14.204", " ✓ Starting..."),
    L("site", "14:38:15.517", " ✓ Ready in 1637ms"),
    L("site", "14:39:02.338", " ○ Compiling /docs/[[...slug]] ..."),
    L("site", "14:39:04.120", " ✓ Compiled /docs/[[...slug]] in 1.8s (1204 modules)"),
    L("site", "14:39:04.391", " GET /docs/getting-started 200 in 2051ms"),
    L("site", "14:40:11.725", " GET /docs/configuration 200 in 64ms"),
    L("site", "14:43:27.096", " GET /docs/profiles 200 in 58ms"),
  ];
  return { orbit, docs, blog: [], "mobile-api": [] };
}

// MARK: - Line generators

const pick = <T,>(xs: readonly T[]): T => xs[Math.floor(Math.random() * xs.length)];
const rnd = (a: number, b: number) => Math.round(a + Math.random() * (b - a));

const ROUTES: Record<string, string[]> = {
  orbit: ["/", "/dashboard", "/projects/42", "/projects/7", "/inbox", "/settings", "/account"],
  docs: ["/docs/getting-started", "/docs/configuration", "/docs/profiles", "/docs/ports", "/docs/cli"],
  blog: ["/", "/posts/shipping-hun", "/posts/ports-are-hard", "/tags/dev", "/about"],
};
const API = ["/api/projects", "/api/tasks", "/api/projects/42", "/api/inbox", "/api/session"];

function bootLines(project: SimProject, s: SimService): { early: string[]; ready: string[] } {
  switch (s.kind) {
    case "next":
      return {
        early: [`> ${project.pkg} dev`, `> next dev --port ${s.port}`, "   ▲ Next.js 15.2.4", `   - Local:        http://localhost:${s.port}`, " ✓ Starting..."],
        ready: [` ✓ Ready in ${rnd(1100, 1900)}ms`],
      };
    case "uvicorn":
      return {
        early: [`INFO:     Started server process [${s.pid}]`, "INFO:     Waiting for application startup."],
        ready: ["INFO:     Application startup complete.", `INFO:     Uvicorn running on http://127.0.0.1:${s.port}`],
      };
    case "worker":
      return { early: ["connecting to postgres…"], ready: ["worker ready · queue=default concurrency=4"] };
    case "postgres":
      return {
        early: [`Container ${project.id}-${s.id}-1  Starting`, `Container ${project.id}-${s.id}-1  Started`, `Attaching to ${s.id}-1`],
        ready: [`${s.id}-1  | LOG:  database system is ready to accept connections`],
      };
    case "go":
      return {
        early: ["go: downloading modules", `level=INFO msg="connecting to db" addr=localhost:5433`],
        ready: [`level=INFO msg="listening" addr=:${s.port}`],
      };
  }
}

function liveLine(project: SimProject, s: SimService): { message: string; level: LogLevel } {
  switch (s.kind) {
    case "next": {
      const routes = ROUTES[project.id] ?? ROUTES.orbit;
      if (Math.random() < 0.3 && project.id === "orbit") {
        const verb = Math.random() < 0.75 ? "GET" : "POST";
        return { message: ` ${verb} ${pick(API)} ${verb === "POST" ? 201 : 200} in ${rnd(12, 96)}ms`, level: "info" };
      }
      return { message: ` GET ${pick(routes)} 200 in ${rnd(18, 140)}ms`, level: "info" };
    }
    case "uvicorn": {
      const path = pick(["/projects", "/tasks", "/projects/42", "/session", "/inbox"]);
      return { message: `INFO:     127.0.0.1:${rnd(52100, 52400)} - "GET ${path} HTTP/1.1" 200 OK`, level: "info" };
    }
    case "worker":
      return { message: `job ${pick(["email.receipt", "order.viewed", "cart.reminder", "search.reindex"])} done in ${rnd(8, 220)}ms`, level: "info" };
    case "postgres":
      return Math.random() < 0.5
        ? { message: `${s.id}-1  | LOG:  checkpoint starting: time`, level: "info" }
        : { message: `${s.id}-1  | LOG:  checkpoint complete: wrote ${rnd(3, 60)} buffers`, level: "info" };
    case "go":
      return Math.random() < 0.12
        ? { message: `level=WARN msg="slow query" took=${rnd(210, 480)}ms`, level: "warning" }
        : {
            message: `level=INFO msg="request" method=GET path=${pick(["/v1/feed", "/v1/me", "/v1/devices", "/v1/notifications"])} status=200 dur=${rnd(2, 40)}ms`,
            level: "info",
          };
  }
}

// MARK: - Helpers

export function projectStatus(p: SimProject): ProjectStatus {
  if (p.services.some((s) => s.status === "starting")) return "starting";
  if (p.services.some((s) => s.status === "running")) return "running";
  return "stopped";
}

/** Services in waves: each wave's dependencies all start in earlier waves. */
function waves(services: SimService[]): SimService[][] {
  const placed = new Set<string>();
  const ids = new Set(services.map((s) => s.id));
  const out: SimService[][] = [];
  let left = [...services];
  while (left.length) {
    const wave = left.filter((s) => s.deps.every((d) => placed.has(d) || !ids.has(d)));
    const next = wave.length ? wave : left;
    next.forEach((s) => placed.add(s.id));
    out.push(next);
    left = left.filter((s) => !next.includes(s));
  }
  return out;
}

function pad(n: number, w = 2) {
  return String(n).padStart(w, "0");
}

// MARK: - Store

const BASE_TIME = (14 * 3600 + 46 * 60 + 41) * 1000; // just after the render's last line

export class HunSim {
  private state: SimState;
  private listeners = new Set<() => void>();
  private timers = new Set<ReturnType<typeof setTimeout>>();
  private mountedAt = Date.now();
  private nextPid = 48230;
  private streamTimer: ReturnType<typeof setTimeout> | null = null;
  /** Visible on screen, tab visible and motion allowed. */
  private live = false;
  /** Set by reduced motion: changes apply without staged timing. */
  private instant = false;

  setInstant(instant: boolean) {
    this.instant = instant;
  }

  constructor() {
    this.state = {
      projects: seedProjects(),
      logs: seedLogs(),
      selectedProjectId: "orbit",
      mode: "multitask",
      modePending: false,
      scope: "service",
      search: "",
      sidebarSearch: "",
    };
  }

  subscribe = (fn: () => void) => {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  };

  getSnapshot = () => this.state;

  private set(patch: Partial<SimState>) {
    this.state = { ...this.state, ...patch };
    this.listeners.forEach((l) => l());
  }

  private after(ms: number, fn: () => void) {
    if (this.instant) {
      fn();
      return;
    }
    const t = setTimeout(() => {
      this.timers.delete(t);
      fn();
    }, ms);
    this.timers.add(t);
  }

  dispose() {
    this.timers.forEach(clearTimeout);
    this.timers.clear();
    if (this.streamTimer) clearTimeout(this.streamTimer);
    this.streamTimer = null;
  }

  now(): string {
    const ms = BASE_TIME + (Date.now() - this.mountedAt);
    const h = Math.floor(ms / 3600000) % 24;
    const m = Math.floor(ms / 60000) % 60;
    const s = Math.floor(ms / 1000) % 60;
    return `${pad(h)}:${pad(m)}:${pad(s)}.${pad(ms % 1000, 3)}`;
  }

  project(id: string) {
    return this.state.projects.find((p) => p.id === id)!;
  }

  private updateProject(id: string, fn: (p: SimProject) => SimProject) {
    this.set({ projects: this.state.projects.map((p) => (p.id === id ? fn(p) : p)) });
  }

  private updateService(pid: string, sid: string, fn: (s: SimService) => SimService) {
    this.updateProject(pid, (p) => ({ ...p, services: p.services.map((s) => (s.id === sid ? fn(s) : s)) }));
  }

  private append(projectId: string, service: string, message: string, level: LogLevel = "info") {
    seq += 1;
    const line: LogLine = { seq, service, time: this.now(), message, level };
    const prev = this.state.logs[projectId] ?? [];
    const next = prev.length >= MAX_LINES ? [...prev.slice(prev.length - MAX_LINES + 1), line] : [...prev, line];
    this.set({ logs: { ...this.state.logs, [projectId]: next } });
  }

  private resetServiceLogs(projectId: string, service: string) {
    const lines = this.state.logs[projectId] ?? [];
    this.set({ logs: { ...this.state.logs, [projectId]: lines.filter((l) => l.service !== service) } });
  }

  // MARK: Selection

  selectProject = (id: string) => this.set({ selectedProjectId: id });

  selectService = (id: string) => {
    this.updateProject(this.state.selectedProjectId, (p) => ({ ...p, selectedServiceId: id }));
    this.set({ scope: "service" });
  };

  setScope = (scope: Scope) => this.set({ scope });
  setSearch = (search: string) => this.set({ search });
  setSidebarSearch = (sidebarSearch: string) => this.set({ sidebarSearch });

  clearLogs = () => {
    const p = this.project(this.state.selectedProjectId);
    const lines = this.state.logs[p.id] ?? [];
    const kept = this.state.scope === "combined" ? [] : lines.filter((l) => l.service !== p.selectedServiceId);
    this.set({ logs: { ...this.state.logs, [p.id]: kept } });
  };

  // MARK: Mode

  setMode = (mode: Mode) => {
    if (mode === this.state.mode) return;
    this.set({ modePending: true });
    this.after(260, () => {
      // Focus keeps the selected project if it runs and stops the rest.
      if (mode === "focus") {
        const keep = this.state.selectedProjectId;
        if (projectStatus(this.project(keep)) !== "stopped") {
          this.state.projects.filter((p) => p.id !== keep && projectStatus(p) !== "stopped").forEach((p) => this.stopNow(p.id));
        }
      }
      this.set({ mode, modePending: false });
    });
  };

  // MARK: Lifecycle

  private stopNow(id: string) {
    this.updateProject(id, (p) => ({
      ...p,
      pending: p.pending === "stop" ? null : p.pending,
      services: p.services.map((s) => ({ ...s, status: "stopped", pid: 0, port: s.desiredPort })),
    }));
  }

  /** Ports held by running or starting services, in every project. */
  private takenPorts() {
    const taken = new Set<number>();
    for (const p of this.state.projects) {
      for (const s of p.services) {
        if (s.status === "stopped" || s.port === 0) continue;
        taken.add(s.port);
      }
    }
    return taken;
  }

  run = (id: string) => {
    const p = this.project(id);
    if (p.pending) return;
    this.updateProject(id, (q) => ({ ...q, pending: "start" }));
    if (this.state.mode === "focus") {
      this.state.projects.filter((q) => q.id !== id && projectStatus(q) !== "stopped").forEach((q) => this.stopNow(q.id));
    }
    this.after(120, () => this.startWaves(id, "start"));
  };

  stop = (id: string) => {
    const p = this.project(id);
    if (p.pending) return;
    this.updateProject(id, (q) => ({ ...q, pending: "stop" }));
    this.after(380, () => this.stopNow(id));
  };

  restart = (id: string) => {
    const p = this.project(id);
    if (p.pending) return;
    this.updateProject(id, (q) => ({ ...q, pending: "restart" }));
    this.after(300, () => {
      this.updateProject(id, (q) => ({
        ...q,
        services: q.services.map((s) => ({ ...s, status: "stopped", pid: 0, port: s.desiredPort })),
      }));
      this.after(120, () => this.startWaves(id, "restart"));
    });
  };

  private startWaves(id: string, kind: "start" | "restart") {
    const list = waves(this.project(id).services);
    const step = (i: number) => {
      if (i >= list.length) {
        this.updateProject(id, (q) => ({ ...q, pending: q.pending === kind ? null : q.pending }));
        return;
      }
      // Starting: a port (the next free one if the configured port is
      // taken), a pid and the first boot lines.
      for (const s of list[i]) {
        const taken = this.takenPorts();
        let port = s.desiredPort;
        if (port) while (taken.has(port)) port += 1;
        const pidNo = this.nextPid;
        this.nextPid += rnd(3, 11);
        this.updateService(id, s.id, (x) => ({ ...x, status: "starting", port, pid: pidNo }));
        // Like the daemon: every start is a fresh log session for that service.
        this.resetServiceLogs(id, s.id);
        const boot = bootLines(this.project(id), this.project(id).services.find((x) => x.id === s.id)!);
        boot.early.forEach((m, k) => this.after(40 + k * 55, () => this.append(id, s.id, m)));
        this.after(400, () => {
          this.updateService(id, s.id, (x) => (x.status === "starting" ? { ...x, status: "running" } : x));
          boot.ready.forEach((m) => this.append(id, s.id, m));
        });
      }
      this.after(400, () => step(i + 1));
    };
    step(0);
  }

  // MARK: Streaming

  setLive(live: boolean) {
    if (live === this.live) return;
    this.live = live;
    if (live) this.scheduleStream();
    else if (this.streamTimer) {
      clearTimeout(this.streamTimer);
      this.streamTimer = null;
    }
  }

  private scheduleStream() {
    if (this.streamTimer) clearTimeout(this.streamTimer);
    this.streamTimer = setTimeout(() => {
      this.streamTimer = null;
      if (!this.live) return;
      this.streamOne();
      this.scheduleStream();
    }, rnd(1500, 3000));
  }

  private streamOne() {
    const p = this.project(this.state.selectedProjectId);
    const running = p.services.filter((s) => s.status === "running");
    if (!running.length || p.pending) return;
    const selected = running.find((s) => s.id === p.selectedServiceId);
    const s = selected && Math.random() < 0.6 ? selected : pick(running);
    const line = liveLine(p, s);
    this.append(p.id, s.id, line.message, line.level);
  }
}

/** Fixed FNV-1a hash, as the app uses, so a service keeps its colour. */
export function serviceColor(name: string): string {
  const palette = ["#445DB7", "#B64C46", "#327C65", "#986327", "#744DA7"];
  let hash = 2166136261;
  for (const byte of new TextEncoder().encode(name)) {
    hash = Math.imul(hash ^ byte, 16777619) >>> 0;
  }
  return palette[hash % palette.length];
}
