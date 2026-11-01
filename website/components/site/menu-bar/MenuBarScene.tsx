"use client";

// The corner of a Mac screen: a wallpaper, the macOS menu bar across the top,
// and Hun's panel hanging from its switch glyph. The panel runs on its own
// HunSim, separate from the hero window's.

import { useCallback, useEffect, useLayoutEffect, useRef, useState, useSyncExternalStore } from "react";
import { HunSim, type Mode, type SimProject, projectStatus } from "../hun-window/sim";
import { MenuPanel, PANEL_W } from "./MenuPanel";

/** The wallpaper behind the menu bar. */
export const MENU_SCENE_BG = "/site/bg/scene-menu.jpg";

/** The tray's height, and the narrowest it lays out at before scaling as a unit. */
const SCENE_H = 440;
const MIN_W = 460;
/** macOS menu bar height, and the gap between it and a menu bar extra's panel. */
const BAR_H = 24;
const PANEL_GAP = 5;
/** HunStatusItem: the panel stays this far inside the screen's edge. */
const SCREEN_MARGIN = 8;

const SYS = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';

const css = `
.mbs-item { height: 22px; display: flex; align-items: center; padding: 0 7px; border-radius: 5px; }
.mbs-hun { all: unset; box-sizing: border-box; cursor: default; height: 22px; display: flex; align-items: center; padding: 0 5px; border-radius: 5px; }
.mbs-hun[aria-expanded="true"] { background: rgba(0,0,0,.1); }
.mbs-hun:focus-visible { outline: 2px solid rgba(94,106,210,.55); outline-offset: 0; }
.mbs-glyph { transition: opacity .16s ease-out; }
.mbs-panel { transition: opacity .12s ease-out; }
@media (prefers-reduced-motion: reduce) { .mbs-glyph, .mbs-panel { transition: none; } }
`;

function useReducedMotion() {
  const [reduced, setReduced] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    const on = () => setReduced(mq.matches);
    on();
    mq.addEventListener("change", on);
    return () => mq.removeEventListener("change", on);
  }, []);
  return reduced;
}

/**
 * A HunSim for the menu, plus the two things the app's store adds on top:
 * running in Focus selects the project, and entering Focus keeps the project
 * the daemon would (the selected one if it runs, else the latest started).
 */
function useMenuSim() {
  const [sim] = useState(() => new HunSim());
  const state = useSyncExternalStore(sim.subscribe, sim.getSnapshot, sim.getSnapshot);
  const reduced = useReducedMotion();
  // docs started at 14:38, orbit at 14:42.
  const started = useRef<string[]>(["docs", "orbit"]);

  useEffect(() => () => sim.dispose(), [sim]);
  useEffect(() => sim.setInstant(reduced), [sim, reduced]);

  const run = useCallback(
    (p: SimProject) => {
      started.current = [...started.current.filter((id) => id !== p.id), p.id];
      sim.selectProject(p.id);
      sim.run(p.id);
    },
    [sim],
  );

  const setMode = useCallback(
    (mode: Mode) => {
      if (mode === "focus") {
        const s = sim.getSnapshot();
        const isUp = (id: string) => projectStatus(s.projects.find((p) => p.id === id)!) !== "stopped";
        if (!isUp(s.selectedProjectId)) {
          const latest = [...started.current].reverse().find(isUp);
          if (latest) sim.selectProject(latest);
        }
      }
      sim.setMode(mode);
    },
    [sim],
  );

  return { sim, state, run, setMode, reduced };
}

/** The panel alone, in its initial state: for the comparison page. */
export function StandaloneMenuPanel({ chrome = false }: { chrome?: boolean }) {
  const { sim, state, run, setMode } = useMenuSim();
  return <MenuPanel sim={sim} state={state} chrome={chrome} onRun={run} onModeChange={setMode} />;
}

