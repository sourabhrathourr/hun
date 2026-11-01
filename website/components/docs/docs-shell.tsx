"use client";

import type { CSSProperties, ReactNode } from "react";
import type * as PageTree from "fumadocs-core/page-tree";
import { DocsLayout } from "fumadocs-ui/layouts/docs";
import { RootProvider } from "fumadocs-ui/provider/next";
import { DocsSearchField } from "./docs-controls";
import { DocsNav, DrawerSiteLinks } from "./docs-nav";

// The site nav spans the full width above the sidebar, page and TOC, so the
// docs grid gets a header row of its own. The page column is sized
// explicitly so the grid lines up with the site's 1248px container.
const GRID_TEMPLATE = `"header header header header header"
  "sidebar sidebar toc-popover toc toc"
  "sidebar sidebar main toc toc" 1fr / minmax(0, 1fr) var(--fd-sidebar-col) min(calc(var(--fd-layout-width) - var(--fd-sidebar-width) - var(--fd-toc-width)), calc(100% - var(--fd-sidebar-col) - var(--fd-toc-width))) var(--fd-toc-width) minmax(0, 1fr)`;

/**
 * Fumadocs' layout with the site's nav, search field and drawer links.
 * The layout renders this as its only child, with the <style> inside it:
 * with a sibling next to the client root, React's useId drifted between the
 * server and the client and the mobile TOC popover failed to hydrate cleanly.
 */
export function DocsShell({
  tree,
  checkoutURL,
  price,
  styles,
  children,
}: {
  tree: PageTree.Root;
  checkoutURL: string;
  price: string;
  styles: string;
  children: ReactNode;
}) {
  return (
    <>
      <style>{styles}</style>
      <RootProvider theme={{ enabled: false }} search={{ options: { api: "/docs/api/search" } }}>
        <DocsLayout
          tree={tree}
          nav={{ title: () => null, component: <DocsNav checkoutURL={checkoutURL} price={price} /> }}
          links={[{ type: "custom", on: "menu", children: <DrawerSiteLinks /> }]}
          searchToggle={{ components: { lg: <DocsSearchField /> } }}
          sidebar={{ collapsible: false }}
          themeSwitch={{ enabled: false }}
          containerProps={{ style: { gridTemplate: GRID_TEMPLATE } as CSSProperties }}
        >
          {children}
        </DocsLayout>
      </RootProvider>
    </>
  );
}
