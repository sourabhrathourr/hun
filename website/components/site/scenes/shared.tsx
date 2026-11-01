"use client";

// Pieces the section scenes share: motion preferences, visibility, the
// ?shot switch, a box that fits a composition to its width, and the app's
// card and log line, built from the window recreation's tokens.

import { type CSSProperties, type ReactNode, useEffect, useLayoutEffect, useRef, useState } from "react";
import { HW_CSS, Highlighted, MLS, MONO, T } from "../hun-window/HunWindow";
import { type LogLine, serviceColor } from "../hun-window/sim";

/** The page's ease-out, for everything that moves. */
export const EASE = "cubic-bezier(.23, 1, .32, 1)";

export function useReducedMotion() {
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

/** `?shot` in the URL: show each scene's settled state, for screenshots. */
export function useShot() {
  const [shot, setShot] = useState(false);
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setShot(new URLSearchParams(window.location.search).has("shot"));
  }, []);
  return shot;
}

/** Whether the element is on screen (any of it) and the tab is visible. */
export function useOnScreen(ref: React.RefObject<HTMLElement | null>, threshold = 0) {
  const [on, setOn] = useState(false);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    let visible = false;
    const update = () => setOn(visible && document.visibilityState === "visible");
    const io = new IntersectionObserver(
      ([e]) => {
        visible = e.isIntersecting;
        update();
      },
      { threshold },
    );
    io.observe(el);
    document.addEventListener("visibilitychange", update);
    return () => {
      io.disconnect();
      document.removeEventListener("visibilitychange", update);
    };
  }, [ref, threshold]);
  return on;
}

/**
 * Lays a composition out at its natural size and scales it down, as a unit,
 * when the box is narrower. `narrowBelow` hands the composition a compact
 * layout on small screens before any scaling is needed.
 */
export function Fit({
  children,
  narrowBelow,
  minHeight,
}: {
  children: (narrow: boolean) => ReactNode;
  narrowBelow: number;
  minHeight: number;
}) {
  const outer = useRef<HTMLDivElement>(null);
  const inner = useRef<HTMLDivElement>(null);
  const [box, setBox] = useState<{ w: number; iw: number; ih: number } | null>(null);

  useLayoutEffect(() => {
    const o = outer.current;
    const i = inner.current;
    if (!o || !i) return;
    const measure = () => setBox({ w: o.clientWidth, iw: i.offsetWidth, ih: i.offsetHeight });
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(o);
    ro.observe(i);
    return () => ro.disconnect();
  }, []);

  const narrow = box !== null && box.w < narrowBelow;
  // A hidden Fit (display: none on this screen size) measures 0 wide.
  const scale = box === null || box.iw === 0 || box.w === 0 ? 1 : Math.min(1, box.w / box.iw);
  return (
    <div ref={outer} style={{ position: "relative", width: "100%", height: box ? box.ih * scale : minHeight }}>
      <div
        ref={inner}
        style={{
          position: "absolute",
          top: 0,
          left: box ? (box.w - box.iw * scale) / 2 : 0,
          width: "max-content",
          transform: scale === 1 ? undefined : `scale(${scale})`,
          transformOrigin: "0 0",
          visibility: box ? undefined : "hidden",
        }}
      >
        {children(narrow)}
      </div>
    </div>
  );
}

/** The window's stylesheet, plus what the scenes add on top. */
const css = `
.hs-card { position: relative; background: ${T.appBg}; border-radius: 12px; overflow: hidden;
  box-shadow: 0 0 0 .5px rgba(31,27,22,.2), 0 1px 2px rgba(31,27,22,.05), 0 30px 60px -28px rgba(64,44,16,.42), 0 12px 24px -16px rgba(64,44,16,.16); }
.hs-card::after { content: ""; position: absolute; inset: 0; border-radius: inherit; box-shadow: inset 0 0 0 1px ${T.divider}; pointer-events: none; corner-shape: inherit; }
`;

export function Styles() {
  return (
    <>
      <style>{HW_CSS}</style>
      <style>{css}</style>
    </>
  );
}

/** A floating card in the app's light look: the Services panel's fill, 12 pt corners. */
export function Card({ children, style, className = "" }: { children: ReactNode; style?: CSSProperties; className?: string }) {
  return (
    <div className={`hs-card sq ${className}`} style={style}>
      {children}
    </div>
  );
}

/** The Services panel's header: same type and height as in the window. */
export function ServicesHeader({ count }: { count: string }) {
  return (
    <>
      <div style={{ height: 46, padding: "0 14px", display: "flex", alignItems: "center", gap: 6 }}>
        <span style={{ fontSize: 13, fontWeight: 600, letterSpacing: -0.08, color: T.text1 }}>Services</span>
        <span style={{ fontSize: 12, fontWeight: 500, color: T.text3, fontVariantNumeric: "tabular-nums", marginLeft: 0.5 }}>{count}</span>
      </div>
      <div style={{ height: 1, background: T.divider }} />
    </>
  );
}

/** Row metrics of the log pane: 15 pt lines, 1.5 pt apart. */
export const LOG_ROW = 16.5;

/**
 * The newest lines of the log pane, in the window's type, with the last line
 * highlighted. Older lines slide up and fade as they leave the top.
 */
export function LogTail({
  lines,
  rows,
  showService,
  animate,
}: {
  lines: LogLine[];
  rows: number;
  showService: boolean;
  animate: boolean;
}) {
  const padTop = 8.5;
  const padBottom = 8;
  const height = padTop + rows * LOG_ROW - 1.5 + padBottom;
  const shift = Math.max(0, lines.length - rows) * LOG_ROW;
  const transition = animate ? `transform 240ms ${EASE}` : "none";
  return (
    <div style={{ position: "relative", height, overflow: "hidden" }}>
      <div
        style={{
          padding: `${padTop}px 22px ${padBottom}px`,
          fontFamily: MONO,
          WebkitFontSmoothing: "antialiased",
          transform: `translateY(${-shift}px)`,
          transition,
        }}
      >
        {lines.map((l, i) => {
          const last = i === lines.length - 1;
          const gone = i < lines.length - rows;
          const ink = l.level === "error" ? T.danger : l.level === "warning" ? T.warning : T.logText;
          return (
            <div
              key={l.seq}
              style={{
                position: "relative",
                height: 15,
                marginBottom: last ? 0 : 1.5,
                fontSize: 12,
                lineHeight: "15px",
                letterSpacing: MLS[12],
                color: ink,
                ["--hw-glyph" as string]: ink,
                opacity: gone ? 0 : 1,
                transition: animate ? `opacity 200ms ${EASE}` : "none",
              }}
            >
              {last && (
                <span aria-hidden style={{ position: "absolute", left: -22, right: -22, top: -0.5, bottom: 0.5, background: "rgba(94,106,210,.13)" }} />
              )}
              <span style={{ position: "relative", display: "block", whiteSpace: "pre", overflow: "hidden", textOverflow: "ellipsis" }}>
                <span style={{ fontSize: 11, letterSpacing: MLS[11], color: T.logTime }}>{l.time.padEnd(13, " ") + "  "}</span>
                {showService && (
                  <span style={{ fontSize: 11, letterSpacing: MLS[11], fontWeight: 500, color: serviceColor(l.service) }}>
                    {l.service.padEnd(10, " ") + "  "}
                  </span>
                )}
                <Highlighted text={l.message} query="" />
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}
