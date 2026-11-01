// Hand-drawn stand-ins for the SF Symbols the window uses, sized to the ink
// of each symbol at the weight and point size the app draws it.

import type { CSSProperties } from "react";

type P = { style?: CSSProperties; color?: string };

const base = (w: number, h: number, style?: CSSProperties): CSSProperties => ({
  display: "block",
  width: w,
  height: h,
  flex: "none",
  overflow: "visible",
  ...style,
});

export function MagnifierIcon({ size = 11, stroke = 1.3, style, color = "currentColor" }: P & { size?: number; stroke?: number }) {
  const r = size * 0.355;
  const c = r + stroke / 2;
  const d = c + r * 0.72;
  return (
    <svg viewBox={`0 0 ${size} ${size}`} style={base(size, size, style)} aria-hidden>
      <circle cx={c} cy={c} r={r} fill="none" stroke={color} strokeWidth={stroke} />
      <path d={`M${d} ${d}L${size - stroke * 0.55} ${size - stroke * 0.55}`} stroke={color} strokeWidth={stroke * 1.12} strokeLinecap="round" />
    </svg>
  );
}

export function PlusIcon({ style, color = "currentColor" }: P) {
  return (
    <svg viewBox="0 0 9.5 9.5" style={base(9.5, 9.5, style)} aria-hidden>
      <path d="M4.75 .7v8.1M.7 4.75h8.1" stroke={color} strokeWidth={1.4} strokeLinecap="round" />
    </svg>
  );
}

export function FolderFillIcon({ style, color = "currentColor" }: P) {
  return (
    <svg viewBox="0 0 13.5 11" style={base(13.5, 11, style)} aria-hidden>
      <path
        d="M0 1.6C0 .7.6.1 1.5.1h2.9c.6 0 .9.2 1.3.6l.5.6c.2.2.4.3.8.3h5c.9 0 1.5.6 1.5 1.5v.3H0z"
        fill={color}
      />
      <path d="M0 3.4h13.5v6.1c0 .9-.6 1.5-1.5 1.5H1.5C.6 11 0 10.4 0 9.5z" fill={color} />
    </svg>
  );
}

export function FolderIcon({ style, color = "currentColor" }: P) {
  return (
    <svg viewBox="0 0 11.5 9" style={base(11.5, 9, style)} aria-hidden>
      <path
        d="M.5 1.6c0-.6.4-1.1 1.1-1.1h2.5c.4 0 .7.1.9.4l.6.7h4.3c.6 0 1.1.5 1.1 1.1v5.2c0 .6-.5 1.1-1.1 1.1H1.6c-.7 0-1.1-.5-1.1-1.1zM.5 3.1h10.5"
        fill="none"
        stroke={color}
        strokeWidth={0.95}
        strokeLinejoin="round"
      />
    </svg>
  );
}

export function SplitIcon({ style, color = "currentColor" }: P) {
  return (
    <svg viewBox="0 0 13 10.5" style={base(13, 10.5, style)} aria-hidden>
      <path d="M1.6 0h4.6v10.5H1.6C.7 10.5 0 9.8 0 8.9V1.6C0 .7.7 0 1.6 0z" fill={color} />
      <path d="M6.8 0h4.6c.9 0 1.6.7 1.6 1.6v7.3c0 .9-.7 1.6-1.6 1.6H6.8z" fill={color} />
    </svg>
  );
}

export function BoltIcon({ style, color = "currentColor" }: P) {
  return (
    <svg viewBox="0 0 8 11" style={base(8, 11, style)} aria-hidden>
      <path d="M4.9 0 .3 6.2h3.1L2.6 11l4.9-6.4H4.3z" fill={color} />
    </svg>
  );
}

