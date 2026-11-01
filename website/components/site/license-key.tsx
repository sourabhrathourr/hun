"use client";

import { useEffect, useRef, useState } from "react";

// The key, front and centre, with one button to copy it. Arriving here, the
// page also tries to copy it straight away. Browsers allow that only some of
// the time (Safari wants a click first), so the note shows only when it worked.

type State = "idle" | "auto" | "copied" | "failed";

export function LicenseKey({ licenseKey }: { licenseKey: string }) {
  const [state, setState] = useState<State>("idle");
  const timer = useRef<number | undefined>(undefined);

  useEffect(() => {
    let cancelled = false;
    navigator.clipboard
      ?.writeText(licenseKey)
      .then(() => !cancelled && setState("auto"))
      .catch(() => {});
    return () => {
      cancelled = true;
      window.clearTimeout(timer.current);
    };
  }, [licenseKey]);

  async function copy() {
    window.clearTimeout(timer.current);
    try {
      await navigator.clipboard.writeText(licenseKey);
      setState("copied");
      timer.current = window.setTimeout(() => setState("idle"), 2200);
    } catch {
      setState("failed");
    }
  }

  const done = state === "copied" || state === "auto";

  return (
    <div>
      <p className="text-[13px] font-semibold uppercase tracking-[0.08em] text-[var(--ink-3)]">Your license key</p>
      <code
        className="site-mono mt-4 block select-all [overflow-wrap:anywhere] rounded-[14px] bg-[rgba(31,27,22,.05)] px-5 py-4 text-center text-[16px] leading-[1.6] tracking-[0.02em] text-[var(--ink)] shadow-[inset_0_0_0_1px_rgba(31,27,22,.08)] sm:text-[18px]"
        aria-label="License key"
      >
        {licenseKey}
      </code>
      <button
        type="button"
        onClick={copy}
        className="site-btn mt-5 flex h-12 w-full items-center justify-center gap-2 rounded-full bg-[var(--ink)] text-[15.5px] font-medium text-[var(--paper)]"
      >
        <span className="relative inline-flex size-4 items-center justify-center" aria-hidden>
          <svg
            width="16"
            height="16"
            viewBox="0 0 16 16"
            className="absolute transition-[opacity,transform] duration-200 ease-out"
            style={{ opacity: done ? 0 : 1, transform: done ? "scale(.6)" : "scale(1)" }}
          >
            <rect x="5" y="5" width="8.5" height="8.5" rx="2" fill="none" stroke="currentColor" strokeWidth="1.5" />
            <path d="M3.5 10.5h-.25A1.25 1.25 0 0 1 2 9.25v-6A1.25 1.25 0 0 1 3.25 2h6A1.25 1.25 0 0 1 10.5 3.25v.25" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
          </svg>
          <svg
            width="16"
            height="16"
            viewBox="0 0 16 16"
            className="absolute transition-[opacity,transform] duration-200 ease-out"
            style={{ opacity: done ? 1 : 0, transform: done ? "scale(1)" : "scale(.6)" }}
          >
            <path d="M3.5 8.4 6.6 11.4 12.5 4.8" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </span>
        <span aria-live="polite">{done ? "Copied" : "Copy key"}</span>
      </button>
      <p className="mt-4 min-h-[20px] text-center text-[13.5px] text-[var(--ink-3)]">
        {state === "auto"
          ? "Already on your clipboard, ready to paste."
          : state === "failed"
            ? "Couldn't copy. Select the key above and copy it yourself."
            : "It's in your receipt email too."}
      </p>
    </div>
  );
}
