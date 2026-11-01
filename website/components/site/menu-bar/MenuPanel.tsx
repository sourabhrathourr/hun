"use client";

// Hun's menu bar panel, rebuilt from MenuBarView.swift at its real 340 pt
// width, light appearance: the olive valley vista, today's date and how many
// projects run, and each project with Hun's switch.

import { useEffect, useRef, useState } from "react";
import { PROJECT_LOGOS } from "../logos";
import { Spinner } from "../hun-window/icons";
import { type HunSim, type Mode, type SimProject, type SimState, projectStatus } from "../hun-window/sim";
import { panelDate, useNow } from "./use-now";

export const PANEL_W = 340;

// AppTheme.swift, light (Clay), and MenuBarView.swift's vista panel.
const css = `
.hm { --hm-bg: #FBF8F3; --hm-white: #FFFCF6; --hm-divider: rgba(31,27,22,.07); --hm-dividerStrong: rgba(31,27,22,.12); --hm-hover: rgba(31,27,22,.035); --hm-rowHover: rgba(31,27,22,.03); --hm-text1: #1F1B16; --hm-text2: #4F483F; --hm-text3: #8A8174; --hm-success: #3E7B4F; --hm-danger: #B84040; --hm-ink: #2B2622; }
.hm { -webkit-font-smoothing: antialiased; font-synthesis: none; text-rendering: optimizeLegibility; }
.hm *, .hm *::before, .hm *::after { box-sizing: border-box; }
.hm button { all: unset; box-sizing: border-box; cursor: default; }
.hm .sq { corner-shape: superellipse(1.45); }
.hm button:focus-visible { outline: 2px solid rgba(194,74,31,.55); outline-offset: 1px; }
.hm .mrow:hover { background: var(--hm-rowHover); }
.hm .mrow.on { background: rgba(31,27,22,.05); }
.hm .mrow:hover .mrow-name { color: var(--hm-text1) !important; }
.hm .mib { color: var(--hm-text2); background: var(--hm-white); }
.hm .mib:hover { color: var(--hm-text1); background: var(--hm-hover); }
.hm .port { color: var(--hm-text3); background: rgba(31,27,22,.05); }
.hm .port:hover { color: var(--hm-text1); background: var(--hm-hover); }
.hm .seg { transition: background-color .12s ease-out, color .12s ease-out; }
.hm .sw-track { transition: background-color .25s ease-out; }
.hm .sw-knob { transition: transform .28s cubic-bezier(.34,1.4,.64,1); }
.hm .press:active { opacity: .7; }
.hm .hw-spin { animation: hm-spin 1s steps(8) infinite; }
@keyframes hm-spin { to { transform: rotate(360deg); } }
.hm .tip { animation: hm-tip .14s ease-out; }
@keyframes hm-tip { from { opacity: 0; transform: translateY(-2px); } to { opacity: 1; transform: none; } }
.hm .count { transition: opacity .2s ease-out; }
@media (prefers-reduced-motion: reduce) {
  .hm .seg, .hm .sw-track, .hm .sw-knob { transition: none; }
  .hm .tip { animation: none; }
}
`;

const UI = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';
const MONO = 'ui-monospace, "SF Mono", SFMono-Regular, Menlo, monospace';
const ROUNDED = 'ui-rounded, "SF Pro Rounded", -apple-system, BlinkMacSystemFont, system-ui, sans-serif';

/** The panel's default vista in light mode: the olive valley. */
export const MENU_VISTA = "/site/bg/pricing-hero.jpg";

type Pending = SimProject["pending"];

/** HunActionKind.statusText */
const pendingText = (p: Pending) => (p === "stop" ? "Stopping..." : p === "restart" ? "Restarting..." : "Starting...");

export interface MenuPanelProps {
  sim: HunSim;
  state: SimState;
  /** The panel window's chrome: corners and shadow. */
  chrome?: boolean;
  onOpenHun?: () => void;
  onRun?: (p: SimProject) => void;
  onModeChange?: (m: Mode) => void;
}

