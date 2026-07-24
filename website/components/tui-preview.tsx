"use client";

import { motion, AnimatePresence } from "framer-motion";
import { useCallback, useEffect, useRef, useState } from "react";

/**
 * TuiPreview — interactive replica of the hun TUI.
 *
 * Upgrades components/mini-tui.tsx: the arrow / j / k / Tab navigation is kept,
 * and the previously-decorative `/` search and `r` restart hints are now real:
 *   - `/`  focuses a search field that live-filters the current log stream
 *   - `r`  replays a lightweight restart animation for the selected service
 *   - `esc` closes search
 *
 * Self-contained: renders with zero props. Pass `projects` to override data.
 */

type Service = { name: string; port: string };
type LogLine = { time: string; text: string };
type Project = {
  name: string;
  services: Service[];
  logs: Record<string, LogLine[]>;
};

const DEFAULT_PROJECTS: Project[] = [
  {
    name: "letraz",
    services: [
      { name: "next-dev", port: ":3000" },
      { name: "thumbnail", port: ":4000" },
      { name: "backend", port: ":8000" },
      { name: "postgres", port: ":5432" },
    ],
    logs: {
      "next-dev": [
        { time: "12:04:01", text: "compiled in 240ms" },
        { time: "12:04:02", text: "GET /api/templates 200 12ms" },
        { time: "12:04:03", text: "GET /dashboard 200 8ms" },
        { time: "12:04:05", text: "compiled in 180ms" },
        { time: "12:04:06", text: "GET /api/resumes 200 14ms" },
        { time: "12:04:08", text: "GET /editor/abc123 200 22ms" },
      ],
      thumbnail: [
        { time: "12:04:01", text: "listening on :4000" },
        { time: "12:04:03", text: "POST /render 200 89ms" },
        { time: "12:04:05", text: "POST /render 200 102ms" },
        { time: "12:04:06", text: "cache hit resume-abc123.png" },
        { time: "12:04:07", text: "POST /render 200 67ms" },
        { time: "12:04:09", text: "POST /render 200 71ms" },
      ],
      backend: [
        { time: "12:04:01", text: "server started on :8000" },
        { time: "12:04:02", text: "POST /auth/login 200 45ms" },
        { time: "12:04:04", text: "GET /api/user/me 200 3ms" },
        { time: "12:04:05", text: "PUT /api/resume/abc123 200 18ms" },
        { time: "12:04:07", text: "GET /api/templates 200 5ms" },
        { time: "12:04:08", text: "GET /api/resumes 200 9ms" },
      ],
      postgres: [
        { time: "12:04:01", text: "database system is ready" },
        { time: "12:04:02", text: "connection authorized: user=letraz" },
        { time: "12:04:04", text: "SELECT resumes WHERE user_id=$1" },
        { time: "12:04:05", text: "UPDATE resumes SET content=$1" },
        { time: "12:04:07", text: "SELECT templates LIMIT 20" },
        { time: "12:04:08", text: "INSERT INTO activity_log" },
      ],
    },
  },
  {
    name: "novara",
    services: [
      { name: "frontend", port: ":3001" },
      { name: "backend", port: ":8000" },
      { name: "worker", port: "—" },
      { name: "compose", port: "—" },
    ],
    logs: {
      frontend: [
        { time: "12:10:01", text: "compiled in 320ms" },
        { time: "12:10:02", text: "GET /patients 200 18ms" },
        { time: "12:10:04", text: "GET /appointments 200 12ms" },
        { time: "12:10:05", text: "compiled in 210ms" },
        { time: "12:10:07", text: "GET /dashboard 200 9ms" },
        { time: "12:10:08", text: "GET /schedule 200 11ms" },
      ],
      backend: [
        { time: "12:10:01", text: "server started on :8000" },
        { time: "12:10:03", text: "POST /api/appointments 201 34ms" },
        { time: "12:10:04", text: "GET /api/patients 200 8ms" },
        { time: "12:10:06", text: "emitting event: appointment.created" },
        { time: "12:10:07", text: "GET /api/schedule 200 11ms" },
        { time: "12:10:08", text: "GET /api/doctors 200 6ms" },
      ],
      worker: [
        { time: "12:10:01", text: "connected to rabbitmq" },
        { time: "12:10:03", text: "processing: appointment.created" },
        { time: "12:10:04", text: "sent notification to patient" },
        { time: "12:10:06", text: "processing: reminder.scheduled" },
        { time: "12:10:07", text: "queued email: appointment reminder" },
        { time: "12:10:09", text: "processing: prescription.updated" },
      ],
      compose: [
        { time: "12:10:01", text: "postgres  | ready on :5432" },
        { time: "12:10:01", text: "redis     | ready on :6379" },
        { time: "12:10:02", text: "rabbitmq  | ready on :5672" },
        { time: "12:10:04", text: "postgres  | connection from backend" },
        { time: "12:10:06", text: "rabbitmq  | publish appointment.created" },
        { time: "12:10:08", text: "redis     | GET session:user-42" },
      ],
    },
  },
];

