"use client";

// Hun's main window, rebuilt from the SwiftUI source (ContentView.swift) at
// 1056×660 pt, light appearance. Sizes, paddings, radii and colours follow
// the app; positions were checked against a render of the real window with
// a difference overlay (see ../compare).

import { type CSSProperties, type ReactNode, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, useSyncExternalStore, createContext, useContext } from "react";
import { PROJECT_LOGOS } from "../logos";
import {
  ArrowDownIcon,
  BoltIcon,
  BranchIcon,
  CheckIcon,
  ChevronDownIcon,
  ChevronRightIcon,
  ChevronUpDownIcon,
  ClockwiseIcon,
  CopyIcon,
  EllipsisIcon,
  FolderFillIcon,
  FolderIcon,
  GearIcon,
  MagnifierIcon,
  PlayFillIcon,
  PlusIcon,
  SidebarIcon,
  Spinner,
  SplitIcon,
  StopFillIcon,
  TextAlignLeftIcon,
  TrashIcon,
  XCircleIcon,
} from "./icons";
import {
  HunSim,
  type LogLine,
  type Mode,
  type SimProject,
  type SimService,
  type SimState,
  projectStatus,
  serviceColor,
} from "./sim";

export const WINDOW_W = 1056;
export const WINDOW_H = 660;

/**
 * Geometry. Desktop is the real window at 1056×660 with its sidebar. Compact
 * is the window narrowed with the sidebar collapsed, for phones: a toolbar row
 * for the window buttons, a narrower services column, the rest for logs.
 */
export type HunLayout = { w: number; h: number; sidebar: boolean; top: number; cardH: number; servicesW: number; oneLineLogs?: boolean };
export const DESKTOP_LAYOUT: HunLayout = { w: WINDOW_W, h: WINDOW_H, sidebar: true, top: 0, cardH: 560, servicesW: 311 };
export const COMPACT_LAYOUT: HunLayout = { w: 600, h: 500, sidebar: false, top: 34, cardH: 366, servicesW: 170, oneLineLogs: true };
const LayoutCtx = createContext<HunLayout>(DESKTOP_LAYOUT);
const useLayout = () => useContext(LayoutCtx);

// AppTheme.swift, light. Each token is a CSS variable, set on .hw below.
export const T = {
  appBg: "var(--hw-appBg)",
  sidebar: "var(--hw-sidebar)",
  white: "var(--hw-white)",
  divider: "var(--hw-divider)",
  dividerStrong: "var(--hw-dividerStrong)",
  hover: "var(--hw-hover)",
  rowHover: "var(--hw-rowHover)",
  floatingBorder: "var(--hw-floatingBorder)",
  floatingShadow: "var(--hw-floatingShadow)",
  text1: "var(--hw-text1)",
  text2: "var(--hw-text2)",
  text3: "var(--hw-text3)",
  logText: "var(--hw-logText)",
  logTime: "var(--hw-logTime)",
  accent: "var(--hw-accent)",
  success: "var(--hw-success)",
  warning: "var(--hw-warning)",
  danger: "var(--hw-danger)",
};


export const UI = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';
export const MONO = 'ui-monospace, "SF Mono", SFMono-Regular, Menlo, monospace';
const ROUNDED = 'ui-rounded, "SF Pro Rounded", -apple-system, BlinkMacSystemFont, system-ui, sans-serif';

/** HunRoundedShape: 12pt continuous corners, capped at 30% of the short side. */
export const hr = (h: number) => Math.min(12, h * 0.3);

/** SwiftUI's `.stroke(lineWidth: 1)`: centred on the edge, half outside. */
export const stroke = (c: string) => `0 0 0 .5px ${c}, inset 0 0 0 .5px ${c}`;

const css = `
.hw { --hw-appBg: #F7F7F2; --hw-sidebar: #F2F2EC; --hw-white: #FFFFFF; --hw-divider: rgba(24,24,22,.07); --hw-dividerStrong: rgba(24,24,22,.12); --hw-hover: rgba(24,24,22,.035); --hw-rowHover: rgba(24,24,22,.01925); --hw-floatingBorder: rgba(24,24,22,.09); --hw-floatingShadow: rgba(24,24,22,.10); --hw-text1: #232321; --hw-text2: #62625D; --hw-text3: #8B8B84; --hw-logText: #4D4D49; --hw-logTime: #92928B; --hw-accent: #5E6AD2; --hw-success: #27833F; --hw-warning: #A76418; --hw-danger: #B84040; --hw-menuBg: rgba(250,250,248,.94); --hw-pill: rgba(250,250,247,.82); --hw-sel: #F2F2EC; }
.hw { -webkit-font-smoothing: subpixel-antialiased; font-synthesis: none; text-rendering: optimizeLegibility; }
.hw *, .hw *::before, .hw *::after { box-sizing: border-box; }
.hw button { all: unset; box-sizing: border-box; cursor: default; }
.hw input { all: unset; box-sizing: border-box; cursor: text; }
.hw .sq { corner-shape: superellipse(1.45); }
.hw .tb:hover { background: ${T.hover}; color: ${T.text1} !important; }
.hw .add:hover { background: ${T.hover}; }
.hw .add:hover .add-t { color: ${T.text1} !important; }
.hw .add:hover .add-k { opacity: 1 !important; }
.hw .sec:hover { background: ${T.hover}; }
.hw .sec:hover .sec-c { opacity: 1 !important; }
.hw .prow:hover { background: ${T.rowHover}; }
.hw .prow:hover .prow-t { color: ${T.text1} !important; }
.hw .prow.sel, .hw .prow.sel:hover { background: var(--hw-sel); }
.hw .mode:hover { background: ${T.rowHover} !important; color: ${T.text1} !important; }
.hw .ab-secondary:hover { background: ${T.hover} !important; }
.hw .ab-danger:hover { background: rgba(184,64,64,.12) !important; box-shadow: ${"0 0 0 .5px rgba(184,64,64,.4), inset 0 0 0 .5px rgba(184,64,64,.4)"} !important; color: ${T.danger} !important; }
.hw .ab-primary { background: rgba(94,106,210,.92); }
.hw .ab-primary:hover { background: ${T.accent}; }
.hw .ab:disabled { pointer-events: none; }
.hw .chip:hover { background: ${T.hover} !important; box-shadow: 0 0 0 .5px rgba(139,139,132,.32), inset 0 0 0 .5px rgba(139,139,132,.32) !important; }
.hw .srow:hover { background: ${T.rowHover}; }
.hw .srow.sel, .hw .srow.sel:hover { background: var(--hw-sel); }
.hw .srow:hover .port-link { color: ${T.text1} !important; text-decoration: underline; }
.hw .lb:hover { background: ${T.hover} !important; color: ${T.text1} !important; }
.hw .lb:disabled { opacity: .45; pointer-events: none; }
.hw .press:active { opacity: .78; }
.hw button:focus-visible, .hw [role=button]:focus-visible { outline: 2px solid rgba(94,106,210,.55); outline-offset: 1px; }
.hw .lt:hover { border-color: var(--hw-dividerStrong); transform: scale(1.03); }
.hw .mi:hover { background: #2F6FEB; color: #fff; }
.hw .mi:hover .mi-k { color: rgba(255,255,255,.8); }
.hw .logs::-webkit-scrollbar { width: 0; height: 0; }
.hw .slist::-webkit-scrollbar { width: 0; height: 0; }
.hw .hw-spin { animation: hw-spin 1s steps(8) infinite; }
@keyframes hw-spin { to { transform: rotate(360deg); } }
.hw .fade { animation: hw-fade .18s ease-out; }
@keyframes hw-fade { from { opacity: 0; } to { opacity: 1; } }
.hw .lt-in { animation: hw-lt .34s cubic-bezier(.2,.9,.3,1.1); }
@keyframes hw-lt { from { opacity: 0; transform: translateY(8px) scale(.88); } to { opacity: 1; transform: none; } }
.hw .menu-in { animation: hw-menu .12s ease-out; transform-origin: top right; }
@keyframes hw-menu { from { opacity: 0; } to { opacity: 1; } }
@media (prefers-reduced-motion: reduce) {
  .hw .fade, .hw .lt-in, .hw .menu-in { animation: none; }
  .hw .lt:hover { transform: none; }
}
`;

