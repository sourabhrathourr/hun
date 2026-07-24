"use client";

import { motion, useReducedMotion } from "framer-motion";
import type { ReactNode } from "react";

/**
 * Shared scroll/load reveal primitives for the landing page.
 *
 * Reveal        — single element, fades/slides in when scrolled into view.
 * RevealGroup   — stagger container; descendants that are RevealItems play
 *                 in sequence. `inView={false}` plays on mount instead
 *                 (used for the hero load choreography).
 * RevealItem    — one step inside a RevealGroup.
 *
 * All of these collapse to plain static divs under prefers-reduced-motion.
 * Only transform / opacity / filter are animated — nothing that triggers
 * layout.
 */

export const EASE_OUT = [0.21, 0.47, 0.32, 0.98] as const;

const VIEWPORT = { once: true, margin: "-72px 0px" } as const;

export function Reveal({
  children,
  className,
  delay = 0,
  x = 0,
  y = 16,
  duration = 0.6,
}: {
  children: ReactNode;
  className?: string;
  delay?: number;
  x?: number;
  y?: number;
  duration?: number;
}) {
  const reduce = useReducedMotion();
  if (reduce) return <div className={className}>{children}</div>;

  return (
    <motion.div
      className={className}
      initial={{ opacity: 0, x, y }}
      whileInView={{ opacity: 1, x: 0, y: 0 }}
      viewport={VIEWPORT}
      transition={{ duration, delay, ease: EASE_OUT }}
    >
      {children}
    </motion.div>
  );
}

export function RevealGroup({
  children,
  className,
  stagger = 0.09,
  delay = 0,
  inView = true,
}: {
  children: ReactNode;
  className?: string;
  stagger?: number;
  delay?: number;
  /** false = play on mount (hero); true = play when scrolled into view */
  inView?: boolean;
}) {
  const reduce = useReducedMotion();
  if (reduce) return <div className={className}>{children}</div>;

  const variants = {
    hidden: {},
    visible: {
      transition: { staggerChildren: stagger, delayChildren: delay },
    },
  };

  if (inView) {
    return (
      <motion.div
        className={className}
        variants={variants}
        initial="hidden"
        whileInView="visible"
        viewport={VIEWPORT}
      >
        {children}
      </motion.div>
    );
  }

  return (
    <motion.div
      className={className}
      variants={variants}
      initial="hidden"
      animate="visible"
    >
      {children}
    </motion.div>
  );
}

export function RevealItem({
  children,
  className,
  x = 0,
  y = 14,
  blur = false,
}: {
  children: ReactNode;
  className?: string;
  x?: number;
  y?: number;
  /** adds a blur(6px) → 0 settle; reserve for the hero headline */
  blur?: boolean;
}) {
  const reduce = useReducedMotion();
  if (reduce) return <div className={className}>{children}</div>;

  return (
    <motion.div
      className={className}
      variants={{
        hidden: {
          opacity: 0,
          x,
          y,
          ...(blur ? { filter: "blur(6px)" } : {}),
        },
        visible: {
          opacity: 1,
          x: 0,
          y: 0,
          ...(blur ? { filter: "blur(0px)" } : {}),
          transition: { duration: 0.6, ease: EASE_OUT },
        },
      }}
    >
      {children}
    </motion.div>
  );
}
