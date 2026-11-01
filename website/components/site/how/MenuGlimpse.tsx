"use client";

import { useLayoutEffect, useRef, useState } from "react";
import { PROJECT_LOGOS } from "../logos";
import { Spinner, StopFillIcon } from "../hun-window/icons";
import type { Menu } from "./timeline";

// The corner of the screen while orbit starts: Hun's switch in the menu bar
// turns on, and its panel lists orbit with its port. Sizes and colours follow
// the menu bar recreation (../menu-bar/MenuPanel.tsx) at its real 340 pt
// width; only orbit is in this panel.

const SYS = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';
const MONO = 'ui-monospace, "SF Mono", SFMono-Regular, Menlo, monospace';
const ROUNDED = 'ui-rounded, "SF Pro Rounded", -apple-system, BlinkMacSystemFont, system-ui, sans-serif';

/** The tray lays out at this width or wider, and scales as a unit below it. */
const MIN_W = 400;
export const GLIMPSE_H = 236;
const BAR_H = 24;
const hr = (h: number) => Math.min(12, h * 0.3);

export function MenuGlimpse({ menu, animate }: { menu: Menu; animate: boolean }) {
  const outer = useRef<HTMLDivElement>(null);
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
            Sun 9:41
          </span>
        </div>

        <div className="mg-panel" style={{ fontFamily: SYS }}>
          <div style={{ height: 53, padding: "0 14px", display: "flex", alignItems: "flex-start" }}>
            <div style={{ paddingTop: 12 }}>
              <div style={{ fontSize: 13, fontWeight: 600, lineHeight: "16px", letterSpacing: -0.08 }}>Hun</div>
              <div style={{ marginTop: 1, fontSize: 11, lineHeight: "14px", color: "var(--mg-text3)", whiteSpace: "nowrap" }}>
                {on ? "1 project running" : "Nothing running"}
              </div>
            </div>
            <div style={{ flex: 1 }} />
            <div className="mg-seg" style={{ marginTop: 16, height: 24, padding: 2, display: "flex", borderRadius: hr(24) }}>
              {["Focus", "Multitask"].map((m, i) => (
                <span
                  key={m}
                  style={{
                    height: 20,
                    padding: "0 9px",
                    display: "flex",
                    alignItems: "center",
                    borderRadius: hr(20),
                    fontSize: 11,
                    fontWeight: 500,
                    letterSpacing: 0.1,
                    color: i === 0 ? "var(--mg-text1)" : "var(--mg-text2)",
                    background: i === 0 ? "var(--mg-bg)" : "transparent",
                  }}
                >
                  {m}
                </span>
              ))}
            </div>
          </div>
          <div style={{ padding: "2px 6px 6px" }}>
            {on && (
              <div style={{ padding: "6px 8px 4px", fontSize: 11, fontWeight: 500, lineHeight: "14px", color: "var(--mg-text3)" }}>Running</div>
            )}
            <Row menu={menu} t={t} />
          </div>
          <div style={{ height: 1, background: "var(--mg-divider)" }} />
          <div style={{ height: 42, padding: "0 14px", display: "flex", alignItems: "center", gap: 8, fontSize: 12.5, letterSpacing: -0.04 }}>
            <svg viewBox="-1 0 15 11" width={15} height={11} style={{ color: "var(--mg-text2)", overflow: "visible", position: "relative", top: 1 }}>
              <rect x={0.55} y={0.55} width={11.9} height={9.9} rx={2.1} fill="none" stroke="currentColor" strokeWidth={1.1} />
              <path d="M1.9 2.55h1.6" stroke="currentColor" strokeWidth={0.9} strokeLinecap="round" opacity={0.7} />
            </svg>
            <span>Open Hun</span>
            <span style={{ flex: 1 }} />
            <span style={{ fontSize: 11, color: "var(--mg-text3)" }}>⌘D</span>
          </div>
        </div>
      </div>
    </div>
  );
}

