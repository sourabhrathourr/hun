"use client";

import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { useState } from "react";

/**
 * ArchitectureAccordion — Daytona-style principle list.
 *
 * Four collapsed rows; opening one reveals its explanation plus a small
 * generative SVG illustration specific to the concept:
 *   daemon model      → breathing concentric rings (the always-on core)
 *   log capture       → ring buffer with a sweeping write head
 *   port leases       → a lease highlight moving across port numbers
 *   state persistence → a timeline whose dots stay lit through a sleep gap
 *
 * Greys + the existing green-500 status accent only. All illustrations go
 * static under prefers-reduced-motion.
 */

const EASE_OUT = [0.25, 1, 0.5, 1] as const;

function DaemonRings({ still }: { still: boolean }) {
  return (
    <svg viewBox="0 0 200 120" className="h-full w-full" aria-hidden>
      <circle cx="100" cy="60" r="4" className="fill-green-500/80" />
      {[18, 34, 50].map((r, i) => (
        <motion.circle
          key={r}
          cx="100"
          cy="60"
          r={r}
          fill="none"
          strokeWidth="1"
          className="stroke-muted-foreground/30"
          animate={still ? undefined : { opacity: [0.5, 1, 0.5], scale: [1, 1.06, 1] }}
          style={{ transformOrigin: "100px 60px" }}
          transition={{
            duration: 4,
            repeat: Infinity,
            ease: "easeInOut",
            delay: i * 0.5,
          }}
        />
      ))}
    </svg>
  );
}

function RingBuffer({ still }: { still: boolean }) {
  const SEGMENTS = 12;
  return (
    <svg viewBox="0 0 200 120" className="h-full w-full" aria-hidden>
      <g style={{ transformOrigin: "100px 60px" }}>
        {Array.from({ length: SEGMENTS }, (_, i) => {
          const angle = (i / SEGMENTS) * Math.PI * 2 - Math.PI / 2;
          const x1 = 100 + Math.cos(angle) * 30;
          const y1 = 60 + Math.sin(angle) * 30;
          const x2 = 100 + Math.cos(angle) * 42;
          const y2 = 60 + Math.sin(angle) * 42;
          return (
            <motion.line
              key={i}
              x1={x1}
              y1={y1}
              x2={x2}
              y2={y2}
              strokeWidth="2.5"
              strokeLinecap="round"
              className="stroke-muted-foreground/40"
              animate={still ? undefined : { opacity: [0.25, 1, 0.25] }}
              transition={{
                duration: 3,
                repeat: Infinity,
                ease: "linear",
                delay: (i / SEGMENTS) * 3,
              }}
            />
          );
        })}
      </g>
      <text
        x="100"
        y="64"
        textAnchor="middle"
        className="fill-muted-foreground/50 font-mono text-[9px]"
      >
        ring buffer
      </text>
    </svg>
  );
}

function PortLeases({ still }: { still: boolean }) {
  const ports = [":3000", ":8000", ":5432"];
  return (
    <svg viewBox="0 0 200 120" className="h-full w-full" aria-hidden>
      {!still && (
        <motion.rect
          x="30"
          y="30"
          width="56"
          height="20"
          rx="3"
          className="fill-muted/60"
          animate={{ y: [30, 52, 74, 52, 30] }}
          transition={{ duration: 6, repeat: Infinity, ease: "easeInOut" }}
        />
      )}
      {still && (
        <rect x="30" y="30" width="56" height="20" rx="3" className="fill-muted/60" />
      )}
      {ports.map((p, i) => (
        <text
          key={p}
          x="38"
          y={44 + i * 22}
          className="fill-muted-foreground/70 font-mono text-[11px]"
        >
          {p}
        </text>
      ))}
      <text
        x="120"
        y="44"
        className="fill-green-500/60 font-mono text-[9px]"
      >
        leased
      </text>
      <text x="120" y="66" className="fill-muted-foreground/40 font-mono text-[9px]">
        free
      </text>
      <text x="120" y="88" className="fill-muted-foreground/40 font-mono text-[9px]">
        free
      </text>
    </svg>
  );
}

