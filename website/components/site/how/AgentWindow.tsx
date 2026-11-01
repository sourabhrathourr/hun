"use client";

// Step 2: you ask your agent to start orbit, and it does it the Hun way. The
// same clock as the ticket and the menu bar drives it: the agent "types"
// `hun run orbit` into its tool call, orbit starts, it checks `hun status`, and
// answers in a sentence. Calm on purpose: three blocks, plain words.

import type { ReactNode } from "react";
import { CMD_RUN, CMD_STATUS, type Frame } from "./timeline";

const ASK = "Start orbit so I can try the new dashboard.";
const REPLY = "orbit is running. The app is on localhost:3000, the API on :8000, and its logs are in Hun.";

export const AGENT_TRANSCRIPT = [
  `You: ${ASK}`,
  `Agent ran: ${CMD_RUN}`,
  "✓ Started orbit in parallel",
  `Agent ran: ${CMD_STATUS}`,
  "app :3000 · postgres :5432 · server :8000 · worker, all running",
  `Agent: ${REPLY}`,
].join("\n");

const css = `
.aw { --aw-ink: #232321; --aw-ink2: #62625D; --aw-ink3: #8B8B84; --aw-line: rgba(24,24,22,.08); --aw-ok: #27833F;
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; color: var(--aw-ink);
  background: #FBFAF6; border-radius: 12px; overflow: hidden;
  box-shadow: 0 0 0 .5px rgba(31,27,22,.22), 0 1px 2px rgba(31,27,22,.05), 0 30px 60px -30px rgba(64,44,16,.38), 0 10px 22px -16px rgba(64,44,16,.16); }
.aw-mono { font-family: ui-monospace, "SF Mono", SFMono-Regular, Menlo, monospace; font-variant-ligatures: none; }
.aw-in { animation: aw-in 260ms cubic-bezier(.23,1,.32,1) both; }
@keyframes aw-in { from { opacity: 0; transform: translateY(6px); } }
.aw-caret { display: inline-block; width: 7px; height: 13px; margin-left: 1px; vertical-align: -2px; background: var(--aw-ink2); }
.aw-dots span { display: inline-block; width: 4px; height: 4px; margin-right: 3px; border-radius: 99px; background: var(--aw-ink3); animation: aw-dot 1s ease-in-out infinite; }
.aw-dots span:nth-child(2) { animation-delay: .15s; } .aw-dots span:nth-child(3) { animation-delay: .3s; }
@keyframes aw-dot { 0%, 100% { opacity: .25; } 50% { opacity: 1; } }
@media (prefers-reduced-motion: reduce) { .aw-in { animation: none; } .aw-dots span { animation: none; opacity: .6; } }
`;

export function AgentWindow({ f }: { f: Frame }) {
  const typing1 = f.typed1 > 0 && !f.ran1;
  const typing2 = f.typed2 > 0 && !f.ran2;
  return (
    <div className="aw" aria-hidden>
      <style>{css}</style>

      {/* Title bar: a generic agent session, not any particular product. */}
      <div style={{ height: 40, display: "flex", alignItems: "center", padding: "0 14px", borderBottom: "1px solid var(--aw-line)", background: "#F2F1EB" }}>
        <span style={{ display: "flex", gap: 8 }}>
          {["#FF5F57", "#FEBC2E", "#28C840"].map((c) => (
            <span key={c} style={{ width: 12, height: 12, borderRadius: 99, background: c, boxShadow: "inset 0 0 0 .5px rgba(0,0,0,.12)" }} />
          ))}
        </span>
        <span style={{ flex: 1, textAlign: "center", marginRight: 52, fontSize: 12.5, fontWeight: 600, color: "var(--aw-ink2)" }}>
          Your agent <span style={{ fontWeight: 500, color: "var(--aw-ink3)" }}>· ~/code/orbit</span>
        </span>
      </div>

      <div style={{ padding: "22px 22px 24px", display: "flex", flexDirection: "column", gap: 18, minHeight: 312 }}>
        {/* You */}
        <div style={{ alignSelf: "flex-end", maxWidth: "82%", padding: "10px 14px", borderRadius: "14px 14px 4px 14px", background: "#EDEAE1", fontSize: 13.5, lineHeight: "19px" }}>
          {ASK}
        </div>

        {/* The agent's tool calls */}
        {f.typed1 > 0 && (
          <Tool
            cmd={CMD_RUN.slice(0, f.typed1)}
            caret={typing1}
            result={f.started ? <><Ok /> Started orbit in parallel</> : f.ran1 ? <Dots /> : null}
          />
        )}
        {f.typed2 > 0 && (
          <Tool
            cmd={CMD_STATUS.slice(0, f.typed2)}
            caret={typing2}
            result={
              f.status ? (
                <>
                  <Ok /> app <b>:3000</b> · postgres <b>:5432</b> · server <b>:8000</b> · worker
                </>
              ) : f.ran2 ? (
                <Dots />
              ) : null
            }
          />
        )}

        {/* The answer */}
        {f.status && (
          <div className="aw-in" style={{ display: "flex", gap: 10, alignItems: "flex-start" }}>
            <AgentMark />
            <p style={{ margin: 0, fontSize: 13.5, lineHeight: "20px", color: "var(--aw-ink)", textWrap: "pretty" }}>{REPLY}</p>
          </div>
        )}
      </div>
    </div>
  );
}