export function MenuBarScene() {
  const { sim, state, run, setMode, reduced } = useMenuSim();
  const [open, setOpen] = useState(true);
  const anyRunning = state.projects.some((p) => projectStatus(p) !== "stopped");

  // Lay out at the box's width; below MIN_W, lay out at MIN_W and scale down.
  const outer = useRef<HTMLDivElement>(null);
  const hunItem = useRef<HTMLButtonElement>(null);
  const [width, setWidth] = useState<number | null>(null);
  const [panelLeft, setPanelLeft] = useState<number | null>(null);

  useLayoutEffect(() => {
    const el = outer.current;
    if (!el) return;
    const measure = () => setWidth(el.clientWidth);
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const layoutW = width === null ? null : Math.max(width, MIN_W);
  const scale = width === null || width >= MIN_W ? 1 : width / MIN_W;

  // HunStatusItem.frame(for:under:): the panel's left edge lines up with the
  // item's, kept on screen with an 8 pt margin.
  useLayoutEffect(() => {
    const item = hunItem.current;
    if (!item || layoutW === null) return;
    setPanelLeft(Math.round(Math.min(Math.max(item.offsetLeft, SCREEN_MARGIN), layoutW - PANEL_W - SCREEN_MARGIN)));
  }, [layoutW]);

  const openHun = useCallback(() => {
    const target = document.querySelector(".hf-hero-tray");
    target?.scrollIntoView({ behavior: reduced ? "auto" : "smooth", block: "center" });
  }, [reduced]);

  return (
    <div ref={outer} style={{ width: "100%", height: SCENE_H * scale }}>
      <style>{css}</style>
      <figure
        aria-label="A Mac's menu bar with Hun's panel open, showing docs and orbit running and blog and mobile-api stopped."
        style={{
          position: "relative",
          margin: 0,
          width: layoutW ?? "100%",
          height: SCENE_H,
          borderRadius: 28 / scale,
          overflow: "hidden",
          backgroundColor: "var(--tray)",
          backgroundImage: `var(--bg-menu, url(${MENU_SCENE_BG}))`,
          backgroundSize: "cover",
          backgroundPosition: "center",
          transform: scale === 1 ? undefined : `scale(${scale})`,
          transformOrigin: "0 0",
          isolation: "isolate",
        }}
      >
        <MenuBar open={open} on={anyRunning} itemRef={hunItem} onToggle={() => setOpen((o) => !o)} />
        <div
          className="mbs-panel"
          aria-hidden={!open}
          inert={!open}
          style={{
            position: "absolute",
            top: BAR_H + PANEL_GAP,
            ...(panelLeft === null ? { right: SCREEN_MARGIN } : { left: panelLeft }),
            opacity: open ? 1 : 0,
            pointerEvents: open ? undefined : "none",
          }}
        >
          <MenuPanel sim={sim} state={state} onRun={run} onModeChange={setMode} onOpenHun={openHun} />
        </div>
      </figure>
    </div>
  );
}

// MARK: - Menu bar

function MenuBar({
  open,
  on,
  itemRef,
  onToggle,
}: {
  open: boolean;
  on: boolean;
  itemRef: React.RefObject<HTMLButtonElement | null>;
  onToggle: () => void;
}) {
  const ink = "rgba(0,0,0,.85)";
  return (
    <div
      style={{
        position: "absolute",
        inset: "0 0 auto 0",
        height: BAR_H,
        display: "flex",
        alignItems: "center",
        justifyContent: "flex-end",
        padding: "0 22px 0 6px",
        background: "rgba(250,250,250,.5)",
        backdropFilter: "blur(20px) saturate(160%)",
        WebkitBackdropFilter: "blur(20px) saturate(160%)",
        boxShadow: "inset 0 -.5px 0 rgba(0,0,0,.12)",
        fontFamily: SYS,
        fontSize: 13,
        lineHeight: "16px",
        color: ink,
        zIndex: 2,
        userSelect: "none",
        WebkitUserSelect: "none",
      }}
    >
      <div style={{ display: "flex", alignItems: "center", flex: "none" }}>
        <button
          ref={itemRef}
          className="mbs-hun"
          aria-label={on ? "Hun, projects running" : "Hun"}
          aria-expanded={open}
          onClick={onToggle}
        >
          <HunGlyph on={on} color={ink} />
        </button>
        <span aria-hidden className="mbs-item">
          <BatteryIcon color={ink} />
        </span>
        <span aria-hidden className="mbs-item">
          <WifiIcon color={ink} />
        </span>
        <span aria-hidden className="mbs-item">
          <ControlCentreIcon color={ink} />
        </span>
        <span aria-hidden className="mbs-item" style={{ fontWeight: 500, paddingRight: 4, letterSpacing: "-0.08px" }}>
          Sun 9:41
        </span>
      </div>
    </div>
  );
}

/** HunMenuBarGlyph: the app icon's switch, off (outline, knob left) or on (solid, knob cut out right). */
function HunGlyph({ on, color }: { on: boolean; color: string }) {
  return (
    <span style={{ position: "relative", width: 24, height: 16, display: "block" }}>
      <svg className="mbs-glyph" viewBox="0 0 24 16" width={24} height={16} aria-hidden style={{ position: "absolute", inset: 0, opacity: on ? 1 : 0 }}>
        <path fillRule="evenodd" fill={color} d="M8 2h8a6 6 0 0 1 0 12H8A6 6 0 0 1 8 2zM16 4.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7z" />
      </svg>
      <svg className="mbs-glyph" viewBox="0 0 24 16" width={24} height={16} aria-hidden style={{ position: "absolute", inset: 0, opacity: on ? 0 : 1 }}>
        <rect x={2.75} y={2.75} width={18.5} height={10.5} rx={5.25} fill="none" stroke={color} strokeWidth={1.5} />
        <circle cx={8} cy={8} r={3.5} fill={color} />
      </svg>
    </span>
  );
}

function BatteryIcon({ color }: { color: string }) {
  return (
    <svg viewBox="0 0 27 13" width={27} height={13} aria-hidden style={{ display: "block" }}>
      <rect x={0.5} y={0.5} width={23} height={12} rx={3.6} fill="none" stroke={color} strokeOpacity={0.45} />
      <rect x={2} y={2} width={16} height={9} rx={2.2} fill={color} />
      <path d="M25 4.6v3.8c.8-.3 1.3-1.1 1.3-1.9s-.5-1.6-1.3-1.9z" fill={color} fillOpacity={0.45} />
    </svg>
  );
}

function WifiIcon({ color }: { color: string }) {
  return (
    <svg viewBox="0 -1.5 17 14" width={17} height={14} aria-hidden style={{ display: "block" }}>
      <path d="M8.5 12.2 10.7 9.6a3.4 3.4 0 0 0-4.4 0z" fill={color} />
      <path d="M4.9 7.9a5.5 5.5 0 0 1 7.2 0" fill="none" stroke={color} strokeWidth={1.6} strokeLinecap="round" />
      <path d="M2.5 5.1a9 9 0 0 1 12 0" fill="none" stroke={color} strokeWidth={1.6} strokeLinecap="round" />
      <path d="M.8 2.6a11.6 11.6 0 0 1 15.4 0" fill="none" stroke={color} strokeWidth={1.6} strokeLinecap="round" />
    </svg>
  );
}

function ControlCentreIcon({ color }: { color: string }) {
  return (
    <svg viewBox="0 0 16 13" width={16} height={13} aria-hidden style={{ display: "block" }}>
      <rect x={0.6} y={0.6} width={14.8} height={5} rx={2.5} fill="none" stroke={color} strokeWidth={1.2} />
      <circle cx={12.9} cy={3.1} r={1.6} fill={color} />
      <rect x={0} y={7.4} width={16} height={5.6} rx={2.8} fill={color} />
      <circle cx={3.1} cy={10.2} r={1.6} fill="#fff" fillOpacity={0.9} />
    </svg>
  );
}
