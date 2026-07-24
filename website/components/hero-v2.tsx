"use client";

import { TerminalSwitcher } from "@/components/terminal-switcher";
import { GodRays } from "@paper-design/shaders-react";
import { motion, useReducedMotion } from "framer-motion";

/**
 * HeroV2 — "light through glass".
 *
 * Soft grey light shafts (GodRays, greys only) fall from above onto a heavy
 * glass panel holding the terminal switcher. The glass refracts the light:
 * a specular top edge, a slow diagonal streak sweeping across the pane, and
 * a prismatic corner highlight. Centered composition, sans display headline
 * — deliberately different voice from v1's left-aligned serif.
 *
 * Grey constraint: rays use resolved --muted/--accent/--ring values; all
 * glass highlights are --foreground alpha. Reduced motion: rays frozen
 * (speed 0, mounted), streak hidden.
 */

const EASE_OUT = [0.21, 0.47, 0.32, 0.98] as const;

export function HeroV2() {
  const reduce = useReducedMotion();

  return (
    <section className="relative overflow-hidden pt-40 pb-section-sm sm:pt-44">
      {/* light source — grey rays from above */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-0 -top-24 h-[780px] select-none"
        style={{
          maskImage:
            "radial-gradient(130% 100% at 50% 0%, black 45%, transparent 95%)",
          WebkitMaskImage:
            "radial-gradient(130% 100% at 50% 0%, black 45%, transparent 95%)",
        }}
      >
        <GodRays
          className="absolute inset-0 opacity-70"
          colorBack="#00000000"
          colorBloom="#737373"
          colors={["#262626", "#404040", "#171717"]}
          offsetY={-0.9}
          density={0.3}
          spotty={0.35}
          midSize={0.1}
          midIntensity={0.35}
          intensity={0.28}
          bloom={0.25}
          speed={reduce ? 0 : 0.35}
        />
      </div>

      <div className="relative mx-auto w-full max-w-3xl px-5 sm:px-6">
        <motion.div
          initial={reduce ? false : { opacity: 0, y: 18 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.7, ease: EASE_OUT }}
          className="text-center"
        >
          <h1
            className="text-display text-foreground"
            style={{ textWrap: "balance" }}
          >
            stop killing terminals.
          </h1>
          <p className="mx-auto mt-6 max-w-xl text-lead text-muted-foreground">
            hun manages your dev services, ports, and logs — and switches your
            entire environment in one command.
          </p>
        </motion.div>

        {/* the glass pane the light falls through */}
        <motion.div
          initial={reduce ? false : { opacity: 0, y: 28 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.15, ease: EASE_OUT }}
          className="relative mt-block sm:-mx-6"
        >
          <div className="relative overflow-hidden rounded-xl border border-foreground/10 bg-terminal/40 p-4 backdrop-blur-2xl shadow-[0_32px_80px_-32px_rgba(0,0,0,0.9)] sm:p-6">
            {/* specular top edge */}
            <div
              aria-hidden
              className="pointer-events-none absolute inset-x-6 top-0 h-px"
              style={{
                background:
                  "linear-gradient(90deg, transparent, oklch(0.985 0 0 / 0.35), transparent)",
              }}
            />
            {/* prismatic corner highlight */}
            <div
              aria-hidden
              className="pointer-events-none absolute -top-16 -left-16 h-48 w-48 rounded-full"
              style={{
                background:
                  "radial-gradient(closest-side, oklch(0.985 0 0 / 0.08), transparent 70%)",
              }}
            />
            {/* refraction streak sweeping across the pane */}
            {!reduce && (
              <motion.div
                aria-hidden
                className="pointer-events-none absolute inset-y-[-40%] w-40 rotate-[16deg]"
                style={{
                  background:
                    "linear-gradient(90deg, transparent, oklch(0.985 0 0 / 0.05), oklch(0.985 0 0 / 0.09), oklch(0.985 0 0 / 0.05), transparent)",
                }}
                initial={{ left: "-25%" }}
                animate={{ left: "115%" }}
                transition={{
                  duration: 9,
                  repeat: Infinity,
                  repeatDelay: 3,
                  ease: "easeInOut",
                }}
              />
            )}

            <TerminalSwitcher />
          </div>
        </motion.div>
      </div>
    </section>
  );
}

export default HeroV2;
