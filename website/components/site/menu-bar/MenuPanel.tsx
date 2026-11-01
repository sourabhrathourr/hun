"use client";

// Hun's menu bar panel, rebuilt from MenuBarView.swift at its real 340 pt
// width, light appearance. Sizes, paddings, colours and hover behaviour
// follow the SwiftUI code; vertical positions were checked against the app's
// own render (public/site/menu-light.png) with a difference overlay, see
// ../compare-menu.

import { useEffect, useRef, useState } from "react";
import { PROJECT_LOGOS } from "../logos";
import { BoltIcon, PlayFillIcon, Spinner, StopFillIcon } from "../hun-window/icons";
import { type HunSim, type Mode, type SimProject, type SimState, projectStatus } from "../hun-window/sim";

export const PANEL_W = 340;

// AppTheme.swift, light.
const css = `
.hm { --hm-bg: #F7F7F2; --hm-white: #FFFFFF; --hm-divider: rgba(24,24,22,.07); --hm-dividerStrong: rgba(24,24,22,.12); --hm-hover: rgba(24,24,22,.035); --hm-rowHover: rgba(24,24,22,.01925); --hm-text1: #232321; --hm-text2: #62625D; --hm-text3: #8B8B84; --hm-success: #27833F; --hm-danger: #B84040; }
.hm { -webkit-font-smoothing: subpixel-antialiased; font-synthesis: none; text-rendering: optimizeLegibility; }
.hm *, .hm *::before, .hm *::after { box-sizing: border-box; }
.hm button { all: unset; box-sizing: border-box; cursor: default; }
.hm .sq { corner-shape: superellipse(1.45); }
.hm button:focus-visible, .hm .mrow:focus-visible { outline: 2px solid rgba(94,106,210,.55); outline-offset: 1px; }

/* MenuProjectRow: hover tints the row, lifts the name and shows the action. */
.hm .mrow:hover { background: var(--hm-rowHover); }
.hm .mrow:hover .mrow-name { color: var(--hm-text1) !important; }
.hm .mrow-act { width: 0; margin-left: -4px; opacity: 0; overflow: hidden; }
.hm .mrow:hover .mrow-act, .hm .mrow:focus-within .mrow-act { width: 24px; margin-left: 0; opacity: 1; overflow: visible; }
@media (hover: none) { .hm .mrow-act { width: 24px; margin-left: 0; opacity: 1; overflow: visible; } }

/* MenuIconButton */
.hm .mib { color: var(--hm-text2); background: var(--hm-white); }
.hm .mib:hover { color: var(--hm-text1); background: var(--hm-hover); }
.hm .mib.danger:hover { color: var(--hm-danger); background: rgba(184,64,64,.14); }
.hm .mib:disabled { pointer-events: none; }

/* MenuPortChip */
.hm .chip { color: var(--hm-text2); background: var(--hm-white); }
.hm .chip .chip-a { opacity: .6; }
.hm .chip:hover { color: var(--hm-text1); background: var(--hm-hover); }
.hm .chip:hover .chip-a { opacity: 1; }

/* MenuModeSwitch: withAnimation(.easeOut(duration: 0.12)) */
.hm .seg { transition: background-color .12s ease-out, color .12s ease-out; }

/* MenuFooter */
.hm .open:hover { background: var(--hm-rowHover); }

/* A plain button dims while pressed. */
.hm .press:active { opacity: .7; }

.hm .hw-spin { animation: hm-spin 1s steps(8) infinite; }
@keyframes hm-spin { to { transform: rotate(360deg); } }
.hm .ring { transition: opacity .16s ease-out; }
.hm .tip { animation: hm-tip .14s ease-out; }
@keyframes hm-tip { from { opacity: 0; transform: translateY(-2px); } to { opacity: 1; transform: none; } }
@media (prefers-reduced-motion: reduce) {
  .hm .seg, .hm .ring { transition: none; }
  .hm .tip { animation: none; }
  .hm .hw-spin { animation-duration: 2.4s; }
}
`;

const UI = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';
const MONO = 'ui-monospace, "SF Mono", SFMono-Regular, Menlo, monospace';
const ROUNDED = 'ui-rounded, "SF Pro Rounded", -apple-system, BlinkMacSystemFont, system-ui, sans-serif';

/** HunRoundedShape: 12 pt continuous corners, capped at 30% of the short side. */
const hr = (h: number) => Math.min(12, h * 0.3);

/** SwiftUI's optical tracking for SF Pro Text at these sizes, in px. */
const LS: Record<number, number> = { 11: 0, 12.5: -0.04, 13: -0.08 };
/** 11 pt medium (the mode switch) sets a touch wider than regular. */
const LS_11_MEDIUM = 0.1;
/** NSFont.monospacedSystemFont tracks SF Mono out at small sizes. */
const MLS_11 = 0.19;

