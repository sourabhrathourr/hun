"use client";

import { motion, AnimatePresence } from "framer-motion";
import { useState, useEffect } from "react";

const sequences = [
  {
    label: "focus mode",
    lines: [
      { type: "cmd" as const, text: "hun switch letraz" },
      { type: "out" as const, text: "stopping novara..." },
      { type: "out" as const, text: "stopping frontend, backend, worker, compose" },
      { type: "out" as const, text: "starting next-dev on :3000" },
      { type: "out" as const, text: "starting thumbnail on :4000" },
      { type: "out" as const, text: "starting backend on :8000" },
      { type: "out" as const, text: "starting postgres on :5432" },
      { type: "out" as const, text: "all services healthy" },
      { type: "ok" as const, text: "\u2713 letraz ready \u2014 4 services" },
    ],
  },
  {
    label: "multitask mode",
    lines: [
      { type: "cmd" as const, text: "hun run novara" },
      { type: "out" as const, text: "letraz still running (4 services)" },
      { type: "out" as const, text: "starting frontend on :3000 \u2192 :4000" },
      { type: "out" as const, text: "starting backend on :8000 \u2192 :9000" },
      { type: "out" as const, text: "starting worker" },
      { type: "out" as const, text: "starting docker compose (db, redis, rabbitmq)" },
      { type: "out" as const, text: "all services healthy" },
      { type: "out" as const, text: "port offsets applied: +1000" },
      { type: "ok" as const, text: "\u2713 novara ready \u2014 4 services" },
    ],
  },
  {
    label: "status",
    lines: [
      { type: "cmd" as const, text: "hun status" },
      { type: "ok" as const, text: "\u25cf letraz" },
      { type: "out" as const, text: "  next-dev    :3000  running" },
      { type: "out" as const, text: "  thumbnail   :4000  running" },
      { type: "out" as const, text: "  backend     :8000  running" },
      { type: "out" as const, text: "  postgres    :5432  running" },
      { type: "ok" as const, text: "\u25cf novara" },
      { type: "out" as const, text: "  frontend    :4000  running" },
      { type: "out" as const, text: "  backend     :9000  running" },
    ],
  },
];

export function Terminal() {
  const [active, setActive] = useState(0);
  const [visibleLines, setVisibleLines] = useState(0);

  const seq = sequences[active];

  useEffect(() => {
    setVisibleLines(0);
    const timers: NodeJS.Timeout[] = [];
    seq.lines.forEach((_, i) => {
      timers.push(setTimeout(() => setVisibleLines(i + 1), (i + 1) * 200));
    });
    return () => timers.forEach(clearTimeout);
  }, [active, seq.lines]);

  return (
    <div>
      <div className="flex gap-2 mb-3">
        {sequences.map((s, i) => (
          <button
            key={s.label}
            onClick={() => setActive(i)}
            className={`text-[11px] px-2 py-0.5 rounded-sm transition-colors cursor-pointer ${
              i === active
                ? "bg-muted text-foreground/80"
                : "text-muted-foreground/50 hover:text-muted-foreground"
            }`}
          >
            {s.label}
          </button>
        ))}
      </div>
      <div className="bg-[#12110f] border border-[#1f1d1a] rounded-sm px-4 py-3 pb-5 sm:pb-3 font-mono text-[13px] leading-relaxed h-auto sm:h-[220px]">
        <AnimatePresence mode="wait">
          <motion.div
            key={active}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.15 }}
          >
            {seq.lines.map((line, i) => (
              <motion.div
                key={i}
                initial={{ opacity: 0 }}
                animate={{ opacity: i < visibleLines ? 1 : 0 }}
                transition={{ duration: 0.2 }}
                className={
                  line.type === "cmd"
                    ? "text-foreground/80"
                    : line.type === "ok"
                      ? "text-foreground/60"
                      : "text-muted-foreground/60"
                }
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
