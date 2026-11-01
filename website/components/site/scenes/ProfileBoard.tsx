"use client";

// Profiles section: orbit's profiles in a window that fills the tray. The
// profiles sit in a sidebar; the services are tiles, the backend drawn with
// its dependency lines. Picking a profile stops and starts only the
// difference, postgres first. It cycles on its own until someone picks one.

import { useCallback, useEffect, useRef, useState } from "react";
import { MONO, T, UI } from "../hun-window/HunWindow";
import { EASE, Fit, Styles, useOnScreen, useReducedMotion, useShot } from "./shared";

type Svc = "app" | "server" | "worker" | "postgres";
type Status = "running" | "starting" | "stopped";
type Profile = "all" | "ui" | "api";

const SERVICES: Record<Svc, { cmd: string; port?: number; deps: Svc[] }> = {
  app: { cmd: "npm run dev", port: 3000, deps: [] },
  server: { cmd: "uv run server", port: 8000, deps: ["postgres"] },
  worker: { cmd: "uv run worker", deps: ["postgres"] },
  postgres: { cmd: "docker compose up postgres", port: 5432, deps: [] },
};

const PROFILES: { id: Profile; name: string; runs: Svc[]; note: string }[] = [
  { id: "all", name: "All services", runs: ["app", "server", "worker", "postgres"], note: "everything" },
  { id: "ui", name: "ui", runs: ["app"], note: "just the frontend" },
  { id: "api", name: "api", runs: ["server", "worker", "postgres"], note: "postgres comes along" },
];

const CYCLE: Profile[] = ["api", "ui", "all"];
const ALL: Svc[] = ["postgres", "server", "worker", "app"];

function useProfiles(settled: boolean) {
  const [profile, setProfile] = useState<Profile>(settled ? "api" : "all");
  const [status, setStatus] = useState<Record<Svc, Status>>(() =>
    settled
      ? { app: "stopped", server: "running", worker: "running", postgres: "running" }
      : { app: "running", server: "running", worker: "running", postgres: "running" },
  );
  const [summary, setSummary] = useState("All services running");
  const timers = useRef<number[]>([]);

  const clear = () => {
    timers.current.forEach((id) => window.clearTimeout(id));
    timers.current = [];
  };

  const pick = useCallback(
    (next: Profile, instant: boolean) => {
      clear();
      setProfile(next);
      const want = new Set(PROFILES.find((p) => p.id === next)!.runs);
      setStatus((prev) => {
        const stopped = ALL.filter((s) => prev[s] !== "stopped" && !want.has(s));
        const started = ALL.filter((s) => prev[s] === "stopped" && want.has(s));
        const name = PROFILES.find((p) => p.id === next)!.name;
        const parts = [
          started.length ? `started ${started.join(", ")}` : "",
          stopped.length ? `stopped ${stopped.join(", ")}` : "",
        ].filter(Boolean);
        setSummary(parts.length ? `Switched to ${name}: ${parts.join(" · ")}` : `${name}: nothing to change`);

        const out = { ...prev };
        stopped.forEach((s) => (out[s] = "stopped"));
        if (instant) {
          started.forEach((s) => (out[s] = "running"));
          return out;
        }
        // Dependency waves: anything whose dependencies are up starts first.
        const waves: Svc[][] = [];
        const placed = new Set(ALL.filter((s) => out[s] === "running"));
        let left = [...started];
        while (left.length) {
          const wave = left.filter((s) => SERVICES[s].deps.every((d) => placed.has(d) || !want.has(d)));
          const now = wave.length ? wave : left;
          waves.push(now);
          now.forEach((s) => placed.add(s));
          left = left.filter((s) => !now.includes(s));
        }
        waves.forEach((wave, i) => {
          timers.current.push(
            window.setTimeout(() => setStatus((p) => ({ ...p, ...Object.fromEntries(wave.map((s) => [s, "starting"])) })), 120 + i * 520),
            window.setTimeout(() => setStatus((p) => ({ ...p, ...Object.fromEntries(wave.map((s) => [s, "running"])) })), 120 + i * 520 + 460),
          );
        });
        return out;
      });
    },
    [],
  );

  useEffect(() => clear, []);
  return { profile, status, summary, pick };
}