function PersistDots({ still }: { still: boolean }) {
  const dots = Array.from({ length: 9 }, (_, i) => 24 + i * 19);
  return (
    <svg viewBox="0 0 200 120" className="h-full w-full" aria-hidden>
      {/* the sleep gap */}
      <rect
        x="82"
        y="30"
        width="36"
        height="60"
        rx="4"
        className="fill-muted/30"
      />
      <text
        x="100"
        y="26"
        textAnchor="middle"
        className="fill-muted-foreground/40 font-mono text-[8px]"
      >
        laptop closed
      </text>
      <line
        x1="16"
        y1="60"
        x2="184"
        y2="60"
        strokeWidth="1"
        className="stroke-muted-foreground/20"
      />
      {dots.map((x, i) => (
        <motion.circle
          key={x}
          cx={x}
          cy="60"
          r="3.5"
          className="fill-green-500/70"
          animate={still ? undefined : { opacity: [0.4, 1, 0.4] }}
          transition={{
            duration: 2.4,
            repeat: Infinity,
            ease: "easeInOut",
            delay: i * 0.15,
          }}
        />
      ))}
    </svg>
  );
}

type Principle = {
  title: string;
  body: string;
  Illustration: React.ComponentType<{ still: boolean }>;
};

const PRINCIPLES: Principle[] = [
  {
    title: "daemon model",
    body: "a lightweight background process owns every service. the cli, tui, and menu bar app are all thin clients talking to it — close them, the daemon keeps running. protocol-versioned, self-recovering from stale locks and dead sockets.",
    Illustration: DaemonRings,
  },
  {
    title: "log capture",
    body: "every service's output lands in an in-memory ring buffer for instant access, and rotates to disk for history. logs are captured whether you're watching or not — nothing scrolls away into a dead terminal tab.",
    Illustration: RingBuffer,
  },
  {
    title: "port leases",
    body: "ports are tracked per service and leased before a process starts, so two services never race for the same port. in multitask mode, genuine collisions get an automatic offset and PORT is injected into every service's env.",
    Illustration: PortLeases,
  },
  {
    title: "state persistence",
    body: "projects, selected services, and log scope survive daemon restarts and upgrades. close your laptop, come back — everything's still there, exactly where you left it.",
    Illustration: PersistDots,
  },
];

export function ArchitectureAccordion({ className = "" }: { className?: string }) {
  const [open, setOpen] = useState(0);
  const reduce = useReducedMotion();
  const still = !!reduce;

  return (
    <div className={`divide-y divide-border border-y border-border ${className}`}>
      {PRINCIPLES.map((p, i) => {
        const isOpen = i === open;
        return (
          <div key={p.title}>
            <button
              onClick={() => setOpen(i)}
              aria-expanded={isOpen}
              className="group flex w-full cursor-pointer items-center justify-between py-4 text-left transition-colors"
            >
              <span
                className={`text-title transition-colors ${
                  isOpen
                    ? "text-foreground"
                    : "text-muted-foreground/60 group-hover:text-muted-foreground"
                }`}
              >
                {p.title}
              </span>
              <motion.span
                animate={{ rotate: isOpen ? 45 : 0 }}
                transition={{ duration: 0.3, ease: EASE_OUT }}
                className={`font-mono text-lead transition-colors ${
                  isOpen
                    ? "text-foreground/70"
                    : "text-muted-foreground/40 group-hover:text-muted-foreground/70"
                }`}
                aria-hidden
              >
                +
              </motion.span>
            </button>
            <AnimatePresence initial={false}>
              {isOpen && (
                <motion.div
                  initial={reduce ? false : { height: 0, opacity: 0 }}
                  animate={{ height: "auto", opacity: 1 }}
                  exit={reduce ? undefined : { height: 0, opacity: 0 }}
                  transition={{ duration: 0.4, ease: EASE_OUT }}
                  className="overflow-hidden"
                >
                  <div className="grid gap-6 pb-6 sm:grid-cols-[1fr_200px] sm:gap-10">
                    <p className="max-w-lg text-body text-muted-foreground">
                      {p.body}
                    </p>
                    <div className="h-[120px] w-full max-w-[200px] rounded-sm border border-terminal-border bg-terminal">
                      <p.Illustration still={still} />
                    </div>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
          </div>
        );
      })}
    </div>
  );
}

export default ArchitectureAccordion;