const MODES: { mode: Mode; title: string; help: string }[] = [
  { mode: "focus", title: "Focus", help: "One project runs at a time. Switching stops the others." },
  { mode: "multitask", title: "Multitask", help: "Run projects in parallel." },
];

type Pending = SimProject["pending"];

/** HunActionKind.statusText */
const pendingText = (p: Pending) => (p === "stop" ? "Stopping..." : p === "restart" ? "Restarting..." : "Starting...");

export interface MenuPanelProps {
  sim: HunSim;
  state: SimState;
  /** The panel window's chrome: corners, hairline edge, shadow. Off for the comparison. */
  chrome?: boolean;
  onOpenHun?: () => void;
  onRun?: (p: SimProject) => void;
  onModeChange?: (m: Mode) => void;
}

export function MenuPanel({ sim, state, chrome = true, onOpenHun, onRun, onModeChange }: MenuPanelProps) {
  // MenuBarView: sorted by name; running includes a project being stopped.
  const projects = [...state.projects].sort((a, b) => a.name.localeCompare(b.name, undefined, { numeric: true }));
  const running = projects.filter((p) => projectStatus(p) !== "stopped" || p.pending === "stop");
  const others = projects.filter((p) => !running.includes(p));

  const row = (p: SimProject) => (
    <MenuProjectRow
      key={p.id}
      project={p}
      mode={state.mode}
      onRun={() => (onRun ? onRun(p) : sim.run(p.id))}
      onStop={() => sim.stop(p.id)}
    />
  );

  return (
    <div
      className="hm"
      style={{
        position: "relative",
        width: PANEL_W,
        background: "var(--hm-bg)",
        fontFamily: UI,
        color: "var(--hm-text1)",
        userSelect: "none",
        WebkitUserSelect: "none",
        lineHeight: "normal",
        textAlign: "left",
        ...(chrome
          ? {
              borderRadius: 12,
              overflow: "hidden",
              boxShadow:
                "inset 0 0 0 1px var(--hm-dividerStrong), 0 0 0 .5px rgba(0,0,0,.06), 0 10px 32px rgba(0,0,0,.16), 0 2px 6px rgba(0,0,0,.06)",
            }
          : null),
      }}
    >
      <style>{css}</style>
      <MenuHeader
        runningCount={running.length}
        mode={state.mode}
        pending={state.modePending}
        onMode={(m) => (onModeChange ? onModeChange(m) : sim.setMode(m))}
      />
      <div style={{ padding: "2px 6px 6px" }}>
        {running.length > 0 && (
          <>
            <MenuSectionLabel title="Running" />
            {running.map(row)}
          </>
        )}
        {running.length > 0 && others.length > 0 && <div style={{ height: 10 }} />}
        {others.length > 0 && (
          <>
            {running.length > 0 && <MenuSectionLabel title="Projects" />}
            {others.map(row)}
          </>
        )}
      </div>
      <div style={{ height: 1, background: "var(--hm-divider)" }} />
      <MenuFooter onOpenHun={onOpenHun} />
      {/* NSPanel's layer border sits inside the bounds, over the content. */}
      {chrome && (
        <div
          aria-hidden
          className="sq"
          style={{ position: "absolute", inset: 0, borderRadius: 12, boxShadow: "inset 0 0 0 1px var(--hm-dividerStrong)", pointerEvents: "none" }}
        />
      )}
    </div>
  );
}

// MARK: - Header

function MenuHeader({ runningCount, mode, pending, onMode }: { runningCount: number; mode: Mode; pending: boolean; onMode: (m: Mode) => void }) {
  const summary = runningCount === 0 ? "Nothing running" : runningCount === 1 ? "1 project running" : `${runningCount} projects running`;
  return (
    <div style={{ height: 53, padding: "0 14px", display: "flex", alignItems: "flex-start", gap: 10 }}>
      <div style={{ paddingTop: 12, minWidth: 0 }}>
        <div style={{ fontSize: 13, fontWeight: 600, lineHeight: "16px", letterSpacing: LS[13] }}>Hun</div>
        <div aria-live="polite" style={{ marginTop: 1, fontSize: 11, lineHeight: "14px", letterSpacing: LS[11], color: "var(--hm-text3)", whiteSpace: "nowrap" }}>
          {summary}
        </div>
      </div>
      <div style={{ flex: 1, minWidth: 8 }} />
      <div
        role="radiogroup"
        aria-label="Mode"
        className="sq"
        style={{
          marginTop: 16,
          height: 24,
          padding: 2,
          display: "flex",
          borderRadius: hr(24),
          background: "var(--hm-white)",
          opacity: pending ? 0.6 : 1,
          pointerEvents: pending ? "none" : undefined,
        }}
      >
        {MODES.map((o) => {
          const active = mode === o.mode;
          return (
            <button
              key={o.mode}
              role="radio"
              aria-checked={active}
              disabled={pending}
              title={o.help}
              onClick={() => onMode(o.mode)}
              className="seg sq press"
              style={{
                height: 20,
                padding: "0 9px",
                display: "flex",
                alignItems: "center",
                borderRadius: hr(20),
                fontSize: 11,
                fontWeight: 500,
                letterSpacing: LS_11_MEDIUM,
                color: active ? "var(--hm-text1)" : "var(--hm-text2)",
                background: active ? "var(--hm-white)" : "transparent",
              }}
            >
              {o.title}
            </button>
          );
        })}
      </div>
    </div>
  );
}

