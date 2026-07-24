import { HeroV3 } from "@/components/hero-v3";
import { LandingSections } from "@/components/landing-sections";
import { PillNav } from "@/components/pill-nav";
import { VersionSwitcher } from "@/components/version-switcher";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "hun.sh — landing v3 (terminal-native)",
  robots: { index: false, follow: false },
};

/**
 * Landing v3 — "terminal-native": massive typographic hero with a dithered
 * sphere. Exploration page; not indexed.
 */
export default function PageV3() {
  return (
    <div className="relative min-h-dvh overflow-x-clip bg-background text-foreground">
      <PillNav />

      <HeroV3 />

      <div className="relative z-10 mx-auto w-full max-w-3xl px-5 sm:px-6">
        <LandingSections />
      </div>

      <VersionSwitcher current="v3" />
    </div>
  );
}
