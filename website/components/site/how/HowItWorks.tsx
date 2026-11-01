"use client";

import { type ReactNode, useEffect, useRef, useState } from "react";
import { useReducedMotion, useShot } from "../scenes/shared";
import { MenuGlimpse } from "./MenuGlimpse";
import { AGENT_TRANSCRIPT, AgentWindow } from "./AgentWindow";
import { Ticket } from "./Ticket";
import { END, frameAt } from "./timeline";

// How it works, as three objects on the desk: orbit's .hun.yml printed as a
// ticket, a Terminal where `hun run orbit` is typed, and the corner of the
// menu bar where orbit shows up. One clock drives all three: the run punches
// the ticket and turns Hun's switch on, then `hun status` prints.

export function HowItWorksSection() {
  return (
    <section className="hw2 border-t border-[var(--line)] py-16 sm:py-40" aria-labelledby="how-title">
      <style>{css}</style>
      <div className="mx-auto w-full max-w-[1248px] px-5 sm:px-8">
        <h2
          id="how-title"
          className="hf-display max-w-[18ch] text-balance text-[36px] font-bold leading-[1.02] tracking-[-0.03em] sm:text-[52px]"
        >
          Write it down once. Start it the same way every time.
        </h2>
        <Steps />
      </div>
    </section>
  );
}

