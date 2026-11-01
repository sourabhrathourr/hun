"use client";

import { useEffect, useState } from "react";
import { HUN_PRICE, hunCheckoutURL } from "@/lib/dodo";
import { DOWNLOAD_URL } from "./links";
import Link from "next/link";
import { HunMark } from "@/components/site/hun-mark";

// Phones: the nav links live behind one button. The panel drops from the top
// bar, closes on Escape, on a link, or when the page is resized past phones.

const LINKS: [string, string][] = [
  ["Pricing", "/pricing"],
  ["Docs", "/docs"],
  ["Changelog", "/changelog"],
  ["Download for Mac", DOWNLOAD_URL],
];

export function MobileNav({ current }: { current?: string }) {
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    const mq = window.matchMedia("(min-width: 640px)");
    const onMq = () => mq.matches && setOpen(false);
    window.addEventListener("keydown", onKey);
    mq.addEventListener("change", onMq);
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      mq.removeEventListener("change", onMq);
      document.body.style.overflow = "";
    };
  }, [open]);

  return (
    <div className="sm:hidden">
      <button
        type="button"
        aria-label={open ? "Close menu" : "Open menu"}
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
        className="relative z-[60] inline-flex size-10 items-center justify-center rounded-full text-[#1F1B16] active:scale-[0.96]"
        style={{ transition: "transform 160ms cubic-bezier(.23,1,.32,1)" }}
      >
        <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
          {open ? (
            <path d="M4 4l10 10M14 4 4 14" />
          ) : (
            <path d="M2.5 6h13M2.5 12h13" />
          )}
        </svg>
      </button>
      {open && (
        <div className="fixed inset-0 z-50 bg-[#F5F0E6]" style={{ animation: "mn-in 200ms cubic-bezier(.23,1,.32,1)" }}>
          <style>{`@keyframes mn-in { from { opacity: 0; transform: translateY(-6px); } } @media (prefers-reduced-motion: reduce) { .mn-panel { animation: none !important; } }`}</style>
          <Link href="/" className="absolute left-5 top-0 flex h-16 items-center gap-2.5" onClick={() => setOpen(false)}>
            <HunMark size={22} />
            <span className="text-[19px] font-semibold tracking-[-0.02em] text-[#1F1B16]" style={{ fontFamily: "var(--f-display), ui-sans-serif, system-ui" }}>
              Hun
            </span>
          </Link>
          <nav className="mn-panel flex h-full flex-col px-5 pb-10 pt-20">
            <ul className="border-t border-[rgba(31,27,22,.1)]">
              {LINKS.map(([label, href]) => (
                <li key={href} className="border-b border-[rgba(31,27,22,.1)]">
                  <a
                    href={href}
                    onClick={() => setOpen(false)}
                    aria-current={current === label ? "page" : undefined}
                    className="flex items-center justify-between py-4 text-[22px] font-semibold tracking-[-0.015em] text-[#1F1B16]"
                    style={{ fontFamily: "var(--f-display), ui-sans-serif, system-ui" }}
                  >
                    {label}
                    <span aria-hidden className="text-[18px] text-[#6E675C]">
                      →
                    </span>
                  </a>
                </li>
              ))}
            </ul>
            <a
              href={hunCheckoutURL}
              className="mt-auto flex h-12 items-center justify-center rounded-full bg-[#1F1B16] text-[16px] font-medium text-[#F5F0E6] active:scale-[0.98]"
            >
              Buy Hun · {HUN_PRICE}
            </a>
            <p className="mt-4 text-center text-[13px] text-[#6E675C]">Apple silicon, macOS 15 or later.</p>
          </nav>
        </div>
      )}
    </div>
  );
}
