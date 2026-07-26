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

const questions = [
  {
    question: "What exactly does Hun replace?",
    answer:
      "The repeated setup around local development: finding the project, starting its processes, resolving port conflicts, locating logs, and rebuilding terminal context. It does not replace your editor, Git host, Docker, or shell.",
  },
  {
    question: "Does my project need a particular framework?",
    answer:
      "No. Hun runs the commands you define in a small .hun.yml file and can detect common Node.js, Go, Python, Docker Compose, and monorepo structures.",
  },
  {
    question: "Is the CLI required?",
    answer:
      "No. The macOS app is the primary product and bundles the runtime it needs. The standalone CLI and TUI remain optional for automation, remote machines, and terminal-first workflows.",
  },
  {
    question: "What happens when the public beta ends?",
    answer:
      "The beta is free through 31 August 2026. After that, continued use will require the planned $15 lifetime license. The paid-license transition will ship before the beta deadline.",
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
              <h1 className="text-[40px] font-medium leading-[0.98] tracking-[-0.045em] text-foreground sm:text-[60px]">
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
                    className="inline-flex h-11 items-center gap-2 rounded-lg border border-border pl-4 pr-3.5 text-[12px] font-medium text-foreground/80 transition-[background-color,color,transform] duration-150 ease-out hover:bg-muted/30 hover:text-foreground active:scale-[0.96] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground"
                  >
                    Get a free beta key
                    <ArrowIcon />
                  </a>
                ) : (
                  <Link
                    href="/pricing"
                    className="inline-flex h-11 items-center gap-2 rounded-lg border border-border pl-4 pr-3.5 text-[12px] font-medium text-foreground/80 transition-[background-color,color,transform] duration-150 ease-out hover:bg-muted/30 hover:text-foreground active:scale-[0.96] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground"
                  >
                    View beta access
                    <ArrowIcon />
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
            <figure className="marketing-surface rounded-[24px] p-2">
              <div className="marketing-image overflow-hidden rounded-[16px] bg-black">
                <Image
                  src={macosImage}
                  alt="Hun showing projects, running services, Docker Compose infrastructure, and live logs in its native macOS workspace"
                  placeholder="blur"
                  priority
                  sizes="(min-width: 1280px) 1152px, calc(100vw - 40px)"
                  className="h-auto w-full"
                />
              </div>
            </figure>
          </Reveal>
        </section>

        <section className="mt-24 sm:mt-36">
          <Reveal>
            <div className="grid gap-5 sm:grid-cols-[1fr_0.85fr] sm:items-end">
              <div>
                <p className="text-[11px] uppercase tracking-[0.18em] text-foreground/35">
                  the whole project
                </p>
                <h2 className="mt-4 max-w-2xl text-[36px] font-medium leading-[1.02] tracking-[-0.04em] sm:text-[48px]">
                  one window. every moving part.
                </h2>
              </div>
              <p className="max-w-xl text-[13px] leading-6 text-foreground/48 sm:justify-self-end sm:text-[14px]">
                Projects, services, Git, logs, and terminals stay together—so
                switching context does not mean rebuilding it.
              </p>
            </div>
          </Reveal>

          <div className="mt-10 grid gap-3 lg:grid-cols-12">
            <Reveal className="h-full lg:col-span-5 lg:row-span-2">
              <BentoCard
                eyebrow="project switcher"
                title="the workspace remembers."
                body="Return to the exact project context you left."
                className="h-full min-h-[360px]"
              >
                <ProjectSidebar />
              </BentoCard>
            </Reveal>

            <Reveal delay={0.04} className="h-full lg:col-span-7">
              <BentoCard
                eyebrow="service control"
                title="your stack, as a system."
                body="Start, stop, and inspect local services together."
                className="h-full min-h-[260px]"
              >
                <ServiceControl />
              </BentoCard>
            </Reveal>

            <Reveal delay={0.08} className="h-full lg:col-span-7">
              <BentoCard
                eyebrow="focus and multitask"
                title="choose how projects coexist."
                body="Focus hands ports to the next project. Multitask keeps both alive."
                className="h-full min-h-[200px]"
              >
                <ModeControl />
              </BentoCard>
            </Reveal>

            <Reveal delay={0.12} className="h-full lg:col-span-7">
              <BentoCard
                eyebrow="git workspace"
                title="stay with the change."
                body="Review diffs, commit, and push without leaving the project."
                className="h-full min-h-[280px]"
              >
                <GitWorkspace />
              </BentoCard>
            </Reveal>

            <Reveal delay={0.16} className="h-full lg:col-span-5">
              <BentoCard
                eyebrow="project recipe"
                title="teach hun once."
                body="Define services, ports, and dependencies once in .hun.yml."
                className="h-full min-h-[280px]"
              >
                <ProjectRecipe />
              </BentoCard>
            </Reveal>
          </div>
        </section>

        <section className="mt-20 sm:mt-28">
          <Reveal>
            <div className="border-y border-border">
              <div className="grid md:grid-cols-[0.9fr_1.1fr]">
                <div className="py-9 md:border-r md:border-border md:pr-10">
                  <p className="text-[11px] uppercase tracking-[0.18em] text-foreground/35">
                    mac, through and through
                  </p>
                  <h2 className="mt-4 max-w-lg text-[34px] font-medium leading-[1.02] tracking-[-0.04em] sm:text-[46px]">
                    built for your machine.
                  </h2>
                  <p className="mt-5 max-w-md text-[13px] leading-6 text-foreground/48">
                    The macOS app is the product. The optional CLI is there when
                    automation or a remote machine calls for it.
                  </p>
                </div>
                <dl className="grid border-t border-border sm:grid-cols-2 md:border-t-0">
                  {[
                    ["native", "SwiftUI", "not a web wrapper"],
                    ["local", "by default", "your project stays on your Mac"],
                    ["runtime", "bundled", "app and daemon stay compatible"],
                    ["updates", "verified", "signed, notarized, and in-app"],
                  ].map(([label, value, detail], index) => (
                    <div
                      key={label}
                      className={`p-5 sm:p-6 ${
                        index % 2 === 1 ? "sm:border-l sm:border-border" : ""
                      } ${index > 1 ? "border-t border-border" : ""}`}
                    >
                      <dt className="text-[9px] uppercase tracking-[0.16em] text-foreground/30">
                        {label}
                      </dt>
                      <dd className="mt-3 text-[19px] font-medium tracking-[-0.025em] text-foreground/90">
                        {value}
                      </dd>
                      <dd className="mt-2 text-[11px] leading-5 text-foreground/40">
                        {detail}
                      </dd>
                    </div>
                  ))}
                </dl>
              </div>
            </div>
          </Reveal>
        </section>

        <section className="mt-28 sm:mt-40">
          <Reveal>
            <div className="marketing-surface rounded-[24px] p-2">
              <div className="overflow-hidden rounded-[16px] bg-black/25 p-6 sm:p-10">
                <div className="grid gap-10 lg:grid-cols-[1fr_auto] lg:items-end">
                  <div>
                    <div className="inline-flex items-center gap-2 rounded-full bg-emerald-400/[0.07] px-3 py-1.5 text-[10px] font-medium text-emerald-300/70 shadow-[0_0_0_1px_oklch(0.8_0.14_155/0.13)]">
                      <span className="size-1.5 rounded-full bg-emerald-300" />
                      Public beta
                    </div>
                    <h2 className="mt-5 max-w-3xl text-[36px] font-medium leading-[1.02] tracking-[-0.04em] sm:text-[48px]">
                      free while we build it with you.
                    </h2>
                    <p className="mt-5 max-w-2xl text-[13px] leading-6 text-foreground/48">
                      Use every feature through 31 August 2026. After beta, the
                      planned price is $15 once for a lifetime license on two
                      Macs—no subscription and no feature ladder.
                    </p>
                  </div>
                  <div className="flex flex-wrap gap-3 lg:justify-end">
                    <Link
                      href="/pricing"
                      className="inline-flex h-11 items-center gap-2 rounded-lg bg-foreground pl-4 pr-3.5 text-[12px] font-medium text-background transition-[opacity,transform] duration-150 ease-out hover:opacity-[0.88] active:scale-[0.96] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground"
                    >
                      See pricing
                      <ArrowIcon />
                    </Link>
                    {hunBetaCheckoutURL ? (
                      <a
                        href={hunBetaCheckoutURL}
                        className="inline-flex h-11 items-center gap-2 rounded-lg border border-border px-4 text-[12px] font-medium text-foreground/70 transition-[background-color,color,transform] duration-150 ease-out hover:bg-white/[0.04] hover:text-foreground active:scale-[0.96] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground"
                      >
                        Get a beta key
                        <ArrowIcon />
                      </a>
                    ) : null}
                  </div>
                </div>
              </div>
            </div>
          </Reveal>
        </section>

        <section className="mt-28 grid gap-10 sm:mt-40 lg:grid-cols-[0.7fr_1.3fr]">
          <Reveal>
            <div>
              <p className="text-[11px] uppercase tracking-[0.18em] text-foreground/35">
                questions
              </p>
              <h2 className="mt-4 text-[32px] font-medium leading-[1.04] tracking-[-0.035em] sm:text-[40px]">
                before you install.
              </h2>
            </div>
          </Reveal>
          <div className="divide-y divide-border border-y border-border">
            {questions.map((item, index) => (
              <Reveal
                key={item.question}
                delay={Math.min(index * 0.04, 0.12)}
              >
                <details className="marketing-faq group">
                  <summary className="flex min-h-16 cursor-pointer items-center justify-between gap-6 py-4 text-left focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-foreground">
                    <span className="text-[12px] font-medium text-foreground/72 sm:text-[13px]">
                      {item.question}
                    </span>
                    <span className="marketing-faq-icon flex size-8 shrink-0 items-center justify-center rounded-full border border-border text-[18px] font-light text-foreground/45 transition-transform duration-150 ease-out">
                      +
                    </span>
                  </summary>
                  <p className="max-w-3xl pb-6 pr-12 text-[12px] leading-6 text-foreground/48 sm:text-[13px]">
                    {item.answer}
                  </p>
                </details>
              </Reveal>
            ))}
          </div>
        </section>

        <MarketingFooter />
      </main>
    </div>
  );
}

