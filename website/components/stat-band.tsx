"use client";

import { GrainGradient } from "@paper-design/shaders-react";
import {
  animate,
  motion,
  useInView,
  useReducedMotion,
} from "framer-motion";
import { useEffect, useRef } from "react";

/**
 * StatBand — the live-stat moment.
 *
 * One big number presented as part of a textured scene (Daytona-style), not
 * a plain card: a slow GrainGradient dot-field in greys behind a mono
 * count-up. The headline figure is hun's own demo number for a full
 * four-service context switch; the two supporting stats are the product's
 * core promises.
 *
 * Greys only — resolved values of --card / --muted / --accent over
 * --background. Reduced motion: shader frozen (speed 0, still mounted),
 * number rendered at its final value.
 */

const SWITCH_MS = 820;

function CountUp({ target }: { target: number }) {
  const reduce = useReducedMotion();
  const ref = useRef<HTMLSpanElement>(null);
  const inView = useInView(ref, { once: true, margin: "-80px" });

  useEffect(() => {
    if (reduce || !inView) return;
    const el = ref.current;
    if (!el) return;
    const controls = animate(0, target, {
      duration: 1.4,
      ease: [0.16, 1, 0.3, 1],
      onUpdate: (v) => {
        el.textContent = String(Math.round(v));
      },
    });
    return () => controls.stop();
  }, [inView, reduce, target]);

  return <span ref={ref}>{reduce || !inView ? target : 0}</span>;
}

export function StatBand({ className = "" }: { className?: string }) {
  const reduce = useReducedMotion();

  return (
    <div
      className={`relative overflow-hidden rounded-md border border-terminal-border ${className}`}
    >
      {/* textured scene */}
      <GrainGradient
        className="absolute inset-0"
        colorBack="#0a0a0a"
        colors={["#171717", "#262626", "#404040"]}
        shape="dots"
        softness={0.7}
        intensity={0.35}
        noise={0.55}
        speed={reduce ? 0 : 0.25}
      />
      {/* keep the number legible over the busiest patches */}
      <div
        className="absolute inset-0"
        style={{
          background:
            "radial-gradient(80% 90% at 30% 50%, oklch(0.145 0 0 / 0.7), transparent 80%)",
        }}
      />

      <div className="relative px-6 py-12 sm:px-10 sm:py-16">
        <motion.p
          initial={{ opacity: 0 }}
          whileInView={{ opacity: 1 }}
          viewport={{ once: true }}
          transition={{ duration: 0.6 }}
          className="font-mono text-[clamp(3.5rem,10vw,6rem)] font-medium leading-none tracking-tight text-foreground"
        >
          <CountUp target={SWITCH_MS} />
          <span className="text-muted-foreground">ms</span>
        </motion.p>
        <p className="mt-3 font-mono text-caption text-muted-foreground">
          full context switch — four services stopped, four started, ports
          reassigned, logs streaming.
        </p>

        <div className="mt-10 flex flex-wrap gap-x-12 gap-y-6 border-t border-border pt-6">
          <div>
            <p className="font-mono text-title text-foreground">0</p>
            <p className="mt-1 font-mono text-caption text-muted-foreground/70">
              orphan processes left behind
            </p>
          </div>
          <div>
            <p className="font-mono text-title text-foreground">1</p>
            <p className="mt-1 font-mono text-caption text-muted-foreground/70">
              command, entire environment
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}

export default StatBand;
