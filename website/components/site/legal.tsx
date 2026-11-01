import type { ReactNode } from "react";
import { Container, SitePage } from "./chrome";

// Terms, Privacy and Refunds: a calm reading page. The title and a plain
// summary up top, then the sections, with an index beside them on wide
// screens. Each section gets an anchor, so it can be linked to directly.

export type LegalSection = { id: string; title: string; body: ReactNode };

const LEGAL_PAGES = [
  ["Terms", "/terms"],
  ["Privacy", "/privacy"],
  ["Refunds", "/refund-policy"],
] as const;

const css = `
.legal-prose { color: var(--ink-2); font-size: 16.5px; line-height: 1.7; }
.legal-prose p + p, .legal-prose p + ul, .legal-prose ul + p { margin-top: 14px; }
.legal-prose ul { margin-top: 12px; }
.legal-prose li { position: relative; padding-left: 20px; }
.legal-prose li + li { margin-top: 8px; }
.legal-prose li::before { content: ""; position: absolute; left: 3px; top: .72em; width: 5px; height: 5px; border-radius: 99px; background: rgba(31, 27, 22, .28); }
.legal-prose a { color: var(--ink); text-decoration: underline; text-decoration-color: rgba(31, 27, 22, .3); text-underline-offset: 3px; transition: text-decoration-color 160ms ease; }
@media (hover: hover) { .legal-prose a:hover { text-decoration-color: currentColor; } }
.legal-prose strong { color: var(--ink); font-weight: 600; }
.legal-section { scroll-margin-top: 24px; }
.legal-section:target h2 { color: var(--accent); }
`;

export function LegalPage({
  title,
  page,
  effective,
  summary,
  sections,
}: {
  title: string;
  page: (typeof LEGAL_PAGES)[number][0];
  effective: string;
  summary: ReactNode;
  sections: LegalSection[];
}) {
  return (
    <SitePage current="Legal">
      <style>{css}</style>
      <main>
        <Container className="pt-12 sm:pt-20">
          <p className="text-[14px] text-[var(--ink-3)]">
            Effective {effective}
          </p>
          <h1 className="site-display mt-4 text-balance text-[44px] font-bold leading-[0.98] tracking-[-0.035em] sm:text-[64px]">
            {title}
          </h1>
          <p className="mt-6 max-w-[38rem] text-pretty text-[18px] leading-[1.55] text-[var(--ink-2)] sm:text-[20px]">
            {summary}
          </p>
          <nav aria-label="Legal pages" className="mt-8 flex flex-wrap gap-2">
            {LEGAL_PAGES.map(([label, href]) => {
              const here = label === page;
              return (
                <a
                  key={href}
                  href={href}
                  aria-current={here ? "page" : undefined}
                  className={`site-btn inline-flex h-9 items-center rounded-full px-4 text-[14px] font-medium ${
                    here
                      ? "bg-[var(--ink)] text-[var(--paper)]"
                      : "text-[var(--ink-2)] shadow-[inset_0_0_0_1px_rgba(31,27,22,.14)]"
                  }`}
                >
                  {label}
                </a>
              );
            })}
          </nav>
        </Container>

        <Container className="mt-14 pb-24 sm:mt-20 sm:pb-32">
          <div className="grid gap-12 border-t border-[var(--line)] pt-12 sm:pt-16 lg:grid-cols-12 lg:gap-8">
            <aside className="hidden lg:col-span-3 lg:block">
              <div className="sticky top-8">
                <p className="text-[12px] font-semibold uppercase tracking-[0.08em] text-[var(--ink-3)]">
                  On this page
                </p>
                <ol className="mt-4 space-y-2.5 text-[14.5px] text-[var(--ink-2)]">
                  {sections.map((s) => (
                    <li key={s.id}>
                      <a href={`#${s.id}`} className="site-link">
                        {s.title}
                      </a>
                    </li>
                  ))}
                </ol>
              </div>
            </aside>
            <article className="max-w-[44rem] lg:col-span-8 lg:col-start-5">
              {sections.map((s, i) => (
                <section
                  key={s.id}
                  id={s.id}
                  className={`legal-section ${i ? "mt-12" : ""}`}
                >
                  <h2 className="site-display text-balance text-[24px] font-semibold leading-[1.2] tracking-[-0.015em] transition-colors sm:text-[26px]">
                    {s.title}
                  </h2>
                  <div className="legal-prose mt-4 text-pretty">{s.body}</div>
                </section>
              ))}
            </article>
          </div>
        </Container>
      </main>
    </SitePage>
  );
}
