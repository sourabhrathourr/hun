import type { ReactNode } from "react";

// orbit's .hun.yml, printed as a ticket: a tear-off stub with the project's
// name and a box the run punches, a perforated fold, and the file itself set
// in the page's mono, with two printed margin notes. The card lays itself out
// by its own width (container queries in the section's css): a stub on the
// left with side notes when there's room, a stub on top with footnotes when not.

/** The type grid the margin art is drawn on. JetBrains Mono advances 0.6em. */
export const TK = { size: 12.5, ch: 7.5, lh: 24 };

type Tok = [string, "k" | "s" | "v" | "n" | "p" | "x" | "c"];
const k = (t: string): Tok => [t, "k"]; // key
const s = (t: string): Tok => [t, "s"]; // a service's name
const v = (t: string): Tok => [t, "v"]; // value
const n = (t: string): Tok => [t, "n"]; // number
const p = (t: string): Tok => [t, "p"]; // punctuation
const x = (t: string): Tok => [t, "x"]; // $PORT

// The file, line by line. Indentation is part of the first token.
const FILE: Tok[][] = [
  [k("name"), p(":"), v(" orbit")],
  [],
  [k("services"), p(":")],
  [s("  app"), p(":")],
  [k("    cmd"), p(":"), v(" npm run dev -- --port "), x("$PORT")],
  [k("    port"), p(":"), n(" 3000")],
  [s("  server"), p(":")],
  [k("    cmd"), p(":"), v(" uv run server")],
  [k("    port"), p(":"), n(" 8000")],
  [k("    depends_on"), p(": ["), v("postgres"), p("]")],
  [s("  worker"), p(":")],
  [k("    cmd"), p(":"), v(" uv run worker")],
  [k("    depends_on"), p(": ["), v("postgres"), p("]")],
  [s("  postgres"), p(":")],
  [k("    cmd"), p(":"), v(" docker compose up postgres")],
  [k("    port"), p(":"), n(" 5432")],
  [],
  [k("profiles"), p(":")],
  [k("  ui"), p(": ["), v("app"), p("]")],
  [k("  api"), p(": ["), v("server"), p(", "), v("worker"), p("]")],
];

const PORT_LINE = 4;
const DEP_A = 9;
const DEP_B = 12;
const PG_LINE = 13;
/** Where the side notes start, in characters: clear of the longest line. */
const NOTE_COL = 40;