export function ChevronUpDownIcon({ style, color = "currentColor" }: P) {
  return (
    <svg viewBox="0 0 6 8" style={base(6, 8, style)} aria-hidden>
      <path d="M.6 2.7 3 .6l2.4 2.1M.6 5.3 3 7.4l2.4-2.1" fill="none" stroke={color} strokeWidth={1.05} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function GearIcon({ style, color = "currentColor" }: P) {
  // Eight rounded teeth around a ring, with a hole in the middle.
  const pts: string[] = [];
  const teeth = 8;
  const ro = 6.0;
  const ri = 4.55;
  for (let i = 0; i < teeth; i++) {
    const a = (i / teeth) * Math.PI * 2 - Math.PI / 2;
    const w = (Math.PI / teeth) * 0.52;
    const g = (Math.PI / teeth) * 0.62;
    const P = (r: number, t: number) => `${(6.5 + r * Math.cos(t)).toFixed(3)} ${(6.5 + r * Math.sin(t)).toFixed(3)}`;
    pts.push(`${i === 0 ? "M" : "L"}${P(ri, a - g - w * 0.2)}`, `L${P(ro, a - w)}`, `L${P(ro, a + w)}`, `L${P(ri, a + g + w * 0.2)}`);
  }
  return (
    <svg viewBox="0 0 13 13" style={base(13, 13, style)} aria-hidden>
      <path d={pts.join("") + "Z"} fill="none" stroke={color} strokeWidth={1.05} strokeLinejoin="round" />
      <circle cx={6.5} cy={6.5} r={1.85} fill="none" stroke={color} strokeWidth={1.05} />
    </svg>
  );
}

export function SidebarIcon({ style, color = "currentColor" }: P) {
  return (
    <svg viewBox="0 0 14 11" style={base(14, 11, style)} aria-hidden>
      <rect x={0.5} y={0.5} width={13} height={10} rx={2.3} fill="none" stroke={color} strokeWidth={1} />
      <path d="M5 .5v10" stroke={color} strokeWidth={1} />
      <path d="M2 2.9h1.8M2 4.4h1.8M2 5.9h1.8" stroke={color} strokeWidth={0.8} opacity={0.85} />
    </svg>
  );
}

export function BranchIcon({ style, color = "currentColor" }: P) {
  return (
    <svg viewBox="0 0 10 10" style={base(10, 10, style)} aria-hidden>
      <path d="M5 9.4V5.1L1.6 1.7M5 5.1l3.4-3.4" fill="none" stroke={color} strokeWidth={1.15} strokeLinecap="butt" strokeLinejoin="round" />
      <path d="M.3 .3h3l-3 3zM9.7 .3h-3l3 3z" fill={color} />
    </svg>
  );
}

export function ChevronDownIcon({ w = 7, h = 4, sw = 1.25, style, color = "currentColor" }: P & { w?: number; h?: number; sw?: number }) {
  return (
    <svg viewBox={`0 0 ${w} ${h}`} style={base(w, h, style)} aria-hidden>
      <path d={`M${sw / 2} ${sw / 2}L${w / 2} ${h - sw / 2}L${w - sw / 2} ${sw / 2}`} fill="none" stroke={color} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function ChevronRightIcon({ style, color = "currentColor" }: P) {
  return (
    <svg viewBox="0 0 5 8" style={base(5, 8, style)} aria-hidden>
      <path d="M.9.9 4.1 4 .9 7.1" fill="none" stroke={color} strokeWidth={1.4} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function StopFillIcon({ style, color = "currentColor" }: P) {
  return (
    <svg viewBox="0 0 8.5 8.5" style={base(8.5, 8.5, style)} aria-hidden>
      <rect width={8.5} height={8.5} rx={1.4} fill={color} />
    </svg>
  );
}

export function PlayFillIcon({ style, color = "currentColor" }: P) {
  return (
    <svg viewBox="0 0 8 9.5" style={base(8, 9.5, style)} aria-hidden>
      <path d="M1.4.2C.7-.2 0 .2 0 1v7.5c0 .8.7 1.2 1.4.8l6.1-3.7c.6-.4.6-1.2 0-1.6z" fill={color} />
    </svg>
  );
}

export function ClockwiseIcon({ style, color = "currentColor" }: P) {
  const cx = 4.3;
  const cy = 6.45;
  const r = 3.75;
  const a = (-22 * Math.PI) / 180;
  return (
    <svg viewBox="0 0 8.6 10.8" style={base(8.6, 10.8, style)} aria-hidden>
      <path
        d={`M${cx} ${cy - r}A${r} ${r} 0 1 0 ${cx + r * Math.cos(a)} ${cy + r * Math.sin(a)}`}
        fill="none"
        stroke={color}
        strokeWidth={1.2}
        strokeLinecap="round"
      />
      <path d={`M${cx - 0.9} ${0.75}L${cx + 1.15} ${cy - r}L${cx - 0.9} ${cy - r + 1.95}`} fill="none" stroke={color} strokeWidth={1.2} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function EllipsisIcon({ style, color = "currentColor" }: P) {
  return (
    <svg viewBox="0 0 11 2.4" style={base(11, 2.4, style)} aria-hidden>
      <circle cx={1.2} cy={1.2} r={1.2} fill={color} />
      <circle cx={5.5} cy={1.2} r={1.2} fill={color} />
      <circle cx={9.8} cy={1.2} r={1.2} fill={color} />
    </svg>
  );
}

export function CopyIcon({ style, color = "currentColor", bg = "#FFFFFF" }: P & { bg?: string }) {
  // doc.on.doc: a back page up and to the right, a front page over it; both
  // with a folded corner.
  return (
    <svg viewBox="0 0 11 13.5" style={base(11, 13.5, style)} aria-hidden>
      <path d="M3.85 2.8V1.1c0-.33.27-.6.6-.6h3.7l2.35 2.4v6.7c0 .33-.27.6-.6.6H7.6" fill="none" stroke={color} strokeWidth={1.1} strokeLinejoin="round" />
      <path d="M.55 3.45c0-.33.27-.6.6-.6h3.6l2.75 2.75v6.65c0 .33-.27.6-.6.6H1.15c-.33 0-.6-.27-.6-.6z" fill={bg} stroke={color} strokeWidth={1.1} strokeLinejoin="round" />
      <path d="M4.6 2.95v2.4c0 .2.15.35.35.35h2.4M7.95.6v2.15c0 .2.15.35.35.35h2.2" fill="none" stroke={color} strokeWidth={0.9} strokeLinejoin="round" />
    </svg>
  );
}

/** TrashOutline from the app, drawn at 10×11 with a 1.25 stroke. */
export function TrashIcon({ style, color = "currentColor" }: P) {
  const w = 10;
  const h = 11;
  const lid = h * 0.2;
  const r = w * 0.12;
  const d = [
    `M${w * 0.36} ${lid}L${w * 0.36} 0L${w * 0.64} 0L${w * 0.64} ${lid}`,
    `M0 ${lid}L${w} ${lid}`,
    `M${w * 0.12} ${lid}L${w * 0.19} ${h - r}Q${w * 0.19} ${h} ${w * 0.19 + r} ${h}L${w * 0.81 - r} ${h}Q${w * 0.81} ${h} ${w * 0.81} ${h - r}L${w * 0.88} ${lid}`,
  ].join("");
  return (
    <svg viewBox={`0 0 ${w} ${h}`} style={base(w, h, style)} aria-hidden>
      <path d={d} fill="none" stroke={color} strokeWidth={1.25} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function CheckIcon({ size = 10, style, color = "currentColor" }: P & { size?: number }) {
  return (
    <svg viewBox="0 0 10 10" style={base(size, size, style)} aria-hidden>
      <path d="M1.2 5.4 3.9 8.1 8.8 1.9" fill="none" stroke={color} strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function TextAlignLeftIcon({ style, color = "currentColor" }: P) {
  return (
    <svg viewBox="0 0 22 18" style={base(22, 18, style)} aria-hidden>
      <path d="M1 1.5h20M1 6.5h13M1 11.5h20M1 16.5h13" stroke={color} strokeWidth={1.1} strokeLinecap="round" />
    </svg>
  );
}

export function ArrowDownIcon({ style, color = "currentColor" }: P) {
  return (
    <svg viewBox="0 0 9 10" style={base(9, 10, style)} aria-hidden>
      <path d="M4.5.9v8.2M1 5.6l3.5 3.5L8 5.6" fill="none" stroke={color} strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function XCircleIcon({ size = 11, style, color = "currentColor" }: P & { size?: number }) {
  return (
    <svg viewBox="0 0 12 12" style={base(size, size, style)} aria-hidden>
      <circle cx={6} cy={6} r={6} fill={color} />
      <path d="M4 4l4 4M8 4 4 8" stroke="#fff" strokeWidth={1.3} strokeLinecap="round" />
    </svg>
  );
}

/** A small native-style spinner (ProgressView at controlSize .mini). */
export function Spinner({ size = 11, color = "currentColor", style }: P & { size?: number }) {
  const bars = Array.from({ length: 8 }, (_, i) => i);
  return (
    <svg viewBox="0 0 12 12" style={base(size, size, style)} className="hw-spin" aria-hidden>
      {bars.map((i) => (
        <rect
          key={i}
          x={5.35}
          y={0.6}
          width={1.3}
          height={3.2}
          rx={0.65}
          fill={color}
          opacity={0.25 + (i / 8) * 0.75}
          transform={`rotate(${i * 45} 6 6)`}
        />
      ))}
    </svg>
  );
}