// MARK: - Rows

function MenuSectionLabel({ title }: { title: string }) {
  return (
    <div style={{ padding: "6px 8px 4px", fontSize: 11, fontWeight: 500, lineHeight: "14px", letterSpacing: LS[11], color: "var(--hm-text3)" }}>
      {title}
    </div>
  );
}

function MenuProjectRow({ project, mode, onRun, onStop }: { project: SimProject; mode: Mode; onRun: () => void; onStop: () => void }) {
  const status = projectStatus(project);
  const isRunning = status !== "stopped";
  const pending = project.pending;

  // Running projects say what's running; stopped ones stay one line.
  let detail: string | null = null;
  if (pending) detail = pendingText(pending);
  else if (status === "running") {
    const n = project.services.filter((s) => s.status !== "stopped").length;
    detail = n === 1 ? "1 service" : `${n} services`;
  } else if (status === "starting") detail = "Starting...";

  // The first running service that serves a page.
  const web = project.services.find((s) => s.status === "running" && s.port > 0);
  const h = detail === null ? 32 : 42;

  return (
    <div
      className="mrow sq"
      title={`Open ${project.name} in Hun`}
      style={{
        position: "relative",
        minHeight: h,
        padding: "0 8px",
        display: "flex",
        alignItems: "center",
        gap: 10,
        borderRadius: hr(h),
      }}
    >
      <LetterTile name={project.name} running={status === "running"} />
      <div style={{ minWidth: 0, display: "flex", flexDirection: "column", gap: 2 }}>
        <div
          className="mrow-name"
          style={{
            fontSize: 13,
            lineHeight: "16px",
            letterSpacing: LS[13],
            fontWeight: isRunning ? 500 : 400,
            color: isRunning ? "var(--hm-text1)" : "var(--hm-text2)",
            whiteSpace: "nowrap",
            overflow: "hidden",
            textOverflow: "ellipsis",
          }}
        >
          {project.name}
        </div>
        {detail !== null && (
          <div style={{ fontSize: 11, lineHeight: "14px", letterSpacing: LS[11], color: "var(--hm-text3)", whiteSpace: "nowrap" }}>{detail}</div>
        )}
      </div>
      <div style={{ flex: 1, minWidth: 6 }} />
      <div style={{ display: "flex", alignItems: "center", gap: 4 }}>
        {web && !pending && <MenuPortChip port={web.port} service={web.name} />}
        {pending ? (
          <MenuIconButton label={pending === "stop" ? "Stopping..." : "Starting..."} loading>
            {null}
          </MenuIconButton>
        ) : (
          <span className="mrow-act" style={{ display: "flex", flex: "none" }}>
            {isRunning ? (
              <MenuIconButton label={`Stop ${project.name}`} danger onClick={onStop}>
                <StopFillIcon style={{ width: 7.5, height: 7.5 }} />
              </MenuIconButton>
            ) : mode === "focus" ? (
              <MenuIconButton label={`Switch to ${project.name}`} onClick={onRun}>
                <BoltIcon style={{ width: 7, height: 9.6 }} />
              </MenuIconButton>
            ) : (
              <MenuIconButton label={`Run ${project.name}`} onClick={onRun}>
                <PlayFillIcon style={{ width: 7, height: 8.3, transform: "translateX(.5px)" }} />
              </MenuIconButton>
            )}
          </span>
        )}
      </div>
    </div>
  );
}

/** ProjectIconView at 20 pt, corner 5, as a letter tile with the running ring. */
function LetterTile({ name, running }: { name: string; running: boolean }) {
  return (
    <span style={{ position: "relative", width: 20, height: 20, flex: "none", display: "block" }}>
      <span
        className="sq"
        style={{
          position: "absolute",
          inset: 0,
          borderRadius: 5,
          background: "var(--hm-white)",
          boxShadow: "inset 0 0 0 .5px var(--hm-divider)",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontFamily: ROUNDED,
          fontSize: 9.6,
          fontWeight: 600,
          color: "var(--hm-text2)",
          lineHeight: 1,
        }}
      >
        {PROJECT_LOGOS[name] ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={PROJECT_LOGOS[name]} alt="" draggable={false} style={{ position: "absolute", inset: 0, width: "100%", height: "100%", borderRadius: 5, objectFit: "cover" }} />
        ) : (
          name.slice(0, 1).toUpperCase()
        )}
        {PROJECT_LOGOS[name] && (
          <span className="sq" style={{ position: "absolute", inset: 0, borderRadius: 5, boxShadow: "inset 0 0 0 .5px rgba(0,0,0,.14)" }} />
        )}
      </span>
      <span
        className="sq ring"
        style={{
          position: "absolute",
          inset: -2,
          borderRadius: 7,
          boxShadow: "inset 0 0 0 1px rgba(39,131,63,.3)",
          opacity: running ? 1 : 0,
        }}
      />
    </span>
  );
}

