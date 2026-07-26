import {
  MarketingFooter,
  MarketingNav,
} from "@/components/marketing-shell";
import { Reveal } from "@/components/reveal";
import releases from "@/content/changelog.json";
import { hunBetaCheckoutURL } from "@/lib/dodo";
import macosImage from "@/public/macos-image.png";
import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";

const downloadURL =
  "https://github.com/sourabhrathourr/hun/releases/latest/download/hun-macos-arm64.dmg";
const currentVersion = releases[0].version;

export const metadata: Metadata = {
  title: "Hun — a native macOS workspace for local development",
  description:
    "Switch projects, run services, inspect Git changes, use project terminals, and follow logs from one native macOS workspace.",
  alternates: { canonical: "/" },
  openGraph: {
    title: "Hun — one place for the code already running around you",
    description:
      "A native macOS workspace for projects, services, Git, terminals, and logs.",
    url: "https://hun.sh",
    images: [{ url: "/api/og/macos", width: 1200, height: 630 }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Hun — one place for the code already running around you",
    description:
      "A native macOS workspace for projects, services, Git, terminals, and logs.",
    images: ["/api/og/macos"],
  },
};

const workflows = [
  {
    index: "01",
    title: "Move between projects without reconstructing them.",
    body: "Hun remembers the services, ports, project state, and working context that belong together. Focus mode hands the machine to one project; Multitask mode keeps several stacks alive safely.",
    detail: "Focus · Multitask · automatic port offsets",
  },
  {
    index: "02",
    title: "Operate the whole local stack from one surface.",
    body: "Start, stop, and restart individual services or an entire project. Local commands, Docker Compose infrastructure, workers, databases, and queues remain visible as one system.",
    detail: "Node · Go · Python · Docker Compose",
  },
  {
    index: "03",
    title: "See what the project is doing while you change it.",
    body: "Follow combined or per-service logs, open persistent project terminals, review staged and working-tree diffs, switch branches safely, and commit without leaving the workspace.",
    detail: "Live logs · terminal · Git workspace",
  },
];

const operatingFacts = [
  ["Native macOS app", "Built with SwiftUI for macOS 15 and Apple silicon."],
  [
    "Bundled runtime",
    "The app and its Go runtime ship together and speak a versioned protocol.",
  ],
  [
    "Local by default",
    "Project files, processes, Git operations, terminals, and logs stay on your Mac.",
  ],
  [
    "Safe distribution",
    "Developer ID signed, notarized by Apple, and updated securely through Sparkle.",
  ],
];

const questions = [
  {
    question: "What exactly does Hun replace?",
    answer:
      "It replaces the repeated setup around local development: finding the right project, starting its processes, resolving port conflicts, locating logs, and rebuilding terminal context. It does not replace your editor, Git host, Docker, or shell.",
  },
  {
    question: "Does my project need to use a particular framework?",
    answer:
      "No. Hun runs commands you define in a small .hun.yml file and can detect common Node.js, Go, Python, Docker Compose, and monorepo structures.",
  },
  {
    question: "Is the CLI required?",
    answer:
      "No. The macOS app is the primary product and bundles the runtime it needs. The standalone CLI and TUI remain optional for automation, remote machines, and terminal-first workflows.",
  },
  {
    question: "What happens when the public beta ends?",
    answer:
      "The beta is free through 31 August 2026. After that, continued use will require the planned $15 lifetime license. We will ship the paid-license transition before the beta deadline.",
  },
];

export default function HomePage() {
  return (
    <div className="min-h-dvh bg-background px-5 py-8 text-foreground sm:px-6 sm:py-12">
      <main className="mx-auto w-full max-w-6xl">
        <Reveal>
          <MarketingNav />
        </Reveal>

        <section className="space-y-8 pt-14 sm:space-y-10 sm:pt-20">
          <Reveal delay={0.06}>
            <div className="max-w-2xl space-y-4">
              <p className="text-[12px] uppercase tracking-[0.18em] text-muted-foreground/40">
                macOS · Apple silicon
              </p>
              <h1 className="font-serif text-[42px] leading-[0.95] text-foreground sm:text-[68px]">
                hun in your menu bar.
              </h1>
              <p className="max-w-xl text-[14px] leading-relaxed text-muted-foreground/65 sm:text-[15px]">
                a native macOS app for switching projects, controlling services,
                and following logs — without opening another terminal pane.
              </p>
              <div className="flex flex-wrap items-center gap-3 pt-2">
                <DownloadButton />
                {hunBetaCheckoutURL ? (
                  <a
                    href={hunBetaCheckoutURL}
                    className="inline-flex h-11 items-center rounded-sm border border-border px-4 text-[12px] font-medium text-foreground/80 transition-colors hover:bg-muted/30 hover:text-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground"
                  >
                    Get a free beta key
                  </a>
                ) : (
                  <Link
                    href="/pricing"
                    className="inline-flex h-11 items-center rounded-sm border border-border px-4 text-[12px] font-medium text-foreground/80 transition-colors hover:bg-muted/30 hover:text-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground"
                  >
                    View beta access
                  </Link>
                )}
                <span className="text-[11px] tabular-nums text-muted-foreground/45">
                  v{currentVersion} · Apple silicon
                </span>
              </div>
            </div>
          </Reveal>

          <Reveal delay={0.12}>
            <div
              id="beta"
              className="grid gap-4 border-y border-border py-4 text-[12px] sm:grid-cols-[1fr_auto] sm:items-center"
            >
              <p className="max-w-3xl leading-relaxed text-muted-foreground/65">
                <span className="font-medium text-foreground/85">
                  The full app is free during the public beta.
                </span>{" "}
                A beta license key is required, works on two Macs, and expires
                for everyone on 31 August 2026.
              </p>
              <Link
                href="/pricing"
                className="inline-flex min-h-11 items-center text-foreground/75 underline underline-offset-4 transition-colors hover:text-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground"
              >
                How beta pricing works
              </Link>
            </div>
          </Reveal>

          <Reveal delay={0.16}>
            <figure className="overflow-hidden rounded-sm border border-border bg-muted/20">
              <Image
                src={macosImage}
                alt="Hun showing projects, running services, Docker Compose infrastructure, and live logs in its native macOS workspace"
                placeholder="blur"
                priority
                sizes="(min-width: 1280px) 1152px, calc(100vw - 40px)"
                className="h-auto w-full"
              />
            </figure>
          </Reveal>
        </section>

        <section className="mt-20 grid gap-10 border-t border-border pt-12 sm:mt-28 sm:grid-cols-[0.8fr_1.2fr] sm:pt-16">
          <Reveal>
            <div className="sm:sticky sm:top-12 sm:self-start">
              <p className="text-[10px] uppercase tracking-[0.18em] text-muted-foreground/40">
                The problem
              </p>
              <h2 className="mt-4 max-w-md font-serif text-[38px] leading-[1.02] sm:text-[52px]">
                Context switching is infrastructure work in disguise.
              </h2>
            </div>
          </Reveal>
          <Reveal delay={0.06}>
            <div className="space-y-8 text-[14px] leading-7 text-muted-foreground/65 sm:text-[15px]">
              <p>
                A modern project is rarely one process. It is a frontend, API,
                worker, database, queue, terminal history, ports, environment,
                and a Git branch that all make sense together.
              </p>
              <p>
                Moving to another project means stopping some of that system,
                preserving the right parts, starting another stack, resolving
                collisions, and finding the logs that explain why something did
                not start. The interruption is small each time and expensive
                across a day.
              </p>
              <div className="grid gap-4 border-t border-border pt-6 sm:grid-cols-3">
                {["fewer orphan processes", "one view of the stack", "less terminal archaeology"].map(
                  (outcome) => (
                    <p
                      key={outcome}
                      className="text-[12px] leading-relaxed text-foreground/70"
                    >
                      {outcome}
                    </p>
                  ),
                )}
              </div>
            </div>
          </Reveal>
        </section>

        <section className="mt-20 border-t border-border pt-12 sm:mt-28 sm:pt-16">
          <Reveal>
            <div className="max-w-2xl">
              <p className="text-[10px] uppercase tracking-[0.18em] text-muted-foreground/40">
                The working loop
              </p>
              <h2 className="mt-4 font-serif text-[38px] leading-[1.02] sm:text-[52px]">
                One place for the code already running around you.
              </h2>
            </div>
          </Reveal>
          <div className="mt-10 divide-y divide-border border-y border-border">
            {workflows.map((workflow, index) => (
              <Reveal key={workflow.index} delay={Math.min(index * 0.05, 0.12)}>
                <article className="grid gap-5 py-8 sm:grid-cols-[4rem_1fr_15rem] sm:gap-8 sm:py-10">
                  <span className="text-[11px] tabular-nums text-muted-foreground/35">
                    {workflow.index}
                  </span>
                  <div>
                    <h3 className="max-w-2xl text-[17px] font-medium leading-7 text-foreground/90 sm:text-[19px]">
                      {workflow.title}
                    </h3>
                    <p className="mt-3 max-w-2xl text-[13px] leading-6 text-muted-foreground/60 sm:text-[14px]">
                      {workflow.body}
                    </p>
                  </div>
                  <p className="text-[11px] leading-5 text-muted-foreground/40 sm:text-right">
                    {workflow.detail}
                  </p>
                </article>
              </Reveal>
            ))}
          </div>
        </section>

        <section className="mt-20 grid gap-10 border-t border-border pt-12 sm:mt-28 sm:grid-cols-[0.9fr_1.1fr] sm:pt-16">
          <Reveal>
            <div>
              <p className="text-[10px] uppercase tracking-[0.18em] text-muted-foreground/40">
                How it works
              </p>
              <h2 className="mt-4 max-w-md font-serif text-[38px] leading-[1.02] sm:text-[52px]">
                Native where you work. Local where your code lives.
              </h2>
              <div
                className="mt-8 overflow-x-auto border-y border-border py-5 text-[11px] text-muted-foreground/55"
                aria-label="Hun architecture"
              >
                <code className="whitespace-nowrap">
                  macOS app → bundled runtime → local daemon → your services
                </code>
              </div>
            </div>
          </Reveal>
          <Reveal delay={0.06}>
            <div className="grid gap-x-8 gap-y-7 sm:grid-cols-2">
              {operatingFacts.map(([title, body]) => (
                <article key={title} className="border-t border-border pt-4">
                  <h3 className="text-[13px] font-medium text-foreground/85">
                    {title}
                  </h3>
                  <p className="mt-2 text-[12px] leading-6 text-muted-foreground/55">
                    {body}
                  </p>
                </article>
              ))}
            </div>
          </Reveal>
        </section>

        <section className="mt-20 border-y border-border py-12 sm:mt-28 sm:py-16">
          <Reveal>
            <div className="grid gap-10 sm:grid-cols-[1.15fr_0.85fr] sm:items-end">
              <div>
                <p className="text-[10px] uppercase tracking-[0.18em] text-muted-foreground/40">
                  Straightforward pricing
                </p>
                <h2 className="mt-4 max-w-xl font-serif text-[42px] leading-[0.98] sm:text-[60px]">
                  Free while we learn. $15 once when beta ends.
                </h2>
                <p className="mt-5 max-w-xl text-[13px] leading-6 text-muted-foreground/60 sm:text-[14px]">
                  No feature-limited trial and no subscription ladder. Beta
                  testers use the complete product for free through 31 August
                  2026. The planned paid release is one lifetime license for two
                  Macs.
                </p>
              </div>
              <div className="flex flex-wrap gap-3 sm:justify-end">
                <Link
                  href="/pricing"
                  className="inline-flex h-11 items-center rounded-sm bg-foreground px-4 text-[12px] font-medium text-background transition-opacity hover:opacity-85 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground"
                >
                  See pricing
                </Link>
                {hunBetaCheckoutURL ? (
                  <a
                    href={hunBetaCheckoutURL}
                    className="inline-flex h-11 items-center rounded-sm border border-border px-4 text-[12px] text-foreground/80 transition-colors hover:bg-muted/30 hover:text-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground"
                  >
                    Join the beta
                  </a>
                ) : null}
              </div>
            </div>
          </Reveal>
        </section>

        <section className="mt-20 grid gap-10 sm:mt-28 sm:grid-cols-[0.7fr_1.3fr]">
          <Reveal>
            <div>
              <p className="text-[10px] uppercase tracking-[0.18em] text-muted-foreground/40">
                Questions
              </p>
              <h2 className="mt-4 font-serif text-[38px] leading-none sm:text-[48px]">
                Before you install.
              </h2>
            </div>
          </Reveal>
          <div className="divide-y divide-border border-y border-border">
            {questions.map((item, index) => (
              <Reveal key={item.question} delay={Math.min(index * 0.04, 0.12)}>
                <article className="py-6">
                  <h3 className="text-[14px] font-medium leading-6 text-foreground/85">
                    {item.question}
                  </h3>
                  <p className="mt-2 max-w-3xl text-[12px] leading-6 text-muted-foreground/60 sm:text-[13px]">
                    {item.answer}
                  </p>
                </article>
              </Reveal>
            ))}
          </div>
        </section>

        <MarketingFooter />
      </main>
    </div>
  );
}

function DownloadButton() {
  return (
    <a
      href={downloadURL}
      aria-label="Download Hun for Apple silicon"
      className="inline-flex h-11 items-center gap-2 rounded-sm bg-foreground px-4 text-[12px] font-medium text-background transition-opacity hover:opacity-85 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground"
    >
      <svg
        aria-hidden="true"
        viewBox="0 0 814 1000"
        className="h-4 w-[13px] shrink-0 fill-current"
      >
        <path d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76.5 0-103.7 40.8-165.9 40.8s-105.6-57-155.5-127C46.7 790.7 0 663 0 541.8c0-194.4 126.4-297.5 250.8-297.5 66.1 0 121.2 43.4 162.7 43.4 39.5 0 101.1-46 176.3-46 28.5 0 130.9 2.6 198.3 99.2zm-234-181.5c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9-110.8 33.7-147.1 75.8-28.5 32.4-55.1 83.6-55.1 135.5 0 7.8 1.3 15.6 1.9 18.1 3.2.6 8.4 1.3 13.6 1.3 45.4 0 102.5-30.4 135.5-71.3z" />
      </svg>
      Download for macOS
    </a>
  );
}
