"use client";

import { DotOrbit } from "@paper-design/shaders-react";
import {
  motion,
  useMotionValue,
  useReducedMotion,
  useSpring,
} from "framer-motion";
import { useEffect, useRef } from "react";

/**
 * HeroGlow — the page's signature moment: the daemon's status light over a
 * quietly alive particle field.
 *
 * Three layers, back to front:
 *  1. DotOrbit shader — tiny dots drifting around their cells, greys only.
 *     Reads as a field of background processes; replaces the old static
 *     SVG grain.
 *  2. Breathing ambient light (~11s cycle) — the LED-at-rest metaphor.
 *  3. Faint pointer-following sheen on a heavy spring.
 *
 * Color constraint: only resolved values of existing grey tokens.
 *   #171717 = --card · #262626 = --muted · #404040 = --accent
 *   glow/sheen = --foreground at low alpha
 * If this ever reads colorful, it's wrong — mute it further.
 *
 * Reduced motion: shader speed 0 (kept mounted so layout never shifts),
 * static glow, no pointer tracking.
 */

export function HeroGlow() {
  const reduce = useReducedMotion();
  const ref = useRef<HTMLDivElement>(null);

  const mx = useMotionValue(0);
  const my = useMotionValue(0);
  // lazy, heavy follow — light drifting toward the cursor, not a tracker
  const sx = useSpring(mx, { stiffness: 40, damping: 18, mass: 0.8 });
  const sy = useSpring(my, { stiffness: 40, damping: 18, mass: 0.8 });

  useEffect(() => {
    if (reduce) return;
    const onMove = (e: PointerEvent) => {
      if (e.pointerType !== "mouse") return;
      const el = ref.current;
      if (!el) return;
      const r = el.getBoundingClientRect();
      const x = e.clientX - (r.left + r.width / 2);
      const y = e.clientY - (r.top + r.height * 0.4);
      mx.set(Math.max(-360, Math.min(360, x)));
      my.set(Math.max(-220, Math.min(260, y)));
    };
    window.addEventListener("pointermove", onMove, { passive: true });
    return () => window.removeEventListener("pointermove", onMove);
  }, [mx, my, reduce]);

  return (
    <div
      ref={ref}
      aria-hidden
      className="pointer-events-none absolute inset-x-0 -top-24 h-[760px] select-none overflow-hidden"
      style={{
        maskImage:
          "radial-gradient(120% 100% at 50% 0%, black 45%, transparent 92%)",
        WebkitMaskImage:
          "radial-gradient(120% 100% at 50% 0%, black 45%, transparent 92%)",
      }}
    >
      {/* 1 — particle field: background processes, quietly alive */}
      <DotOrbit
        className="absolute inset-0 opacity-45"
        colorBack="#00000000"
        colors={["#171717", "#262626", "#404040"]}
        size={0.14}
        sizeRange={0.6}
        spreading={0.35}
        stepsPerColor={2}
        scale={0.6}
        speed={reduce ? 0 : 0.12}
      />

      {/* 2 — ambient light, slow breathing */}
      <motion.div
        className="absolute left-1/2 top-0 -ml-[500px] h-[560px] w-[1000px]"
        style={{
          background:
            "radial-gradient(50% 50% at 50% 34%, oklch(0.985 0 0 / 0.08), transparent 72%)",
        }}
        animate={
          reduce ? undefined : { opacity: [0.65, 1, 0.65], scale: [1, 1.05, 1] }
        }
        transition={{ duration: 11, repeat: Infinity, ease: "easeInOut" }}
      />

      {/* 3 — pointer-following sheen, very faint */}
      {!reduce && (
        <motion.div
          className="absolute left-1/2 top-[38%] -ml-[220px] -mt-[220px] h-[440px] w-[440px]"
          style={{
            x: sx,
            y: sy,
            background:
              "radial-gradient(closest-side, oklch(0.985 0 0 / 0.05), transparent 70%)",
          }}
        />
      )}
    </div>
  );
}

export default HeroGlow;
