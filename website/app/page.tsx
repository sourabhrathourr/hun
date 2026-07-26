import { Reveal } from "@/components/reveal";
import releases from "@/content/changelog.json";
import macosImage from "@/public/macos-image.png";
import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";

const downloadURL =
  "https://github.com/sourabhrathourr/hun/releases/latest/download/hun-macos-arm64.dmg";
const currentVersion = releases[0].version;

export const metadata: Metadata = {
  title: "hun for macOS",
  description:
    "The native Hun workspace for switching projects, reviewing Git changes, running terminals, watching logs, and managing dev services.",
  alternates: {
    canonical: "/",
  },
  openGraph: {
    title: "hun for macOS",
    description:
      "The native Hun workspace for projects, Git changes, terminals, logs, and dev services.",
    url: "https://hun.sh",
    images: [{ url: "/api/og/macos", width: 1200, height: 630 }],
  },
  twitter: {
    card: "summary_large_image",
    title: "hun for macOS",
    description:
      "The native Hun workspace for projects, Git changes, terminals, logs, and dev services.",
    images: ["/api/og/macos"],
  },
};

const details = [
  {
    title: "menu bar first",
    body: "open hun from the menu bar, switch projects, restart services, and jump into logs without keeping the terminal in front.",
  },
  {
    title: "focus and multitask",
    body: "run one project cleanly, or keep multiple stacks alive when you need frontend, workers, databases, and queues side by side.",
  },
  {
    title: "docker aware",
    body: "services that depend on docker can start Docker Desktop before hun asks compose to pull images or boot containers.",
  },
  {
    title: "bundled cli",
    body: "the app ships with its own hun cli inside the bundle, so the app uses the protocol it was built and tested with.",
  },
];

export default function HomePage() {
  const d = 0.1;

  return (
    <div className="min-h-dvh bg-background text-foreground px-5 sm:px-6 py-8 sm:py-12">
      <main className="mx-auto w-full max-w-6xl">
        <Reveal>
          <nav className="flex items-center justify-between gap-4 text-[12px] text-muted-foreground/45">
            <Link
              href="/"
              className="font-serif text-[24px] leading-none text-foreground hover:text-foreground/80"
            >
              hun.sh
            </Link>
            <div className="flex items-center gap-4">
              <Link
                href="/legacy"
                className="underline underline-offset-2 hover:text-muted-foreground/70"
              >
                cli
              </Link>
              <Link
                href="/changelog"
                className="underline underline-offset-2 hover:text-muted-foreground/70"
              >
                changelog
              </Link>
              <Link
                href="/docs"
                className="underline underline-offset-2 hover:text-muted-foreground/70"
              >
                docs
              </Link>
              <a
                href="https://github.com/sourabhrathourr/hun"
                className="underline underline-offset-2 hover:text-muted-foreground/70"
              >
                github
              </a>
            </div>
          </nav>
        </Reveal>

        <section className="pt-12 sm:pt-16 space-y-8 sm:space-y-10">
          <Reveal delay={d}>
            <div className="max-w-2xl space-y-4">
              <p className="text-[12px] uppercase tracking-[0.18em] text-muted-foreground/40">
                macOS · Apple silicon
              </p>
              <h1 className="font-serif text-[42px] sm:text-[68px] leading-[0.95] text-foreground">
                hun in your menu bar.
              </h1>
              <p className="max-w-xl text-[14px] sm:text-[15px] leading-relaxed text-muted-foreground/65">
                a native macOS app for switching projects, controlling services,
                and following logs — without opening another terminal pane.
              </p>
              <div className="flex flex-wrap items-center gap-3 pt-2">
                <a
                  href={downloadURL}
                  aria-label="Download Hun for Apple silicon"
                  className="relative inline-flex h-9 items-center gap-2 rounded-sm bg-foreground px-3 text-[12px] font-medium text-background transition-opacity before:absolute before:-inset-y-1 before:inset-x-0 before:content-[''] hover:opacity-85 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground"
                >
                  <svg
                    aria-hidden="true"
                    viewBox="0 0 814 1000"
                    className="h-4 w-[13px] shrink-0 fill-current"
                  >
                    <path d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76.5 0-103.7 40.8-165.9 40.8s-105.6-57-155.5-127C46.7 790.7 0 663 0 541.8c0-194.4 126.4-297.5 250.8-297.5 66.1 0 121.2 43.4 162.7 43.4 39.5 0 101.1-46 176.3-46 28.5 0 130.9 2.6 198.3 99.2zm-234-181.5c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9-110.8 33.7-147.1 75.8-28.5 32.4-55.1 83.6-55.1 135.5 0 7.8 1.3 15.6 1.9 18.1 3.2.6 8.4 1.3 13.6 1.3 45.4 0 102.5-30.4 135.5-71.3z" />
                  </svg>
                  Download
                </a>
                <span className="text-[11px] tabular-nums text-muted-foreground/40">
                  v{currentVersion} · Apple silicon
                </span>
              </div>
            </div>
          </Reveal>

          <Reveal delay={d * 2}>
            <figure className="overflow-hidden rounded-sm border border-border bg-muted/20">
              <Image
                src={macosImage}
                alt="Hun macOS app showing running services, Docker Compose services, and live logs"
                placeholder="blur"
                loading="lazy"
                sizes="(min-width: 1280px) 1152px, calc(100vw - 40px)"
                className="h-auto w-full"
              />
            </figure>
          </Reveal>
        </section>

        <section className="grid gap-10 border-t border-border mt-12 sm:mt-16 pt-10 sm:grid-cols-[0.85fr_1.15fr]">
          <Reveal delay={d * 3}>
            <div className="space-y-4">
              <h2 className="font-serif text-[30px] sm:text-[40px] leading-tight text-foreground">
                ready for the workday
              </h2>
              <p className="text-[14px] leading-relaxed text-muted-foreground/60">
                Developer ID signed, notarized by Apple, and shipped with secure
                in-app updates. Download the DMG, drag Hun to Applications, and
                future releases arrive inside the app.
              </p>
            </div>
          </Reveal>

          <Reveal delay={d * 4}>
            <div className="space-y-6">
              <p className="max-w-lg text-[12px] leading-relaxed text-muted-foreground/45">
                Hun checks for updates hourly. You stay in control of when an
                update installs and the app relaunches.
              </p>
              <div className="grid gap-4 sm:grid-cols-2">
                {details.map((detail) => (
                  <div
                    key={detail.title}
                    className="border-t border-border pt-4 space-y-2"
                  >
                    <h3 className="text-[13px] font-medium text-foreground/85">
                      {detail.title}
                    </h3>
                    <p className="text-[13px] leading-relaxed text-muted-foreground/55">
                      {detail.body}
                    </p>
                  </div>
                ))}
              </div>
            </div>
          </Reveal>
        </section>

        <Reveal delay={d * 5}>
          <footer className="border-t border-border mt-14 pt-6 pb-4 text-[12px] text-muted-foreground/40">
            <Link
              href="/legacy"
              className="underline underline-offset-2 hover:text-muted-foreground/60"
            >
              legacy CLI page
            </Link>{" "}
            &middot;{" "}
            <Link
              href="/changelog"
              className="underline underline-offset-2 hover:text-muted-foreground/60"
            >
              changelog
            </Link>{" "}
            &middot; app installs to{" "}
            <code className="text-muted-foreground/55">
              /Applications/hun.app
            </code>
          </footer>
        </Reveal>
      </main>
    </div>
  );
}
