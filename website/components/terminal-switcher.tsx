"use client";

import { motion, AnimatePresence } from "framer-motion";
import { useCallback, useEffect, useRef, useState } from "react";

/**
 * TerminalSwitcher — hero interaction.
 *
 * Two project tabs (letraz / novara). Clicking the inactive tab plays an
 * animated `hun switch` sequence: the current project's services stop and
 * free their ports, the new project's services start, then logs stream.
 *
 * Self-contained: renders with zero props. Pass `projects` to override the
 * demo data (exactly two projects work best for the tab interaction).
 *
 * Built on the same idea as components/terminal.tsx, but data-driven around
 * a real switch transition rather than three unrelated canned sequences.
 */

export type SwitcherService = {
  name: string;
  /** Port number as a string, e.g. "3000". Omit for portless services. */
  port?: string;
};

export type SwitcherProject = {
  name: string;
  services: SwitcherService[];
};

type Line = {
  type: "cmd" | "stop" | "start" | "ok" | "log";
  text: string;
};

const DEFAULT_PROJECTS: SwitcherProject[] = [
  {
    name: "letraz",
    services: [
      { name: "next-dev", port: "3000" },
      { name: "thumbnail", port: "4000" },
      { name: "backend", port: "8000" },
      { name: "postgres", port: "5432" },
    ],
  },
  {
    name: "novara",
    services: [
      { name: "frontend", port: "3000" },
      { name: "backend", port: "8000" },
      { name: "worker" },
      { name: "compose", port: "5432" },
    ],
  },
];

const LOG_POOL = [
  "compiled in 184ms",
  "GET /health 200 3ms",
  "listening",
  "ready",
  "connection authorized",
];

function buildSequence(
  from: SwitcherProject | null,
  to: SwitcherProject
): Line[] {
  const lines: Line[] = [{ type: "cmd", text: `hun switch ${to.name}` }];

  if (from) {
    lines.push({ type: "stop", text: `stopping ${from.name}...` });
    for (const s of from.services) {
      lines.push({
        type: "stop",
        text: s.port
          ? `  stopped ${s.name}  :${s.port} freed`
          : `  stopped ${s.name}`,
      });
    }
  }

  lines.push({ type: "start", text: `starting ${to.name}` });
  for (const s of to.services) {
    lines.push({
      type: "start",
      text: s.port
        ? `  starting ${s.name} on :${s.port}`
        : `  starting ${s.name}`,
    });
  }

  lines.push({
    type: "ok",
    text: `✓ ${to.name} ready — ${to.services.length} services`,
  });

  to.services.slice(0, 3).forEach((s, i) => {
    lines.push({ type: "log", text: `[${s.name}] ${LOG_POOL[i % LOG_POOL.length]}` });
  });

  return lines;
}

const LINE_CLASS: Record<Line["type"], string> = {
  cmd: "text-foreground/90",
  stop: "text-muted-foreground/45",
  start: "text-foreground/70",
  ok: "text-green-500/80",
  log: "text-muted-foreground/40",
};

export function TerminalSwitcher({
  projects = DEFAULT_PROJECTS,
  className = "",
  glass = false,
}: {
  projects?: SwitcherProject[];
  className?: string;
  /**
   * Translucent panel + backdrop blur. Only meaningful where the component
   * sits over a textured/glowing background (the hero); leave off on flat
   * sections — there's nothing behind them to blur.
   */
  glass?: boolean;
}) {
  const [active, setActive] = useState(0);
  const [lines, setLines] = useState<Line[]>(() =>
    buildSequence(null, projects[0])
  );
  const [visible, setVisible] = useState(0);
  // reset the reveal counter during render when a new sequence starts,
  // rather than synchronously inside the stagger effect
  const [prevLines, setPrevLines] = useState(lines);
  if (prevLines !== lines) {
    setPrevLines(lines);
    setVisible(0);
  }
  const scrollRef = useRef<HTMLDivElement>(null);

  const switchTo = useCallback(
    (i: number) => {
      if (i === active) return;
      setLines(buildSequence(projects[active], projects[i]));
      setActive(i);
    },
    [active, projects]
  );

  // stagger lines in whenever the sequence changes
  useEffect(() => {
    const timers: ReturnType<typeof setTimeout>[] = [];
    lines.forEach((_, i) => {
      timers.push(setTimeout(() => setVisible(i + 1), (i + 1) * 130));
    });
    return () => timers.forEach(clearTimeout);
  }, [lines]);

  // keep the newest line in view
  useEffect(() => {
    const el = scrollRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [visible]);

  return (
    <div className={className}>
      <div className="flex gap-2 mb-3">
        {projects.map((p, i) => (
          <motion.button
            key={p.name}
            onClick={() => switchTo(i)}
            aria-pressed={i === active}
            whileHover={{ y: -1 }}
            whileTap={{ scale: 0.96 }}
            transition={{ type: "spring", stiffness: 480, damping: 26 }}
            className={`flex items-center gap-1.5 text-caption px-2.5 py-1 rounded-sm transition-colors cursor-pointer ${
              i === active
                ? "bg-muted text-foreground/80"
                : "text-muted-foreground/50 hover:text-muted-foreground"
            }`}
          >
            <span
              className={`text-[8px] leading-none ${
                i === active ? "text-green-500/70" : "text-muted-foreground/30"
              }`}
            >
              &#9679;
            </span>
            {p.name}
          </motion.button>
        ))}
      </div>

      <div
        ref={scrollRef}
        className={`${
          glass
            ? "bg-terminal/65 backdrop-blur-md shadow-[0_24px_64px_-32px_rgba(0,0,0,0.85)]"
            : "bg-terminal"
        } border border-terminal-border rounded-sm px-4 py-3 font-mono text-caption h-auto sm:h-[300px] overflow-y-auto`}
      >
        <AnimatePresence mode="wait">
          <motion.div
            key={active}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.15 }}
          >
            {lines.map((line, i) => (
              <motion.div
                key={i}
                initial={{ opacity: 0 }}
                animate={{ opacity: i < visible ? 1 : 0 }}
                transition={{ duration: 0.18 }}
                className={LINE_CLASS[line.type]}
              >
                {line.type === "cmd" && (
                  <span className="text-muted-foreground/40">$ </span>
                )}
                {line.text}
              </motion.div>
            ))}
          </motion.div>
        </AnimatePresence>
      </div>
    </div>
  );
}

export default TerminalSwitcher;