function BentoCard({
  eyebrow,
  title,
  body,
  className = "",
  children,
}: {
  eyebrow: string;
  title: string;
  body: string;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <article
      className={`marketing-surface-interactive group rounded-[24px] p-2 ${className}`}
    >
      <div className="flex h-full flex-col overflow-hidden rounded-[16px] bg-black/25 p-5">
        <div>
          <p className="text-[9px] uppercase tracking-[0.18em] text-foreground/30">
            {eyebrow}
          </p>
          <h3 className="mt-2.5 text-[22px] font-medium leading-[1.08] tracking-[-0.03em] text-foreground/92 sm:text-[24px]">
            {title}
          </h3>
          <p className="mt-2.5 max-w-xl text-[12px] leading-5 text-foreground/46 sm:text-[13px]">
            {body}
          </p>
        </div>
        {children}
      </div>
    </article>
  );
}

function ProjectSidebar() {
  const projects = [
    {
      name: "voice-ai",
      branch: "main",
      detail: "4 services",
      state: "running",
    },
    {
      name: "storefront",
      branch: "checkout",
      detail: "6 services",
      state: "idle",
    },
    {
      name: "docs",
      branch: "content",
      detail: "2 services",
      state: "idle",
    },
  ];

  return (
    <div className="mt-4 flex flex-1 flex-col overflow-hidden rounded-[14px] bg-white/[0.025] p-2 shadow-[inset_0_0_0_1px_oklch(1_0_0/0.07)]">
      <div className="flex items-center justify-between px-2 py-2">
        <span className="text-[10px] font-medium text-foreground/42">
          Recent projects
        </span>
        <span className="inline-flex h-7 items-center rounded-lg bg-white/[0.04] px-2 text-[9px] text-foreground/32 shadow-[inset_0_0_0_1px_oklch(1_0_0/0.06)]">
          ⌘ K
        </span>
      </div>
      <div className="space-y-1">
        {projects.map((project, index) => (
          <div
            key={project.name}
            className={`flex items-center gap-3 rounded-[11px] px-3 py-2.5 ${
              index === 0
                ? "bg-white/[0.07] shadow-[inset_0_0_0_1px_oklch(1_0_0/0.07)]"
                : "text-foreground/46"
            }`}
          >
            <span
              className={`flex size-8 shrink-0 items-center justify-center rounded-[9px] text-[11px] font-medium ${
                index === 0
                  ? "bg-white/[0.09] text-foreground/80"
                  : "bg-white/[0.035] text-foreground/38"
              }`}
            >
              {project.name.slice(0, 1).toUpperCase()}
            </span>
            <span className="min-w-0 flex-1">
              <span
                className={`block truncate text-[11px] ${
                  index === 0 ? "text-foreground/85" : ""
                }`}
              >
                {project.name}
              </span>
              <span className="mt-1 block truncate text-[9px] text-foreground/28">
                {project.branch}
              </span>
            </span>
            <span className="text-right">
              <span className="block text-[9px] text-foreground/38">
                {project.detail}
              </span>
              <span
                className={`mt-1.5 ml-auto block size-1.5 rounded-full ${
                  project.state === "running"
                    ? "bg-emerald-300"
                    : "bg-foreground/14"
                }`}
              />
            </span>
          </div>
        ))}
      </div>

      <div className="mt-2 rounded-[12px] bg-black/20 p-3 shadow-[inset_0_0_0_1px_oklch(1_0_0/0.05)]">
        <div className="flex items-center justify-between">
          <p className="text-[9px] uppercase tracking-[0.14em] text-foreground/26">
            running in voice-ai
          </p>
          <span className="text-[8px] text-emerald-300/48">4 healthy</span>
        </div>
        <div className="mt-3 grid grid-cols-3 gap-2">
          {[
            ["web", ":3000"],
            ["api", ":8080"],
            ["postgres", ":5432"],
          ].map(([name, port]) => (
            <div key={name} className="min-w-0">
              <span className="flex items-center gap-1.5">
                <span className="size-1.5 rounded-full bg-emerald-300" />
                <span className="truncate text-[8px] text-foreground/45">
                  {name}
                </span>
              </span>
              <span className="mt-1 block text-[8px] tabular-nums text-foreground/24">
                {port}
              </span>
            </div>
          ))}
        </div>
      </div>

      <div className="mt-auto p-1 pt-2">
        <div className="flex items-center justify-between rounded-[11px] bg-black/25 px-3.5 py-3 shadow-[inset_0_0_0_1px_oklch(1_0_0/0.055)]">
          <span>
            <span className="block text-[9px] text-foreground/55">
              Saved context
            </span>
            <span className="mt-1 block text-[8px] text-foreground/25">
              4 services · 2 terminals · main
            </span>
          </span>
          <span className="flex size-7 items-center justify-center rounded-full bg-white/[0.055] text-[13px] text-foreground/42">
            ↗
          </span>
        </div>
      </div>
    </div>
  );
}

