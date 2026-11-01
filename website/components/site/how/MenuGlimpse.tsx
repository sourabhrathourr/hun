"use client";

import { useLayoutEffect, useRef, useState } from "react";
import { PROJECT_LOGOS } from "../logos";
import { Spinner } from "../hun-window/icons";
import type { Menu } from "./timeline";
import { menuBarClock, panelDate, useNow } from "../menu-bar/use-now";

// The corner of the screen while orbit starts: Hun's switch in the menu bar
// turns on, the panel's count goes from 0 to 1, and orbit's switch flips on.
// Follows the menu bar recreation (../menu-bar/MenuPanel.tsx) at its real
// 340 pt width; only orbit is in this panel.

const SYS = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';
const MONO = 'ui-monospace, "SF Mono", SFMono-Regular, Menlo, monospace';
const ROUNDED = 'ui-rounded, "SF Pro Rounded", -apple-system, BlinkMacSystemFont, system-ui, sans-serif';

/** The tray lays out at this width or wider, and scales as a unit below it. */
const MIN_W = 400;
export const GLIMPSE_H = 236;
const BAR_H = 24;

export function MenuGlimpse({ menu, animate }: { menu: Menu; animate: boolean }) {
  const outer = useRef<HTMLDivElement>(null);
  const now = useNow();
  const [w, setW] = useState<number | null>(null);
  useLayoutEffect(() => {
    const el = outer.current;
    if (!el) return;
    const m = () => setW(el.clientWidth);
    m();
    const ro = new ResizeObserver(m);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  const layoutW = w === null ? MIN_W : Math.max(w, MIN_W);
  const scale = w === null || w >= MIN_W ? 1 : w / MIN_W;
  const on = menu !== "idle";
  const t = (prop: string, ms = 200) => (animate ? `${prop} ${ms}ms cubic-bezier(.23,1,.32,1)` : "none");

  return (
    <div ref={outer} className="mg" style={{ height: GLIMPSE_H * scale }}>
      <div
        className="mg-tray"
        style={{
          width: layoutW,
          height: GLIMPSE_H,
          borderRadius: 20 / scale,
          transform: scale === 1 ? undefined : `scale(${scale})`,
        }}
      >
        <div className="mg-bar" style={{ height: BAR_H, fontFamily: SYS }}>
          <span className="mg-item" style={{ padding: "0 5px" }}>
            <span style={{ position: "relative", width: 24, height: 16, display: "block" }}>
              <svg viewBox="0 0 24 16" width={24} height={16} style={{ position: "absolute", inset: 0, opacity: on ? 1 : 0, transition: t("opacity", 160) }}>
                <path fillRule="evenodd" fill="currentColor" d="M8 2h8a6 6 0 0 1 0 12H8A6 6 0 0 1 8 2zM16 4.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7z" />
              </svg>
              <svg viewBox="0 0 24 16" width={24} height={16} style={{ position: "absolute", inset: 0, opacity: on ? 0 : 1, transition: t("opacity", 160) }}>
                <rect x={2.75} y={2.75} width={18.5} height={10.5} rx={5.25} fill="none" stroke="currentColor" strokeWidth={1.5} />
                <circle cx={8} cy={8} r={3.5} fill="currentColor" />
              </svg>
            </span>
          </span>
          <span className="mg-item">
            <svg viewBox="0 0 27 13" width={27} height={13}>
              <rect x={0.5} y={0.5} width={23} height={12} rx={3.6} fill="none" stroke="currentColor" strokeOpacity={0.45} />
              <rect x={2} y={2} width={16} height={9} rx={2.2} fill="currentColor" />
              <path d="M25 4.6v3.8c.8-.3 1.3-1.1 1.3-1.9s-.5-1.6-1.3-1.9z" fill="currentColor" fillOpacity={0.45} />
            </svg>
          </span>
          <span className="mg-item">
            <svg viewBox="0 -1.5 17 14" width={17} height={14}>
              <path d="M8.5 12.2 10.7 9.6a3.4 3.4 0 0 0-4.4 0z" fill="currentColor" />
              <path d="M4.9 7.9a5.5 5.5 0 0 1 7.2 0M2.5 5.1a9 9 0 0 1 12 0M.8 2.6a11.6 11.6 0 0 1 15.4 0" fill="none" stroke="currentColor" strokeWidth={1.6} strokeLinecap="round" />
            </svg>
          </span>
          <span className="mg-item" style={{ fontWeight: 500, paddingRight: 4, letterSpacing: "-0.08px" }}>
            {menuBarClock(now)}
          </span>
        </div>

        <div className="mg-panel" style={{ fontFamily: SYS }}>
          {/* The sky: the date and how many projects run. */}
          <div style={{ height: 116, paddingTop: 22, display: "flex", flexDirection: "column", alignItems: "center", color: "var(--mg-ink)" }}>
            <div style={{ fontSize: 12.5, fontWeight: 600, opacity: 0.7 }}>{panelDate(now)}</div>
            <div style={{ fontFamily: ROUNDED, fontSize: 56, fontWeight: 600, lineHeight: 1, opacity: 0.78, marginTop: 4 }}>{on ? 1 : 0}</div>
            <div style={{ fontSize: 12.5, fontWeight: 500, opacity: 0.72, marginTop: 2 }}>{on ? "running" : "all quiet"}</div>
          </div>
          <div className="mg-sill">
            <div style={{ padding: 6 }}>
              <Row menu={menu} t={t} />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

/** orbit's row: its logo, its ports once it runs, and Hun's switch flipping on. */
function Row({ menu, t }: { menu: Menu; t: (p: string, ms?: number) => string }) {
  const running = menu === "running";
  const on = menu !== "idle";
  return (
    <div
      style={{
        position: "relative",
        padding: "6px 8px",
        display: "flex",
        alignItems: "center",
        gap: 10,
        borderRadius: 12,
        background: on ? "var(--mg-rowHover)" : "transparent",
        transition: t("background-color"),
      }}
    >
      <span style={{ position: "relative", width: 22, height: 22, flex: "none", borderRadius: 6, overflow: "hidden", boxShadow: "inset 0 0 0 .5px var(--mg-divider)" }}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={PROJECT_LOGOS.orbit} alt="" draggable={false} style={{ position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover" }} />
      </span>
      <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
        <div style={{ fontSize: 13, lineHeight: "16px", fontWeight: on ? 600 : 400, color: on ? "var(--mg-text1)" : "var(--mg-text2)" }}>orbit</div>
        {menu === "starting" && <div style={{ fontSize: 11, lineHeight: "14px", color: "var(--mg-text3)" }}>Starting...</div>}
        {running && (
          <div style={{ display: "flex", gap: 4 }}>
            {[3000, 5432, 8000].map((port) => (
              <span key={port} style={{ height: 17, padding: "0 5px", display: "flex", alignItems: "center", borderRadius: 5, fontFamily: MONO, fontSize: 10.5, color: "var(--mg-text3)", background: "rgba(31,27,22,.05)" }}>
                :{port}
              </span>
            ))}
          </div>
        )}
      </div>
      <div style={{ flex: 1 }} />
      {/* Hun's switch. */}
      <span style={{ position: "relative", width: 34, height: 20, flex: "none", borderRadius: 10, background: on ? "var(--mg-success)" : "rgba(138,129,116,.3)", transition: t("background-color", 250) }}>
        <span
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
            transition: animateKnob(t),
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          {menu === "starting" && <Spinner size={8} color="var(--mg-text3)" />}
        </span>
      </span>
      {/* The pointer, having flipped the switch. */}
      <svg
        viewBox="0 0 13 19"
        width={13}
        height={19}
        style={{ position: "absolute", right: 4, top: 22, opacity: on ? 1 : 0, transform: on ? "none" : "translate(6px, 8px)", transition: `${t("opacity")}, ${t("transform", 240)}`, filter: "drop-shadow(0 1px 1.2px rgba(0,0,0,.3))" }}
      >
        <path d="M1 1v14.2l3.4-3.3 2.2 5.1 2.3-1-2.2-5h4.8z" fill="#000" stroke="#fff" strokeWidth={1.1} strokeLinejoin="round" />
      </svg>
    </div>
  );
}

/** The knob springs across, like the app's. */
function animateKnob(t: (p: string, ms?: number) => string) {
  const base = t("transform", 280);
  return base === "none" ? "none" : base.replace("cubic-bezier(.23,1,.32,1)", "cubic-bezier(.34,1.4,.64,1)");
}
