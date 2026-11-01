"use client";

// Docker section: atlas starting, as a timeline in a window that fills the
// tray. Each service is a row; its bar grows from the moment it starts, is
// striped while starting and solid once ready. Docker Desktop goes first,
// then what runs in Docker, then the frontend on the Mac.

import { useEffect, useRef, useState } from "react";
import { MONO, T, UI } from "../hun-window/HunWindow";
import { EASE, Fit, Styles, useOnScreen, useReducedMotion, useShot } from "./shared";

type Row = { id: string; cmd: string; port?: number; start: number; ready: number; group: "docker" | "compose" | "mac" };

const ROWS: Row[] = [
  { id: "Docker Desktop", cmd: "started in the background", start: 0, ready: 1.5, group: "docker" },
  { id: "postgres", cmd: "docker compose up postgres", port: 5432, start: 1.5, ready: 2.5, group: "compose" },
  { id: "redis", cmd: "docker compose up redis", port: 6379, start: 1.5, ready: 2.0, group: "compose" },
  { id: "api", cmd: "docker compose up api", port: 8000, start: 2.5, ready: 3.5, group: "compose" },
  { id: "worker", cmd: "docker compose up worker", start: 2.5, ready: 3.1, group: "compose" },
  { id: "web", cmd: "npm run dev", port: 3000, start: 3.5, ready: 4.7, group: "mac" },
];

const END = 5.4; // seconds shown on the axis
const DONE = 4.7;

const LOG: [number, string][] = [
  [0.05, "Docker isn't running; starting it in the background..."],
  [1.5, "Docker is ready."],
  [2.5, "postgres-1  | database system is ready to accept connections"],
  [3.1, "worker-1  | ready, waiting for jobs"],
  [3.5, "api-1  | Uvicorn running on http://0.0.0.0:8000"],
  [4.7, "web  ✓ Ready in 1.2s on localhost:3000"],
];