export interface HunWindowProps {
  /** Stream log lines while on screen. Off for the static comparison. */
  live?: boolean;
  /** Draw the traffic lights grey, as in an inactive window (comparison). */
  inactive?: boolean;
  className?: string;
  style?: CSSProperties;
}

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

export function HunWindow({ live = true, inactive = false, className = "", style, layout = DESKTOP_LAYOUT, lights = true }: HunWindowProps & { layout?: HunLayout; lights?: boolean }) {
  const [sim] = useState(() => new HunSim());
  const state = useSyncExternalStore(sim.subscribe, sim.getSnapshot, sim.getSnapshot);
  const rootRef = useRef<HTMLDivElement>(null);
  const reduced = useReducedMotion();

  useEffect(() => () => sim.dispose(), [sim]);

  // Stream only while the window is on screen, the tab is visible and
  // motion is allowed.
  useEffect(() => {
    sim.setInstant(reduced);
    if (!live || reduced) {
      sim.setLive(false);
      return;
    }
    let onScreen = false;
    const update = () => sim.setLive(onScreen && document.visibilityState === "visible");
    const io = new IntersectionObserver(
      ([e]) => {
        onScreen = e.isIntersecting;
        update();
      },
      { threshold: 0.15 },
    );
    if (rootRef.current) io.observe(rootRef.current);
    document.addEventListener("visibilitychange", update);
    return () => {
      io.disconnect();
      document.removeEventListener("visibilitychange", update);
      sim.setLive(false);
    };
  }, [sim, live, reduced]);

  const project = state.projects.find((p) => p.id === state.selectedProjectId)!;

  return (
    <div
      ref={rootRef}
      className={`hw ${className}`}
      style={{
        position: "relative",
        width: layout.w,
        height: layout.h,
        overflow: "hidden",
        background: T.sidebar,
        fontFamily: UI,
        color: T.text1,
        userSelect: "none",
        WebkitUserSelect: "none",
        ...style,
      }}
    >
      <style>{css}</style>
      <LayoutCtx.Provider value={layout}>
        {layout.sidebar && <Sidebar sim={sim} state={state} />}
        {lights && <TrafficLights inactive={inactive} />}
        <div
          key={project.id}
          className={reduced ? undefined : "fade"}
          style={{ position: "absolute", inset: 0, left: layout.sidebar ? 228 : 0, top: layout.top }}
        >
          <Header sim={sim} state={state} project={project} />
          <Card sim={sim} state={state} project={project} />
        </div>
      </LayoutCtx.Provider>
    </div>
  );
}

// MARK: - Window chrome

function TrafficLights({ inactive }: { inactive: boolean }) {
  const lights: [string, number][] = inactive
    ? [
        ["#E8E8E7", 16],
        ["#E8E8E7", 39],
        ["#E8E8E7", 62],
      ]
    : [
        ["#FF5F57", 16],
        ["#FEBC2E", 39],
        ["#28C840", 62],
      ];
  return (
    <svg className="hw-tl" width={80} height={32} viewBox="0 0 80 32" style={{ position: "absolute", left: 0, top: 0 }} aria-hidden>
      {lights.map(([fill, cx]) => (
        <circle key={cx} cx={cx} cy={16} r={6.5} fill={fill} stroke="rgba(0,0,0,.12)" strokeWidth={0.5} />
      ))}
    </svg>
  );
}

// MARK: - Sidebar

