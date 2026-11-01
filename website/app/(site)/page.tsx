import type { ReactNode } from "react";
import { Container, SitePage } from "@/components/site/chrome";
import { DOWNLOAD_URL } from "@/components/site/links";
import { ProfilesSection } from "@/components/site/profiles";
import { StartupTimeline } from "@/components/site/scenes/StartupTimeline";
import { HunWindowHero } from "@/components/site/hun-window/HunWindowHero";
import { MenuBarScene } from "@/components/site/menu-bar/MenuBarScene";
import { HowItWorksSection } from "@/components/site/how/HowItWorks";

// Direction F: D's message in E's warm type and colour, rebuilt from scratch.
// One idea per section, no side notes, and the product shown as itself:
// the window and menu are rendered by the app's own SwiftUI code.

const css = `
.hf {
  --paper: #F5F0E6;
  --raised: #FFFCF6;
  --ink: #1F1B16;
  --ink-2: #4F483F;
  --ink-3: #6E675C;
  --line: rgba(31, 27, 22, .1);
  --accent: #C24A1F;
  --run: #3E7B4F;
  --tray: #EAE2D2;
  --bg-menu: url(/site/bg/hero-f.jpg);
  --bg-docker: url(/site/bg/scene-docker.jpg);
  --bg-wide: url(/site/bg/hero-e.jpg);
  --code-bg: rgba(31, 27, 22, .06);
  --shot-bg: #F4F4EF;
  --band-2: rgba(245, 240, 230, .72);
  --band-3: rgba(245, 240, 230, .55);
  --band-4: rgba(245, 240, 230, .5);
  --band-code: rgba(245, 240, 230, .1);
  background: var(--paper);
  color: var(--ink);
  font-family: var(--f-text), ui-sans-serif, system-ui, sans-serif;
  -webkit-font-smoothing: antialiased;
}
.hf-shot, .hf-panel { position: relative; z-index: 2; }
.hf-hero-tray { background-image: url(/site/bg/hero-a.jpg); }
/* Multiply can only darken, so the dark bands carry their own grain that lightens. */
.hf-band { position: relative; }
.hf-band::before { content: ""; position: absolute; inset: 0; pointer-events: none; background-image: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='240' height='240'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='.8' numOctaves='4' stitchTiles='stitch'/><feColorMatrix type='saturate' values='0'/></filter><rect width='100%25' height='100%25' filter='url(%23n)'/></svg>"); background-size: 240px 240px; opacity: .14; mix-blend-mode: screen; filter: contrast(60%); }
.hf-band > * { position: relative; }
.hf ::selection { background: rgba(194, 74, 31, .18); }
.hf-display { font-family: var(--f-display), ui-sans-serif, system-ui, sans-serif; font-variation-settings: "opsz" 96; }
.hf-mono { font-family: var(--f-mono), ui-monospace, monospace; font-variant-ligatures: none; }
.hf-btn { transition: transform 160ms cubic-bezier(.23, 1, .32, 1), background-color 160ms ease; }
.hf-btn:active { transform: scale(.97); }
.hf-link { text-decoration-line: underline; text-decoration-color: transparent; text-underline-offset: 4px; transition: text-decoration-color 160ms ease, color 160ms ease; }
@media (hover: hover) { .hf-link:hover { text-decoration-color: currentColor; color: var(--ink); } }
.hf-shot { box-shadow: 0 0 0 .5px rgba(31, 27, 22, .22), 0 1px 2px rgba(31, 27, 22, .06), 0 40px 80px -36px rgba(64, 44, 16, .38); }
.hf-panel { box-shadow: 0 0 0 .5px rgba(31, 27, 22, .24), 0 2px 4px rgba(31, 27, 22, .06), 0 28px 56px -22px rgba(64, 44, 16, .42); }
`;


export default function VariantF() {
  return (
    <SitePage current="Home" className="hf">
      <style>{css}</style>
      <main>
        <Hero />
        <Agents />
        <MenuSection />
        <DockerSection />
        <ProfilesSection />
        <HowItWorks />
        <JustYou />
        <Price />
      </main>
    </SitePage>
  );
}


function Code({ children }: { children: ReactNode }) {
  return <code className="hf-mono rounded-[5px] bg-[var(--code-bg)] px-[5px] py-[1px] text-[.86em]">{children}</code>;
}