export function TuiPreview({
  projects = DEFAULT_PROJECTS,
  className = "",
}: {
  projects?: Project[];
  className?: string;
}) {
  const [projectIdx, setProjectIdx] = useState(0);
  const [serviceIdx, setServiceIdx] = useState(0);
  const [visibleLogs, setVisibleLogs] = useState(0);
  const [query, setQuery] = useState("");
  const [searching, setSearching] = useState(false);
  const [restarting, setRestarting] = useState(false);
  // bumped on every restart to re-trigger the log stream animation
  const [restartNonce, setRestartNonce] = useState(0);

  const containerRef = useRef<HTMLDivElement>(null);
  const searchRef = useRef<HTMLInputElement>(null);

  const project = projects[projectIdx];
  const service = project.services[serviceIdx];
  const sourceLogs = project.logs[service.name] || [];

  const filteredLogs = query
    ? sourceLogs.filter((l) =>
        l.text.toLowerCase().includes(query.toLowerCase())
      )
    : sourceLogs;

  const restartLine: LogLine = {
    time: "now",
    text: `⟳ restarting ${service.name}...`,
  };
  const displayLogs = restarting ? [restartLine, ...sourceLogs] : filteredLogs;

  // animate logs in on service / project / restart change
  useEffect(() => {
    setVisibleLogs(0);
    const timers = displayLogs.map((_, i) =>
      setTimeout(() => setVisibleLogs(i + 1), 80 + i * 120)
    );
    return () => timers.forEach(clearTimeout);
    // deliberately keyed on the identity-defining state, not displayLogs
    // (which changes on every keystroke while filtering)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [projectIdx, serviceIdx, restartNonce]);

  const switchProject = useCallback(
    (idx: number) => {
      if (idx !== projectIdx) {
        setProjectIdx(idx);
        setServiceIdx(0);
        setQuery("");
      }
    },
    [projectIdx]
  );

  const openSearch = useCallback(() => {
    setSearching(true);
    // focus after the input mounts
    requestAnimationFrame(() => searchRef.current?.focus());
  }, []);

  const closeSearch = useCallback(() => {
    setSearching(false);
    setQuery("");
    containerRef.current?.focus();
  }, []);

  const restart = useCallback(() => {
    if (restarting) return;
    setQuery("");
    setSearching(false);
    setRestarting(true);
    setRestartNonce((n) => n + 1);
    const total = 80 + (sourceLogs.length + 1) * 120 + 300;
    const t = setTimeout(() => {
      setRestarting(false);
      setRestartNonce((n) => n + 1);
    }, total);
    return () => clearTimeout(t);
  }, [restarting, sourceLogs.length]);

  // keyboard nav
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;

    const handler = (e: KeyboardEvent) => {
      // while the search field is open, only Escape is a nav key;
      // everything else belongs to the input
      if (searching) {
        if (e.key === "Escape") {
          e.preventDefault();
          closeSearch();
        }
        return;
      }

      if (e.key === "ArrowUp" || e.key === "k") {
        e.preventDefault();
        setServiceIdx((i) => Math.max(0, i - 1));
      } else if (e.key === "ArrowDown" || e.key === "j") {
        e.preventDefault();
        setServiceIdx((i) =>
          Math.min(projects[projectIdx].services.length - 1, i + 1)
        );
      } else if (e.key === "Tab") {
        e.preventDefault();
        switchProject((projectIdx + 1) % projects.length);
      } else if (e.key === "/") {
        e.preventDefault();
        openSearch();
      } else if (e.key === "r") {
        e.preventDefault();
        restart();
      }
    };

    el.addEventListener("keydown", handler);
    return () => el.removeEventListener("keydown", handler);
  }, [
    projectIdx,
    searching,
    switchProject,
    openSearch,
    closeSearch,
    restart,
    projects,
  ]);

  return (
    <div
      ref={containerRef}
      tabIndex={0}
      className={`bg-terminal border border-terminal-border rounded-sm text-caption font-mono overflow-hidden outline-none focus:ring-1 focus:ring-terminal-ring ${className}`}
    >
      {/* top bar */}
      <div className="flex items-center justify-between px-3 py-1.5 border-b border-border">
        <div className="flex items-center gap-1">
          <span className="text-foreground/70 text-[11px] font-bold mr-1">
            hun
          </span>
          {projects.map((p, i) => (
            <motion.button
              key={p.name}
              onClick={() => switchProject(i)}
              whileHover={{ y: -1 }}
              whileTap={{ scale: 0.95 }}
              transition={{ type: "spring", stiffness: 480, damping: 26 }}
              className={`text-[11px] px-1.5 py-0 rounded-sm cursor-pointer transition-colors ${
                i === projectIdx
                  ? "text-foreground/70 bg-muted"
                  : "text-muted-foreground/30 hover:text-muted-foreground/50"
              }`}
            >
              {p.name}
            </motion.button>
          ))}
        </div>
        <span className="text-muted-foreground/30 text-[10px]">multi</span>
      </div>

      <div className="flex h-[196px]">
        {/* services panel */}
        <div className="w-[150px] sm:w-[170px] border-r border-border px-2 py-2 shrink-0">
          <p className="text-muted-foreground/30 text-[10px] mb-1.5 px-1">
            services
          </p>
          <AnimatePresence mode="wait">
            <motion.div
              key={projectIdx}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.12 }}
            >
              {project.services.map((s, i) => (
                <motion.button
                  key={s.name}
                  onClick={() => setServiceIdx(i)}
                  whileHover={{ x: 2 }}
                  whileTap={{ scale: 0.97 }}
                  transition={{ type: "spring", stiffness: 480, damping: 30 }}
                  className={`flex items-center justify-between w-full px-1 py-1 rounded-sm cursor-pointer transition-colors leading-none ${
                    i === serviceIdx
                      ? "text-foreground/80 bg-muted"
                      : "text-muted-foreground/50 hover:text-muted-foreground/70"
                  }`}
                >
                  <span className="flex items-center gap-1.5 leading-none">
                    <motion.span
                      className="text-green-500/70 text-[8px] leading-none"
                      animate={
                        restarting && i === serviceIdx
                          ? { opacity: [1, 0.2, 1] }
                          : { opacity: 1 }
                      }
                      transition={
                        restarting && i === serviceIdx
                          ? { duration: 0.5, repeat: Infinity }
                          : { duration: 0.2 }
                      }
                    >
                      &#9679;
                    </motion.span>
                    <span className="leading-none">{s.name}</span>
                  </span>
                  <span className="text-muted-foreground/25 leading-none">
                    {s.port}
                  </span>
                </motion.button>
              ))}
            </motion.div>
          </AnimatePresence>
        </div>

        {/* logs panel */}
        <div className="flex-1 px-3 py-2 overflow-hidden">
          <p className="text-muted-foreground/30 text-[10px] mb-1.5 flex items-center justify-between">
            <span>{service.name}</span>
            {query && (
              <span className="text-muted-foreground/40">
                {filteredLogs.length} match
                {filteredLogs.length === 1 ? "" : "es"}
              </span>
            )}
          </p>
          <AnimatePresence mode="wait">
            <motion.div
              key={`${projectIdx}-${serviceIdx}-${restartNonce}-${query}`}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.1 }}
              className="space-y-0.5"
            >
              {displayLogs.length === 0 && (
                <p className="text-muted-foreground/30 text-[11px]">
                  no matching log lines
                </p>
              )}
              {displayLogs.map((log, i) => {
                const shown = query ? true : i < visibleLogs;
                const isRestart = restarting && i === 0;
                return (
                  <motion.div
                    key={`${log.time}-${i}`}
                    initial={{ opacity: 0 }}
                    animate={{ opacity: shown ? 1 : 0 }}
                    transition={{ duration: 0.15 }}
                    className="flex gap-2"
                  >
                    <span className="text-muted-foreground/25 shrink-0">
                      {log.time}
                    </span>
                    <span
                      className={`truncate ${
                        isRestart
                          ? "text-green-500/70"
                          : "text-muted-foreground/60"
                      }`}
                    >
                      {log.text}
                    </span>
                  </motion.div>
                );
              })}
            </motion.div>
          </AnimatePresence>
        </div>
      </div>

      {/* status bar — search field or hints */}
      {searching ? (
        <div className="flex items-center gap-2 px-3 py-1 border-t border-border text-[10px]">
          <span className="text-muted-foreground/50">/</span>
          <input
            ref={searchRef}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="filter logs..."
            className="flex-1 bg-transparent outline-none text-foreground/80 placeholder:text-muted-foreground/30 text-[10px]"
          />
          <span className="text-muted-foreground/40">
            <kbd className="text-muted-foreground/40">esc</kbd> close
          </span>
        </div>
      ) : (
        <div className="flex items-center gap-3 px-3 py-1 border-t border-border text-[10px] text-muted-foreground/25">
          <span>
            <kbd className="text-muted-foreground/40">&#8593;&#8595;</kbd> select
          </span>
          <span>
            <kbd className="text-muted-foreground/40">tab</kbd> switch project
          </span>
          <button
            onClick={openSearch}
            className="cursor-pointer hover:text-muted-foreground/50 transition-colors"
          >
            <kbd className="text-muted-foreground/40">/</kbd> search
          </button>
          <button
            onClick={restart}
            className="cursor-pointer hover:text-muted-foreground/50 transition-colors"
          >
            <kbd className="text-muted-foreground/40">r</kbd> restart
          </button>
        </div>
      )}
    </div>
  );
}

export default TuiPreview;
