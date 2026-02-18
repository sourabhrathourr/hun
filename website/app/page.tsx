import { Reveal } from "@/components/reveal";
import { InstallButton } from "@/components/install-button";
import { Terminal } from "@/components/terminal";
import { MiniTui } from "@/components/mini-tui";

export default function Page() {
  const d = 0.1;

  return (
    <div className="min-h-dvh bg-background text-foreground flex items-start justify-center px-5 sm:px-6 py-12 sm:py-20">
      <main className="max-w-xl w-full">
        <div className="space-y-6 sm:space-y-7 text-[14px] sm:text-[15px] leading-relaxed text-muted-foreground">
          <Reveal>
            <div className="mb-8">
              <span className="text-foreground font-serif text-[30px] sm:text-[42px] leading-tight block mb-5">
                hun.sh
              </span>
              <div className="text-[13px] text-muted-foreground/50 space-y-1">
                <p>brew tap hundotsh/tap</p>
                <code className="text-foreground/80 bg-muted pl-2 pr-1.5 py-0.5 rounded-sm inline-flex items-center gap-2">
                  brew install hun
                  <InstallButton
                    copyText={"brew tap hundotsh/tap && brew install hun"}
                  />
                </code>
              </div>
            </div>
          </Reveal>

          <Reveal delay={d}>
            <p>
              a command-line tool for seamless project context switching.
              manages your dev services, ports, and logs. switches your entire
              environment in one command.
            </p>
          </Reveal>

          <Reveal delay={d * 2}>
            <MiniTui />
          </Reveal>

          <Reveal delay={d * 3}>
            <p>
              say you&apos;re working on two projects. letraz, an ai resume
              builder, runs a next.js frontend on 3000, a thumbnail service on
              4000, a backend on 8000, and postgres on 5432. novara, a remote
              healthcare platform, needs a frontend on 3000, backend on 8000, a
              node worker, and docker compose running a database, redis, and
              rabbitmq. now picture yourself ctrl+c-ing through six terminal
              tabs, killing orphan processes on :3000, restarting docker, and
              doing this every single time you switch. you lose context,
              hun preserves it.
            </p>
          </Reveal>

          <Reveal delay={d * 4}>
            <Terminal />
          </Reveal>

          <Reveal delay={d * 5}>
            <p>
              run{" "}
              <code className="text-foreground/80 bg-muted px-1.5 py-0.5 rounded-sm text-[13px]">
                hun init
              </code>{" "}
              in each project and it detects your services automatically. then{" "}
              <code className="text-foreground/80 bg-muted px-1.5 py-0.5 rounded-sm text-[13px]">
                hun switch
              </code>{" "}
              to swap between them, or{" "}
              <code className="text-foreground/80 bg-muted px-1.5 py-0.5 rounded-sm text-[13px]">
                hun run
              </code>{" "}
              to run them side by side with automatic port offsets.
            </p>
          </Reveal>

          <Reveal delay={d * 6}>
            <p>
              a daemon runs in the background. manages process groups, captures
              all output, detects ports. close your laptop, come back,
              everything&apos;s still there.
            </p>
          </Reveal>

          <Reveal delay={d * 7}>
            <div className="flex flex-wrap gap-2 text-[12px]">
              {[
                "node",
                "go",
                "python",
                "docker compose",
                "monorepos",
                "hybrid stacks",
              ].map((s) => (
                <span
                  key={s}
                  className="text-muted-foreground/50 border border-border rounded-sm px-2 py-0.5"
                >
                  {s}
                </span>
              ))}
            </div>
          </Reveal>

          <Reveal delay={d * 8}>
            <p>
              not a tmux replacement. tmux does session persistence and terminal
              multiplexing. hun thinks in projects — which services to start,
              which ports to free, which logs to capture. use both.
            </p>
          </Reveal>

          <Reveal delay={d * 9}>
            <p className="text-muted-foreground/40 text-[12px]">
              <a
                href="/docs"
                className="underline underline-offset-2 hover:text-muted-foreground/60"
              >
                docs
              </a>{" "}
              &middot;{" "}
              <a
                href="https://github.com/sourabhrathourr/hun"
                className="underline underline-offset-2 hover:text-muted-foreground/60"
              >
                github
              </a>{" "}
              &middot; built by{" "}
              <a
                href="https://sourabh.fun"
                className="underline underline-offset-2 hover:text-muted-foreground/60"
              >
                sourabh rathour
              </a>
            </p>
          </Reveal>
        </div>
      </main>
    </div>
  );
}