function BuyButton({ label = "Buy Hun · $9", tone = "ink" }: { label?: string; tone?: "ink" | "paper" }) {
  return (
    <a
      href="/pricing"
      className={`hf-btn inline-flex h-11 items-center rounded-full px-5 text-[15px] font-medium ${
        tone === "ink" ? "bg-[var(--ink)] text-[var(--paper)] hover:opacity-90" : "bg-[var(--paper)] text-[var(--ink)] hover:opacity-90"
      }`}
    >
      {label}
    </a>
  );
}

function AppleLogo() {
  return (
    <svg width="14" height="17" viewBox="0 0 814 1000" aria-hidden className="-mt-[2px] shrink-0">
      <path
        fill="currentColor"
        d="M788 340c-6 4-108 62-108 190 0 148 130 200 134 202-1 3-21 72-69 142-43 62-88 124-156 124s-86-40-164-40c-77 0-104 41-167 41s-106-58-156-128C44 788 0 668 0 554 0 371 119 274 236 274c62 0 114 41 153 41 37 0 95-43 166-43 27 0 124 2 188 93zM554 159c29-35 50-83 50-131 0-7-1-14-2-19-48 2-104 32-138 72-27 30-52 78-52 127 0 7 1 15 2 17 3 1 8 1 12 1 43 0 97-29 128-67z"
      />
    </svg>
  );
}

/** The secondary action on the dark band: an outlined pill with a download glyph. */
function DownloadButton({ tone = "ink" }: { tone?: "ink" | "paper" }) {
  const ink = tone === "ink";
  return (
    <a
      href={DOWNLOAD_URL}
      className={`hf-btn inline-flex h-11 items-center gap-2 rounded-full px-5 text-[15px] font-medium ${
        ink
          ? "bg-[rgba(31,27,22,.07)] text-[var(--ink)] hover:bg-[rgba(31,27,22,.11)]"
          : "text-[var(--paper)] shadow-[inset_0_0_0_1px_rgba(245,240,230,.3)] hover:bg-[rgba(245,240,230,.06)]"
      }`}
    >
      <svg width="14" height="14" viewBox="0 0 16 16" aria-hidden fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
        <path d="M8 2.5v8M4.5 7.2 8 10.7l3.5-3.5M3 13.5h10" />
      </svg>
      Download for Mac
    </a>
  );
}


function Hero() {
  return (
    <section className="pt-12 sm:pt-20">
      <Container>
        <h1 className="hf-display max-w-[15ch] text-balance text-[44px] font-bold leading-[0.98] tracking-[-0.035em] sm:text-[64px] lg:max-w-none lg:text-[80px]">
          Always know what’s running,<br className="hidden lg:block" /> and on which port.
        </h1>
        <p className="mt-6 max-w-[34rem] text-pretty text-[18px] leading-[1.55] text-[var(--ink-2)] sm:text-[20px]">
          Your agents start dev servers all day. Hun gives them one way to do it, and shows you every server they or you
          started, with its port and its logs, in your menu bar.
        </p>
        <div className="mt-8 flex flex-wrap items-center gap-x-6 gap-y-4">
          <a
            href={DOWNLOAD_URL}
            className="hf-btn inline-flex h-11 items-center gap-2 rounded-full bg-[var(--ink)] pl-[18px] pr-5 text-[15px] font-medium text-[var(--paper)] hover:opacity-90"
          >
            <AppleLogo />
            Download for Mac
          </a>
          <a href="/pricing" className="hf-link text-[15px] font-medium text-[var(--ink-2)]">
            Pricing
          </a>
        </div>
        <p className="mt-4 text-[13.5px] text-[var(--ink-3)]">Apple silicon, macOS 15 or later.</p>
      </Container>

      <div className="relative mx-auto mt-12 w-full max-w-[1248px] px-5 sm:mt-16 sm:px-8">
        <ProductShot />
      </div>
    </section>
  );
}

/** The live window on a warm tray, at its real 1056×660 on wide screens. */
function ProductShot() {
  return (
    <figure className="hf-hero-tray relative rounded-[22px] bg-[var(--tray)] bg-cover bg-center p-3 sm:rounded-[28px] sm:p-10 xl:p-16" style={{ containerType: "inline-size" }}>
      <div style={{ height: "min(calc(100cqw / 1.6), 660px)" }}>
        <HunWindowHero
          poster="/site/window-light.png"
          alt="Hun's window showing the project orbit: its four services with ports, and the live log of its Next.js app."
        />
      </div>
    </figure>
  );
}