function Sidebar({ sim, state }: { sim: HunSim; state: SimState }) {
  const [collapsed, setCollapsed] = useState(false);
  const q = state.sidebarSearch.trim().toLowerCase();
  const projects = state.projects.filter((p) => !q || p.name.toLowerCase().includes(q) || p.path.toLowerCase().includes(q));
  return (
    <div style={{ position: "absolute", left: 0, top: 0, width: 228, height: WINDOW_H }}>
      {/* SidebarTitlebarChrome: ToolbarIconButton("sidebar.left"), trailing 6 */}
      <button
        className="tb sq"
        aria-label="Hide sidebar"
        title="Hide sidebar"
        style={{
          position: "absolute",
          left: 196,
          top: 9,
          width: 26,
          height: 26,
          borderRadius: hr(26),
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          color: T.text3,
        }}
      >
        <SidebarIcon style={{ transform: "translateY(.5px)" }} />
      </button>

      <SearchField
        value={state.sidebarSearch}
        onChange={sim.setSidebarSearch}
        placeholder="Search"
        height={30}
        fontSize={12}
        iconSize={11}
        style={{ position: "absolute", left: 10, top: 54, width: 208, paddingTop: 1 }}
      />

      <button
        className="add sq press"
        title="Run hun init in a project folder"
        style={{
          position: "absolute",
          left: 10,
          top: 90,
          width: 208,
          height: 30,
          padding: "0 8px",
          borderRadius: hr(30),
          display: "flex",
          alignItems: "center",
          gap: 8,
        }}
      >
        <span style={{ width: 14, display: "flex", justifyContent: "center", color: T.text3 }}>
          <PlusIcon style={{ transform: "translateX(-.5px)" }} />
        </span>
        <span className="add-t" style={{ fontSize: 12.5, fontWeight: 500, color: T.text2, letterSpacing: LS[12.5] }}>
          Add project
        </span>
        <span style={{ flex: 1 }} />
        <span className="add-k" style={{ fontFamily: ROUNDED, fontSize: 10, fontWeight: 500, color: T.text3, opacity: 0 }}>
          ⌘N
        </span>
      </button>

      <div style={{ position: "absolute", left: 10, top: 132, width: 208 }}>
        <button
          className="sec sq press"
          onClick={() => setCollapsed((c) => !c)}
          aria-expanded={!collapsed}
          style={{
            width: 208,
            height: 28,
            padding: "1px 8px 0",
            borderRadius: hr(28),
            display: "flex",
            alignItems: "center",
            gap: 8,
          }}
        >
          <span style={{ width: 14, display: "flex", justifyContent: "center", color: T.text3 }}>
            <FolderFillIcon style={{ transform: "translateX(-.5px)" }} />
          </span>
          <span style={{ fontSize: 12.5, fontWeight: 500, color: T.text2, letterSpacing: LS[12.5] }}>Code</span>
          <span style={{ flex: 1 }} />
          <span
            className="sec-c"
            style={{
              color: T.text3,
              opacity: collapsed ? 1 : 0,
              transform: `rotate(${collapsed ? 0 : 90}deg)`,
              transition: "opacity .12s ease-out, transform .15s ease-out",
            }}
          >
            <ChevronRightIcon />
          </span>
        </button>
        {!collapsed && (
          <div style={{ marginTop: 3, display: "flex", flexDirection: "column", gap: 2 }}>
            {projects.map((p) => (
              <ProjectRow key={p.id} project={p} selected={p.id === state.selectedProjectId} onSelect={() => sim.selectProject(p.id)} />
            ))}
          </div>
        )}
      </div>

      <ModeMenuButton sim={sim} mode={state.mode} pending={state.modePending} />

      <button
        className="tb sq press"
        aria-label="Open Settings"
        title="Settings (⌘,)"
        style={{
          position: "absolute",
          left: 190.5,
          top: 623.5,
          width: 26,
          height: 26,
          borderRadius: hr(26),
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          color: T.text3,
        }}
      >
        <GearIcon />
      </button>
    </div>
  );
}

function ProjectRow({ project, selected, onSelect }: { project: SimProject; selected: boolean; onSelect: () => void }) {
  const status = projectStatus(project);
  return (
    <button
      className={`prow sq press ${selected ? "sel" : ""}`}
      onClick={onSelect}
      aria-current={selected ? "page" : undefined}
      title={`${project.name}\n${project.path}`}
      style={{
        width: 208,
        height: 30,
        paddingLeft: 30,
        paddingRight: 8,
        borderRadius: hr(30),
        display: "flex",
        alignItems: "center",
        gap: 10,
      }}
    >
      <span style={{ marginTop: 1, display: "flex" }}>
        <LetterTile name={project.name} size={17} radius={4} emphasized={selected} running={status === "running"} />
      </span>
      <span
        className="prow-t"
        style={{
          fontSize: 13,
          color: selected ? T.text1 : T.text2,
          letterSpacing: LS[13],
          whiteSpace: "nowrap",
          overflow: "hidden",
          textOverflow: "ellipsis",
        }}
      >
        {project.name}
      </span>
    </button>
  );
}

function LetterTile({
  name,
  size,
  radius,
  emphasized = false,
  running = false,
}: {
  name: string;
  size: number;
  radius: number;
  emphasized?: boolean;
  running?: boolean;
}) {
  return (
    <span style={{ position: "relative", width: size, height: size, flex: "none", display: "block" }}>
      <span
        className="sq"
        style={{
          position: "absolute",
          inset: 0,
          borderRadius: radius,
          background: T.white,
          boxShadow: `inset 0 0 0 .5px ${T.divider}`,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontFamily: ROUNDED,
          fontSize: Math.max(9, size * 0.48),
          fontWeight: 600,
          color: emphasized ? T.text1 : T.text2,
          lineHeight: 1,
        }}
      >
        {PROJECT_LOGOS[name] ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={PROJECT_LOGOS[name]} alt="" draggable={false} style={{ position: "absolute", inset: 0, width: "100%", height: "100%", borderRadius: radius, objectFit: "cover" }} />
        ) : (
          name.slice(0, 1).toUpperCase()
        )}
        {PROJECT_LOGOS[name] && (
          <span className="sq" style={{ position: "absolute", inset: 0, borderRadius: radius, boxShadow: "inset 0 0 0 .5px rgba(0,0,0,.14)" }} />
        )}
      </span>
      {/* Running: a thin green ring 2pt outside the icon. */}
      <span
        className="sq"
        style={{
          position: "absolute",
          inset: -2,
          borderRadius: radius + 2,
          boxShadow: "inset 0 0 0 1px rgba(39,131,63,.3)",
          opacity: running ? 1 : 0,
          transition: "opacity .16s ease-out",
        }}
      />
    </span>
  );
}