function MenuPortChip({ port, service }: { port: number; service: string }) {
  const url = `http://localhost:${port}`;
  const [tip, setTip] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => () => {
    if (timer.current) clearTimeout(timer.current);
  }, []);
  return (
    <span style={{ position: "relative", display: "flex" }}>
      <button
        className="chip sq press"
        title={`Open ${service} at ${url}`}
        aria-label={`Open ${service} at ${url}`}
        onClick={() => {
          // A picture of a Mac can't open your browser; say what it would do.
          setTip(true);
          if (timer.current) clearTimeout(timer.current);
          timer.current = setTimeout(() => setTip(false), 1800);
        }}
        style={{ height: 22, padding: "0 7px", display: "flex", alignItems: "center", gap: 3, borderRadius: hr(22) }}
      >
        <span style={{ fontFamily: MONO, fontSize: 11, fontWeight: 500, letterSpacing: MLS_11, lineHeight: "14px", position: "relative", top: 0.5 }}>:{port}</span>
        <svg className="chip-a" viewBox="0 0 9 9" width={9} height={9} aria-hidden style={{ display: "block", overflow: "visible", position: "relative", top: 0.5 }}>
          <path d="M2.1 6.9 6.8 2.2M3.1 2.1h3.8v3.8" fill="none" stroke="currentColor" strokeWidth={1.25} strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>
      {tip && (
        <span
          role="status"
          className="tip"
          style={{
            position: "absolute",
            top: 26,
            right: 0,
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

function MenuIconButton({
  label,
  danger = false,
  loading = false,
  onClick,
  children,
}: {
  label: string;
  danger?: boolean;
  loading?: boolean;
  onClick?: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      className={`mib sq press ${danger ? "danger" : ""}`}
      title={label}
      aria-label={label}
      disabled={loading}
      onClick={onClick}
      style={{ width: 24, height: 22, flex: "none", display: "flex", alignItems: "center", justifyContent: "center", borderRadius: hr(22) }}
    >
      {loading ? <Spinner size={10} color="var(--hm-text2)" /> : children}
    </button>
  );
}

// MARK: - Footer

function MenuFooter({ onOpenHun }: { onOpenHun?: () => void }) {
  return (
    <div style={{ padding: 6, display: "flex", alignItems: "center", gap: 4 }}>
      <button
        className="open sq press"
        onClick={onOpenHun}
        style={{ flex: 1, height: 30, padding: "0 8px", display: "flex", alignItems: "center", gap: 8, borderRadius: hr(30) }}
      >
        <span style={{ color: "var(--hm-text2)", display: "flex", position: "relative", top: 1 }}>
          <svg viewBox="-1 0 15 11" width={15} height={11} aria-hidden style={{ display: "block", overflow: "visible" }}>
            <rect x={0.55} y={0.55} width={11.9} height={9.9} rx={2.1} fill="none" stroke="currentColor" strokeWidth={1.1} />
            <path d="M1.9 2.55h1.6" stroke="currentColor" strokeWidth={0.9} strokeLinecap="round" opacity={0.7} />
          </svg>
        </span>
        <span style={{ fontSize: 12.5, letterSpacing: LS[12.5], lineHeight: "15px", color: "var(--hm-text1)", position: "relative", top: 0.5 }}>Open Hun</span>
        <span style={{ flex: 1, minWidth: 8 }} />
        <span style={{ fontSize: 11, lineHeight: "14px", letterSpacing: LS[11], color: "var(--hm-text3)", position: "relative", left: -0.9 }}>⌘D</span>
      </button>
      <MenuIconButton label="Quit Hun (⌘Q)">
        <svg viewBox="0 0 10 10.5" width={10} height={10.5} aria-hidden style={{ display: "block", overflow: "visible" }}>
          <path d="M2.55 2.5A4.1 4.1 0 1 0 7.45 2.5" fill="none" stroke="currentColor" strokeWidth={1.2} strokeLinecap="round" />
          <path d="M5 .6v4.3" stroke="currentColor" strokeWidth={1.2} strokeLinecap="round" />
        </svg>
      </MenuIconButton>
    </div>
  );
}
