import { ArchitectureAccordion } from "@/components/architecture-accordion";
import { ConfigTabs } from "@/components/config-tabs";
import { InstallButton } from "@/components/install-button";
import { Reveal, RevealGroup, RevealItem } from "@/components/motion";
import { StatBand } from "@/components/stat-band";
import { TuiPreview } from "@/components/tui-preview";
import macosImage from "@/public/macos-image.png";
import Image from "next/image";
import Link from "next/link";

/**
 * LandingSections — everything below the hero, shared by all landing page
 * versions (/, /v2, /v3). The hero is the exploration surface; these
 * sections stay identical so versions compare apples to apples.
 */

type TermLine = { kind: "cmd" | "out" | "ok" | "dim"; text: string };

function TerminalBlock({ title, lines }: { title: string; lines: TermLine[] }) {
  return (
    <div className="overflow-hidden rounded-md border border-terminal-border bg-terminal font-mono text-[13px] leading-relaxed">
      <div className="border-b border-terminal-border px-4 py-2 text-caption text-muted-foreground/40">
        {title}
      </div>
      <div className="overflow-x-auto px-4 py-3">
        {lines.map((line, i) => (
          <div
            key={i}
            className={
              line.kind === "cmd"
                ? "text-foreground/90"
                : line.kind === "ok"
                  ? "text-green-500/70"
                  : line.kind === "dim"
                    ? "text-muted-foreground/40"
                    : "text-muted-foreground/70"
            }
          >
            {line.kind === "cmd" && (
              <span className="text-muted-foreground/40">$ </span>
            )}
            {line.text}
          </div>
        ))}
      </div>
    </div>
  );
}

const focusLines: TermLine[] = [
  { kind: "cmd", text: "hun switch letraz" },
  { kind: "out", text: "stopping novara — frontend, backend, worker, compose" },
  { kind: "out", text: "freeing :3000 :8000 :5672" },
  { kind: "out", text: "starting next-dev on :3000" },
  { kind: "out", text: "starting thumbnail on :4000" },
  { kind: "out", text: "starting backend on :8000" },
  { kind: "out", text: "starting postgres on :5432" },
  { kind: "ok", text: "✓ letraz ready — 4 services healthy" },
];

const multitaskLines: TermLine[] = [
  { kind: "cmd", text: "hun run novara" },
  { kind: "dim", text: "letraz still running (4 services)" },
  { kind: "out", text: "starting frontend on :3000 → :3100" },
  { kind: "out", text: "starting backend on :8000 → :8100" },
  { kind: "out", text: "starting worker" },
  { kind: "out", text: "starting docker compose (db, redis, rabbitmq)" },
  { kind: "dim", text: "PORT injected per service · offsets applied to collisions only" },
  { kind: "ok", text: "✓ novara ready — running alongside letraz" },
];

const brewCommand = "brew tap hundotsh/tap && brew install hun";

// each chaos step renders as a dead terminal tab — fixed rotations/offsets,
// deliberately misaligned against the calm side
const withoutHun: { text: string; rotate: number; offset: number }[] = [
  { text: "ctrl+c in six terminal tabs", rotate: -1.2, offset: 0 },
  { text: "lsof -i :3000 · kill -9 the orphan", rotate: 0.8, offset: 14 },
  { text: "docker compose down, wait, up again", rotate: -0.6, offset: 4 },
  { text: "relaunch services in the right order", rotate: 1.4, offset: 18 },
  { text: "scroll back to find where the logs went", rotate: -1.6, offset: 8 },
  { text: "repeat every time you switch", rotate: 0.7, offset: 2 },
];

const withHun: TermLine[] = [
  { kind: "cmd", text: "hun switch letraz" },
  { kind: "out", text: "novara stopped · ports freed" },
  { kind: "out", text: "letraz started · logs streaming" },
  { kind: "ok", text: "✓ done. context intact." },
];

const detected = ["node", "go", "python", "docker compose", "monorepos", "hybrid stacks"];

