"use client";

// Search is always on in the docs, so these render unconditionally.

import { useSearchContext } from "fumadocs-ui/contexts/search";
import { SidebarTrigger } from "fumadocs-ui/components/sidebar/base";

function SearchGlyph({ className = "" }: { className?: string }) {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      aria-hidden
      className={className}
    >
      <circle cx="7" cy="7" r="4.6" />
      <path d="m10.5 10.5 3 3" />
    </svg>
  );
}

/** The sidebar's search field: a quiet raised pill with the shortcut on the right. */
export function DocsSearchField() {
  const { hotKey, setOpenSearch } = useSearchContext();
  return (
    <button type="button" data-search-full="" className="docs-search-field" onClick={() => setOpenSearch(true)}>
      <SearchGlyph className="shrink-0" />
      <span className="flex-1 text-start">Search docs</span>
      <span className="docs-kbd" aria-hidden>
        {hotKey.map((k, i) => (
          <span key={i}>{k.display}</span>
        ))}
      </span>
    </button>
  );
}

/** Icon-only search button for the narrow nav. */
export function DocsSearchIcon() {
  const { setOpenSearch } = useSearchContext();
  return (
    <button type="button" data-search="" aria-label="Search docs" className="docs-icon-btn" onClick={() => setOpenSearch(true)}>
      <SearchGlyph />
    </button>
  );
}

/** Opens the docs drawer on narrow screens. */
export function DocsMenuButton() {
  return (
    <SidebarTrigger aria-label="Open docs menu" className="docs-icon-btn">
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" aria-hidden>
        <path d="M2.5 5h11M2.5 11h11" />
      </svg>
    </SidebarTrigger>
  );
}

/** Opens search from the docs home banner. */
export function DocsSearchLink({ children }: { children: React.ReactNode }) {
  const { setOpenSearch } = useSearchContext();
  return (
    <button type="button" className="docs-banner-link" onClick={() => setOpenSearch(true)}>
      {children}
    </button>
  );
}
