"use client";

import { useLayoutEffect, useRef, useState } from "react";
import { HunWindow, WINDOW_H, WINDOW_H as H, WINDOW_W, WINDOW_W as W } from "./HunWindow";

/**
 * The interactive window in the hero. It fits the box it's given, by width and
 * by height, centred, and never grows past its real 1056×660. The frame's size
 * is pure CSS (container query units), so the server-rendered poster already
 * sits exactly where the live window will; once measured, the live window
 * replaces it, scaled (never reflowed).
 */
export function HunWindowHero({ poster, alt }: { poster: string; alt: string }) {
  const frame = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState<number | null>(null);

  useLayoutEffect(() => {
    const el = frame.current;
    if (!el) return;
    const measure = () => setScale(el.clientWidth / WINDOW_W);
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  return (
    <div className="flex h-full min-h-0 w-full items-center justify-center" style={{ containerType: "size" }}>
      <div
        ref={frame}
        className="hwh-frame hf-shot relative shrink-0 overflow-hidden rounded-[10px] bg-[var(--shot-bg)] sm:rounded-[14px]"
        style={{
          // Phones: the tray is 22px round with 12px padding, so 10px keeps the
          // corners concentric (and still clears the traffic lights).
          width: `min(100cqw, ${(W / H) * 100}cqh, ${W}px)`,
          aspectRatio: `${W} / ${H}`,
        }}
      >
        {scale === null ? (
          <>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={poster} alt={alt} width={WINDOW_W} height={WINDOW_H} className="absolute inset-0 block h-full w-full" />
              {/* Phones: the poster's own (grey, inactive) window buttons are
                painted over with the sidebar's colour, so only the small
                lights ever show while the live window loads. */}
            <span
              aria-hidden
              className="hwh-poster-mask pointer-events-none absolute left-0 top-0"
              style={{ width: `${(84 / WINDOW_W) * 100}%`, height: `${(32 / WINDOW_H) * 100}%`, background: "#F2F2EC" }}
            />
          <svg viewBox={`0 0 ${WINDOW_W} ${WINDOW_H}`} className="hwh-tl-poster pointer-events-none absolute inset-0 h-full w-full" aria-hidden="true">
              {(
                [
                  ["#FF5F57", 16],
                  ["#FEBC2E", 39],
                  ["#28C840", 62],
                ] as const
              ).map(([fill, cx]) => (
                <circle key={cx} cx={cx} cy={16} r={6.5} fill={fill} stroke="rgba(0,0,0,.12)" strokeWidth={0.5} />
              ))}
            </svg>
          </>
        ) : (
          <div
            role="region"
            aria-label={alt}
            style={{
              position: "absolute",
              left: 0,
              top: 0,
              width: WINDOW_W,
              height: WINDOW_H,
              transform: scale === 1 ? undefined : `scale(${scale})`,
              transformOrigin: "0 0",
            }}
          >
            <HunWindow />
          </div>
        )}
        {/* Phones: the lights at a size and inset that read small, rather than
            the desktop ones shrunk into the corner. Chosen by CSS, so they sit
            in their final place from the first frame, before any script runs. */}
        <span aria-hidden className="hwh-tl-small pointer-events-none absolute" style={{ left: 8, top: 7, gap: 3 }}>
          {["#FF5F57", "#FEBC2E", "#28C840"].map((c) => (
            <span key={c} style={{ width: 4.5, height: 4.5, borderRadius: 99, background: c, boxShadow: "inset 0 0 0 .5px rgba(0,0,0,.14)" }} />
          ))}
        </span>
        <style>{`
          .hwh-tl-small, .hwh-poster-mask { display: none; }
          @media (max-width: 639.98px) {
            .hwh-tl-small { display: flex; }
            .hwh-poster-mask { display: block; }
            .hwh-frame .hw-tl, .hwh-frame .hwh-tl-poster { display: none; }
          }
        `}</style>
      </div>
    </div>
  );
}

/**
 * Phones: the window at a readable size inside a frame you can swipe
 * sideways. It opens on the project's header and services; the logs are a
 * swipe to the right. Same live window as on desktop.
 */

/**
 * Phones: the same window in its compact layout (no sidebar, a narrower
 * services column, wider logs), scaled to fit the width. Logs keep streaming,
 * but it doesn't take touches, so scrolling the page always scrolls the page.
 */
