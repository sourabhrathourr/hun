import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { ImageResponse } from "next/og";
import type { ReactNode } from "react";
import { HUN_MARK_TILE } from "@/components/site/hun-mark";

// Hun's social cards, 1200 × 630: one of the site's photographs, full bleed
// in a rounded tray, with a cream card holding the page's title. It's the
// same tray-and-card the pages themselves use.
// Fonts are static cuts of the site's own: Bricolage Grotesque (opsz 96)
// for display, Instrument Sans for text, JetBrains Mono for addresses.

export const OG_SIZE = { width: 1200, height: 630 };
export const OG_CONTENT_TYPE = "image/png";

const C = {
  paper: "#F5F0E6",
  raised: "#FFFCF6",
  ink: "#1F1B16",
  heading: "#2B2622",
  ink2: "#4F483F",
  ink3: "#6E675C",
  accent: "#C24A1F",
  tray: "#EAE2D2",
};

const ROOT = process.cwd();
const files = new Map<string, Promise<Buffer>>();
const read = (path: string) => {
  let f = files.get(path);
  if (!f) {
    f = readFile(join(ROOT, path));
    files.set(path, f);
  }
  return f;
};

async function fonts() {
  const [b7, b6, i4, i5, mono] = await Promise.all([
    read("lib/og/fonts/bricolage-700.woff"),
    read("lib/og/fonts/bricolage-600.woff"),
    read("lib/og/fonts/instrument-400.woff"),
    read("lib/og/fonts/instrument-500.woff"),
    read("lib/og/fonts/jetbrains-mono.ttf"),
  ]);
  return [
    { name: "Bricolage", data: b7, weight: 700 as const, style: "normal" as const },
    { name: "Bricolage", data: b6, weight: 600 as const, style: "normal" as const },
    { name: "Instrument", data: i4, weight: 400 as const, style: "normal" as const },
    { name: "Instrument", data: i5, weight: 500 as const, style: "normal" as const },
    { name: "Mono", data: mono, weight: 400 as const, style: "normal" as const },
  ];
}

/** A file from public/ as a data URI, for <img src>. */
export async function publicImage(path: string) {
  const data = await read(join("public", path));
  const type = path.endsWith(".png") ? "image/png" : "image/jpeg";
  return `data:${type};base64,${data.toString("base64")}`;
}

export async function renderOG(node: ReactNode) {
  return new ImageResponse(node as React.ReactElement, { ...OG_SIZE, fonts: await fonts() });
}

/* ── Pieces ─────────────────────────────────────────────────────────────── */

function Mark({ size }: { size: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24">
      <path d={HUN_MARK_TILE} fill={C.ink} />
      <rect x="3.5" y="7" width="17" height="10" rx="5" fill={C.paper} fillOpacity=".2" />
      <circle cx="15.5" cy="12" r="4.1" fill={C.paper} />
    </svg>
  );
}

function Brand() {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
      <Mark size={34} />
      <span style={{ fontFamily: "Bricolage", fontWeight: 600, fontSize: 30, letterSpacing: -0.6, color: C.heading }}>Hun</span>
    </div>
  );
}

function Eyebrow({ children }: { children: ReactNode }) {
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        height: 38,
        padding: "0 16px",
        borderRadius: 99,
        fontFamily: "Instrument",
        fontWeight: 500,
        fontSize: 19,
        color: C.ink2,
        background: "rgba(31,27,22,.055)",
      }}
    >
      {children}
    </div>
  );
}

/** Display sizes step down as titles get longer, so every card keeps its shape. */
function titleSize(title: string) {
  const n = title.length;
  if (n <= 14) return 78;
  if (n <= 22) return 68;
  if (n <= 34) return 60;
  return 52;
}

function clip(text: string, max: number) {
  if (text.length <= max) return text;
  const cut = text.slice(0, max);
  return `${cut.slice(0, cut.lastIndexOf(" "))}…`;
}

