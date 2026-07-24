import { HeroGlow } from "@/components/hero-glow";
import { LandingSections } from "@/components/landing-sections";
import { RevealGroup, RevealItem } from "@/components/motion";
import { PillNav } from "@/components/pill-nav";
import { TerminalSwitcher } from "@/components/terminal-switcher";
import { VersionSwitcher } from "@/components/version-switcher";

/**
 * Landing v1 — "the daemon's status light": serif display headline over a
 * DotOrbit particle field with a breathing ambient light. Sections below the
 * hero are shared across versions (components/landing-sections.tsx).
 */

export default function Page() {
  return (
    <div className="relative min-h-dvh overflow-x-clip bg-background text-foreground">
      {/* signature moment: breathing light over a quietly-alive dot field */}
      <HeroGlow />

      {/* floating pill nav */}
      <PillNav />

      <div className="relative z-10 mx-auto w-full max-w-3xl px-5 sm:px-6">
        {/* hero enters as one choreographed sequence on load */}
        <RevealGroup inView={false} stagger={0.12}>
          <section className="pt-40 pb-section-sm sm:pt-44">
            <RevealItem blur y={16}>
              <h1
                className="font-serif text-[clamp(3rem,7vw,4.75rem)] leading-[1.02] text-foreground"
                style={{ textWrap: "balance" }}
              >
                stop killing terminals.
              </h1>
            </RevealItem>
            <RevealItem y={14}>
              <p className="mt-6 max-w-xl text-lead text-muted-foreground">
                hun manages your dev services, ports, and logs — and switches
                your entire environment in one command.
              </p>
            </RevealItem>
            <RevealItem y={20} className="mt-block sm:-mx-10">
              {/* glass: the one panel that actually overlaps the glow */}
              <TerminalSwitcher glass />
            </RevealItem>
          </section>
        </RevealGroup>

        <LandingSections />
      </div>

      <VersionSwitcher current="v1" />
    </div>
  );
}