function ModeMenuButton({ sim, mode, pending }: { sim: HunSim; mode: Mode; pending: boolean }) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  useDismiss(open, ref, () => setOpen(false));
  const title = mode === "focus" ? "Focus" : "Multitask";
  return (
    <div ref={ref} style={{ position: "absolute", left: 10, top: 622 }}>
      <button
        className="mode sq"
        aria-haspopup="menu"
        aria-expanded={open}
        disabled={pending}
        onClick={() => setOpen((o) => !o)}
        title={mode === "focus" ? "Focus: running a project stops the others" : "Multitask: projects run side by side"}
        style={{
          height: 28,
          padding: "1px 8px 0",
          borderRadius: hr(28),
          display: "flex",
          alignItems: "center",
          gap: 8,
          color: open ? T.text1 : T.text2,
          background: open ? T.rowHover : undefined,
          opacity: pending ? 0.6 : 1,
        }}
      >
        <span style={{ width: 14, display: "flex", justifyContent: "center" }}>{mode === "focus" ? <BoltIcon /> : <SplitIcon style={{ transform: "translateX(.5px)" }} />}</span>
        <span style={{ fontSize: 12.5, fontWeight: 500, letterSpacing: LS[12.5] }}>{title}</span>
        <span style={{ color: T.text3, marginLeft: 2 }}>
          <ChevronUpDownIcon style={{ transform: "translateY(.5px)" }} />
        </span>
      </button>
      {open && (
        <Menu style={{ left: 0, bottom: 32 }} origin="bottom left">
          {(["focus", "multitask"] as Mode[]).map((m) => (
            <MenuItem
              key={m}
              checked={m === mode}
              icon={m === "focus" ? <BoltIcon /> : <SplitIcon />}
              onClick={() => {
                setOpen(false);
                sim.setMode(m);
              }}
            >
              {m === "focus" ? "Focus" : "Multitask"}
            </MenuItem>
          ))}
        </Menu>
      )}
    </div>
  );
}

// MARK: - Menus

function useDismiss(open: boolean, ref: React.RefObject<HTMLElement | null>, close: () => void) {
  useEffect(() => {
    if (!open) return;
    const down = (e: PointerEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) close();
    };
    const key = (e: KeyboardEvent) => e.key === "Escape" && close();
    window.addEventListener("pointerdown", down);
    window.addEventListener("keydown", key);
    return () => {
      window.removeEventListener("pointerdown", down);
      window.removeEventListener("keydown", key);
    };
  }, [open, ref, close]);
}

function Menu({ children, style, origin = "top right" }: { children: ReactNode; style: CSSProperties; origin?: string }) {
  return (
    <div
      role="menu"
      className="menu-in"
      style={{
        position: "absolute",
        zIndex: 30,
        minWidth: 168,
        padding: 5,
        borderRadius: 10,
        background: "var(--hw-menuBg)",
        backdropFilter: "blur(20px) saturate(1.6)",
        WebkitBackdropFilter: "blur(20px) saturate(1.6)",
        boxShadow: "0 0 0 .5px rgba(0,0,0,.16), 0 10px 28px rgba(0,0,0,.16), 0 2px 6px rgba(0,0,0,.08)",
        transformOrigin: origin,
        ...style,
      }}
    >
      {children}
    </div>
  );
}

function MenuItem({
  children,
  onClick,
  checked,
  icon,
  disabled,
}: {
  children: ReactNode;
  onClick?: () => void;
  checked?: boolean;
  icon?: ReactNode;
  disabled?: boolean;
}) {
  return (
    <button
      role="menuitem"
      className={disabled ? undefined : "mi"}
      disabled={disabled}
      onClick={onClick}
      style={{
        display: "flex",
        alignItems: "center",
        gap: 6,
        width: "100%",
        height: 22,
        padding: "0 10px 0 6px",
        borderRadius: 5,
        fontSize: 13,
        letterSpacing: LS[13],
        color: disabled ? T.text3 : T.text1,
        whiteSpace: "nowrap",
      }}
    >
      <span style={{ width: 12, display: "flex", justifyContent: "center" }}>{checked ? <CheckIcon size={10} /> : null}</span>
      {icon && <span style={{ width: 16, display: "flex", justifyContent: "center" }}>{icon}</span>}
      {children}
    </button>
  );
}

function MenuSeparator() {
  return <div style={{ height: 1, margin: "5px 10px", background: T.dividerStrong }} />;
}

// MARK: - Search field

function SearchField({
  value,
  onChange,
  placeholder,
  height,
  fontSize,
  iconSize,
  textGap = 7,
  style,
}: {
  value: string;
  onChange: (v: string) => void;
  placeholder: string;
  height: number;
  fontSize: number;
  iconSize: number;
  textGap?: number;
  style?: CSSProperties;
}) {
  const [focused, setFocused] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  return (
    <div
      className="sq"
      onClick={() => inputRef.current?.focus()}
      style={{
        height,
        padding: "0 10px",
        display: "flex",
        alignItems: "center",
        gap: textGap,
        borderRadius: hr(height),
        background: T.sidebar,
        boxShadow: `inset 0 0 0 1px ${focused ? T.dividerStrong : "transparent"}`,
        transition: "box-shadow .12s ease-out",
        cursor: "text",
        ...style,
      }}
    >
      {/* The symbol's image is wider than its ink. */}
      <span style={{ color: T.text3, display: "flex", width: iconSize + 1.5, justifyContent: "center" }}>
        <MagnifierIcon size={iconSize} stroke={iconSize * 0.12} />
      </span>
      <span style={{ position: "relative", flex: 1, height: "100%", display: "flex", alignItems: "center" }}>
        {!value && (
          <span
            aria-hidden
            style={{
              position: "absolute",
              left: 0,
              fontSize,
              color: T.text3,
              letterSpacing: LS[fontSize] ?? 0,
              whiteSpace: "nowrap",
              pointerEvents: "none",
            }}
          >
            {placeholder}
          </span>
        )}
        <input
          ref={inputRef}
          value={value}
          aria-label={placeholder}
          spellCheck={false}
          onChange={(e) => onChange(e.target.value)}
          onFocus={() => setFocused(true)}
          onBlur={() => setFocused(false)}
          onKeyDown={(e) => {
            if (e.key === "Escape") onChange("");
          }}
          style={{ width: "100%", fontSize, color: T.text1, letterSpacing: LS[fontSize] ?? 0, fontFamily: UI }}
        />
      </span>
      {value && (
        <button
          aria-label="Clear search"
          title="Clear search"
          onClick={(e) => {
            e.stopPropagation();
            onChange("");
          }}
          style={{ display: "flex", color: T.text3 }}
        >
          <XCircleIcon size={fontSize - 1} />
        </button>
      )}
    </div>
  );
}

/** NSFont.monospacedSystemFont tracks SF Mono out at small sizes. */
export const MLS: Record<number, number> = { 10.5: 0.05, 11: 0.19, 12: 0.18 };

/** SwiftUI's optical tracking for SF Pro Text at these sizes, in px. */
export const LS: Record<number, number> = {
  10: 0.12,
  10.5: 0.09,
  11: 0.06,
  11.5: -0.08,
  12: 0,
  12.5: -0.04,
  13: -0.08,
  20: -0.68,
};

// MARK: - Header