/* ── SceneCard ──────────────────────────────────────────────────────────── */

export type SceneCardProps = {
  /** A photograph in public/, e.g. /site/bg/pricing-hero.jpg. */
  image: string;
  /** Where the photo's subject is; the card covers the left. */
  focus?: "center" | "right";
  eyebrow?: string;
  title: string;
  description?: string;
  /** Replaces the description, e.g. the price. */
  feature?: ReactNode;
  /** Shown under the title, e.g. the latest version. */
  badge?: string;
  /** The page's address, without https://. */
  address: string;
};

export async function sceneCard(p: SceneCardProps) {
  const src = await publicImage(p.image);
  const size = titleSize(p.title.split("\n").reduce((a, b) => (a.length > b.length ? a : b)));
  return renderOG(
    <div style={{ width: 1200, height: 630, display: "flex", position: "relative", background: C.paper }}>
      {/* The tray: the photo, inset like on the site. */}
      <div style={{ position: "absolute", left: 24, top: 24, right: 24, bottom: 24, display: "flex", borderRadius: 34, overflow: "hidden", background: C.tray }}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={src}
          alt=""
          width={1152}
          height={582}
          style={{ width: 1152, height: 582, objectFit: "cover", objectPosition: p.focus === "right" ? "right center" : "center" }}
        />
      </div>

      {/* The card. */}
      <div
        style={{
          position: "absolute",
          left: 64,
          top: 64,
          bottom: 64,
          width: 640,
          display: "flex",
          flexDirection: "column",
          padding: "42px 48px 38px",
          borderRadius: 26,
          background: C.raised,
          boxShadow: "0 0 0 1px rgba(31,27,22,.14), 0 40px 80px -36px rgba(64,44,16,.55), 0 14px 28px -18px rgba(64,44,16,.25)",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <Brand />
          {p.eyebrow ? <Eyebrow>{p.eyebrow}</Eyebrow> : null}
        </div>

        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center" }}>
          {p.badge ? (
            <div style={{ display: "flex", marginBottom: 18 }}>
              <span
                style={{
                  display: "flex",
                  padding: "6px 14px",
                  borderRadius: 99,
                  background: "rgba(194,74,31,.1)",
                  color: C.accent,
                  fontFamily: "Mono",
                  fontSize: 19,
                }}
              >
                {p.badge}
              </span>
            </div>
          ) : null}
          <div
            style={{
              display: "flex",
              fontFamily: "Bricolage",
              fontWeight: 700,
              fontSize: size,
              lineHeight: 1.02,
              letterSpacing: -size * 0.035,
              color: C.heading,
              flexDirection: "column",
            }}
          >
            {p.title.split("\n").map((line) => (
              <span key={line}>{line}</span>
            ))}
          </div>
          {p.feature ? (
            <div style={{ display: "flex", marginTop: 22 }}>{p.feature}</div>
          ) : p.description ? (
            <div
              style={{
                display: "flex",
                marginTop: 20,
                fontFamily: "Instrument",
                fontSize: 25,
                lineHeight: 1.42,
                color: C.ink2,
              }}
            >
              {clip(p.description, 120)}
            </div>
          ) : null}
        </div>

        <div style={{ display: "flex", fontFamily: "Mono", fontSize: 19, color: C.ink3 }}>{p.address}</div>
      </div>
    </div>,
  );
}

/** The price, as the pricing card shows it. */
export function PriceFeature({ price, note }: { price: string; note: string }) {
  return (
    <div style={{ display: "flex", alignItems: "baseline", gap: 16 }}>
      <span style={{ fontFamily: "Bricolage", fontWeight: 700, fontSize: 96, lineHeight: 1, letterSpacing: -4, color: C.heading }}>{price}</span>
      <span style={{ fontFamily: "Instrument", fontSize: 24, color: C.ink3 }}>{note}</span>
    </div>
  );
}