export function Ticket({ punched, animate }: { punched: boolean; animate: boolean }) {
  return (
    <div className="ht">
      <div className="ht-shadow">
        <div className={`ht-card ${punched ? "punched" : ""} ${animate ? "anim" : ""}`}>
          <div className="ht-grain" aria-hidden />
          <Stub />
          <div className="ht-perf" aria-hidden />
          <div className="ht-body">
            <div className="ht-head">
              <span className="hf-mono">~/code/orbit/.hun.yml</span>
            </div>
            <div className="ht-rule" aria-hidden />
            <div className="ht-file">
              <pre className="hf-mono" style={{ fontSize: TK.size, lineHeight: `${TK.lh}px` }}>
                <code>
                  {FILE.map((line, i) => (
                    <span key={i} className="ht-line">
                      {line.map(([t, c], j) => (
                        <span key={j} className={`ht-${c}`}>
                          {t}
                        </span>
                      ))}
                      {"\n"}
                    </span>
                  ))}
                </code>
              </pre>
              <Margin />
            </div>
            <ol className="ht-foot">
              <li>
                <Mark>*</Mark>
                <span>
                  Hun fills in <span className="hf-mono ht-fx">$PORT</span>: 3000, or the next free port if it’s taken.
                </span>
              </li>
              <li>
                <Mark>†</Mark>
                <span>server and worker wait for postgres, so it starts first.</span>
              </li>
            </ol>
            <p className="ht-fine">
              Start it with <span className="hf-mono">hun run orbit</span>
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}

function Mark({ children }: { children: ReactNode }) {
  return (
    <span className="ht-mark" aria-hidden>
      {children}
    </span>
  );
}

/** The stub: what's on the ticket at a glance, and the box a run punches. */
function Stub() {
  return (
    <div className="ht-stub">
      <p className="ht-serial">No. 0001</p>
      <div className="ht-title">
        <p className="hf-display ht-name">orbit</p>
        <p className="ht-count">4 services</p>
      </div>
      <div className="ht-punch" aria-hidden>
        <span className="ht-ring" />
        <span className="ht-punch-label">Run</span>
      </div>
    </div>
  );
}

/**
 * Printed on the file's grid: a leader from $PORT to its note, and a bracket
 * gathering both depends_on lines with an arrow down to postgres.
 */
function Margin() {
  const { ch, lh } = TK;
  const mid = (line: number) => line * lh + lh / 2;
  const portEnd = 36 * ch; // "    cmd: npm run dev -- --port $PORT"
  const depEnd = 26 * ch; // "    depends_on: [postgres]"
  const bx = depEnd + 1.5 * ch;
  const pgEnd = 11 * ch; // "  postgres:"
  const ay = mid(PG_LINE);
  const depMid = (mid(DEP_A) + mid(DEP_B)) / 2;
  const w = (NOTE_COL + 1) * ch;
  const h = FILE.length * lh;
  const ink = "var(--ink-3)";
  const accent = "var(--accent)";
  return (
    <>
      <svg className="ht-art" width={w} height={h} viewBox={`0 0 ${w} ${h}`} aria-hidden>
        {/* $PORT → its note (side-note layout only). */}
        <path className="ht-side" d={`M${portEnd + 0.6 * ch} ${mid(PORT_LINE)}H${NOTE_COL * ch - 0.6 * ch}`} stroke={accent} strokeWidth={1} opacity={0.55} />
        {/* The bracket: two ticks at the depends_on lines, joined. */}
        <path
          d={`M${depEnd + 0.5 * ch} ${mid(DEP_A)}H${bx}V${mid(DEP_B)}H${depEnd + 0.5 * ch}`}
          fill="none"
          stroke={ink}
          strokeWidth={1}
          strokeLinejoin="round"
          opacity={0.7}
        />
        <path className="ht-side" d={`M${bx} ${depMid}H${NOTE_COL * ch - 0.6 * ch}`} stroke={ink} strokeWidth={1} opacity={0.45} />
        {/* …and from it, down and left to postgres. */}
        <path
          d={`M${bx} ${mid(DEP_B)}V${ay - 7}Q${bx} ${ay} ${bx - 7} ${ay}H${pgEnd + 0.9 * ch}`}
          fill="none"
          stroke={ink}
          strokeWidth={1}
          opacity={0.7}
        />
        <path d={`M${pgEnd + 0.9 * ch + 4.5} ${ay - 3}L${pgEnd + 0.9 * ch} ${ay}L${pgEnd + 0.9 * ch + 4.5} ${ay + 3}`} fill="none" stroke={ink} strokeWidth={1} strokeLinecap="round" strokeLinejoin="round" opacity={0.7} />
        {/* Footnote marks for the narrow layout. */}
        <text className="ht-fmark" x={portEnd + 0.8 * ch} y={mid(PORT_LINE) - 1}>
          *
        </text>
        <text className="ht-fmark" x={bx + 0.6 * ch} y={depMid + 4}>
          †
        </text>
      </svg>
      <p className="ht-note ht-side" style={{ top: mid(PORT_LINE) - 11, left: NOTE_COL * ch }}>
        <Mark>*</Mark>
        <span>Hun fills in 3000, or the next free port if it’s taken.</span>
      </p>
      <p className="ht-note ht-side" style={{ top: depMid - 11, left: NOTE_COL * ch }}>
        <Mark>†</Mark>
        <span>server and worker wait for postgres, so it starts first.</span>
      </p>
    </>
  );
}
