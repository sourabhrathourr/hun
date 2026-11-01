import type { Metadata } from "next";
import releases from "@/content/changelog.json";
import { Container, SitePage } from "@/components/site/chrome";
import { DOWNLOAD_URL } from "@/components/site/links";
import { pageMetadata } from "@/lib/og/meta";

// Direction F's changelog: the latest release on a warm tray, then every
// release down the page, grouped by month. Anchors stay #v0.4.3, which the
// app's update notice links to.

export const metadata: Metadata = pageMetadata({
  title: "Changelog · Hun",
  description: "Every Hun release, newest first.",
  path: "/changelog",
});

type Release = (typeof releases)[number];

const css = `
.hc {
  --paper: #F5F0E6;
  --raised: #FFFCF6;
  --ink: #1F1B16;
  --ink-2: #4F483F;
  --ink-3: #6E675C;
  --line: rgba(31, 27, 22, .1);
  --accent: #C24A1F;
  --tray: #EAE2D2;
  background: var(--paper);
  color: var(--ink);
  font-family: var(--f-text), ui-sans-serif, system-ui, sans-serif;
  -webkit-font-smoothing: antialiased;
}
.hc ::selection { background: rgba(194, 74, 31, .18); }
.hc-display { font-family: var(--f-display), ui-sans-serif, system-ui, sans-serif; font-variation-settings: "opsz" 96; }
.hc-mono { font-family: var(--f-mono), ui-monospace, monospace; font-variant-ligatures: none; }
.hc-btn { transition: transform 160ms cubic-bezier(.23, 1, .32, 1), opacity 160ms ease; }
.hc-btn:active { transform: scale(.97); }
@media (hover: hover) { .hc-btn:hover { opacity: .9; } }
.hc-link { text-decoration-line: underline; text-decoration-color: transparent; text-underline-offset: 4px; transition: text-decoration-color 160ms ease, color 160ms ease; }
@media (hover: hover) { .hc-link:hover { text-decoration-color: currentColor; color: var(--ink); } }
.hc-card { box-shadow: 0 0 0 .5px rgba(31, 27, 22, .2), 0 1px 2px rgba(31, 27, 22, .05), 0 40px 80px -36px rgba(64, 44, 16, .45), 0 14px 28px -18px rgba(64, 44, 16, .2); }
.hc-rel { scroll-margin-top: 24px; }
.hc-rel:target .hc-ver { color: var(--accent); }
.hc-list li { position: relative; padding-left: 18px; }
.hc-list li::before { content: ""; position: absolute; left: 2px; top: .7em; width: 5px; height: 5px; border-radius: 99px; background: rgba(31, 27, 22, .28); }
`;

const fmtDay = new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" });
const fmtMonth = new Intl.DateTimeFormat("en-GB", { month: "long", year: "numeric", timeZone: "UTC" });
const day = (iso: string) => fmtDay.format(new Date(`${iso}T00:00:00Z`));
const month = (iso: string) => fmtMonth.format(new Date(`${iso}T00:00:00Z`));

