import { InstallButton } from "@/components/install-button";
import { Reveal } from "@/components/reveal";
import macosImage from "@/public/macos-image.png";
import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";

const installCommand = "curl -fsSL https://hun.sh/install-macos-beta.sh | sh";

export const metadata: Metadata = {
  title: "hun macOS app beta",
  description:
    "Early testing build of the hun macOS menu bar app for switching projects, watching logs, and managing dev services.",
  openGraph: {
    title: "hun macOS app beta",
    description:
      "Early testing build of the hun macOS menu bar app for switching projects, watching logs, and managing dev services.",
    url: "https://hun.sh/macos",
    images: [{ url: "/api/og/macos", width: 1200, height: 630 }],
  },
  twitter: {
    card: "summary_large_image",
    title: "hun macOS app beta",
    description:
      "Early testing build of the hun macOS menu bar app for switching projects, watching logs, and managing dev services.",
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

export default function MacosPage() {
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

        <section className="pt-14 sm:pt-20 space-y-8 sm:space-y-10">
          <Reveal delay={d}>
            <div className="max-w-2xl space-y-4">
              <p className="text-[12px] uppercase tracking-[0.18em] text-muted-foreground/40">
                macOS app beta
              </p>
              <h1 className="font-serif text-[42px] sm:text-[68px] leading-[0.95] text-foreground">
                hun in your menu bar.
              </h1>
              <p className="max-w-xl text-[14px] sm:text-[15px] leading-relaxed text-muted-foreground/65">
                a native-feeling desktop app for project switching, service
                control, and logs. built for the moment when you want hun visible
                without opening another terminal pane.
              </p>
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
                early testing build
              </h2>
              <p className="text-[14px] leading-relaxed text-muted-foreground/60">
                this is the current beta path before the signed dmg. the
                installer verifies the zip, removes old hun cli installs that can
                conflict with the daemon protocol, installs hun.app, and opens it.
              </p>
            </div>
          </Reveal>

          <Reveal delay={d * 4}>
            <div className="space-y-5">
              <div className="bg-muted px-3 py-2 rounded-sm flex items-start gap-2 text-[12px] leading-relaxed font-mono text-foreground/80">
                <code className="min-w-0 flex-1 whitespace-pre-wrap break-all sm:break-normal">
                  {installCommand}
                </code>
                <InstallButton copyText={installCommand} />
              </div>
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
              href="/"
              className="underline underline-offset-2 hover:text-muted-foreground/60"
            >
              back to hun.sh
            </Link>{" "}
            &middot; beta app installs to{" "}
            <code className="text-muted-foreground/55">
              /Applications/hun.app
            </code>
          </footer>
        </Reveal>
      </main>
    </div>
  );
}
