import type { ReactNode } from "react";
import Link from "next/link";
import type * as PageTree from "fumadocs-core/page-tree";
import { DocsSearchLink } from "./docs-controls";

/**
 * The docs home banner image. Swap the file here, or override the
 * `--docs-banner` variable on `.docs-root`.
 */
export const DOCS_BANNER_IMAGE = "/site/bg/docs-a.jpg";

type Neighbour = PageTree.Item | undefined;

/** Previous / next cards at the foot of every page. */
export function DocsPager({ previous, next }: { previous: Neighbour; next: Neighbour }) {
  if (!previous && !next) return null;
  return (
    <nav aria-label="Pages" className="docs-pager">
      {previous ? <PagerCard item={previous} dir="prev" /> : <span aria-hidden className="max-sm:hidden" />}
      {next ? <PagerCard item={next} dir="next" /> : null}
    </nav>
  );
}

function PagerCard({ item, dir }: { item: PageTree.Item; dir: "prev" | "next" }) {
  return (
    <Link href={item.url} className="docs-pager-card" data-dir={dir}>
      <span className="docs-pager-label">
        {dir === "prev" ? (
          <>
            <Arrow dir="prev" /> Previous
          </>
        ) : (
          <>
            Next <Arrow dir="next" />
          </>
        )}
      </span>
      <span className="docs-pager-title">{item.name}</span>
    </Link>
  );
}

function Arrow({ dir }: { dir: "prev" | "next" }) {
  return (
    <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      {dir === "prev" ? <path d="M7.5 2.5 4 6l3.5 3.5" /> : <path d="M4.5 2.5 8 6 4.5 9.5" />}
    </svg>
  );
}

/** The docs home's banner tray: title, description and a short intro on the calm left of the image. */
export function DocsBanner({
  title,
  description,
  start,
}: {
  title: ReactNode;
  description?: ReactNode;
  start?: PageTree.Item;
}) {
  return (
    <header className="docs-banner">
      <div className="docs-banner-copy">
        <h1 className="docs-banner-title">{title}</h1>
        {description ? <p className="docs-banner-desc">{description}</p> : null}
        <p className="docs-banner-intro">
          How to install Hun, add your projects, and run them from the menu bar or the <code>hun</code> command.
        </p>
        <div className="docs-banner-actions">
          {start ? (
            <Link href={start.url} className="docs-btn docs-banner-primary">
              Start with {start.name}
            </Link>
          ) : null}
          <DocsSearchLink>
            Search the docs <kbd>⌘K</kbd>
          </DocsSearchLink>
        </div>
      </div>
    </header>
  );
}