function Header({ sim, state, project }: { sim: HunSim; state: SimState; project: SimProject }) {
  const status = projectStatus(project);
  const pending = project.pending;
  const running = status === "running" || status === "starting";
  const focus = state.mode === "focus";

  let primary: { title: string; icon: ReactNode; style: "primary" | "danger"; loading: boolean; action: () => void };
  if (pending === "start") {
    primary = { title: focus ? "Switch" : "Run", icon: null, style: "primary", loading: true, action: () => sim.run(project.id) };
  } else if (pending === "stop") {
    primary = { title: "Stop", icon: null, style: "danger", loading: true, action: () => sim.stop(project.id) };
  } else if (running) {
    primary = { title: "Stop", icon: <StopFillIcon />, style: "danger", loading: false, action: () => sim.stop(project.id) };
  } else {
    primary = {
      title: focus ? "Switch" : "Run",
      icon: focus ? <BoltIcon /> : <PlayFillIcon />,
      style: "primary",
      loading: false,
      action: () => sim.run(project.id),
    };
  }

  return (
    <>
      <div style={{ position: "absolute", left: 24, top: 21 }}>
        <LetterTile name={project.name} size={22} radius={6} />
      </div>
      <div
        title={project.name}
        style={{
          position: "absolute",
          left: 55,
          top: 19,
          height: 24,
          display: "flex",
          alignItems: "center",
          fontSize: 21,
          fontWeight: 600,
          color: T.text1,
          letterSpacing: LS[20],
          whiteSpace: "nowrap",
        }}
      >
        {project.name}
      </div>
      <div style={{ position: "absolute", left: 24, top: 52, height: 22, display: "flex", alignItems: "center", gap: 14 }}>
        <span style={{ fontSize: 11, color: T.text3, letterSpacing: LS[11] }}>
          {status === "running" ? "Running" : status === "starting" ? "Starting…" : "Stopped"}
        </span>
        <button
          className="chip sq press"
          title="Switch branch"
          style={{
            height: 22,
            padding: "0 7px",
            display: "flex",
            alignItems: "center",
            gap: 5,
            borderRadius: hr(22),
            background: T.white,
            boxShadow: stroke(T.divider),
            color: T.text2,
            fontSize: 11,
            fontWeight: 500,
            letterSpacing: LS[11],
          }}
        >
          <BranchIcon style={{ margin: "0 .4px 0 1px", width: 9.5 }} />
          <span>{project.branch}</span>
          <span style={{ opacity: 0.65, display: "flex", margin: "0 .9px 0 1.5px" }}>
            <ChevronDownIcon w={7} h={4} sw={1.3} />
          </span>
        </button>
        <span style={{ display: "flex", alignItems: "center", gap: 5, color: T.text3 }}>
          <FolderIcon style={{ margin: "0 .75px" }} />
          <span style={{ fontSize: 11, letterSpacing: LS[11], whiteSpace: "nowrap" }}>{project.path}</span>
        </span>
      </div>

      <div style={{ position: "absolute", right: 10, top: 35, height: 25, display: "flex", alignItems: "center", gap: 6 }}>
        <ActionButton
          title={primary.title}
          icon={primary.icon}
          kind={primary.style}
          loading={primary.loading}
          disabled={pending !== null}
          onClick={primary.action}
        />
        <ActionButton
          title="Restart"
          icon={<ClockwiseIcon />}
          kind="secondary"
          loading={pending === "restart"}
          disabled={pending !== null}
          onClick={() => sim.restart(project.id)}
        />
        <MoreMenu project={project} />
      </div>
    </>
  );
}

function ActionButton({
  title,
  icon,
  kind,
  loading,
  disabled,
  onClick,
}: {
  title: string;
  icon: ReactNode;
  kind: "primary" | "secondary" | "danger";
  loading: boolean;
  disabled: boolean;
  onClick: () => void;
}) {
  const color = kind === "primary" ? "#FFFFFF" : kind === "secondary" ? T.text1 : T.text2;
  return (
    <button
      className={`ab ab-${kind} sq press`}
      disabled={disabled}
      onClick={onClick}
      style={{
        height: 25,
        padding: "0 10px",
        display: "flex",
        alignItems: "center",
        gap: 5,
        borderRadius: hr(25),
        background: kind === "primary" ? undefined : T.white,
        boxShadow: stroke(kind === "primary" ? "rgba(255,255,255,.1)" : T.divider),
        color,
        fontSize: 12,
        fontWeight: 500,
        letterSpacing: LS[12],
        opacity: disabled && !loading ? 0.55 : 1,
        whiteSpace: "nowrap",
      }}
    >
      <span style={{ width: 11, height: 11, display: "flex", alignItems: "center", justifyContent: "center" }}>
        {loading ? <Spinner size={9} /> : icon}
      </span>
      <span style={{ padding: "0 .5px" }}>{title}</span>
    </button>
  );
}