export function ProfileBoard() {
  const ref = useRef<HTMLDivElement>(null);
  const on = useOnScreen(ref, 0.45);
  const reduced = useReducedMotion();
  const shot = useShot();
  const settled = reduced || shot;
  const { profile, status, summary, pick } = useProfiles(false);
  const [touched, setTouched] = useState(false);
  const [hint, setHint] = useState<Profile | null>(null);
  const step = useRef(0);

  // ?shot shows api, settled.
  useEffect(() => {
    if (shot) pick("api", true);
  }, [shot, pick]);

  // Auto-cycle while on screen, until someone picks a profile themselves.
  useEffect(() => {
    if (!on || touched || settled) return;
    let alive = true;
    const run = () => {
      const next = CYCLE[step.current % CYCLE.length];
      step.current += 1;
      setHint(next);
      window.setTimeout(() => {
        if (!alive) return;
        setHint(null);
        pick(next, false);
      }, 520);
    };
    const first = window.setTimeout(run, 1200);
    const id = window.setInterval(run, 3800);
    return () => {
      alive = false;
      window.clearTimeout(first);
      window.clearInterval(id);
    };
  }, [on, touched, settled, pick]);

  const choose = (p: Profile) => {
    setTouched(true);
    setHint(null);
    pick(p, settled);
  };

  return (
    <div ref={ref} className="hw">
      <Styles />
      <Fit narrowBelow={720} minHeight={480}>
        {(narrow) => <Board narrow={narrow} profile={profile} status={status} summary={summary} hint={hint} onPick={choose} />}
      </Fit>
    </div>
  );
}

