"use client";

import { motion, AnimatePresence } from "framer-motion";
import { useState, useEffect, useCallback, useRef } from "react";

type Service = {
  name: string;
  port: string;
};

type Project = {
  name: string;
  services: Service[];
  logs: Record<string, { time: string; text: string }[]>;
};

const projects: Project[] = [
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
      { name: "frontend", port: ":3000" },
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

export function MiniTui() {
  const [projectIdx, setProjectIdx] = useState(0);
  const [serviceIdx, setServiceIdx] = useState(0);
  const [visibleLogs, setVisibleLogs] = useState(0);
  const containerRef = useRef<HTMLDivElement>(null);

  const project = projects[projectIdx];
  const service = project.services[serviceIdx];
  const currentLogs = project.logs[service.name] || [];

  // animate logs in when service or project changes
  useEffect(() => {
    setVisibleLogs(0);
    const timers = currentLogs.map((_, i) =>
      setTimeout(() => setVisibleLogs(i + 1), 80 + i * 120)
    );
    return () => timers.forEach(clearTimeout);
  }, [projectIdx, serviceIdx, currentLogs]);

  const switchProject = useCallback(
    (idx: number) => {
      if (idx !== projectIdx) {
        setProjectIdx(idx);
        setServiceIdx(0);
      }
    },
    [projectIdx]
  );

  // keyboard nav
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;

    const handler = (e: KeyboardEvent) => {
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
        const next = (projectIdx + 1) % projects.length;
        switchProject(next);
      }
    };

    el.addEventListener("keydown", handler);
    return () => el.removeEventListener("keydown", handler);
  }, [projectIdx, switchProject]);

  return (
    <div
      ref={containerRef}
      tabIndex={0}
      className="bg-[#12110f] border border-[#1f1d1a] rounded-sm text-[12px] font-mono overflow-hidden outline-none focus:ring-1 focus:ring-[#2a2825]"
    >
      {/* top bar */}
      <div className="flex items-center justify-between px-3 py-1.5 border-b border-border">
        <div className="flex items-center gap-1">
          <span className="text-foreground/70 text-[11px] font-bold mr-1">
            hun
          </span>
          {projects.map((p, i) => (
            <button
              key={p.name}
              onClick={() => switchProject(i)}
              className={`text-[11px] px-1.5 py-0 rounded-sm cursor-pointer transition-colors ${
                i === projectIdx
                  ? "text-foreground/70 bg-muted"
                  : "text-muted-foreground/30 hover:text-muted-foreground/50"
              }`}
            >
              {p.name}
            </button>
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
                <button
                  key={s.name}
                  onClick={() => setServiceIdx(i)}
                  className={`flex items-center justify-between w-full px-1 py-0.5 rounded-sm cursor-pointer transition-colors ${
                    i === serviceIdx
                      ? "text-foreground/80 bg-muted"
                      : "text-muted-foreground/50 hover:text-muted-foreground/70"
                  }`}
                >
                  <span className="flex items-center gap-1.5">
                    <span className="text-green-500/70 text-[8px]">
                      &#9679;
                    </span>
                    {s.name}
                  </span>
                  <span className="text-muted-foreground/25">{s.port}</span>
                </button>
              ))}
            </motion.div>
          </AnimatePresence>
        </div>

        {/* logs panel */}
        <div className="flex-1 px-3 py-2 overflow-hidden">
          <p className="text-muted-foreground/30 text-[10px] mb-1.5">
            {service.name}
          </p>
          <AnimatePresence mode="wait">
            <motion.div
              key={`${projectIdx}-${serviceIdx}`}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.1 }}
              className="space-y-0.5"
            >
              {currentLogs.map((log, i) => (
                <motion.div
                  key={i}
                  initial={{ opacity: 0 }}
                  animate={{ opacity: i < visibleLogs ? 1 : 0 }}
                  transition={{ duration: 0.15 }}
                  className="flex gap-2"
                >
                  <span className="text-muted-foreground/25 shrink-0">
                    {log.time}
                  </span>
                  <span className="text-muted-foreground/60 truncate">
                    {log.text}
                  </span>
                </motion.div>
              ))}
            </motion.div>
          </AnimatePresence>
        </div>
      </div>

      {/* status bar */}
      <div className="flex items-center gap-3 px-3 py-1 border-t border-border text-[10px] text-muted-foreground/25">
        <span>
          <kbd className="text-muted-foreground/40">&#8593;&#8595;</kbd> select
        </span>
        <span>
          <kbd className="text-muted-foreground/40">tab</kbd> switch project
        </span>
        <span>
          <kbd className="text-muted-foreground/40">/</kbd> search
        </span>
        <span>
          <kbd className="text-muted-foreground/40">r</kbd> restart
        </span>
      </div>
    </div>
  );
}
