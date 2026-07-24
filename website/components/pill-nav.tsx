"use client";

import { motion, useReducedMotion } from "framer-motion";
import Link from "next/link";

/**
 * PillNav — floating pill-shaped nav for the homepage.
 *
 * Fixed, centered, rounded-full container: serif wordmark left, quiet links,
 * one light CTA pill (the only "accent" on the page — inverted greys, no new
 * colors). Drops in with the hero choreography on load.
 */

const EASE_OUT = [0.21, 0.47, 0.32, 0.98] as const;

export function PillNav() {
  const reduce = useReducedMotion();

  return (
    <motion.header
      initial={reduce ? false : { opacity: 0, y: -12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, ease: EASE_OUT }}
      className="fixed inset-x-0 top-4 z-50 flex justify-center px-4"
    >
      <nav className="flex items-center gap-0.5 rounded-full border border-border bg-background/70 py-1.5 pl-4 pr-1.5 shadow-[0_8px_32px_-12px_rgba(0,0,0,0.7)] backdrop-blur-md">
        <Link
          href="/"
          className="mr-2 font-serif text-[19px] leading-none text-foreground"
        >
          hun
        </Link>
        <Link
          href="/docs"
          className="rounded-full px-2.5 py-1 text-caption text-muted-foreground transition-colors hover:bg-muted/50 hover:text-foreground max-[400px]:hidden"
        >
          docs
        </Link>
        <Link
          href="/changelog"
          className="rounded-full px-2.5 py-1 text-caption text-muted-foreground transition-colors hover:bg-muted/50 hover:text-foreground max-[400px]:hidden"
        >
          changelog
        </Link>
        <a
          href="https://github.com/sourabhrathourr/hun"
          className="rounded-full px-2.5 py-1 text-caption text-muted-foreground transition-colors hover:bg-muted/50 hover:text-foreground"
        >
          github
        </a>
        <a
          href="#install"
          className="ml-1.5 rounded-full bg-primary px-3.5 py-1 text-caption font-medium text-primary-foreground transition-transform hover:bg-primary/90 active:scale-[0.97]"
        >
          install
        </a>
      </nav>
    </motion.header>
  );
}

export default PillNav;