export function MenuPanel({ sim, state, chrome = true, onOpenHun, onRun, onModeChange }: MenuPanelProps) {
  const projects = [...state.projects].sort((a, b) => a.name.localeCompare(b.name, undefined, { numeric: true }));
  const running = projects.filter((p) => projectStatus(p) !== "stopped" || p.pending === "stop");
  const others = projects.filter((p) => !running.includes(p));
  const ordered = [...running, ...others];

  return (
    <div
      className="hm sq"
      style={{
        position: "relative",
        width: PANEL_W,
        fontFamily: UI,
        color: "var(--hm-text1)",
        userSelect: "none",
        WebkitUserSelect: "none",
        lineHeight: "normal",
        textAlign: "left",
        borderRadius: 26,
        overflow: "hidden",
        backgroundColor: "#E9DCC6",
        backgroundImage: `url(${MENU_VISTA})`,
        backgroundSize: "cover",
        backgroundPosition: "35% 45%",
        ...(chrome
          ? { boxShadow: "inset 0 0 0 1px rgba(0,0,0,.12), 0 0 0 .5px rgba(0,0,0,.06), 0 14px 40px rgba(0,0,0,.2), 0 2px 6px rgba(0,0,0,.06)" }
          : null),
      }}
    >
      <style>{css}</style>
      {/* MenuDoorwayView's saturation(0.82): a little less warmth. */}
      <div aria-hidden style={{ position: "absolute", inset: 0, background: "rgba(255,255,255,.08)", mixBlendMode: "saturation", pointerEvents: "none" }} />
      <MenuSky running={running} mode={state.mode} />
      <div style={{ height: 56 }} />
      <div
        className="sq"
        style={{
          position: "relative",
          margin: 10,
          borderRadius: 16,
          overflow: "hidden",
          background: "rgba(251,248,243,.95)",
          backdropFilter: "blur(20px)",
          WebkitBackdropFilter: "blur(20px)",
          boxShadow: "inset 0 0 0 1px var(--hm-divider)",
        }}
      >
        <div style={{ padding: 6, display: "flex", flexDirection: "column", gap: 2 }}>
          {ordered.map((p) => (
            <MenuSwitchRow
              key={p.id}
              project={p}
              onRun={() => (onRun ? onRun(p) : sim.run(p.id))}
              onStop={() => sim.stop(p.id)}
            />
          ))}
        </div>
        <div style={{ height: 1, background: "var(--hm-divider)" }} />
        <MenuSillFooter
          mode={state.mode}
          pending={state.modePending}
          onMode={(m) => (onModeChange ? onModeChange(m) : sim.setMode(m))}
          onOpenHun={onOpenHun}
        />
      </div>
    </div>
  );
}

// MARK: - Sky