function Steps() {
  const ref = useRef<HTMLLIElement>(null);
  const shot = useShot();
  const reduced = useReducedMotion();
  const settled = shot || reduced;
  const [inView, setInView] = useState(false);
  const [t, setT] = useState(0);
  const tRef = useRef(0);

  // Run while the terminal is mostly on screen and the tab is visible.
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    let visible = false;
    const update = () => setInView(visible && document.visibilityState === "visible");
    const io = new IntersectionObserver(
      ([e]) => {
        visible = e.isIntersecting;
        update();
      },
      { threshold: 0.5 },
    );
    io.observe(el);
    document.addEventListener("visibilitychange", update);
    return () => {
      io.disconnect();
      document.removeEventListener("visibilitychange", update);
    };
  }, []);

  useEffect(() => {
    if (settled) {
      tRef.current = END;
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setT(END);
      return;
    }
    if (!inView || tRef.current >= END) return;
    let raf = 0;
    let last = performance.now();
    const tick = (now: number) => {
      // A dropped frame or a background tab doesn't skip the typing.
      tRef.current = Math.min(END, tRef.current + Math.min(now - last, 64));
      last = now;
      setT(tRef.current);
      if (tRef.current < END) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [inView, settled]);

  const f = frameAt(t);
  const animate = !settled;

  return (
    <ol className="hw2-steps mt-14 sm:mt-20">
      <li className="hw2-s1">
        <Caption n={1} title="Describe it once">
          A short <Code>.hun.yml</Code> lists what your project runs and on which ports. Your agent can write it, then
          check it with <Code>hun validate .</Code>
        </Caption>
        <Ticket punched={f.started} animate={animate} />
      </li>
      <li ref={ref} className="hw2-s2">
        <Caption n={2} title="Your agent starts it the same way">
          Ask your agent to run the app and it uses <Code>hun run orbit</Code>, not a guess. Postgres starts first, and a
          busy port moves to the next free one.
        </Caption>
        <figure className="hw2-fig">
          <div aria-hidden>
            <AgentWindow f={f} />
          </div>
          <figcaption className="sr-only">
            A coding agent in ~/code/orbit:
            <pre>{AGENT_TRANSCRIPT}</pre>
          </figcaption>
        </figure>
      </li>
      <li className="hw2-s3">
        <Caption n={3} title="See it, stop it">
          Hun’s switch in your menu bar turns on and lists orbit with its port. One click opens it, another stops it.
        </Caption>
        <figure className="hw2-fig" aria-label="Hun's menu bar panel listing orbit as running, with port 3000 and a Stop button under the pointer.">
          <div aria-hidden>
            <MenuGlimpse menu={f.menu} animate={animate} />
          </div>
        </figure>
      </li>
    </ol>
  );
}

function Caption({ n, title, children }: { n: number; title: string; children: ReactNode }) {
  return (
    <div className="hw2-cap">
      <span className="hw2-n hf-display" aria-hidden>
        {n}
      </span>
      <h3 className="hf-display text-[21px] font-semibold leading-[1.2] tracking-[-0.015em]">
        <span className="sr-only">Step {n}: </span>
        {title}
      </h3>
      <p className="hw2-cap-p max-w-[38ch] text-pretty text-[16px] leading-[1.55] text-[var(--ink-2)]">{children}</p>
    </div>
  );
}

function Code({ children }: { children: ReactNode }) {
  return <code className="hf-mono whitespace-nowrap rounded-[5px] bg-[var(--code-bg)] px-[5px] py-[1px] text-[.86em]">{children}</code>;
}

const GRAIN =
  "url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='180' height='180'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='3' stitchTiles='stitch'/><feColorMatrix type='saturate' values='0'/></filter><rect width='100%25' height='100%25' filter='url(%23n)'/></svg>\")";
const PERF_V = "url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='4' height='8'><circle cx='2' cy='4' r='1.3' fill='%23E9E1D2'/></svg>\")";
const PERF_H = "url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='8' height='4'><circle cx='4' cy='2' r='1.3' fill='%23E9E1D2'/></svg>\")";

const STUB_W = 112;
const STUB_H = 84;
const NOTCH = 9;

export const css = `
/* Layout: the ticket on the left across two rows, the terminal and the menu bar on the right. */
.hw2-steps { display: grid; gap: 72px; list-style: none; padding: 0; margin-left: 0; }
.hw2-steps > li { min-width: 0; display: flex; flex-direction: column; gap: 28px; }
@media (min-width: 1200px) {
  .hw2-steps { grid-template-columns: minmax(0, 640fr) minmax(0, 488fr); grid-template-rows: auto 1fr; column-gap: 56px; row-gap: 64px; }
  .hw2-s1 { grid-row: 1 / span 2; }
  .hw2-s2 { grid-column: 2; grid-row: 1; }
  .hw2-s3 { grid-column: 2; grid-row: 2; }
}
@media (min-width: 640px) and (max-width: 1199.98px) { .hw2-steps > li { max-width: 640px; } }
.hw2-fig { margin: 0; }

/* Step captions: a hairline ring with the number, hung in the margin on wide screens. */
.hw2-cap { display: grid; grid-template-columns: 28px minmax(0, 1fr); column-gap: 12px; row-gap: 8px; align-items: center; }
.hw2-cap-p { grid-column: 1 / -1; }
@media (min-width: 640px) { .hw2-cap { column-gap: 14px; row-gap: 6px; } .hw2-cap-p { grid-column: 2; } }
.hw2-n { width: 28px; height: 28px; border-radius: 50%; display: grid; place-items: center;
  font-size: 14px; font-weight: 600; line-height: 1; color: var(--accent); font-variant-numeric: tabular-nums;
  box-shadow: inset 0 0 0 1px rgba(194, 74, 31, .38); }
@media (min-width: 1360px) { .hw2-cap { margin-left: -42px; } }

/* The ticket. */
.ht { container: ticket / inline-size; flex: 1; display: flex; flex-direction: column; }
.ht-shadow { flex: 1; display: flex; flex-direction: column; }
.ht-card { flex: 1; }
.ht-body { display: flex; flex-direction: column; }
.ht-fine { margin-top: auto; padding-top: 28px; font-size: 12px; line-height: 16px; color: var(--ink-3); }
.ht-fine::before { content: ""; display: block; height: 4px; margin-bottom: 12px; border-top: .5px solid rgba(31,27,22,.16); border-bottom: 1px solid rgba(31,27,22,.16); }
.ht-fine .hf-mono { color: var(--ink-2); font-size: 11.5px; }
.ht-shadow { filter: drop-shadow(0 0 .5px rgba(31,27,22,.32)) drop-shadow(0 1px .5px rgba(31,27,22,.10)) drop-shadow(0 2px 3px rgba(31,27,22,.04)) drop-shadow(0 22px 22px rgba(64,44,16,.10)); }
@property --hole { syntax: "<length>"; inherits: true; initial-value: -1px; }
.ht-card { position: relative; display: flex; flex-direction: column; background: var(--raised); border-radius: 10px;
  --n1: 0 ${STUB_H}px; --n2: 100% ${STUB_H}px; --hp: calc(100% - 34px) 30px; --hole: -1px;
  --ht-mask: radial-gradient(circle at var(--n1), #0000 ${NOTCH}px, #000 ${NOTCH + 0.5}px),
             radial-gradient(circle at var(--n2), #0000 ${NOTCH}px, #000 ${NOTCH + 0.5}px),
             radial-gradient(circle at var(--hp), #0000 var(--hole), #000 calc(var(--hole) + .6px));
  -webkit-mask-image: var(--ht-mask); -webkit-mask-composite: source-in;
  mask-image: var(--ht-mask); mask-composite: intersect; }
.ht-card.punched { --hole: 8px; }
.ht-card.anim { transition: --hole 180ms cubic-bezier(.23,1,.32,1); }
.ht-grain { position: absolute; inset: 0; pointer-events: none; background-image: ${GRAIN}; background-size: 180px; opacity: .1; mix-blend-mode: multiply; border-radius: inherit; }
.ht-card > :not(.ht-grain) { position: relative; }

.ht-stub { height: ${STUB_H - 2}px; padding: 0 20px; display: grid; grid-template-columns: auto 1fr auto; grid-template-areas: "title serial punch"; align-items: center; column-gap: 16px; }
.ht-title { grid-area: title; }
.ht-name { font-size: 30px; font-weight: 700; line-height: 1; letter-spacing: -0.03em; }
.ht-count { margin-top: 5px; font-size: 12.5px; line-height: 1; color: var(--ink-2); }
.ht-serial { grid-area: serial; align-self: start; justify-self: end; margin-top: 15px; font-size: 10.5px; line-height: 1; letter-spacing: .08em; text-transform: uppercase; color: var(--ink-3); font-variant-numeric: tabular-nums; }
.ht-punch { grid-area: punch; position: relative; width: 30px; height: 44px; display: flex; flex-direction: column; align-items: center; }
.ht-ring { width: 24px; height: 24px; border-radius: 50%; border: 1px dashed rgba(31,27,22,.32); }
.ht-punch-label { margin-top: 6px; font-size: 9.5px; font-weight: 600; line-height: 1; letter-spacing: .12em; text-transform: uppercase; color: var(--ink-3); }

.ht-perf { height: 4px; margin: 0 ${NOTCH + 6}px; background: ${PERF_H} repeat-x left center; }
.ht-body { min-width: 0; padding: 18px 20px 24px; }
.ht-head { font-size: 11.5px; line-height: 16px; color: var(--ink-3); }
.ht-rule { height: 4px; margin-top: 12px; border-top: 1px solid rgba(31,27,22,.16); border-bottom: .5px solid rgba(31,27,22,.16); }
.ht-file { position: relative; margin-top: 18px; }
.ht-file pre { margin: 0; white-space: pre; color: var(--ink); }
.ht-k { color: var(--ink); }
.ht-s { color: var(--ink); font-weight: 600; }
.ht-v { color: var(--ink-2); }
.ht-n { color: var(--ink-2); font-variant-numeric: tabular-nums; }
.ht-p { color: var(--ink-3); }
.ht-x, .ht-fx { color: var(--accent); }
.ht-art { position: absolute; top: 0; left: 0; overflow: visible; pointer-events: none; }
.ht-fmark { font: 600 11px/1 var(--f-text), system-ui, sans-serif; fill: var(--accent); }
.ht-mark { display: inline-block; color: var(--accent); font-weight: 600; }
.ht-note { position: absolute; display: grid; grid-template-columns: 14px 1fr; width: 22ch; margin: 0; font-size: 12.5px; line-height: 18px; color: var(--ink-3); text-wrap: pretty; padding-top: 2px; }
.ht-side { display: none; }
.ht-foot { list-style: none; margin: 18px 0 0; padding: 14px 0 0; border-top: .5px solid rgba(31,27,22,.16); display: grid; gap: 6px; font-size: 12.5px; line-height: 18px; color: var(--ink-3); }
.ht-foot li { display: grid; grid-template-columns: 14px 1fr; }

@container ticket (min-width: 520px) {
  .ht-card { flex-direction: row; --n1: ${STUB_W}px 0; --n2: ${STUB_W}px 100%; --hp: 56px calc(100% - 57px); }
  .ht-stub { width: ${STUB_W - 2}px; height: auto; flex: none; padding: 22px 0 24px; grid-template-columns: 1fr; grid-template-rows: auto 1fr auto;
    grid-template-areas: "serial" "title" "punch"; justify-items: center; }
  .ht-serial { justify-self: center; margin-top: 0; }
  .ht-title { align-self: center; writing-mode: vertical-rl; transform: rotate(180deg); display: flex; align-items: baseline; gap: 12px; }
  .ht-name { font-size: 44px; }
  .ht-count { margin: 0; font-size: 13px; }
  .ht-perf { width: 4px; height: auto; margin: ${NOTCH + 6}px 0; flex: none; background: ${PERF_V} repeat-y center top; }
  .ht-body { flex: 1; padding: 22px 28px 28px 30px; }
}
@container ticket (min-width: 600px) {
  p.ht-side { display: grid; }
  path.ht-side { display: inline; }
  .ht-fmark, .ht-foot { display: none; }
}

/* The Terminal window. */
.tw { overflow: hidden; border-radius: 12px; background: #fff; color: rgba(0,0,0,.88);
  box-shadow: 0 0 0 .5px rgba(0,0,0,.26), 0 1px 2px rgba(31,27,22,.08), 0 34px 64px -30px rgba(64,44,16,.42), 0 12px 24px -16px rgba(64,44,16,.14); }
.tw-bar { position: relative; height: 30px; display: flex; align-items: center; justify-content: center; background: #EDEDEC; box-shadow: inset 0 -.5px 0 rgba(0,0,0,.14), inset 0 .5px 0 rgba(255,255,255,.7); }
.tw-lights { position: absolute; left: 12px; top: 9px; display: flex; gap: 8px; }
.tw-lights i { width: 12px; height: 12px; border-radius: 50%; box-shadow: inset 0 0 0 .5px rgba(0,0,0,.14); }
.tw-title { display: flex; align-items: center; gap: 5px; padding: 0 76px; min-width: 0; font-size: 13px; font-weight: 600; letter-spacing: -0.08px; color: rgba(0,0,0,.72); white-space: nowrap; }
.tw-title > span { overflow: hidden; text-overflow: ellipsis; }
.tw-screen { position: relative; overflow: hidden; -webkit-font-smoothing: antialiased; }
.tw-line { height: ${18}px; white-space: pre; }
.tw-ok { color: #1F8A3B; }
.tw-b { font-weight: 600; }
.tw-caret { display: inline-block; width: 1ch; height: 15px; vertical-align: -3px; background: rgba(0,0,0,.62); }
.tw-caret.blink { animation: tw-blink 1.06s steps(1, end) infinite; }
.tw-caret.paused { animation-play-state: paused; }
@keyframes tw-blink { 50% { opacity: 0; } }
@media (prefers-reduced-motion: reduce) { .tw-caret.blink { animation: none; } }

/* The menu bar corner. */
.mg { position: relative; --mg-bg: #F7F7F2; --mg-divider: rgba(24,24,22,.07); --mg-dividerStrong: rgba(24,24,22,.12); --mg-rowHover: rgba(24,24,22,.035);
  --mg-text1: #232321; --mg-text2: #62625D; --mg-text3: #8B8B84; --mg-danger: #B84040; }
.mg-tray { position: relative; overflow: hidden; transform-origin: 0 0; isolation: isolate; background-color: var(--tray);
  background-image: var(--bg-menu, url(/site/bg/scene-menu.jpg)); background-size: cover; background-position: 70% 0; }
.mg-bar { position: absolute; inset: 0 0 auto 0; display: flex; align-items: center; justify-content: flex-end; padding: 0 22px 0 6px;
  background: rgba(250,250,250,.5); -webkit-backdrop-filter: blur(20px) saturate(160%); backdrop-filter: blur(20px) saturate(160%);
  box-shadow: inset 0 -.5px 0 rgba(0,0,0,.12); font-size: 13px; line-height: 16px; color: rgba(0,0,0,.85); z-index: 2; }
.mg-item { height: 22px; display: flex; align-items: center; padding: 0 7px; }
.mg-item svg { display: block; }
.mg-panel { position: absolute; top: 29px; right: 8px; width: 340px; border-radius: 12px; overflow: hidden; background: var(--mg-bg); color: var(--mg-text1);
  box-shadow: inset 0 0 0 1px var(--mg-dividerStrong), 0 0 0 .5px rgba(0,0,0,.06), 0 10px 32px rgba(0,0,0,.16), 0 2px 6px rgba(0,0,0,.06);
  -webkit-font-smoothing: subpixel-antialiased; }
.mg-seg { background: #fff; }
.mg-chip { color: var(--mg-text2); background: #fff; }
.mg .hw-spin { animation: mg-spin 1s steps(8) infinite; }
@keyframes mg-spin { to { transform: rotate(360deg); } }
`;
