"use client";

import { DOWNLOAD_URL } from "@/components/site/links";
import { DocsMenuButton, DocsSearchIcon } from "./docs-controls";
import Link from "next/link";
import { HunMark } from "@/components/site/hun-mark";

export const SITE_LINKS = [
  { label: "Pricing", href: "/pricing" },
  { label: "Docs", href: "/docs" },
  { label: "Changelog", href: "/changelog" },
  { label: "Download", href: DOWNLOAD_URL },
] as const;

/** The site's nav, sticky across the docs, with search and the drawer on narrow screens. */
export function DocsNav({ checkoutURL, price }: { checkoutURL: string; price: string }) {
  return (
    <header id="docs-nav" className="docs-nav">
      <div className="mx-auto flex h-full w-full max-w-[1248px] items-center justify-between gap-4 px-5 sm:px-8">
        <Link href="/" className="docs-focus flex items-center gap-2.5 rounded-md">
          <HunMark size={22} />
          <span className="docs-display text-[19px] font-semibold tracking-[-0.02em] text-[var(--hd-ink)]">Hun</span>
        </Link>
        <nav aria-label="Site" className="flex items-center gap-6 text-[14.5px] text-[var(--hd-ink-2)]">
          {SITE_LINKS.map((l) => (
            <a
              key={l.label}
              href={l.href}
              aria-current={l.label === "Docs" ? "page" : undefined}
              className={`docs-nav-link hidden sm:inline ${l.label === "Docs" ? "text-[var(--hd-ink)]" : ""}`}
            >
              {l.label}
            </a>
          ))}
          <div className="-mr-1.5 flex items-center gap-0.5 md:hidden">
            <DocsSearchIcon />
          </div>
          <a
            href={checkoutURL}
            className="docs-btn inline-flex h-9 items-center whitespace-nowrap rounded-full bg-[var(--hd-ink)] px-4 text-[14px] font-medium text-[var(--hd-paper)]"
          >
            Buy · {price}
          </a>
          <div className="-ml-3 -mr-2 md:hidden">
            <DocsMenuButton />
          </div>
        </nav>
      </div>
    </header>
  );
}

/** Site links at the top of the mobile drawer; hidden in the desktop sidebar. */
export function DrawerSiteLinks() {
  return (
    <div className="docs-drawer-links">
      {SITE_LINKS.filter((l) => l.label !== "Docs").map((l) => (
        <a key={l.label} href={l.href}>
          {l.label}
        </a>
      ))}
    </div>
  );
}
