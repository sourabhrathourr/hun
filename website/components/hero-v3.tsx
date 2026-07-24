"use client";

import { InstallButton } from "@/components/install-button";
import { Dithering } from "@paper-design/shaders-react";
import { motion, useReducedMotion } from "framer-motion";

/**
 * HeroV3 — "terminal-native".
 *
 * High-contrast typographic hero: massive lowercase sans display on the
 * left, a slowly-rotating dithered sphere on the right — retro terminal
 * rendering (ordered dither = how old displays faked shading) as the one
 * generative moment. Install command inline in the hero; this version gets
 * straight to the point.
 *
 * Greys only: dither front is the resolved --accent value on --background.
 * Reduced motion: sphere frozen via speed 0, kept mounted.
 */

const EASE_OUT = [0.21, 0.47, 0.32, 0.98] as const;
const brewCommand = "brew tap hundotsh/tap && brew install hun";

export function HeroV3() {
  const reduce = useReducedMotion();

  return (
    <section className="relative overflow-hidden pt-36 pb-section-sm sm:pt-40">
      {/* dithered sphere — the daemon as a retro-rendered body */}
      <div
        aria-hidden
        className="pointer-events-none absolute -right-24 top-8 h-[420px] w-[420px] select-none opacity-60 sm:-right-12 sm:top-16 sm:h-[540px] sm:w-[540px] sm:opacity-80"
        style={{
          maskImage:
            "radial-gradient(closest-side, black 60%, transparent 100%)",
          WebkitMaskImage:
            "radial-gradient(closest-side, black 60%, transparent 100%)",
        }}
      >
        <Dithering
          className="absolute inset-0"
          colorBack="#00000000"
          colorFront="#404040"
          shape="sphere"
          size={2.4}
          speed={reduce ? 0 : 0.4}
        />
      </div>

      <div className="relative mx-auto w-full max-w-3xl px-5 sm:px-6">
        <motion.div
          initial={reduce ? false : { opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.7, ease: EASE_OUT }}
        >
          <h1
            className="max-w-[12ch] text-[clamp(3.25rem,9vw,6rem)] font-medium leading-[0.95] tracking-[-0.03em] text-foreground"
            style={{ textWrap: "balance" }}
          >
            stop killing terminals.
          </h1>
        </motion.div>

        <motion.p
          initial={reduce ? false : { opacity: 0, y: 14 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.7, delay: 0.12, ease: EASE_OUT }}
          className="mt-8 max-w-md font-mono text-[14px] leading-relaxed text-muted-foreground"
        >
          hun manages your dev services, ports, and logs — and switches your
          entire environment in one command.
        </motion.p>

        <motion.div
          initial={reduce ? false : { opacity: 0, y: 14 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.7, delay: 0.24, ease: EASE_OUT }}
          className="mt-10 inline-flex max-w-full items-center gap-3 rounded-sm border border-terminal-border bg-terminal px-4 py-3 font-mono text-[13px]"
        >
          <code className="min-w-0 flex-1 truncate text-foreground/90">
            <span className="text-muted-foreground/40">$ </span>
            {brewCommand}
          </code>
          <InstallButton copyText={brewCommand} />
        </motion.div>
      </div>
    </section>
  );
}

export default HeroV3;
