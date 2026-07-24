import type { Metadata } from "next";
import Link from "next/link";
import { releases } from "./releases";

export const metadata: Metadata = {
  title: "changelog — hun.sh",
  description: "what's new in hun. every release, in order.",
  openGraph: {
    title: "changelog — hun.sh",
    description: "what's new in hun. every release, in order.",
    url: "https://hun.sh/changelog",
    images: [
      {
        url: "/api/og?type=docs&title=changelog&description=what%27s%20new%20in%20hun",
        width: 1200,
        height: 630,
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "changelog — hun.sh",
    description: "what's new in hun. every release, in order.",
  },
};

function formatDate(iso: string) {
  return new Date(`${iso}T00:00:00Z`).toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
    timeZone: "UTC",
  });
}

export default function ChangelogPage() {
  return (
    <div className="min-h-dvh bg-background text-foreground px-5 sm:px-6">
      <div className="mx-auto w-full max-w-3xl py-10 sm:py-14">
        <nav className="flex items-center justify-between gap-4 text-caption text-muted-foreground/60">
          <Link
            href="/"
            className="font-serif text-[24px] leading-none text-foreground hover:text-foreground/80"
          >
            hun.sh
          </Link>
          <div className="flex items-center gap-4">
            <Link href="/docs" className="hover:text-foreground">
              docs
            </Link>
            <a
              href="https://github.com/sourabhrathourr/hun/releases"
              className="hover:text-foreground"
            >
              github releases
            </a>
          </div>
        </nav>

        <header className="mt-section-sm">
          <h1 className="text-headline text-foreground">changelog</h1>
          <p className="mt-3 text-lead text-muted-foreground">
            what&apos;s new in hun. every release, in order.
          </p>
        </header>

        <div className="mt-block divide-y divide-border">
          {releases.map((release) => (
            <article
              key={release.tag ?? release.version}
              className="py-block sm:grid sm:grid-cols-[160px_1fr] sm:gap-8"
            >
              <div className="mb-4 sm:mb-0">
                <h2 className="font-mono text-body font-medium text-foreground">
                  {release.version}
                </h2>
                <time
                  dateTime={release.date}
                  className="mt-1 block text-caption text-muted-foreground/60"
                >
                  {formatDate(release.date)}
                </time>
              </div>
              <div>
                <p className="text-body text-foreground/85">{release.summary}</p>
                <ul className="mt-4 space-y-2">
                  {release.changes.map((change) => (
                    <li
                      key={change}
                      className="flex gap-3 text-body text-muted-foreground"
                    >
                      <span
                        aria-hidden
                        className="mt-[0.72em] h-px w-3 shrink-0 bg-muted-foreground/40"
                      />
                      <span>{change}</span>
                    </li>
                  ))}
                </ul>
              </div>
            </article>
          ))}
        </div>

        <footer className="border-t border-border pt-8 pb-4 text-caption text-muted-foreground/60">
          <Link href="/" className="hover:text-foreground">
            back to hun.sh
          </Link>{" "}
          &middot;{" "}
          <a
            href="https://github.com/sourabhrathourr/hun/releases"
            className="hover:text-foreground"
          >
            full release notes on github
          </a>
        </footer>
      </div>
    </div>
  );
}