function MoreMenu({ project }: { project: SimProject }) {
  const [open, setOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const close = useCallback(() => setOpen(false), []);
  useDismiss(open, ref, close);
  const running = project.services.some((s) => s.status !== "stopped");
  useEffect(() => {
    if (!copied) return;
    const t = setTimeout(() => setCopied(false), 1400);
    return () => clearTimeout(t);
  }, [copied]);
  return (
    <div ref={ref} style={{ position: "relative" }}>
      <button
        className="ab ab-secondary sq press"
        aria-haspopup="menu"
        aria-expanded={open}
        aria-label="More actions"
        title={copied ? "Agent prompt copied" : "More actions"}
        onClick={() => setOpen((o) => !o)}
        style={{
          width: 28,
          height: 24,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          borderRadius: hr(24),
          background: T.white,
          boxShadow: stroke(copied ? "rgba(39,131,63,.35)" : T.divider),
          color: copied ? T.success : T.text1,
        }}
      >
        {copied ? <CheckIcon size={10} /> : <EllipsisIcon />}
      </button>
      {open && (
        <Menu style={{ right: 0, top: 29 }}>
          <MenuItem onClick={close}>Edit .hun.yml</MenuItem>
          <MenuItem onClick={close} disabled={!running}>
            Save Running Services as Profile…
          </MenuItem>
          <MenuSeparator />
          <MenuItem onClick={close}>Choose Logo…</MenuItem>
          <MenuSeparator />
          <MenuItem
            onClick={() => {
              close();
              void navigator.clipboard?.writeText(`Use Hun to run ${project.name}: hun run ${project.name}`).catch(() => {});
              setCopied(true);
            }}
          >
            Copy Agent Prompt
          </MenuItem>
        </Menu>
      )}
    </div>
  );
}

// MARK: - Card: services and logs

function Card({ sim, state, project }: { sim: HunSim; state: SimState; project: SimProject }) {
  const L = useLayout();
  const cardW = L.w - (L.sidebar ? 228 : 0) - 20;
  return (
    <div
      className="sq"
      style={{
        position: "absolute",
        left: 10,
        top: 90,
        width: cardW,
        height: L.cardH,
        borderRadius: 12,
        background: T.appBg,
        overflow: "hidden",
      }}
    >
      <ServicesPanel sim={sim} project={project} />
      <div style={{ position: "absolute", left: L.servicesW, top: 0, width: 1, height: L.cardH, background: T.divider }} />
      <LogsPanel sim={sim} state={state} project={project} />
      <div
        className="sq"
        style={{ position: "absolute", inset: 0, borderRadius: 12, boxShadow: `inset 0 0 0 1px ${T.divider}`, pointerEvents: "none" }}
      />
    </div>
  );
}

function ServicesPanel({ sim, project }: { sim: HunSim; project: SimProject }) {
  const L = useLayout();
  return (
    <div style={{ position: "absolute", left: 0, top: 0, width: L.servicesW, height: L.cardH }}>
      <div style={{ height: 46, padding: "0 14px", display: "flex", alignItems: "center", gap: 6 }}>
        <span style={{ fontSize: 13, fontWeight: 600, letterSpacing: LS[13], color: T.text1 }}>Services</span>
        <span style={{ fontSize: 12, fontWeight: 500, color: T.text3, fontVariantNumeric: "tabular-nums", marginLeft: 0.5 }}>{project.services.length}</span>
      </div>
      <div style={{ height: 1, background: T.divider }} />
      <div className="slist" style={{ height: L.cardH - 47, overflowY: "auto", padding: "8px 8px 12px", display: "flex", flexDirection: "column", gap: 4 }}>
        {project.services.map((s) => (
          <ServiceRow
            key={s.id}
            service={s}
            selected={s.id === project.selectedServiceId}
            onSelect={() => sim.selectService(s.id)}
          />
        ))}
      </div>
    </div>
  );
}

export function ServiceRow({ service: s, selected, onSelect }: { service: SimService; selected: boolean; onSelect: () => void }) {
  const warming = s.status === "starting";
  const dotColor = s.status === "running" ? T.success : s.status === "starting" ? T.warning : T.text3;
  const linked = s.status === "running" && s.pid > 0 && s.port > 0;
  const help = [s.status === "running" ? "Running" : s.status === "starting" ? "Starting" : "Stopped"];
  if (s.pid > 0) help.push(`pid ${s.pid}`);
  if (s.port > 0) help.push(`port ${s.port}`);
  if (s.status === "running") help.push("ready");
  return (
    <div
      role="button"
      tabIndex={0}
      aria-pressed={selected}
      className={`srow sq ${selected ? "sel" : ""}`}
      onClick={onSelect}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onSelect();
        }
      }}
      title={help.join(" · ")}
      style={{
        flex: "none",
        padding: 12,
        display: "flex",
        alignItems: "flex-start",
        gap: 10,
        borderRadius: 12,
        outline: "none",
      }}
    >
      <span style={{ width: 8, height: 17, flex: "none", display: "flex", alignItems: "center", justifyContent: "center" }}>
        {warming ? (
          <span style={{ width: 7, height: 7, borderRadius: 99, boxShadow: `inset 0 0 0 1.5px ${dotColor}` }} />
        ) : (
          <span style={{ width: 6, height: 6, borderRadius: 99, background: dotColor, transition: "background-color .16s ease-out" }} />
        )}
      </span>
      <span style={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column", gap: 6 }}>
        <span style={{ height: 17, paddingTop: 1, display: "flex", alignItems: "center", gap: 6 }}>
          <span style={{ fontSize: 13, fontWeight: 500, color: T.text1, letterSpacing: LS[13], whiteSpace: "nowrap" }}>{s.name}</span>
          {warming && <span style={{ fontSize: 10.5, fontWeight: 500, color: T.warning, letterSpacing: LS[10.5] }}>starting</span>}
          <span style={{ flex: 1, minWidth: 8 }} />
          {s.port > 0 && (
            <span
              className={linked ? "port-link" : undefined}
              title={linked ? `Open http://localhost:${s.port}` : undefined}
              style={{ fontFamily: MONO, WebkitFontSmoothing: "antialiased", fontSize: 11, letterSpacing: MLS[11], color: linked ? T.text2 : T.text3, textUnderlineOffset: 2 }}
            >
              :{s.port}
            </span>
          )}
        </span>
        <span style={{ height: 14, display: "flex", alignItems: "center", gap: 8 }}>
          <span
            style={{
              fontFamily: MONO,
              WebkitFontSmoothing: "antialiased",
              fontSize: 11,
              letterSpacing: MLS[11],
              color: T.text3,
              whiteSpace: "nowrap",
              overflow: "hidden",
              textOverflow: "ellipsis",
              minWidth: 0,
            }}
          >
            {s.command}
          </span>
          <span style={{ flex: 1, minWidth: 8 }} />
          {s.pid > 0 && <span style={{ marginTop: 2, marginRight: 1, fontFamily: MONO, WebkitFontSmoothing: "antialiased", fontSize: 10.5, letterSpacing: MLS[10.5], color: T.text3 }}>{s.pid}</span>}
        </span>
      </span>
    </div>
  );
}

// MARK: - Logs

function useLogFilter(state: SimState, project: SimProject) {
  const L = useLayout();
  const query = state.search.trim().toLowerCase();
  const lines = state.logs[project.id];
  const service = state.scope === "service" ? project.selectedServiceId : null;
  return useMemo(() => {
    const matching = (lines ?? []).filter(
      (l) =>
        (service === null || l.service === service) &&
        (!query || l.message.toLowerCase().includes(query) || l.service.toLowerCase().includes(query)),
    );
    return fitToPane(matching, service === null, L);
  }, [lines, service, query, L]);
}

