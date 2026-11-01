import type { ReactNode } from "react";
import { HUN_PRICE, hunCheckoutURL } from "@/lib/dodo";
import { display, mono, text } from "./fonts";
import { DOWNLOAD_URL } from "./links";
import { MobileNav } from "./mobile-nav";
import Link from "next/link";
import { HunMark } from "@/components/site/hun-mark";

// The site's shared frame: tokens, type, the top bar and the footer. Every
// page renders inside <SitePage>, so they all share one nav and one footer.

const SITE_CSS = `
.site {
  --paper: #F5F0E6;
  --raised: #FFFCF6;
  --ink: #1F1B16;
  --heading-ink: #2B2622;
  --ink-2: #4F483F;
  --ink-3: #6E675C;
  --line: rgba(31, 27, 22, .1);
  --accent: #C24A1F;
  --run: #3E7B4F;
  --tray: #EAE2D2;
  --code-bg: rgba(31, 27, 22, .06);
  background: var(--paper);
  color: var(--ink);
  font-family: var(--f-text), ui-sans-serif, system-ui, sans-serif;
  -webkit-font-smoothing: antialiased;
}
.site ::selection { background: rgba(194, 74, 31, .18); }
/* Headings on the light sections are a step softer than ink; solid fills
   (buttons, the dark bands) keep full ink. Not the dark bands, not muted labels. */
.site :is(h1, h2):not(.hf-band *):not([class*="ink-3"]) { color: var(--heading-ink); }
.site-display { font-family: var(--f-display), ui-sans-serif, system-ui, sans-serif; font-variation-settings: "opsz" 96; }
.site-mono { font-family: var(--f-mono), ui-monospace, monospace; font-variant-ligatures: none; }
.site-btn { transition: transform 160ms cubic-bezier(.23, 1, .32, 1), opacity 160ms ease; }
.site-btn:active { transform: scale(.97); }
@media (hover: hover) { .site-btn:hover { opacity: .9; } }
.site-link { text-decoration-line: underline; text-decoration-color: transparent; text-underline-offset: 4px; transition: text-decoration-color 160ms ease, color 160ms ease; }
@media (hover: hover) { .site-link:hover { text-decoration-color: currentColor; color: var(--ink); } }
.site-card { box-shadow: 0 0 0 .5px rgba(31, 27, 22, .2), 0 1px 2px rgba(31, 27, 22, .05), 0 40px 80px -36px rgba(64, 44, 16, .45), 0 14px 28px -18px rgba(64, 44, 16, .2); }
.site :focus-visible { outline: 2px solid var(--accent); outline-offset: 3px; border-radius: 6px; }
@media (prefers-reduced-motion: reduce) { .site-btn, .site-link { transition: none; } }
`;

export type SitePageName = "Home" | "Pricing" | "Changelog" | "Docs" | "Legal" | "License";

/** The page frame: tokens and fonts, the nav, the page, the footer. */
export function SitePage({
  current,
  className = "",
  children,
}: {
  current: SitePageName;
  className?: string;
  children: ReactNode;
}) {
  return (
    <div className={`site ${display.variable} ${text.variable} ${mono.variable} min-h-dvh ${className}`}>
      <style>{SITE_CSS}</style>
      <SiteNav current={current} />
      {children}
      <SiteFooter />
    </div>
  );
}

export function Container({ children, className = "" }: { children: ReactNode; className?: string }) {
  return <div className={`mx-auto w-full max-w-[1248px] px-5 sm:px-8 ${className}`}>{children}</div>;
}

const NAV: [label: SitePageName | "Download", href: string][] = [
  ["Pricing", "/pricing"],
  ["Docs", "/docs/getting-started"],
  ["Changelog", "/changelog"],
  ["Download", DOWNLOAD_URL],
];

function SiteNav({ current }: { current: SitePageName }) {
  return (
    <header>
      <Container className="flex h-16 items-center justify-between">
        <Link href="/" aria-label="Hun home" className="flex items-center gap-2.5">
          <HunMark size={22} />
          <span className="site-display text-[19px] font-semibold tracking-[-0.02em]">Hun</span>
        </Link>
        <nav className="flex items-center gap-3 text-[14.5px] text-[var(--ink-2)] sm:gap-6">
          {NAV.map(([label, href]) => (
            <a
              key={label}
              href={href}
              aria-current={current === label ? "page" : undefined}
              className={`site-link hidden sm:inline ${current === label ? "text-[var(--ink)]" : ""}`}
            >
              {label}
            </a>
          ))}
          {/* On the pricing page the button goes straight to checkout. */}
          <a
            href={current === "Pricing" ? hunCheckoutURL : "/pricing"}
            className="site-btn inline-flex h-9 items-center rounded-full bg-[var(--ink)] px-4 text-[14px] font-medium text-[var(--paper)]"
          >
            Buy · {HUN_PRICE}
          </a>
          <MobileNav current={current} />
        </nav>
      </Container>
    </header>
  );
}

const FOOTER: [string, string][] = [
  ["Docs", "/docs/getting-started"],
  ["Changelog", "/changelog"],
  ["Pricing", "/pricing"],
  ["Refunds", "/refund-policy"],
  ["Privacy", "/privacy"],
  ["Terms", "/terms"],
];

function SiteFooter() {
  return (
    <footer className="text-[var(--ink-3)]">
      <Container className="flex flex-col gap-6 py-12 text-[14px] sm:flex-row sm:items-center sm:justify-between sm:py-14">
        <div className="flex items-center gap-2.5">
          <HunMark size={18} />
          <span>Hun, for the dev servers on your Mac.</span>
        </div>
        <nav className="grid grid-cols-3 gap-x-6 gap-y-3 sm:flex sm:flex-wrap sm:gap-y-2">
          {FOOTER.map(([label, href]) => (
            <a key={href} href={href} className="site-link">
              {label}
            </a>
          ))}
        </nav>
      </Container>
    </footer>
  );
}