function Tool({ cmd, caret, result }: { cmd: string; caret: boolean; result: ReactNode }) {
  return (
    <div className="aw-in" style={{ display: "flex", gap: 10, alignItems: "flex-start" }}>
      <AgentMark />
      <div style={{ flex: 1, minWidth: 0, borderRadius: 10, background: "#FFFFFF", boxShadow: "0 0 0 .5px rgba(24,24,22,.14)", overflow: "hidden" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8, padding: "8px 12px" }}>
          <span style={{ fontSize: 11, fontWeight: 600, color: "var(--aw-ink3)", letterSpacing: 0.1 }}>Ran</span>
          <span className="aw-mono" style={{ fontSize: 12.5, color: "var(--aw-ink)" }}>
            {cmd}
            {caret && <span className="aw-caret" />}
          </span>
        </div>
        {result && (
          <div className="aw-mono aw-in" style={{ padding: "7px 12px 8px", borderTop: "1px solid var(--aw-line)", background: "#FBFAF6", fontSize: 11.5, color: "var(--aw-ink2)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
            {result}
          </div>
        )}
      </div>
    </div>
  );
}

/** Claude's mark (from SVGL) beside each of the agent's turns. */
function AgentMark() {
  return (
    <svg width="18" height="18" viewBox="0 0 256 257" aria-hidden style={{ flex: "none", marginTop: 5 }}>
      <path fill="#D97757" d="m50.228 170.321 50.357-28.257.843-2.463-.843-1.361h-2.462l-8.426-.518-28.775-.778-24.952-1.037-24.175-1.296-6.092-1.297L0 125.796l.583-3.759 5.12-3.434 7.324.648 16.202 1.101 24.304 1.685 17.629 1.037 26.118 2.722h4.148l.583-1.685-1.426-1.037-1.101-1.037-25.147-17.045-27.22-18.017-14.258-10.37-7.713-5.25-3.888-4.925-1.685-10.758 7-7.713 9.397.649 2.398.648 9.527 7.323 20.35 15.75L94.817 91.9l3.889 3.24 1.555-1.102.195-.777-1.75-2.917-14.453-26.118-15.425-26.572-6.87-11.018-1.814-6.61c-.648-2.723-1.102-4.991-1.102-7.778l7.972-10.823L71.42 0 82.05 1.426l4.472 3.888 6.61 15.101 10.694 23.786 16.591 32.34 4.861 9.592 2.592 8.879.973 2.722h1.685v-1.556l1.36-18.211 2.528-22.36 2.463-28.776.843-8.1 4.018-9.722 7.971-5.25 6.222 2.981 5.12 7.324-.713 4.73-3.046 19.768-5.962 30.98-3.889 20.739h2.268l2.593-2.593 10.499-13.934 17.628-22.036 7.778-8.749 9.073-9.657 5.833-4.601h11.018l8.1 12.055-3.628 12.443-11.342 14.388-9.398 12.184-13.48 18.147-8.426 14.518.778 1.166 2.01-.194 30.46-6.481 16.462-2.982 19.637-3.37 8.88 4.148.971 4.213-3.5 8.62-20.998 5.184-24.628 4.926-36.682 8.685-.454.324.519.648 16.526 1.555 7.065.389h17.304l32.21 2.398 8.426 5.574 5.055 6.805-.843 5.184-12.962 6.611-17.498-4.148-40.83-9.721-14-3.5h-1.944v1.167l11.666 11.406 21.387 19.314 26.767 24.887 1.36 6.157-3.434 4.86-3.63-.518-23.526-17.693-9.073-7.972-20.545-17.304h-1.36v1.814l4.73 6.935 25.017 37.59 1.296 11.536-1.814 3.76-6.481 2.268-7.13-1.297-14.647-20.544-15.1-23.138-12.185-20.739-1.49.843-7.194 77.448-3.37 3.953-7.778 2.981-6.48-4.925-3.436-7.972 3.435-15.749 4.148-20.544 3.37-16.333 3.046-20.285 1.815-6.74-.13-.454-1.49.194-15.295 20.999-23.267 31.433-18.406 19.702-4.407 1.75-7.648-3.954.713-7.064 4.277-6.286 25.47-32.405 15.36-20.092 9.917-11.6-.065-1.686h-.583L44.07 198.125l-12.055 1.555-5.185-4.86.648-7.972 2.463-2.593 20.35-13.999-.064.065Z" />
    </svg>
  );
}

function Ok() {
  return <span style={{ color: "var(--aw-ok)", fontWeight: 600 }}>✓</span>;
}

function Dots() {
  return (
    <span className="aw-dots" style={{ display: "inline-flex", alignItems: "center", height: 14 }}>
      <span />
      <span />
      <span />
    </span>
  );
}