// The page shouldn't hand its scroll to the log pane, so the pane only ever
// holds what fits: the newest lines, oldest dropping off the top. Wrapped
// lines count for as many rows as they take (about 52 characters a row, fewer
// in All, where each line also carries its service's name).
function fitToPane(lines: LogLine[], combined: boolean, L: HunLayout): LogLine[] {
  // Rows of 16.5 pt in the pane; characters per row from the pane's width
  // (desktop: 27 rows, 52 characters, or 44 in All with the service column).
  const PANE_ROWS = Math.floor((L.cardH - 47) / 16.5) - 4;
  const logW = L.w - (L.sidebar ? 228 : 0) - 20 - L.servicesW - 1;
  const perRow = Math.max(16, Math.floor((logW - 140 - (combined ? 56 : 0)) / 6.6));
  let rows = 0;
  let start = lines.length;
  while (start > 0) {
    const need = L.oneLineLogs ? 1 : Math.max(1, Math.ceil(lines[start - 1].message.length / perRow));
    if (rows + need > PANE_ROWS) break;
    rows += need;
    start -= 1;
  }
  return start === 0 ? lines : lines.slice(start);
}

function LogsPanel({ sim, state, project }: { sim: HunSim; state: SimState; project: SimProject }) {
  const L = useLayout();
  const cardW = L.w - (L.sidebar ? 228 : 0) - 20;
  const visible = useLogFilter(state, project);
  const selected = project.services.find((s) => s.id === project.selectedServiceId);
  const title = state.scope === "combined" ? "All logs" : (selected?.name ?? "Logs");
  const hasLogs = visible.length > 0;
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    if (!copied) return;
    const t = setTimeout(() => setCopied(false), 1400);
    return () => clearTimeout(t);
  }, [copied]);

  const copyAll = () => {
    if (!visible.length) return;
    const text = visible.map((l) => `${l.time}  ${l.service.padEnd(10, " ")}  ${l.message}`).join("\n");
    void navigator.clipboard?.writeText(text).catch(() => {});
    setCopied(true);
  };

  return (
    <div style={{ position: "absolute", left: L.servicesW + 1, top: 0, width: cardW - L.servicesW - 1, height: L.cardH }}>
      <div style={{ height: 46, padding: "0 14px", display: "flex", alignItems: "center", gap: 10 }}>
        <span style={{ fontSize: 13, fontWeight: 600, color: T.text1, letterSpacing: LS[13], whiteSpace: "nowrap" }}>{title}</span>
        <span style={{ flex: 1 }} />
        <SearchFieldLogs value={state.search} onChange={sim.setSearch} />
        <button
          className="lb sq press"
          disabled={!hasLogs}
          onClick={copyAll}
          aria-label="Copy all visible logs"
          title={copied ? "Copied" : "Copy all visible logs (⌘C)"}
          style={{
            width: 26,
            height: 26,
            flex: "none",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            borderRadius: hr(26),
            background: T.white,
            boxShadow: stroke(copied ? "rgba(39,131,63,.3)" : T.divider),
            color: copied ? T.success : T.text2,
          }}
        >
          {copied ? <CheckIcon size={10} /> : <CopyIcon style={{ transform: "translate(.5px, .3px)" }} />}
        </button>
        <button
          className="lb sq press"
          disabled={!hasLogs}
          onClick={sim.clearLogs}
          aria-label={state.scope === "combined" ? "Clear all logs for this project" : `Clear logs for ${selected?.name ?? "this service"}`}
          title={state.scope === "combined" ? "Clear all logs for this project" : `Clear logs for ${selected?.name ?? "this service"}`}
          style={{
            width: 26,
            height: 26,
            flex: "none",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            borderRadius: hr(26),
            background: T.white,
            boxShadow: stroke(T.divider),
            color: T.text2,
          }}
        >
          <TrashIcon style={{ transform: "translateY(.5px)" }} />
        </button>
        <div
          role="radiogroup"
          aria-label="Log scope"
          className="sq"
          style={{ height: 26, padding: 2, display: "flex", borderRadius: hr(26), background: T.white, flex: "none" }}
        >
          {(
            [
              ["Service", "service"],
              ["All", "combined"],
            ] as const
          ).map(([label, value]) => (
            <button
              key={value}
              role="radio"
              aria-checked={state.scope === value}
              className="sq press"
              onClick={() => sim.setScope(value)}
              style={{
                height: 22,
                padding: value === "service" ? "0 11px 0 9.5px" : "0 10px",
                display: "flex",
                alignItems: "center",
                borderRadius: hr(22),
                fontSize: 11,
                fontWeight: 500,
                letterSpacing: LS[11],
                color: state.scope === value ? T.text1 : T.text2,
                background: state.scope === value ? T.white : "transparent",
              }}
            >
              {label}
            </button>
          ))}
        </div>
      </div>
      <div style={{ height: 1, background: T.divider }} />
      {hasLogs ? (
        <LogsTail
          key={state.scope === "combined" ? "combined" : `service|${project.selectedServiceId}`}
          lines={visible}
          showService={state.scope === "combined"}
          query={state.search.trim()}
        />
      ) : (
        <div
          style={{
            height: L.cardH - 47,
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            gap: 8,
          }}
        >
          <span style={{ color: T.text3 }}>
            <TextAlignLeftIcon />
          </span>
          <span style={{ fontSize: 12, fontWeight: 500, color: T.text2 }}>No logs yet</span>
          <span style={{ fontSize: 11, color: T.text3, letterSpacing: LS[11] }}>Output from this service will appear here.</span>
        </div>
      )}
    </div>
  );
}