export function LandingSections() {
  return (
    <>
      {/* section 2: the problem — chaos staggers in restlessly, hun lands
          as one calm block */}
      <section className="border-t border-border py-section-sm">
        <Reveal>
          <h2 className="text-headline text-foreground">
            you know the ritual.
          </h2>
        </Reveal>
        <RevealGroup stagger={0.07} className="mt-block grid gap-8 sm:grid-cols-2">
          <div>
            <RevealItem x={-10} y={0}>
              <p className="mb-4 text-caption text-muted-foreground/50">
                without hun
              </p>
            </RevealItem>
            <ul className="space-y-2 font-mono text-[12px] leading-relaxed">
              {withoutHun.map((step) => (
                <li key={step.text}>
                  <RevealItem x={-14} y={0}>
                    <div
                      className="inline-flex max-w-full items-center gap-2 rounded-sm border border-dashed border-border bg-terminal/60 px-2.5 py-1.5 text-muted-foreground/60"
                      style={{
                        transform: `rotate(${step.rotate}deg)`,
                        marginLeft: step.offset,
                      }}
                    >
                      <span aria-hidden className="text-destructive/60">
                        ×
                      </span>
                      <span className="truncate">{step.text}</span>
                    </div>
                  </RevealItem>
                </li>
              ))}
            </ul>
          </div>
          <RevealItem y={18}>
            <p className="mb-4 text-caption text-muted-foreground/50">
              with hun
            </p>
            <TerminalBlock title="one command" lines={withHun} />
          </RevealItem>
        </RevealGroup>
        <Reveal delay={0.1}>
          <p className="mt-block max-w-xl text-body text-muted-foreground">
            every switch costs real minutes and breaks flow state. you lose
            context. hun preserves it.
          </p>
        </Reveal>
      </section>

      {/* section 3: focus & multitask */}
      <section className="border-t border-border py-section-sm">
        <Reveal>
          <h2 className="text-headline text-foreground">two modes.</h2>
        </Reveal>
        <div className="mt-block space-y-block">
          <Reveal className="grid gap-6 sm:grid-cols-[220px_1fr] sm:gap-10">
            <div>
              <h3 className="flex items-baseline gap-2 text-title text-foreground">
                <span aria-hidden className="font-mono text-[10px] text-green-500/70">
                  ●
                </span>
                focus
              </h3>
              <p className="mt-2 text-body text-muted-foreground">
                one project at a time. switch cleanly.
              </p>
            </div>
            <TerminalBlock title="hun switch" lines={focusLines} />
          </Reveal>
          <Reveal className="grid gap-6 sm:grid-cols-[220px_1fr] sm:gap-10">
            <div>
              <h3 className="flex items-baseline gap-2 text-title text-foreground">
                <span aria-hidden className="font-mono text-[10px] text-green-500/70">
                  ●●
                </span>
                multitask
              </h3>
              <p className="mt-2 text-body text-muted-foreground">
                run everything side by side. ports handled.
              </p>
            </div>
            <TerminalBlock title="hun run" lines={multitaskLines} />
          </Reveal>
        </div>

        {/* the proof moment: live-stat readout on a textured field */}
        <Reveal y={24} className="mt-section-sm sm:-mx-10">
          <StatBand />
        </Reveal>
      </section>

      {/* section 4: the tui */}
      <section className="border-t border-border py-section-sm">
        <Reveal>
          <h2 className="text-headline text-foreground">
            mission control, in your terminal.
          </h2>
          <p className="mt-4 max-w-xl text-body text-muted-foreground">
            services, logs, and project switching — all in one pane. vim
            keybindings, search, mouse support.
          </p>
        </Reveal>
        <Reveal y={22} delay={0.08} className="mt-block sm:-mx-10">
          <TuiPreview />
        </Reveal>
      </section>

      {/* section 5: configuration */}
      <section className="border-t border-border py-section-sm">
        <Reveal>
          <h2 className="text-headline text-foreground">
            define your project once. or let hun detect it.
          </h2>
          <p className="mt-4 max-w-xl text-body text-muted-foreground">
            run{" "}
            <code className="rounded-sm bg-muted px-1.5 py-0.5 font-mono text-[0.85em] text-foreground/90">
              hun init
            </code>{" "}
            and it scans your project, figures out your stack, and writes a{" "}
            <code className="rounded-sm bg-muted px-1.5 py-0.5 font-mono text-[0.85em] text-foreground/90">
              .hun.yml
            </code>{" "}
            you can commit so your team shares the same environment.
          </p>
        </Reveal>
        <Reveal y={22} delay={0.08} className="mt-block sm:-mx-10">
          <ConfigTabs />
        </Reveal>
        <Reveal delay={0.14} className="mt-6 flex flex-wrap gap-2">
          {detected.map((s) => (
            <span
              key={s}
              className="rounded-sm border border-border px-2 py-0.5 font-mono text-caption text-muted-foreground/60"
            >
              {s}
            </span>
          ))}
        </Reveal>
      </section>

      {/* section 6: architecture — accordion of principles, each with a
          generative illustration */}
      <section className="border-t border-border py-section-sm">
        <Reveal>
          <h2 className="text-headline text-foreground">
            a daemon does the work.
          </h2>
          <p className="mt-4 max-w-xl text-body text-muted-foreground">
            a lightweight background process manages process groups, captures
            output, and tracks ports. close your laptop, come back —
            everything&apos;s still there.
          </p>
        </Reveal>
        <Reveal y={18} className="mt-block">
          <ArchitectureAccordion />
        </Reveal>
        <Reveal delay={0.1}>
          <p className="mt-6 max-w-xl text-body text-muted-foreground">
            docker-aware, too: services that need it can start Docker Desktop
            before compose runs. not a tmux replacement — hun thinks in
            projects, not panes. use both.
          </p>
        </Reveal>
      </section>

      {/* section 7: macos app */}
      <section className="border-t border-border py-section-sm">
        <Reveal className="grid items-center gap-8 sm:grid-cols-2">
          <div>
            <p className="mb-3 font-mono text-caption uppercase tracking-[0.14em] text-muted-foreground/50">
              beta
            </p>
            <h2 className="text-headline text-foreground">
              hun in your menu bar.
            </h2>
            <p className="mt-4 text-body text-muted-foreground">
              switch projects, restart services, and read logs without
              opening a terminal. native swift app with the cli bundled in.
            </p>
            <Link
              href="/macos"
              className="mt-5 inline-block text-body text-foreground underline underline-offset-4 hover:text-foreground/80"
            >
              get the macOS beta →
            </Link>
          </div>
          <div className="relative">
            {/* soft light behind the app — quiet echo of the hero */}
            <div
              aria-hidden
              className="pointer-events-none absolute -inset-8"
              style={{
                background:
                  "radial-gradient(60% 60% at 50% 45%, oklch(0.985 0 0 / 0.05), transparent 75%)",
              }}
            />
            <figure className="relative overflow-hidden rounded-md border border-border bg-muted/20">
              <Image
                src={macosImage}
                alt="hun macOS menu bar app showing running services and live logs"
                placeholder="blur"
                loading="lazy"
                sizes="(min-width: 640px) 360px, calc(100vw - 40px)"
                className="h-auto w-full"
              />
            </figure>
          </div>
        </Reveal>
      </section>

      {/* section 8: install + footer */}
      <section
        id="install"
        className="scroll-mt-24 border-t border-border py-section-sm"
      >
        <Reveal>
          <h2 className="text-headline text-foreground">try it.</h2>
        </Reveal>
        <Reveal
          delay={0.08}
          className="mt-block max-w-xl overflow-hidden rounded-md border border-terminal-border bg-terminal font-mono text-[13px]"
        >
          <div className="flex items-start gap-3 px-4 py-3">
            <code className="min-w-0 flex-1 whitespace-pre-wrap break-all text-foreground/90 sm:break-normal">
              <span className="text-muted-foreground/40">$ </span>
              brew tap hundotsh/tap
              {"\n"}
              <span className="text-muted-foreground/40">$ </span>
              brew install hun
            </code>
            <InstallButton copyText={brewCommand} />
          </div>
        </Reveal>
        <p className="mt-4 text-caption text-muted-foreground/60">
          or{" "}
          <code className="font-mono">
            curl -fsSL https://hun.sh/install.sh | sh
          </code>{" "}
          · then run{" "}
          <code className="font-mono text-foreground/70">hun init</code> in a
          project.
        </p>

        <footer className="mt-section-sm border-t border-border pt-6 pb-10 text-caption text-muted-foreground/50">
          <Link href="/docs" className="hover:text-foreground">
            docs
          </Link>{" "}
          &middot;{" "}
          <Link href="/changelog" className="hover:text-foreground">
            changelog
          </Link>{" "}
          &middot;{" "}
          <Link href="/macos" className="hover:text-foreground">
            macOS app beta
          </Link>{" "}
          &middot;{" "}
          <a
            href="https://github.com/sourabhrathourr/hun"
            className="hover:text-foreground"
          >
            github
          </a>{" "}
          &middot; built by{" "}
          <a href="https://sourabh.fun" className="hover:text-foreground">
            sourabh rathour
          </a>
        </footer>
      </section>
    </>
  );
}

export default LandingSections;
