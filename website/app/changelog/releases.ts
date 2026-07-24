// Changelog content, curated from GitHub releases
// (https://github.com/sourabhrathourr/hun/releases). To add a release,
// prepend an entry — newest first.

export type Release = {
  version: string;
  date: string; // ISO date
  summary: string;
  changes: string[];
  tag?: string; // github tag if it differs from version
};

export const releases: Release[] = [
  {
    version: "v0.2.2",
    date: "2026-07-11",
    summary:
      "reliable multitask ports, automatic PORT delivery, and a more resilient daemon.",
    changes: [
      "multitask port allocation keeps configured ports unchanged when free — only genuine collisions are offset",
      "every configured service now receives PORT automatically; port_env stays as an optional custom alias",
      "runtime listener ownership is verified, with safe adoption of valid framework fallbacks",
      "daemon recovers from stale locks, missing sockets, stale PID files, and failed termination",
      "readiness and live-port state stay accurate — no more stale waiting indicators",
      "dashboard remembers project tabs, selected service, and log scope across launches",
      "menu bar focus switches now select the destination project in the dashboard",
      "running-project indicators, reduced-motion-aware transitions, and an adaptive menu bar symbol",
    ],
  },
  {
    version: "v0.2.1",
    date: "2026-07-11",
    summary: "focus mode enforcement, daemon health settings, and port fixes.",
    changes: [
      "focus mode transitions are now enforced end to end",
      "daemon health settings are configurable",
      "open running services directly in the browser",
      "configured ports are authoritative",
      "Next.js readiness output is matched correctly",
      "macOS Sequoia beta app support",
    ],
  },
  {
    version: "v0.2.0",
    date: "2026-06-20",
    summary: "groundwork release alongside the first macOS app beta.",
    changes: ["Go 1.22 support in hun init detection tests"],
  },
  {
    version: "macOS app beta",
    tag: "macos-beta-20260620-211133",
    date: "2026-06-20",
    summary:
      "first public build of the menu bar app. unnotarized friends beta — install via the beta script only if you trust the build.",
    changes: [
      "menu bar app with bundled daemon",
      "install with: curl -fsSL https://hun.sh/install-macos-beta.sh | sh",
    ],
  },
  {
    version: "v0.1.6",
    date: "2026-02-20",
    summary: "log viewer v2 with a dual-pane UX.",
    changes: [
      "dual-pane log viewer with pane-focused keyboard and mouse routing, live mode, wrap toggle, and range selection",
      "clipboard pipeline with OSC52 + native fallbacks, toast feedback, and a flash effect on log copy",
      "strict fresh in-memory logs via per-service resets; explicit service stop separated from project stop",
      "daemon protocol versioning and client auto-restart of stale daemons after upgrade",
      "fixed log UI cropping in multi mode",
    ],
  },
  {
    version: "v0.1.5",
    date: "2026-02-18",
    summary: "docs, installer endpoint, and onboarding polish.",
    changes: [
      "full documentation section at hun.sh/docs",
      "install.sh endpoint for installing the latest binary from GitHub releases",
      "refined landing page copy and mobile layout",
      "CLI version display fixed, with versions fetched from git tags",
    ],
  },
  {
    version: "v0.1.4",
    date: "2026-02-17",
    summary: "initial public release.",
    changes: [
      "focus mode: switch between projects instantly",
      "multitask mode: run multiple projects side by side with automatic port management",
      "TUI for managing services and logs",
      "unified log streaming and querying",
      "registry synced with the .hun.yml lifecycle, with an overwrite prompt in hun init",
    ],
  },
  {
    version: "v0.1.3",
    date: "2026-02-17",
    summary: "release pipeline fix.",
    changes: [
      "homebrew tap formula path updated; untracked changes detected during release",
    ],
  },
  {
    version: "v0.1.2",
    date: "2026-02-17",
    summary: "homebrew distribution.",
    changes: [
      "homebrew formula published from release checksums",
      "goreleaser config migrated to formats and homebrew_casks",
    ],
  },
  {
    version: "v0.1.1",
    date: "2026-02-17",
    summary: "first tagged release.",
    changes: ["cmd entrypoint included in git; ignore rules narrowed"],
  },
];