function Agents() {
  return (
    <section className="hf-band mt-16 bg-[var(--ink)] py-20 text-[var(--paper)] sm:mt-40 sm:py-40 lg:py-48">
      <Container>
        <h2 className="hf-display max-w-[18ch] text-balance text-[38px] font-bold leading-[1] tracking-[-0.032em] sm:text-[56px] lg:text-[68px]">
          “My agent already starts the dev server.”
        </h2>
        <div className="mt-14 grid gap-12 border-t border-[rgba(245,240,230,.14)] pt-12 text-pretty text-[18px] leading-[1.65] sm:mt-16 sm:text-[19px] md:grid-cols-2 md:gap-16">
          <div>
            <p className="hf-display text-[15px] font-semibold text-[var(--band-3)]">Without Hun</p>
            <p className="mt-4 text-[var(--band-2)]">
              It does. It runs <DarkCode>npm run dev</DarkCode> inside its own session, and that’s where it goes wrong.
              The logs scroll by in a terminal you never see. The server dies with the session, or stays behind holding{" "}
              <DarkCode>:3000</DarkCode>. And when a second agent needs that port, it frees it the quick way:{" "}
              <DarkCode>kill -9</DarkCode>, on your other project.
            </p>
          </div>
          <div>
            <p className="hf-display text-[15px] font-semibold text-[var(--accent)]">With Hun</p>
            <p className="mt-4 text-[var(--paper)]">
              Every agent starts your project the same way, <DarkCode>hun run orbit</DarkCode>. Each server shows up in
              your menu bar with its port and logs. Ports don’t collide, nothing gets killed to make room, and the server
              keeps running after the session ends, until you stop it.
            </p>
          </div>
        </div>
        <p className="mt-14 text-[15px] leading-[1.6] text-[var(--band-3)]">
          Hun installs a skill that teaches Claude Code, Codex and Cursor to work this way.
        </p>
      </Container>
    </section>
  );
}

function DarkCode({ children }: { children: ReactNode }) {
  return (
    <code className="hf-mono rounded-[5px] bg-[var(--band-code)] px-[5px] py-[1px] text-[.86em] text-[var(--paper)]">
      {children}
    </code>
  );
}

function MenuSection() {
  const points: { title: string; body: ReactNode }[] = [
    { title: "Open it", body: "Click a port and it opens in your browser." },
    { title: "Start or stop it", body: "Run or stop any project right from its row." },
    { title: "Focus or Multitask", body: "One project at a time, or as many as you like." },
    { title: "Close it, they keep running", body: "Closing the window doesn’t stop anything. Your servers run until you stop them." },
  ];
  return (
    <section className="py-16 sm:py-40">
      <Container className="grid items-center gap-14 lg:grid-cols-12 lg:gap-8">
        <div className="lg:col-span-5">
          <h2 className="hf-display max-w-[14ch] text-balance text-[36px] font-bold leading-[1.02] tracking-[-0.03em] sm:text-[52px]">
            Right there in your menu bar.
          </h2>
          <p className="mt-7 max-w-[30rem] text-pretty text-[18px] leading-[1.6] text-[var(--ink-2)]">
            Click the switch in your menu bar and Hun drops down with everything that’s running, each project with its port.
          </p>
          <dl className="mt-10 max-w-[30rem] border-t border-[var(--line)]">
            {points.map((p) => (
              <div key={p.title} className="border-b border-[var(--line)] py-4">
                <dt className="hf-display text-[18px] font-semibold tracking-[-0.01em]">{p.title}</dt>
                <dd className="mt-1 text-pretty text-[16px] leading-[1.55] text-[var(--ink-2)]">{p.body}</dd>
              </div>
            ))}
          </dl>
        </div>
        <div className="min-w-0 lg:col-span-7">
          <MenuBarScene />
        </div>
      </Container>
    </section>
  );
}

const DOCKER_POINTS = [
  { title: "Docker, started for you", body: "If Docker Desktop isn’t running, Hun starts it before the services that need it." },
  { title: "One log per container", body: "Read the API without scrolling past Postgres and Redis, or switch to All to see them together." },
  { title: "Honest when Docker isn’t", body: "If Docker stops answering, Hun stops those services instead of showing them as running." },
];