/** orbit's row: the letter tile with its ring, the port, and Stop under the pointer. */
function Row({ menu, t }: { menu: Menu; t: (p: string, ms?: number) => string }) {
  const running = menu === "running";
  return (
    <div
      style={{
        position: "relative",
        height: menu === "idle" ? 32 : 42,
        padding: "0 8px",
        display: "flex",
        alignItems: "center",
        gap: 10,
        borderRadius: hr(42),
        background: running ? "var(--mg-rowHover)" : "transparent",
        transition: t("background-color"),
      }}
    >
      <span style={{ position: "relative", width: 20, height: 20, flex: "none" }}>
        <span
          style={{
            position: "absolute",
            inset: 0,
            borderRadius: 5,
            background: "#fff",
            boxShadow: "inset 0 0 0 .5px var(--mg-divider)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontFamily: ROUNDED,
            fontSize: 9.6,
            fontWeight: 600,
            color: "var(--mg-text2)",
          }}
        >
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={PROJECT_LOGOS.orbit} alt="" draggable={false} style={{ position: "absolute", inset: 0, width: "100%", height: "100%", borderRadius: 5, objectFit: "cover" }} />
          <span style={{ position: "absolute", inset: 0, borderRadius: 5, boxShadow: "inset 0 0 0 .5px rgba(0,0,0,.14)" }} />
        </span>
        <span style={{ position: "absolute", inset: -2, borderRadius: 7, boxShadow: "inset 0 0 0 1px rgba(39,131,63,.3)", opacity: running ? 1 : 0, transition: t("opacity", 160) }} />
      </span>
      <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
        <div style={{ fontSize: 13, lineHeight: "16px", letterSpacing: -0.08, fontWeight: menu === "idle" ? 400 : 500, color: menu === "idle" ? "var(--mg-text2)" : "var(--mg-text1)" }}>
          orbit
        </div>
        {menu !== "idle" && (
          <div style={{ fontSize: 11, lineHeight: "14px", color: "var(--mg-text3)", whiteSpace: "nowrap" }}>{running ? "4 services" : "Starting..."}</div>
        )}
      </div>
      <div style={{ flex: 1 }} />
      <div style={{ display: "flex", alignItems: "center", gap: 4 }}>
        {running && (
          <span className="mg-chip" style={{ height: 22, padding: "0 7px", display: "flex", alignItems: "center", gap: 3, borderRadius: hr(22) }}>
            <span style={{ fontFamily: MONO, fontSize: 11, fontWeight: 500, letterSpacing: 0.19, lineHeight: "14px", position: "relative", top: 0.5 }}>:3000</span>
            <svg viewBox="0 0 9 9" width={9} height={9} style={{ overflow: "visible", position: "relative", top: 0.5, opacity: 0.6 }}>
              <path d="M2.1 6.9 6.8 2.2M3.1 2.1h3.8v3.8" fill="none" stroke="currentColor" strokeWidth={1.25} strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </span>
        )}
        {menu !== "idle" && (
        <span
          className="mg-btn"
          style={{
            width: 24,
            height: 22,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            borderRadius: hr(22),
            color: running ? "var(--mg-danger)" : "var(--mg-text2)",
            background: running ? "rgba(184,64,64,.14)" : "#fff",
            transition: t("background-color"),
          }}
        >
          {running ? <StopFillIcon style={{ width: 7.5, height: 7.5 }} /> : <Spinner size={10} color="var(--mg-text2)" />}
        </span>
        )}
      </div>
      {/* The pointer, resting on Stop. */}
      <svg
        viewBox="0 0 13 19"
        width={13}
        height={19}
        style={{ position: "absolute", right: 1, top: 23, opacity: running ? 1 : 0, transform: running ? "none" : "translate(6px, 8px)", transition: `${t("opacity")}, ${t("transform", 240)}`, filter: "drop-shadow(0 1px 1.2px rgba(0,0,0,.3))" }}
      >
        <path d="M1 1v14.2l3.4-3.3 2.2 5.1 2.3-1-2.2-5h4.8z" fill="#000" stroke="#fff" strokeWidth={1.1} strokeLinejoin="round" />
      </svg>
    </div>
  );
}