function ServiceControl() {
  const services = [
    {
      name: "web",
      command: "pnpm dev",
      port: ":3000",
      state: "running",
    },
    {
      name: "api",
      command: "go run ./cmd/api",
      port: ":8080",
      state: "running",
    },
  ];

  return (
    <div className="mt-3 flex flex-1 flex-col overflow-hidden rounded-[14px] bg-white/[0.025] p-2 shadow-[inset_0_0_0_1px_oklch(1_0_0/0.07)]">
      <div className="flex items-center justify-between px-1 pb-1.5">
        <span className="text-[9px] text-foreground/42">
          voice-ai · main
        </span>
        <span className="text-[8px] text-foreground/30">
          Restart · Stop
        </span>
      </div>
      <div className="grid flex-1 grid-rows-2 gap-1">
        {services.map((service) => (
          <div
            key={service.name}
            className="grid grid-cols-[1fr_auto] items-center gap-4 rounded-[10px] bg-black/20 px-3 py-2 shadow-[inset_0_0_0_1px_oklch(1_0_0/0.045)]"
          >
            <div className="flex min-w-0 items-center gap-3">
              <span className="size-1.5 shrink-0 rounded-full bg-emerald-300" />
              <span className="min-w-0">
                <span className="block truncate text-[10px] text-foreground/70">
                  {service.name}
                </span>
                <span className="mt-1 block truncate text-[8px] text-foreground/27">
                  {service.command}
                </span>
              </span>
            </div>
            <div className="flex items-center gap-3">
              <span className="text-[9px] tabular-nums text-foreground/32">
                {service.port}
              </span>
              <span className="rounded-full bg-emerald-400/[0.07] px-2 py-1 text-[8px] text-emerald-200/55">
                {service.state}
              </span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function ModeControl() {
  return (
    <div className="mt-3 flex flex-1 flex-col overflow-hidden rounded-[14px] bg-white/[0.025] p-2 shadow-[inset_0_0_0_1px_oklch(1_0_0/0.07)]">
      <div className="grid flex-1 gap-2 sm:grid-cols-[1fr_auto_1fr] sm:items-center">
        <ProjectHandoff
          name="voice-ai"
          branch="main"
          port="releasing :3000"
          active={false}
        />
        <div className="flex items-center justify-center gap-1.5 text-[8px] text-foreground/24">
          <span>→</span>
          <span className="tabular-nums">312ms</span>
        </div>
        <ProjectHandoff
          name="storefront"
          branch="checkout"
          port="owns :3000"
          active
        />
      </div>

    </div>
  );
}

function ProjectHandoff({
  name,
  branch,
  port,
  active,
}: {
  name: string;
  branch: string;
  port: string;
  active: boolean;
}) {
  return (
    <div
      className={`flex min-h-14 items-center justify-between gap-3 rounded-[10px] p-2.5 shadow-[inset_0_0_0_1px_oklch(1_0_0/0.055)] ${
        active ? "bg-white/[0.06]" : "bg-black/20"
      }`}
    >
      <div className="flex min-w-0 items-center gap-3">
        <span
          className={`flex size-6 shrink-0 items-center justify-center rounded-[7px] text-[9px] ${
            active
              ? "bg-white/[0.08] text-foreground/68"
              : "bg-white/[0.035] text-foreground/35"
          }`}
        >
          {name.slice(0, 1).toUpperCase()}
        </span>
        <span className="min-w-0">
          <span className="block truncate text-[10px] text-foreground/65">
            {name}
          </span>
          <span className="mt-1 block text-[8px] text-foreground/25">
            {branch}
          </span>
        </span>
      </div>
      <div className="text-right">
        <span
          className={`block text-[8px] ${
            active ? "text-emerald-300/50" : "text-foreground/25"
          }`}
        >
          {port}
        </span>
        <span
          className={`mt-1.5 ml-auto block size-1.5 rounded-full ${
            active ? "bg-emerald-300" : "bg-foreground/14"
          }`}
        />
      </div>
    </div>
  );
}

function GitWorkspace() {
  return (
    <div className="mt-auto overflow-hidden rounded-[14px] bg-white/[0.025] p-2 shadow-[inset_0_0_0_1px_oklch(1_0_0/0.07)]">
      <div className="grid gap-2 sm:grid-cols-[0.7fr_1.3fr]">
        <div className="rounded-[11px] bg-black/25 p-3 shadow-[inset_0_0_0_1px_oklch(1_0_0/0.045)]">
          <div className="flex items-center justify-between">
            <span className="text-[9px] uppercase tracking-[0.14em] text-foreground/28">
              changes
            </span>
            <span className="text-[9px] text-foreground/28">2 files</span>
          </div>
          <div className="mt-3 space-y-1">
            <div className="rounded-[8px] bg-white/[0.06] px-3 py-2 text-[10px] text-foreground/68">
              DashboardModel.swift
            </div>
            <div className="rounded-[8px] px-3 py-2 text-[10px] text-foreground/36">
              ProjectWorkspace.swift
            </div>
          </div>
        </div>
        <div className="rounded-[11px] bg-black/25 p-3 text-[9px] leading-5 shadow-[inset_0_0_0_1px_oklch(1_0_0/0.045)]">
          <div className="mb-2 flex items-center justify-between pb-1 text-foreground/28">
            <span>DashboardModel.swift</span>
            <span className="rounded-full bg-white/[0.04] px-2 py-0.5">
              main
            </span>
          </div>
          <div className="space-y-1">
            <p className="rounded-[6px] bg-rose-400/[0.055] px-2 text-rose-200/40">
              − selectedProject = nil
            </p>
            <p className="rounded-[6px] bg-emerald-400/[0.065] px-2 text-emerald-200/55">
              + restoreWorkspace(for: project)
            </p>
            <p className="rounded-[6px] bg-emerald-400/[0.065] px-2 text-emerald-200/55">
              + selectedProject = project
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}

function ProjectRecipe() {
  return (
    <div className="mt-auto overflow-hidden rounded-[14px] bg-white/[0.025] p-2 shadow-[inset_0_0_0_1px_oklch(1_0_0/0.07)]">
      <div className="flex items-center justify-between rounded-[10px] bg-black/20 px-3 py-2.5 text-[9px] text-foreground/28">
        <span>.hun.yml</span>
        <span className="rounded-full bg-white/[0.04] px-2 py-0.5">
          voice-ai
        </span>
      </div>
      <dl className="mt-2 space-y-1 text-[9px] leading-5">
        {[
          ["services", "web · api · worker · postgres"],
          ["ports", "3000 · 8080 · 5432"],
          ["compose", "docker-compose.yml"],
        ].map(([label, value]) => (
          <div
            key={label}
            className="grid grid-cols-[64px_1fr] items-center rounded-[9px] px-3 py-1.5"
          >
            <dt className="text-foreground/28">{label}</dt>
            <dd className="text-foreground/55">{value}</dd>
          </div>
        ))}
      </dl>
      <div className="mt-1 flex items-center gap-2 rounded-[10px] bg-emerald-400/[0.045] px-3 py-2.5 text-[9px] text-emerald-300/48">
        <span className="size-1.5 rounded-full bg-emerald-300" />
        Project ready
      </div>
    </div>
  );
}

function ArrowIcon() {
  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 16 16"
      fill="none"
      className="mx-auto size-3.5 shrink-0 text-current opacity-55"
    >
      <path
        d="M3.5 8h9m-3.25-3.25L12.5 8l-3.25 3.25"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function DownloadButton() {
  return (
    <a
      href={downloadURL}
      aria-label="Download Hun for Apple silicon"
      className="inline-flex h-11 items-center gap-2 rounded-lg bg-foreground px-4 text-[12px] font-medium text-background transition-[opacity,transform] duration-150 ease-out hover:opacity-85 active:scale-[0.96] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground"
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
