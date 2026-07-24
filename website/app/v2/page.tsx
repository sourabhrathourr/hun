import { HeroV2 } from "@/components/hero-v2";
import { LandingSections } from "@/components/landing-sections";
import { PillNav } from "@/components/pill-nav";
import { VersionSwitcher } from "@/components/version-switcher";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "hun.sh — landing v2 (glass)",
  robots: { index: false, follow: false },
};

/**
 * Landing v2 — "light through glass": god-ray light shafts refracting
 * through a heavy glass hero panel. Exploration page; not indexed.
 */
export default function PageV2() {
  return (
    <div className="relative min-h-dvh overflow-x-clip bg-background text-foreground">
      <PillNav />

      <HeroV2 />

      <div className="relative z-10 mx-auto w-full max-w-3xl px-5 sm:px-6">
        <LandingSections />
      </div>

      <VersionSwitcher current="v2" />
    </div>
  );
}
