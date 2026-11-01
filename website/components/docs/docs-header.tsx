import { existsSync } from "node:fs";
import { join } from "node:path";
import type { CSSProperties, ReactNode } from "react";

/** One landscape per sidebar section. */
export const SECTION_IMAGES = {
  start: "/site/bg/docs-start.jpg",
  using: "/site/bg/docs-using.jpg",
  reference: "/site/bg/docs-reference.jpg",
} as const;

/** Used until a section's image exists, and for pages not listed below. */
const FALLBACK_IMAGE = "/site/bg/docs-b.jpg";

/** Which section each page belongs to, by slug. */
export const PAGE_SECTIONS: Record<string, keyof typeof SECTION_IMAGES> = {
  install: "start",
  "getting-started": "start",
  "menu-bar": "using",
  window: "using",
  "focus-and-multitask": "using",
  ports: "using",
  profiles: "using",
  docker: "using",
  agents: "using",
  "hun-yml": "reference",
  cli: "reference",
  "license-and-updates": "reference",
  troubleshooting: "reference",
};

function headerImage(slug: string) {
  const section = PAGE_SECTIONS[slug];
  const file = section ? SECTION_IMAGES[section] : undefined;
  if (file && existsSync(join(process.cwd(), "public", file))) return file;
  return FALLBACK_IMAGE;
}

/**
 * An inner page's header: the section's landscape in a tray, with the title
 * and description on a cream card. Every page's tray and card are the same
 * size, so moving between pages doesn't shift anything.
 */
export function DocsPageHeader({ slug, title, description }: { slug: string; title: ReactNode; description?: ReactNode }) {
  return (
    <header
      className="docs-tray"
      style={{ "--docs-tray-image": `url(${headerImage(slug)})` } as CSSProperties}
    >
      <div className="docs-tray-copy">
        <h1 className="docs-title">{title}</h1>
        {description ? <p className="docs-description">{description}</p> : null}
      </div>
    </header>
  );
}