export default function ChangelogF() {
  const all = releases as Release[];
  const [latest] = all;
  const byMonth: { month: string; items: Release[] }[] = [];
  for (const r of all) {
    const m = month(r.date);
    const last = byMonth[byMonth.length - 1];
    if (last?.month === m) last.items.push(r);
    else byMonth.push({ month: m, items: [r] });
  }

  return (
    <SitePage current="Changelog" className="hc">
      <style>{css}</style>
      <main>
        <section className="pt-12 sm:pt-20">
          <Container>
            <h1 className="hc-display text-balance text-[44px] font-bold leading-[0.98] tracking-[-0.035em] sm:text-[64px] lg:text-[80px]">
              What’s new in Hun.
            </h1>
            <p className="mt-6 max-w-[34rem] text-pretty text-[18px] leading-[1.55] text-[var(--ink-2)] sm:text-[20px]">
              Every release, newest first. When a new one is out, Hun shows a note in the app and installs it in one click.
            </p>
          </Container>

          <Container className="mt-12 sm:mt-16">
            <div
              className="rounded-[28px] bg-[var(--tray)] bg-cover bg-center px-5 py-10 sm:px-12 sm:py-16 lg:px-16"
              style={{ backgroundImage: "url(/site/bg/changelog-hero.jpg)" }}
            >
              <a
                href={`#v${latest.version}`}
                className="hc-card group block max-w-[560px] rounded-[20px] bg-[var(--raised)] p-7 sm:p-9"
              >
                <p className="flex items-center gap-3 text-[13.5px] text-[var(--ink-3)]">
                  <span className="hc-mono rounded-full bg-[rgba(194,74,31,.1)] px-2.5 py-[3px] text-[12.5px] font-medium text-[var(--accent)]">
                    v{latest.version}
                  </span>
                  Latest · {day(latest.date)}
                </p>
                <h2 className="hc-display mt-5 text-balance text-[28px] font-bold leading-[1.08] tracking-[-0.02em] sm:text-[34px]">
                  {latest.title}
                </h2>
                <p className="mt-4 text-pretty text-[16.5px] leading-[1.55] text-[var(--ink-2)]">{latest.summary}</p>
                <p className="mt-7 text-[15px] font-medium text-[var(--ink)]">
                  <span className="hc-link group-hover:underline">Read the notes</span> ↓
                </p>
              </a>
            </div>
          </Container>
        </section>

        <section className="py-24 sm:py-32">
          <Container>
            {byMonth.map((g) => (
              <div key={g.month} className="border-t border-[var(--line)] pt-6 first:border-t-0 first:pt-0">
                <h2 className="hc-display sticky top-0 z-10 -mx-1 bg-[var(--paper)] px-1 py-4 text-[14px] font-semibold uppercase tracking-[0.08em] text-[var(--ink-3)]">
                  {g.month}
                </h2>
                <ol>
                  {g.items.map((r) => (
                    <ReleaseEntry key={r.version} r={r} latest={r.version === latest.version} />
                  ))}
                </ol>
              </div>
            ))}
          </Container>
        </section>

        <section className="border-t border-[var(--line)] py-24 text-center sm:py-32">
          <Container>
            <h2 className="hc-display text-balance text-[36px] font-bold leading-[1.02] tracking-[-0.03em] sm:text-[52px]">
              Get every one of these.
            </h2>
            <p className="mx-auto mt-5 max-w-[30rem] text-pretty text-[18px] leading-[1.55] text-[var(--ink-2)]">
              Every update is included with your license. Hun lets you know when one is ready.
            </p>
            <div className="mt-9 flex flex-wrap items-center justify-center gap-x-6 gap-y-4">
              <a
                href={DOWNLOAD_URL}
                className="hc-btn inline-flex h-11 items-center rounded-full bg-[var(--ink)] px-5 text-[15px] font-medium text-[var(--paper)]"
              >
                Download for Mac
              </a>
              <a href="/pricing" className="hc-link text-[15px] font-medium text-[var(--ink-2)]">
                Pricing
              </a>
            </div>
          </Container>
        </section>
      </main>
    </SitePage>
  );
}

function ReleaseEntry({ r, latest }: { r: Release; latest: boolean }) {
  return (
    <li id={`v${r.version}`} className="hc-rel grid gap-6 border-t border-[var(--line)] py-12 first:border-t-0 first:pt-8 sm:py-14 sm:first:pt-10 lg:grid-cols-12 lg:gap-8">
      <div className="lg:col-span-3">
        <div className="lg:sticky lg:top-16">
          <a href={`#v${r.version}`} className="hc-ver hc-display text-[30px] font-bold leading-none tracking-[-0.025em] transition-colors hover:text-[var(--accent)]">
            {r.version}
          </a>
          <p className="mt-2 flex items-center gap-2 text-[14px] text-[var(--ink-3)]">
            {day(r.date)}
            {latest && (
              <span className="rounded-full bg-[rgba(194,74,31,.1)] px-2 py-[2px] text-[11.5px] font-medium text-[var(--accent)]">Latest</span>
            )}
          </p>
        </div>
      </div>
      <div className="max-w-[46rem] lg:col-span-8 lg:col-start-5">
        <h3 className="hc-display text-balance text-[24px] font-semibold leading-[1.15] tracking-[-0.015em] sm:text-[28px]">{r.title}</h3>
        {r.summary && <p className="mt-3 text-pretty text-[17px] leading-[1.6] text-[var(--ink-2)]">{r.summary}</p>}
        <div className="mt-8 space-y-8">
          {r.groups.map((g) => (
            <div key={g.title}>
              <p className="text-[12px] font-semibold uppercase tracking-[0.08em] text-[var(--ink-3)]">{g.title}</p>
              <ul className="hc-list mt-3 space-y-2.5 text-pretty text-[16px] leading-[1.6] text-[var(--ink-2)]">
                {g.changes.map((c) => (
                  <li key={c}>{c}</li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </div>
    </li>
  );
}