function MenuSky({ running, mode }: { running: SimProject[]; mode: Mode }) {
  const now = useNow();
  const focused = mode === "focus" ? running[0] : undefined;
  const services = focused ? focused.services.filter((s) => s.status === "running").length : 0;
  const ink = "var(--hm-ink)";
  return (
    <div style={{ position: "relative", height: 170, marginTop: 30, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center" }}>
      <div style={{ fontSize: 12.5, fontWeight: 600, color: ink, opacity: 0.7 }}>
        {focused ? "Focused on" : panelDate(now)}
      </div>
      {focused ? (
        <div style={{ fontFamily: ROUNDED, fontSize: 46, fontWeight: 600, color: ink, opacity: 0.8, lineHeight: 1.1, padding: "8px 24px" }}>{focused.name}</div>
      ) : (
        <div className="count" aria-live="polite" style={{ fontFamily: ROUNDED, fontSize: 88, fontWeight: 600, color: ink, opacity: 0.78, lineHeight: 1, marginTop: 2 }}>
          {running.length}
        </div>
      )}
      <div style={{ marginTop: focused ? -2 : 0, fontSize: 13, fontWeight: 500, color: ink, opacity: 0.72 }}>
        {focused ? (services === 1 ? "1 service running" : `${services} services running`) : running.length === 0 ? "all quiet" : "running"}
      </div>
    </div>
  );
}

// MARK: - Rows

function MenuSwitchRow({ project, onRun, onStop }: { project: SimProject; onRun: () => void; onStop: () => void }) {
  const status = projectStatus(project);
  const on = status !== "stopped" || project.pending === "start";
  const busy = project.pending !== null;
  const ports = project.services.filter((s) => s.status === "running" && s.port > 0).sort((a, b) => a.port - b.port);

  return (
    <div
      className={`mrow sq ${on ? "on" : ""}`}
      style={{ padding: "6px 8px", display: "flex", alignItems: "center", gap: 10, borderRadius: 12 }}
    >
      <LetterTile name={project.name} dim={!on} />
      <div style={{ minWidth: 0, display: "flex", flexDirection: "column", gap: 2 }}>
        <div
          className="mrow-name"
          style={{
            fontSize: 13,
            lineHeight: "16px",
            fontWeight: on ? 600 : 400,
            color: on ? "var(--hm-text1)" : "var(--hm-text2)",
            whiteSpace: "nowrap",
            overflow: "hidden",
            textOverflow: "ellipsis",
          }}
        >
          {project.name}
        </div>
        {project.pending ? (
          <div style={{ fontSize: 11, lineHeight: "14px", color: "var(--hm-text3)" }}>{pendingText(project.pending)}</div>
        ) : on && ports.length > 0 ? (
          <div style={{ display: "flex", gap: 4 }}>
            {ports.slice(0, 3).map((s) => (
              <MenuPortLink key={s.id} port={s.port} service={s.name} />
            ))}
            {ports.length > 3 && <span style={{ fontSize: 10.5, color: "var(--hm-text3)" }}>+{ports.length - 3}</span>}
          </div>
        ) : null}
      </div>
      <div style={{ flex: 1, minWidth: 6 }} />
      <HunSwitch on={on} busy={busy} label={on ? `Stop ${project.name}` : `Run ${project.name}`} onClick={on ? onStop : onRun} />
    </div>
  );
}

/** Hun's switch: green when on, a white knob. */
function HunSwitch({ on, busy, label, onClick }: { on: boolean; busy: boolean; label: string; onClick: () => void }) {
  return (
    <button
      role="switch"
      aria-checked={on}
      aria-label={label}
      disabled={busy}
      onClick={onClick}
      className="sw-track"
      style={{
        position: "relative",
        width: 34,
        height: 20,
        flex: "none",
        borderRadius: 10,
        background: on ? "var(--hm-success)" : "rgba(138,129,116,.3)",
      }}
    >
      <span
        className="sw-knob"
        style={{
          position: "absolute",
          top: 2,
          left: 2,
          width: 16,
          height: 16,
          borderRadius: 8,
          background: "#fff",
          boxShadow: "0 .5px 1px rgba(0,0,0,.2)",
          transform: on ? "translateX(14px)" : "none",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        {busy && <Spinner size={8} color="var(--hm-text3)" />}
      </span>
    </button>
  );
}

/** ProjectIconView at 22 pt, corner 6. */
function LetterTile({ name, dim }: { name: string; dim: boolean }) {
  return (
    <span
      className="sq"
      style={{
        position: "relative",
        width: 22,
        height: 22,
        flex: "none",
        borderRadius: 6,
        background: "var(--hm-white)",
        boxShadow: "inset 0 0 0 .5px var(--hm-divider)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        fontFamily: ROUNDED,
        fontSize: 10.5,
        fontWeight: 600,
        color: "var(--hm-text2)",
        lineHeight: 1,
        opacity: dim ? 0.7 : 1,
      }}
    >
      {PROJECT_LOGOS[name] ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={PROJECT_LOGOS[name]} alt="" draggable={false} style={{ position: "absolute", inset: 0, width: "100%", height: "100%", borderRadius: 6, objectFit: "cover" }} />
      ) : (
        name.slice(0, 1).toUpperCase()
      )}
    </span>
  );
}

function MenuPortLink({ port, service }: { port: number; service: string }) {
  const url = `http://localhost:${port}`;
  const [tip, setTip] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => () => {
    if (timer.current) clearTimeout(timer.current);
  }, []);
  return (
    <span style={{ position: "relative", display: "flex" }}>
      <button
        className="port sq press"
        aria-label={`Open ${service} at ${url}`}
        onClick={() => {
          // A picture of a Mac can't open your browser; say what it would do.
          setTip(true);
          if (timer.current) clearTimeout(timer.current);
          timer.current = setTimeout(() => setTip(false), 1800);
        }}
        style={{ height: 17, padding: "0 5px", display: "flex", alignItems: "center", borderRadius: 5, fontFamily: MONO, fontSize: 10.5 }}
      >
        :{port}
      </button>
      {tip && (
        <span
          role="status"
          className="tip"
          style={{
            position: "absolute",
            top: 21,
            left: 0,
            zIndex: 5,
            whiteSpace: "nowrap",
            padding: "3px 7px",
            borderRadius: 6,
            fontSize: 11,
            lineHeight: "14px",
            color: "var(--hm-text2)",
            background: "var(--hm-white)",
            boxShadow: "0 0 0 .5px rgba(0,0,0,.14), 0 3px 10px rgba(0,0,0,.1)",
            pointerEvents: "none",
          }}
        >
          Opens {url} in your browser
        </span>
      )}
    </span>
  );
}

// MARK: - Footer

function MenuSillFooter({ mode, pending, onMode, onOpenHun }: { mode: Mode; pending: boolean; onMode: (m: Mode) => void; onOpenHun?: () => void }) {
  return (
    <div style={{ padding: "7px 8px", display: "flex", alignItems: "center", gap: 6 }}>
      <div
        role="radiogroup"
        aria-label="Mode"
        className="sq"
        style={{ height: 24, padding: 2, display: "flex", borderRadius: 7, background: "rgba(31,27,22,.05)", opacity: pending ? 0.6 : 1, pointerEvents: pending ? "none" : undefined }}
      >
        {(["focus", "multitask"] as Mode[]).map((m) => {
          const active = mode === m;
          return (
            <button
              key={m}
              role="radio"
              aria-checked={active}
              onClick={() => onMode(m)}
              className="seg sq press"
              style={{
                height: 20,
                padding: "0 9px",
                display: "flex",
                alignItems: "center",
                borderRadius: 6,
                fontSize: 11,
                fontWeight: 500,
                color: active ? "var(--hm-text1)" : "var(--hm-text2)",
                background: active ? "var(--hm-white)" : "transparent",
                boxShadow: active ? "0 .5px 1px rgba(0,0,0,.08)" : undefined,
              }}
            >
              {m === "focus" ? "Focus" : "Multitask"}
            </button>
          );
        })}
      </div>
      <div style={{ flex: 1 }} />
      <MenuIconButton label="Open Hun (⌘D)" onClick={onOpenHun}>
        <svg viewBox="-1 0 15 11" width={14} height={10} aria-hidden style={{ display: "block", overflow: "visible" }}>
          <rect x={0.55} y={0.55} width={11.9} height={9.9} rx={2.1} fill="none" stroke="currentColor" strokeWidth={1.1} />
          <path d="M1.9 2.55h1.6" stroke="currentColor" strokeWidth={0.9} strokeLinecap="round" opacity={0.7} />
        </svg>
      </MenuIconButton>
      <MenuIconButton label="Quit Hun (⌘Q)">
        <svg viewBox="0 0 10 10.5" width={10} height={10.5} aria-hidden style={{ display: "block", overflow: "visible" }}>
          <path d="M2.55 2.5A4.1 4.1 0 1 0 7.45 2.5" fill="none" stroke="currentColor" strokeWidth={1.2} strokeLinecap="round" />
          <path d="M5 .6v4.3" stroke="currentColor" strokeWidth={1.2} strokeLinecap="round" />
        </svg>
      </MenuIconButton>
    </div>
  );
}

function MenuIconButton({ label, onClick, children }: { label: string; onClick?: () => void; children: React.ReactNode }) {
  return (
    <button
      className="mib sq press"
      aria-label={label}
      onClick={onClick}
      style={{ width: 24, height: 22, flex: "none", display: "flex", alignItems: "center", justifyContent: "center", borderRadius: 6 }}
    >
      {children}
    </button>
  );
}