function Board({
  narrow,
  profile,
  status,
  summary,
  hint,
  onPick,
}: {
  narrow: boolean;
  profile: Profile;
  status: Record<Svc, Status>;
  summary: string;
  hint: Profile | null;
  onPick: (p: Profile) => void;
}) {
  const W = narrow ? 600 : 1056;
  const running = ALL.filter((s) => status[s] === "running").length;
  return (
    <div className="hs-card sq" style={{ width: W, fontFamily: UI, color: T.text1, background: T.appBg, borderRadius: narrow ? 18 : 14 }}>
      <style>{`
        .pb-item { transition: background-color 160ms ease, box-shadow 160ms ease, color 160ms ease; }
        @media (hover: hover) { .pb-item:not(.on):hover { background: ${T.hover}; } }
        .pb-item:active { transform: scale(.985); }
        .pb-tile { transition: box-shadow 220ms ${EASE}, background-color 220ms ${EASE}; }
        .pb-pulse { animation: pb-pulse 900ms ease-in-out infinite; }
        @keyframes pb-pulse { 50% { opacity: .35; } }
        .pb-line { transition: stroke 260ms ease, opacity 260ms ease; }
        .pb-sum { animation: pb-in 220ms ${EASE}; }
        @keyframes pb-in { from { opacity: 0; transform: translateY(4px); } }
        @media (prefers-reduced-motion: reduce) { .pb-tile, .pb-line, .pb-item { transition: none; } .pb-sum, .pb-pulse { animation: none; } }
      `}</style>

      {/* Title bar */}
      <div style={{ height: 44, display: "flex", alignItems: "center", padding: "0 16px", borderBottom: `1px solid ${T.divider}`, background: T.sidebar }}>
        <span style={{ display: "flex", gap: 8 }} aria-hidden>
          {["#FF5F57", "#FEBC2E", "#28C840"].map((c) => (
            <span key={c} style={{ width: 12, height: 12, borderRadius: 99, background: c, boxShadow: "inset 0 0 0 .5px rgba(0,0,0,.12)" }} />
          ))}
        </span>
        <span style={{ flex: 1, textAlign: "center", fontSize: 13, fontWeight: 600, color: T.text2, letterSpacing: -0.08, marginRight: 52 }}>
          orbit <span style={{ color: T.text3, fontWeight: 500 }}>· profiles</span>
        </span>
      </div>

      <div style={{ display: "flex", flexDirection: narrow ? "column" : "row" }}>
        {/* Profiles */}
        <div
          style={{
            width: narrow ? "auto" : 248,
            flex: "none",
            background: T.sidebar,
            borderRight: narrow ? undefined : `1px solid ${T.divider}`,
            borderBottom: narrow ? `1px solid ${T.divider}` : undefined,
            padding: narrow ? "12px 12px" : "16px 12px",
          }}
        >
          <p style={{ fontSize: 11, fontWeight: 600, color: T.text2, margin: "0 8px 10px", letterSpacing: 0.2, textTransform: "uppercase" }}>Profiles</p>
          <div role="radiogroup" aria-label="Profile" style={{ display: "flex", flexDirection: narrow ? "row" : "column", gap: 4 }}>
            {PROFILES.map((p) => {
              const on = p.id === profile;
              const hinted = p.id === hint;
              return (
                <button
                  key={p.id}
                  type="button"
                  role="radio"
                  aria-checked={on}
                  onClick={() => onPick(p.id)}
                  className={`pb-item ${on ? "on" : ""}`}
                  style={{
                    all: "unset",
                    boxSizing: "border-box",
                    cursor: "default",
                    flex: narrow ? 1 : undefined,
                    display: "flex",
                    alignItems: "center",
                    gap: 8,
                    padding: narrow ? "7px 10px" : "8px 10px",
                    borderRadius: 9,
                    background: on ? T.white : hinted ? T.hover : "transparent",
                    boxShadow: on ? `0 0 0 .5px ${T.dividerStrong}, 0 1px 2px rgba(0,0,0,.05)` : undefined,
                  }}
                >
                  <span style={{ flex: 1, minWidth: 0 }}>
                    <span style={{ display: "block", fontSize: 13.5, fontWeight: 600, color: T.text1, letterSpacing: -0.1 }}>{p.name}</span>
                    {!narrow && <span style={{ display: "block", marginTop: 2, fontSize: 11.5, color: T.text2 }}>{p.note}</span>}
                  </span>
                  {!narrow && (
                    <span style={{ minWidth: 20, height: 20, display: "inline-grid", placeItems: "center", borderRadius: 6, fontSize: 11, fontWeight: 600, color: on ? T.text1 : T.text2, background: on ? "rgba(24,24,22,.06)" : "rgba(24,24,22,.045)", fontVariantNumeric: "tabular-nums" }}>{p.runs.length}</span>
                  )}
                </button>
              );
            })}
          </div>

          {!narrow && (
            <pre
              aria-hidden
              style={{ margin: "18px 4px 0", padding: "12px 12px", borderTop: `1px solid ${T.divider}`, fontFamily: MONO, fontSize: 11.5, lineHeight: "20px", color: T.text2 }}
            >
              <span style={{ color: T.text2 }}>profiles:</span>
              {"\n"}
              <YamlLine on={profile === "ui"} k="ui" v="[app]" />
              {"\n"}
              <YamlLine on={profile === "api"} k="api" v="[server, worker]" />
            </pre>
          )}
        </div>

        {/* Services */}
        <div style={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column" }}>
          <div style={{ height: 46, display: "flex", alignItems: "center", gap: 6, padding: "0 20px", borderBottom: `1px solid ${T.divider}` }}>
            <span style={{ fontSize: 13, fontWeight: 600, letterSpacing: -0.08 }}>Services</span>
            <span style={{ fontSize: 12, fontWeight: 500, color: T.text2, fontVariantNumeric: "tabular-nums" }}>{running} of 4 running</span>
          </div>
          <TileMap status={status} compact={narrow} />
        </div>
      </div>

      {/* Status line */}
      <div style={{ height: 40, display: "flex", alignItems: "center", padding: "0 20px", borderTop: `1px solid ${T.divider}`, background: T.sidebar }}>
        <span key={summary} className="pb-sum" style={{ fontSize: 12.5, color: T.text1, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
          {summary}
        </span>
      </div>
    </div>
  );
}

function YamlLine({ on, k, v }: { on: boolean; k: string; v: string }) {
  return (
    <span
      style={{
        display: "inline-block",
        margin: "0 -6px",
        padding: "0 6px",
        borderRadius: 4,
        background: on ? "rgba(194,74,31,.12)" : "transparent",
        color: on ? T.text1 : T.text2,
        transition: "background-color 200ms ease, color 200ms ease",
      }}
    >
      {"  "}
      {k}: {v}
    </span>
  );
}

const TILE = { w: 220, h: 92 };
const POS: Record<Svc, { x: number; y: number }> = {
  postgres: { x: 28, y: 128 },
  server: { x: 300, y: 52 },
  worker: { x: 300, y: 204 },
  app: { x: 556, y: 128 },
};

/** The backend drawn as a small dependency map, the frontend apart. Compact is the same map, tighter, for phones. */
function TileMap({ status, compact = false }: { status: Record<Svc, Status>; compact?: boolean }) {
  const tile = compact ? { w: 168, h: 86 } : TILE;
  const pos: Record<Svc, { x: number; y: number }> = compact
    ? { postgres: { x: 16, y: 112 }, server: { x: 222, y: 40 }, worker: { x: 222, y: 184 }, app: { x: 416, y: 112 } }
    : POS;
  const H = compact ? 300 : 352;
  const split = compact ? 404 : 538;
  const from = { x: pos.postgres.x + tile.w, y: pos.postgres.y + tile.h / 2 };
  const to = (s: Svc) => ({ x: pos[s].x, y: pos[s].y + tile.h / 2 });
  const edge = (s: Svc) => {
    const b = to(s);
    const mid = (from.x + b.x) / 2;
    return `M ${from.x} ${from.y} C ${mid} ${from.y}, ${mid} ${b.y}, ${b.x} ${b.y}`;
  };
  const live = (s: Svc) => status.postgres === "running" && status[s] === "running";
  const lineColor = (s: Svc) => (live(s) ? "#3E8C55" : "rgba(35,35,33,.22)");
  return (
    <div style={{ position: "relative", height: H }}>
      <Label style={{ left: pos.postgres.x, top: 16 }}>Backend</Label>
      <Label style={{ left: pos.app.x, top: 16 }}>Frontend</Label>
      <span aria-hidden style={{ position: "absolute", left: split, top: 20, bottom: 20, width: 1, background: T.divider }} />
      <svg aria-hidden width="100%" height={H} style={{ position: "absolute", inset: 0, overflow: "visible" }}>
        {(["server", "worker"] as Svc[]).map((s) => (
          <g key={s} className="pb-line">
            <path d={edge(s)} fill="none" stroke={lineColor(s)} strokeWidth={1.5} strokeLinecap="round" />
            <circle cx={to(s).x} cy={to(s).y} r={3} fill={T.appBg} stroke={lineColor(s)} strokeWidth={1.5} />
          </g>
        ))}
        <circle cx={from.x} cy={from.y} r={3} fill={T.appBg} stroke={status.postgres === "running" ? "#3E8C55" : "rgba(35,35,33,.22)"} strokeWidth={1.5} />
      </svg>
      {(Object.keys(pos) as Svc[]).map((s) => (
        <Tile key={s} id={s} status={status[s]} width={tile.w} height={tile.h} style={{ position: "absolute", left: pos[s].x, top: pos[s].y }} />
      ))}
      <span style={{ position: "absolute", left: pos.postgres.x + 2, top: pos.postgres.y + tile.h + 10, fontSize: 11.5, color: T.text2 }}>
        {compact ? "Starts first." : "Starts first. server and worker need it."}
      </span>
    </div>
  );
}

function Label({ children, style }: { children: React.ReactNode; style: React.CSSProperties }) {
  return (
    <span style={{ position: "absolute", ...style, fontSize: 11, fontWeight: 600, color: T.text2, letterSpacing: 0.2, textTransform: "uppercase" }}>
      {children}
    </span>
  );
}


const PILL: Record<Status, { fg: string; bg: string; ring: string; label: string }> = {
  running: { fg: "#1F6B35", bg: "rgba(39,131,63,.1)", ring: "rgba(39,131,63,.22)", label: "Running" },
  starting: { fg: "#8A5212", bg: "rgba(167,100,24,.1)", ring: "rgba(167,100,24,.24)", label: "Starting" },
  stopped: { fg: "#5C5C57", bg: "rgba(35,35,33,.05)", ring: "rgba(35,35,33,.1)", label: "Stopped" },
};

function Tile({ id, status, style, compact, width, height }: { id: Svc; status: Status; style?: React.CSSProperties; compact?: boolean; width?: number; height?: number }) {
  const svc = SERVICES[id];
  const off = status === "stopped";
  const pill = PILL[status];
  return (
    <div
      className="pb-tile"
      style={{
        ...style,
        width: compact ? "auto" : (width ?? TILE.w),
        height: compact ? 82 : (height ?? TILE.h),
        boxSizing: "border-box",
        padding: compact ? "11px 12px" : "14px 15px",
        borderRadius: 12,
        background: off ? "#FBFBF8" : "#FFFFFF",
        boxShadow: off
          ? "0 0 0 1px rgba(24,24,22,.08)"
          : "0 0 0 .5px rgba(24,24,22,.14), 0 1px 2px rgba(24,24,22,.05), 0 10px 22px -14px rgba(64,44,16,.32)",
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <span style={{ flex: 1, fontSize: 14, fontWeight: 600, letterSpacing: -0.15, color: off ? T.text2 : T.text1 }}>{id}</span>
        {svc.port && !compact && (
          <span style={{ fontFamily: MONO, fontSize: 11.5, fontWeight: 500, color: off ? T.text3 : T.text2, fontVariantNumeric: "tabular-nums" }}>
            :{svc.port}
          </span>
        )}
      </div>
      <p style={{ margin: "5px 0 0", fontFamily: MONO, fontSize: 11.5, color: off ? T.text3 : T.text2, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
        {svc.cmd}
      </p>
      <span
        style={{
          marginTop: 9,
          display: "inline-flex",
          alignItems: "center",
          gap: 5,
          height: 18,
          padding: "0 7px 0 6px",
          borderRadius: 99,
          background: pill.bg,
          boxShadow: `inset 0 0 0 .5px ${pill.ring}`,
          color: pill.fg,
          fontSize: 10.5,
          fontWeight: 600,
          letterSpacing: 0.1,
          transition: "background-color 200ms ease, color 200ms ease",
        }}
      >
        <span
          className={status === "starting" ? "pb-pulse" : undefined}
          style={{ width: 6, height: 6, borderRadius: 99, background: off ? "transparent" : pill.fg, boxShadow: off ? `inset 0 0 0 1.25px ${pill.fg}` : undefined }}
        />
        {pill.label}
      </span>
    </div>
  );
}