function DockerSection() {
  return (
    <section className="border-t border-[var(--line)] py-16 sm:py-40">
      <Container>
        <div className="grid gap-8 lg:grid-cols-12">
          <h2 className="hf-display text-balance text-[36px] font-bold leading-[1.02] tracking-[-0.03em] sm:text-[52px] lg:col-span-6">
            Your frontend on the Mac. The rest in Docker.
          </h2>
          <p className="max-w-[32rem] text-pretty text-[18px] leading-[1.6] text-[var(--ink-2)] lg:col-span-5 lg:col-start-8 lg:pt-2">
            Most projects are a mix: <Code>npm run dev</Code> on your machine, and the API, workers, Postgres and
            Redis in Docker Compose. In Hun that’s one project, started in order, each service with its own port and logs.
          </p>
        </div>
      </Container>
      <div className="mx-auto mt-14 w-full max-w-[1248px] px-5 sm:mt-20 sm:px-8">
        <figure
          aria-label="Hun starting the project atlas: Docker Desktop first, then postgres and redis, then api and worker, then the web frontend on the Mac."
          className="rounded-[22px] bg-[var(--tray)] bg-cover bg-center p-3 sm:rounded-[28px] sm:p-10 xl:p-16"
          style={{ backgroundImage: "var(--bg-docker, url(/site/bg/scene-docker.jpg))" }}
        >
          <StartupTimeline />
        </figure>
      </div>
      <Container>
        <dl className="mt-14 grid gap-10 sm:mt-16 md:grid-cols-3 md:gap-8">
          {DOCKER_POINTS.map((p) => (
            <div key={p.title} className="border-t border-[var(--line)] pt-6">
              <dt className="hf-display text-[19px] font-semibold tracking-[-0.01em]">{p.title}</dt>
              <dd className="mt-2 text-pretty text-[16px] leading-[1.55] text-[var(--ink-2)]">{p.body}</dd>
            </div>
          ))}
        </dl>
      </Container>
    </section>
  );
}

function HowItWorks() {
  return <HowItWorksSection />;
}

const JUST_YOU = [
  {
    title: "Switch projects in one click",
    body: "In Focus, starting one project stops the last, so it always gets its own ports.",
  },
  {
    title: "Search every log",
    body: "Filter one service’s output as you type, or switch to All and search the whole project at once.",
  },
  {
    title: "Two projects, both on :3000",
    body: "Both run. The second gets the next free port, and nothing gets killed to make room.",
  },
  {
    title: "Something else on your port",
    body: "Hun tells you what holds it, like node (pid 4121), and stops it only if you ask.",
  },
  {
    title: "Crashes don’t hide",
    body: "A crashed service says so, keeps its log, and restarts with one click.",
  },
  {
    title: "Branches and a terminal",
    body: "Switch a project’s branch from its header, and open a terminal that’s already in the right folder.",
  },
];

function JustYou() {
  return (
    <section className="border-t border-[var(--line)] py-16 sm:py-40">
      <Container>
        <div className="grid gap-12 lg:grid-cols-12 lg:gap-8">
          <h2 className="hf-display text-balance text-[36px] font-bold leading-[1.02] tracking-[-0.03em] sm:text-[52px] lg:col-span-5">
            Useful on the days it’s just you, too.
          </h2>
          <dl className="grid gap-x-10 gap-y-10 sm:grid-cols-2 lg:col-span-7">
            {JUST_YOU.map((item) => (
              <div key={item.title}>
                <dt className="hf-display text-[19px] font-semibold tracking-[-0.01em]">{item.title}</dt>
                <dd className="mt-2 text-pretty text-[16px] leading-[1.55] text-[var(--ink-2)]">{item.body}</dd>
              </div>
            ))}
          </dl>
        </div>
      </Container>
    </section>
  );
}

function Price() {
  return (
    <section className="hf-band bg-[var(--ink)] py-20 text-center text-[var(--paper)] sm:py-40">
      <Container>
        <h2 className="hf-display text-[88px] font-bold leading-[0.9] tracking-[-0.045em] sm:text-[140px]">$9, once.</h2>
        <p className="mx-auto mt-8 max-w-[32rem] text-pretty text-[18px] leading-[1.55] text-[var(--band-2)] sm:text-[20px]">
          One key works on three Macs, and every update is included. No subscription.
        </p>
        <div className="mt-10 flex flex-wrap items-center justify-center gap-x-6 gap-y-4">
          <BuyButton tone="paper" />
          <DownloadButton tone="paper" />
        </div>
        <p className="mt-5 text-[13.5px] text-[var(--band-4)]">Apple silicon, macOS 15 or later.</p>
      </Container>
    </section>
  );
}

