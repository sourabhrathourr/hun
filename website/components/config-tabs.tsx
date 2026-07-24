"use client";

import { motion, AnimatePresence } from "framer-motion";
import { Fragment, useState } from "react";

/**
 * ConfigTabs — tabbed `.hun.yml` viewer.
 *
 * Shows the generated config for different project types (Node.js / Go /
 * Python / monorepo) to demonstrate breadth of `hun init` auto-detection.
 *
 * Syntax highlighting is a small self-contained YAML tokenizer (below) so the
 * component has no highlighting dependency. It uses only the existing palette
 * — foreground / muted-foreground tiers plus the green-500 accent already used
 * elsewhere — so it introduces no new colors.
 *
 * Self-contained: renders with zero props. Pass `tabs` to override the data.
 */

export type ConfigTab = {
  /** Tab label, e.g. "node.js" */
  label: string;
  /** Comment/annotation shown as the first line and header hint */
  detected: string;
  /** Raw .hun.yml body */
  code: string;
};

const DEFAULT_TABS: ConfigTab[] = [
  {
    label: "node.js",
    detected: "package.json, next.js",
    code: `project: my-app
mode: focus

services:
  web:
    dir: .
    cmd: npm run dev
    port: 3000
    env:
      NODE_ENV: development`,
  },
  {
    label: "go",
    detected: "go.mod",
    code: `project: api
mode: focus

services:
  server:
    dir: .
    cmd: go run ./cmd/server
    port: 8080
    watch: true`,
  },
  {
    label: "python",
    detected: "pyproject.toml, uvicorn",
    code: `project: service
mode: focus

services:
  api:
    dir: .
    cmd: uvicorn app.main:app --reload
    port: 8000`,
  },
  {
    label: "monorepo",
    detected: "pnpm-workspace.yaml",
    code: `project: platform
mode: multitask

services:
  web:
    dir: ./apps/web
    cmd: pnpm dev
    port: 3000
  api:
    dir: ./apps/api
    cmd: pnpm start:dev
    port: 4000
  worker:
    dir: ./services/worker
    cmd: pnpm worker
  db:
    compose: ./docker-compose.yml`,
  },
];

type Token = { text: string; cls: string };

const CLS = {
  comment: "text-muted-foreground/40",
  key: "text-foreground/80",
  value: "text-green-500/70",
  punct: "text-muted-foreground/40",
  plain: "text-muted-foreground/70",
};

/** Minimal YAML line tokenizer — sufficient for the controlled samples above. */
function tokenizeLine(line: string): Token[] {
  if (line.trim() === "") return [{ text: " ", cls: CLS.plain }];

  const trimmed = line.trimStart();
  const indent = line.slice(0, line.length - trimmed.length);

  // whole-line comment
  if (trimmed.startsWith("#")) {
    return [{ text: line, cls: CLS.comment }];
  }

  const tokens: Token[] = [];
  if (indent) tokens.push({ text: indent, cls: CLS.plain });

  let rest = trimmed;

  // leading list dash
  if (rest.startsWith("- ")) {
    tokens.push({ text: "- ", cls: CLS.punct });
    rest = rest.slice(2);
  }

  // key: value
  const kv = rest.match(/^([\w.-]+)(:)(\s*)(.*)$/);
  if (kv) {
    const [, key, colon, space, value] = kv;
    tokens.push({ text: key, cls: CLS.key });
    tokens.push({ text: colon, cls: CLS.punct });
    if (space) tokens.push({ text: space, cls: CLS.plain });
    if (value) tokens.push({ text: value, cls: CLS.value });
    return tokens;
  }

  tokens.push({ text: rest, cls: CLS.plain });
  return tokens;
}

export function ConfigTabs({
  tabs = DEFAULT_TABS,
  className = "",
}: {
  tabs?: ConfigTab[];
  className?: string;
}) {
  const [active, setActive] = useState(0);
  const tab = tabs[active];
  const lines = tab.code.split("\n");

  return (
    <div
      className={`bg-terminal border border-terminal-border rounded-sm font-mono text-caption overflow-hidden ${className}`}
    >
      {/* header: filename + detection hint */}
      <div className="flex items-center justify-between px-4 py-2 border-b border-border">
        <span className="text-muted-foreground/50 text-[11px]">.hun.yml</span>
        <span className="text-muted-foreground/30 text-[10px]">
          detected: {tab.detected}
        </span>
      </div>

      {/* tabs */}
      <div className="flex gap-1 px-3 pt-3 pb-1">
        {tabs.map((t, i) => (
          <button
            key={t.label}
            onClick={() => setActive(i)}
            aria-pressed={i === active}
            className={`text-[11px] px-2 py-0.5 rounded-sm transition-colors cursor-pointer ${
              i === active
                ? "bg-muted text-foreground/80"
                : "text-muted-foreground/50 hover:text-muted-foreground"
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      {/* code */}
      <div className="px-4 py-3 overflow-x-auto">
        <AnimatePresence mode="wait">
          <motion.pre
            key={active}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.15 }}
            className="leading-relaxed"
          >
            {lines.map((line, li) => (
              <div key={li} className="whitespace-pre">
                {tokenizeLine(line).map((tok, ti) => (
                  <Fragment key={ti}>
                    <span className={tok.cls}>{tok.text}</span>
                  </Fragment>
                ))}
              </div>
            ))}
          </motion.pre>
        </AnimatePresence>
      </div>
    </div>
  );
}

export default ConfigTabs;
