import { Reveal } from "@/components/reveal";
import releases from "@/content/changelog.json";
import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Changelog",
  description: "Every meaningful change shipped in hun.",
  alternates: { canonical: "/changelog" },
  openGraph: {
    title: "hun changelog",
    description: "Every meaningful change shipped in hun.",
    url: "https://hun.sh/changelog",
  },
};

const releaseDate = new Intl.DateTimeFormat("en", {
  day: "2-digit",
  month: "short",
  year: "numeric",
  timeZone: "UTC",
});

export default function ChangelogPage() {
  return (
    <div className="min-h-dvh bg-background px-5 py-8 text-foreground sm:px-6 sm:py-12">
      <main className="mx-auto w-full max-w-5xl">
        <Reveal>
          <nav className="flex items-center justify-between gap-4 text-[12px] text-muted-foreground/45">
            <Link
              href="/"
              aria-label="Hun home"
              className="inline-flex size-11 items-center transition-opacity hover:opacity-80"
            >
              <Image
                src="/hun-app-icon.png"
                alt=""
                width={34}
                height={34}
                className="size-[34px]"
                priority
              />
            </Link>
            <div className="flex items-center gap-4">
              <Link
                href="/"
                className="underline underline-offset-2 transition-colors hover:text-muted-foreground/70"
              >
                macOS
              </Link>
              <Link
                href="/docs"
                className="underline underline-offset-2 transition-colors hover:text-muted-foreground/70"
              >
                docs
              </Link>
            </div>
          </nav>
        </Reveal>

        <header className="border-b border-border pb-12 pt-16 sm:pb-16 sm:pt-24">
          <Reveal delay={0.08}>
            <p className="mb-4 text-[11px] uppercase tracking-[0.2em] text-muted-foreground/35">
              shipped work
            </p>
            <h1 className="max-w-2xl text-[42px] font-medium leading-[1.02] tracking-[-0.045em] text-foreground sm:text-[62px]">
              changes that alter the way you work.
            </h1>
            <p className="mt-6 max-w-xl text-[14px] leading-relaxed text-muted-foreground/55 sm:text-[15px]">
              A record of meaningful behavior—not every commit, dependency
              bump, or coat of paint.
            </p>
          </Reveal>
        </header>

        <div>
          {releases.map((release, index) => (
            <Reveal key={release.version} delay={Math.min(0.12 + index * 0.035, 0.28)}>
              <article
                id={`v${release.version}`}
                className="scroll-mt-8 border-b border-border py-10 sm:grid sm:grid-cols-[9rem_minmax(0,1fr)] sm:gap-10 sm:py-14"
              >
                <aside className="mb-6 sm:mb-0">
                  <div className="sm:sticky sm:top-8">
                    <div className="flex items-center gap-2">
                      {index === 0 && (
                        <span
                          className="h-1.5 w-1.5 rounded-full bg-emerald-400/80"
                          aria-label="Current release"
                        />
                      )}
                      <a
                        href={`#v${release.version}`}
                        className="text-[13px] font-medium text-foreground/85 transition-colors hover:text-foreground"
                      >
                        v{release.version}
                      </a>
                    </div>
                    <time
                      dateTime={release.date}
                      className="mt-2 block text-[11px] text-muted-foreground/35"
                    >
                      {releaseDate.format(new Date(`${release.date}T00:00:00Z`))}
                    </time>
                  </div>
                </aside>

                <div className="min-w-0">
                  <h2 className="text-[25px] font-medium leading-[1.1] tracking-[-0.03em] text-foreground sm:text-[30px]">
                    {release.title}
                  </h2>
                  <p className="mt-3 max-w-2xl text-[13px] leading-relaxed text-muted-foreground/55 sm:text-[14px]">
                    {release.summary}
                  </p>

                  <div className="mt-8 space-y-8">
                    {release.groups.map((group) => (
                      <section
                        key={group.title}
                        aria-labelledby={`v${release.version}-${group.title
                          .toLowerCase()
                          .replaceAll(" ", "-")}`}
                      >
                        <h3
                          id={`v${release.version}-${group.title
                            .toLowerCase()
                            .replaceAll(" ", "-")}`}
                          className="text-[10px] font-semibold uppercase tracking-[0.16em] text-muted-foreground/35"
                        >
                          {group.title}
                        </h3>
                        <ul className="mt-3 divide-y divide-border/60 border-t border-border/60">
                          {group.changes.map((change) => (
                            <li
                              key={change}
                              className="grid grid-cols-[12px_1fr] gap-3 py-3 text-[13px] leading-relaxed text-muted-foreground/65"
                            >
                              <span
                                className="pt-[1px] text-muted-foreground/25"
                                aria-hidden="true"
                              >
                                +
                              </span>
                              <span>{change}</span>
                            </li>
                          ))}
                        </ul>
                      </section>
                    ))}
                  </div>
                </div>
              </article>
            </Reveal>
          ))}
        </div>

        <footer className="flex flex-wrap items-center justify-between gap-4 py-8 text-[12px] text-muted-foreground/35">
          <Link
            href="/"
            className="underline underline-offset-2 transition-colors hover:text-muted-foreground/60"
          >
            back home
          </Link>
          <a
            href="https://github.com/sourabhrathourr/hun/releases"
            className="underline underline-offset-2 transition-colors hover:text-muted-foreground/60"
          >
            release artifacts
          </a>
        </footer>
      </main>
    </div>
  );
}