/** Time since the scene first came on screen, in seconds, paused off screen. */
function useClock(on: boolean, settled: boolean, runId: number) {
  const [t, setT] = useState(0);
  const acc = useRef(0);
  useEffect(() => {
    acc.current = 0;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setT(0);
  }, [runId]);
  useEffect(() => {
    if (settled) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setT(END);
      return;
    }
    if (!on) return;
    let raf = 0;
    let last = performance.now();
    const tick = (now: number) => {
      acc.current = Math.min(END, acc.current + (now - last) / 1000);
      last = now;
      setT(acc.current);
      if (acc.current < END) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [on, settled, runId]);
  return t;
}

export function StartupTimeline() {
  const ref = useRef<HTMLDivElement>(null);
  const on = useOnScreen(ref, 0.45);
  const reduced = useReducedMotion();
  const shot = useShot();
  const [runId, setRunId] = useState(0);
  const t = useClock(on, reduced || shot, runId);
  return (
    <div ref={ref} className="hw">
      <Styles />
      <Fit narrowBelow={720} minHeight={520}>
        {(narrow) => <Timeline t={t} narrow={narrow} onReplay={reduced || shot ? undefined : () => setRunId((n) => n + 1)} />}
      </Fit>
    </div>
  );
}

function state(r: Row, t: number) {
  return t < r.start ? "stopped" : t < r.ready ? "starting" : "running";
}

function Timeline({ t, narrow, onReplay }: { t: number; narrow: boolean; onReplay?: () => void }) {
  const W = narrow ? 600 : 1056;
  const label = narrow ? 170 : 256;
  const portCol = narrow ? 0 : 96;
  const chart = W - label - portCol - (narrow ? 32 : 56);
  const x = (s: number) => (s / END) * chart;
  const running = ROWS.filter((r) => t >= r.ready && r.group !== "docker").length;
  const log = [...LOG].reverse().find(([at]) => t >= at)?.[1] ?? "~/code/atlas % hun run atlas";
  const finished = t >= DONE;

  const groups: { key: Row["group"]; title: string }[] = [
    { key: "docker", title: "Started for you" },
    { key: "compose", title: "In Docker" },
    { key: "mac", title: "On your Mac" },
  ];

  return (
    <div
      className="hs-card sq"
      style={{ width: W, fontFamily: UI, color: T.text1, background: T.appBg, borderRadius: narrow ? 18 : 14 }}
    >
      {/* Title bar */}
      <div style={{ height: 44, display: "flex", alignItems: "center", padding: "0 16px", borderBottom: `1px solid ${T.divider}`, background: T.sidebar }}>
        <span style={{ display: "flex", gap: 8 }} aria-hidden>
          {["#FF5F57", "#FEBC2E", "#28C840"].map((c) => (
            <span key={c} style={{ width: 12, height: 12, borderRadius: 99, background: c, boxShadow: "inset 0 0 0 .5px rgba(0,0,0,.12)" }} />
          ))}
        </span>
        <span style={{ flex: 1, textAlign: "center", fontSize: 13, fontWeight: 600, color: T.text2, letterSpacing: -0.08 }}>
          atlas <span style={{ color: T.text3, fontWeight: 500 }}>· {finished ? "running" : "starting"}</span>
        </span>
        <span style={{ width: 52, textAlign: "right" }}>
          {onReplay && finished && (
            <button
              type="button"
              onClick={onReplay}
              style={{ all: "unset", cursor: "pointer", fontSize: 12, fontWeight: 500, color: T.text3 }}
              className="hs-replay"
            >
              Replay
            </button>
          )}
        </span>
      </div>

      {/* Axis */}
      <div style={{ display: "flex", alignItems: "flex-end", height: 34, padding: `0 ${narrow ? 16 : 28}px`, borderBottom: `1px solid ${T.divider}` }}>
        <span style={{ width: label, fontSize: 11, fontWeight: 500, color: T.text3, paddingBottom: 8 }}>Service</span>
        <div style={{ position: "relative", width: chart, height: "100%" }}>
          {[0, 1, 2, 3, 4, 5].map((s) => (
            <span
              key={s}
              style={{ position: "absolute", left: x(s), bottom: 8, transform: "translateX(-50%)", fontFamily: MONO, fontSize: 10.5, color: T.text3, fontVariantNumeric: "tabular-nums" }}
            >
              {s}s
            </span>
          ))}
        </div>
        {!narrow && <span style={{ width: portCol, textAlign: "right", fontSize: 11, fontWeight: 500, color: T.text3, paddingBottom: 8 }}>Port</span>}
      </div>

      {/* Rows, grouped */}
      <div style={{ position: "relative", padding: `4px ${narrow ? 16 : 28}px 8px` }}>
        {/* Gridlines and the playhead, across every row. */}
        <div aria-hidden style={{ position: "absolute", top: 0, bottom: 0, left: (narrow ? 16 : 28) + label, width: chart, pointerEvents: "none" }}>
          {[1, 2, 3, 4, 5].map((s) => (
            <span key={s} style={{ position: "absolute", top: 0, bottom: 0, left: x(s), width: 1, background: T.divider }} />
          ))}
          {!finished && t > 0 && (
            <span style={{ position: "absolute", top: 0, bottom: 0, left: x(t), width: 1, background: "rgba(194,74,31,.55)" }} />
          )}
        </div>

        {groups.map((g) => (
          <div key={g.key}>
            <p style={{ position: "relative", fontSize: 11, fontWeight: 600, color: T.text3, margin: narrow ? "8px 0 0" : "10px 0 2px", letterSpacing: 0.1 }}>{g.title}</p>
            {ROWS.filter((r) => r.group === g.key).map((r) => (
              <TimelineRow key={r.id} r={r} t={t} label={label} chart={chart} portCol={portCol} x={x} narrow={narrow} />
            ))}
          </div>
        ))}
      </div>

      {/* Status line: the newest log line */}
      <div style={{ height: 40, display: "flex", alignItems: "center", gap: 12, padding: `0 ${narrow ? 16 : 28}px`, borderTop: `1px solid ${T.divider}`, background: T.sidebar }}>
        <span
          key={log}
          className="hs-logline"
          style={{ flex: 1, minWidth: 0, fontFamily: MONO, fontSize: 11.5, color: T.text2, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}
        >
          {log}
        </span>
        <span style={{ fontSize: 11.5, fontWeight: 500, color: finished ? T.success : T.text3, whiteSpace: "nowrap", fontVariantNumeric: "tabular-nums" }}>
          {finished ? `5 services running · ${DONE.toFixed(1)}s` : `${running} of 5 running`}
        </span>
      </div>
      <style>{`
        .hs-logline { animation: hs-in 220ms ${EASE}; }
        @keyframes hs-in { from { opacity: 0; transform: translateY(4px); } }
        .hs-replay:hover { color: ${T.text1} !important; }
        @media (prefers-reduced-motion: reduce) { .hs-logline { animation: none; } }
      `}</style>
    </div>
  );
}

function TimelineRow({
  r,
  t,
  label,
  chart,
  portCol,
  x,
  narrow,
}: {
  r: Row;
  t: number;
  label: number;
  chart: number;
  portCol: number;
  x: (s: number) => number;
  narrow: boolean;
}) {
  const s = state(r, t);
  const dot = s === "running" ? T.success : s === "starting" ? T.warning : T.text3;
  const startEnd = Math.min(t, r.ready);
  const runEnd = Math.min(t, END);
  const docker = r.group === "docker";
  return (
    <div style={{ display: "flex", alignItems: "center", height: narrow ? 32 : 50 }}>
      <div style={{ width: label, display: "flex", alignItems: "flex-start", gap: 9, minWidth: 0 }}>
        <span style={{ marginTop: narrow ? 0 : 6, alignSelf: narrow ? "center" : undefined, width: 6, height: 6, borderRadius: 99, flex: "none", background: s === "stopped" ? "transparent" : dot, boxShadow: s === "stopped" ? `inset 0 0 0 1.5px ${T.text3}` : undefined, transition: "background-color .16s ease-out" }} />
        <span style={{ minWidth: 0 }}>
          <span style={{ display: "block", fontSize: 13, fontWeight: 600, letterSpacing: -0.08, color: s === "stopped" ? T.text2 : T.text1, whiteSpace: "nowrap" }}>
            {r.id}
            {narrow && r.port && (
              <span style={{ marginLeft: 7, fontFamily: MONO, fontSize: 11, fontWeight: 500, color: s === "running" ? T.text2 : T.text3 }}>:{r.port}</span>
            )}
          </span>
          {narrow ? null : (
            <span style={{ display: "block", marginTop: 2, fontFamily: MONO, fontSize: 11, color: T.text3, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
              {r.cmd}
            </span>
          )}
        </span>
      </div>
      <div style={{ position: "relative", width: chart, height: 18 }}>
        {t > r.start && (
          <span
            style={{
              position: "absolute",
              top: 4,
              height: 10,
              left: x(r.start),
              width: Math.max(2, x(startEnd) - x(r.start)),
              borderRadius: "5px 0 0 5px",
              background: `repeating-linear-gradient(135deg, rgba(167,100,24,.42) 0 3px, rgba(167,100,24,.14) 3px 6px)`,
            }}
          />
        )}
        {t > r.ready && (
          <span
            style={{
              position: "absolute",
              top: 4,
              height: 10,
              left: x(r.ready),
              width: x(runEnd) - x(r.ready),
              borderRadius: "0 5px 5px 0",
              background: docker ? "rgba(98,98,93,.35)" : "rgba(39,131,63,.5)",
            }}
          />
        )}
        {t >= r.ready && (
          <span
            style={{
              position: "absolute",
              top: -10,
              left: x(r.ready) + 4,
              fontFamily: MONO,
              fontSize: 10,
              color: T.text3,
              whiteSpace: "nowrap",
              fontVariantNumeric: "tabular-nums",
            }}
          >
            {docker ? "ready" : `ready ${(r.ready - r.start).toFixed(1)}s`}
          </span>
        )}
      </div>
      {!narrow && (
        <div style={{ width: portCol, display: "flex", justifyContent: "flex-end" }}>
          {r.port && s === "running" ? (
            <span
              style={{
                fontFamily: MONO,
                fontSize: 11,
                fontWeight: 500,
                color: T.text2,
                height: 22,
                display: "inline-flex",
                alignItems: "center",
                padding: "0 7px",
                borderRadius: 6.6,
                background: T.white,
                boxShadow: `0 0 0 .5px ${T.divider}, inset 0 0 0 .5px ${T.divider}`,
              }}
            >
              :{r.port}
            </span>
          ) : (
            <span style={{ fontFamily: MONO, fontSize: 11, color: T.text3 }}>{r.port ? `:${r.port}` : ""}</span>
          )}
        </div>
      )}
    </div>
  );
}