function SearchFieldLogs({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  return (
    <SearchField
      value={value}
      onChange={onChange}
      placeholder="Search logs"
      height={26}
      fontSize={11.5}
      iconSize={10.5}
      textGap={8}
      style={{ width: 220, flex: "0 1 220px" }}
    />
  );
}

function LogsTail({ lines, showService, query }: { lines: LogLine[]; showService: boolean; query: string }) {
  const layout = useLayout();
  const logsHeight = layout.cardH - 47;
  const oneLine = !!layout.oneLineLogs;
  const ref = useRef<HTMLDivElement>(null);
  const [tailing, setTailing] = useState(true);
  const [newCount, setNewCount] = useState(0);
  const lastSeq = lines.length ? lines[lines.length - 1].seq : 0;
  const prevSeq = useRef(lastSeq);
  const tailingRef = useRef(true);

  const toBottom = () => {
    const el = ref.current;
    if (el) el.scrollTop = el.scrollHeight;
  };

  // Follow the live edge; while reading back, count what arrives instead.
  useLayoutEffect(() => {
    const before = prevSeq.current;
    prevSeq.current = lastSeq;
    if (tailingRef.current) toBottom();
    else if (lastSeq > before) {
      const added = lines.filter((l) => l.seq > before).length;
      setNewCount((n) => n + added);
    }
  }, [lastSeq, lines]);

  useLayoutEffect(() => {
    toBottom();
  }, [query]);

  const onScroll = () => {
    const el = ref.current;
    if (!el) return;
    const near = el.scrollTop + el.clientHeight >= el.scrollHeight - 30;
    if (near !== tailingRef.current) {
      tailingRef.current = near;
      setTailing(near);
      if (near) setNewCount(0);
    }
  };

  const indent = (showService ? 100 : 0) + 114;
  return (
    <div style={{ position: "relative", height: logsHeight }}>
      <div
        ref={ref}
        className="logs"
        onScroll={onScroll}
        style={{
          height: "100%",
          overflowY: "auto",
          padding: oneLine ? "8.5px 14px 8px" : "8.5px 22px 8px",
          fontFamily: MONO,
          WebkitFontSmoothing: "antialiased",
          userSelect: "text",
          WebkitUserSelect: "text",
          cursor: "text",
        }}
      >
        {lines.map((l, i) => (
          <div
            key={l.seq}
            style={{
              position: "relative",
              fontSize: 12,
              lineHeight: "15px",
              letterSpacing: MLS[12],
              marginBottom: i === lines.length - 1 ? 0 : 1.5,
              ...(oneLine
                ? { whiteSpace: "pre", overflow: "hidden", textOverflow: "ellipsis" }
                : { paddingLeft: indent, textIndent: -indent, whiteSpace: "pre-wrap", overflowWrap: "anywhere" }),
              color: l.level === "error" ? T.danger : l.level === "warning" ? T.warning : T.logText,
              ["--hw-glyph" as string]: l.level === "error" ? T.danger : l.level === "warning" ? T.warning : T.logText,
            }}
          >
            {i === lines.length - 1 && (
              <span aria-hidden style={{ position: "absolute", left: oneLine ? -14 : -22, right: oneLine ? -14 : -22, top: -0.5, bottom: 0.5, background: "rgba(94,106,210,.13)" }} />
            )}
            <span style={{ position: "relative", fontSize: 11, lineHeight: "11px", letterSpacing: MLS[11], color: T.logTime }}>{l.time.padEnd(13, " ") + "  "}</span>
            {showService && (
              <span style={{ position: "relative", fontSize: 11, lineHeight: "11px", letterSpacing: MLS[11], fontWeight: 500, color: serviceColor(l.service) }}>
                <Highlighted text={l.service.padEnd(10, " ")} query={query} />
                {"  "}
              </span>
            )}
            <span style={{ position: "relative" }}>
              <Highlighted text={l.message} query={query} />
            </span>
          </div>
        ))}
      </div>
      {!tailing && (
        <button
          className="lt lt-in sq"
          onClick={() => {
            tailingRef.current = true;
            setTailing(true);
            setNewCount(0);
            toBottom();
          }}
          title="Resume following the latest logs (jump to bottom)"
          style={{
            position: "absolute",
            left: "50%",
            bottom: 16,
            translate: "-50% 0",
            height: 30,
            padding: "0 14px",
            display: "flex",
            alignItems: "center",
            gap: 6,
            borderRadius: hr(30),
            background: "var(--hw-pill)",
            backdropFilter: "blur(16px)",
            WebkitBackdropFilter: "blur(16px)",
            border: `1px solid ${T.floatingBorder}`,
            boxShadow: `0 4px 20px ${T.floatingShadow}`,
            color: T.text1,
            fontFamily: UI,
            fontSize: 12,
            fontWeight: 500,
            transition: "transform .15s ease-out, border-color .15s ease-out",
            whiteSpace: "nowrap",
          }}
        >
          <ArrowDownIcon />
          Live tail
          {newCount > 0 && (
            <>
              <span style={{ fontSize: 11, color: T.text3 }}>·</span>
              <span style={{ fontSize: 11.5, fontWeight: 600, color: T.accent, fontVariantNumeric: "tabular-nums" }}>{newCount} new</span>
            </>
          )}
        </button>
      )}
    </div>
  );
}

/**
 * ✓ and ○ come from the system monospaced font in the app; browsers fall
 * back to other fonts for them, so they are drawn here, one cell wide. The
 * character stays in the text (transparent) for selection and copying.
 */
function MonoGlyph({ ch }: { ch: string }) {
  return (
    <span style={{ position: "relative", display: "inline-block", width: `calc(1ch + ${MLS[12]}px)`, color: "transparent", textIndent: 0 }}>
      {ch}
      <svg
        aria-hidden
        viewBox="0 0 7.4 15"
        width={7.4}
        height={15}
        style={{ position: "absolute", left: 0, top: 0, overflow: "visible", color: "currentcolor" }}
      >
        {ch === "✓" ? (
          <path d="M.05 7.75 2.06 10.15 6.2 5.75" fill="none" stroke="var(--hw-glyph)" strokeWidth={1.1} strokeLinecap="round" strokeLinejoin="round" />
        ) : (
          <circle cx={3.05} cy={7.75} r={3.3} fill="none" stroke="var(--hw-glyph)" strokeWidth={0.95} />
        )}
      </svg>
    </span>
  );
}

function withGlyphs(text: string, key: number): ReactNode {
  if (!/[✓○]/.test(text)) return text;
  return text.split(/([✓○])/).map((part, i) =>
    part === "✓" || part === "○" ? <MonoGlyph key={`${key}-${i}`} ch={part} /> : part,
  );
}

export function Highlighted({ text, query }: { text: string; query: string }) {
  if (!query) return <>{withGlyphs(text, 0)}</>;
  const lower = text.toLowerCase();
  const q = query.toLowerCase();
  const out: ReactNode[] = [];
  let i = 0;
  let k = 0;
  while (i < text.length) {
    const at = lower.indexOf(q, i);
    if (at < 0) break;
    if (at > i) out.push(withGlyphs(text.slice(i, at), k++));
    out.push(
      <mark key={k++} style={{ background: "rgba(252,204,77,.32)", color: "#3A3020", borderRadius: 0, padding: 0 }}>
        {text.slice(at, at + q.length)}
      </mark>,
    );
    i = at + q.length;
  }
  if (i < text.length) out.push(withGlyphs(text.slice(i), k++));
  return <>{out}</>;
}

/** The window's stylesheet (tokens on .hw, hover rules), for scenes that reuse its pieces. */
export { css as HW_CSS };
