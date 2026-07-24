# hun.sh Website Audit

Audit of `website/` as of 2026-07-12 (branch `main`, clean tree). Compiled to plan the landing page redesign.

---

## 1. Project structure

- **Framework:** Next.js **16.1.6** with the **App Router** (`app/` directory), React 19.2.3, TypeScript 5 (strict).
- **Package manager:** **Bun** in practice — the only lockfile is `bun.lock`. Note the contradiction: `package.json` declares `"packageManager": "yarn@1.22.22"`, but there is no `yarn.lock`. Treat bun as the source of truth.
- **Docs engine:** Fumadocs (fumadocs-core / fumadocs-mdx / fumadocs-ui v16) compiling MDX from `content/docs/` via the `.source/` generated directory (gitignored, regenerated at build).

### Directory tree (2 levels)

```
website/
├── app/
│   ├── api/            # OG image routes + font binaries
│   ├── docs/           # docs layout + catch-all page
│   ├── macos/          # macOS beta page
│   ├── favicon.ico
│   ├── globals.css
│   ├── layout.tsx
│   ├── page.tsx        # landing page
│   ├── robots.ts
│   └── sitemap.ts
├── components/
│   ├── ui/             # 13 shadcn components (ALL UNUSED — see §4)
│   ├── install-button.tsx
│   ├── mini-tui.tsx
│   ├── reveal.tsx
│   └── terminal.tsx
├── content/
│   └── docs/           # 11 MDX files + meta.json
├── lib/
│   ├── source.ts
│   └── utils.ts
├── public/             # install scripts, favicon.svg, macos screenshot
├── .source/            # fumadocs-mdx generated (gitignored)
├── components.json     # shadcn config
├── mdx-components.tsx
├── next.config.ts
├── postcss.config.mjs
├── source.config.ts
├── eslint.config.mjs
├── tsconfig.json
├── package.json / bun.lock
└── README.md           # untouched create-next-app boilerplate
```

### Every file, one line each

| File | Purpose |
|---|---|
| `app/layout.tsx` | Root layout: global metadata/OG/Twitter, forces `class="dark"` + `color-scheme: dark`, links `favicon.svg`. |
| `app/page.tsx` | The landing page — single-column, prose-driven (see §8). |
| `app/globals.css` | Tailwind v4 entry, font imports, full CSS-variable theme, scrollbar/selection styles, docs overrides. |
| `app/robots.ts` | Generates `robots.txt` (allow all, points at sitemap). |
| `app/sitemap.ts` | Generates `sitemap.xml` — **only lists `https://hun.sh`**; `/macos` and `/docs/*` are missing. |
| `app/favicon.ico` | Fallback favicon. |
| `app/macos/page.tsx` | macOS app beta page: hero, screenshot, install command, 4 feature blurbs. |
| `app/docs/layout.tsx` | Wraps docs in fumadocs `DocsLayout` + `RootProvider` (theme switch disabled), applies Geist Sans. |
| `app/docs/[[...slug]]/page.tsx` | Optional catch-all rendering MDX docs pages; `generateStaticParams` + per-page OG metadata. |
| `app/api/og/route.tsx` | Dynamic OG image (satori/`next/og`, nodejs runtime): home card + `?type=docs` variant, supports `w`/`h`/`scale` params. |
| `app/api/og/macos/route.tsx` | OG image for `/macos`, embeds `public/macos-image.png` as base64. |
| `app/api/og/*.ttf/.woff/.woff2` | Font binaries (JetBrains Mono, Instrument Serif) read from disk by the OG routes. |
| `components/reveal.tsx` | Framer-motion fade/blur-in wrapper with `delay` prop. |
| `components/install-button.tsx` | Clipboard-copy button with check-icon feedback. |
| `components/terminal.tsx` | Animated fake terminal with 3 tab-switchable command sequences. |
| `components/mini-tui.tsx` | Interactive mock of the hun TUI (projects, services, streaming logs, keyboard nav). |
| `components/ui/*.tsx` (13 files) | shadcn "base-nova" components — alert-dialog, badge, button, card, combobox, dropdown-menu, field, input, input-group, label, select, separator, textarea. **None are imported anywhere.** |
| `lib/source.ts` | Fumadocs loader: mounts `content/docs` at `/docs`. |
| `lib/utils.ts` | `cn()` (clsx + tailwind-merge). |
| `mdx-components.tsx` | Exposes fumadocs default MDX components. |
| `source.config.ts` | fumadocs-mdx collection config (`dir: content/docs`). |
| `content/docs/*.mdx` (11) | Docs pages: index, install, getting-started, concepts, workflow, configuration, tui, commands, changelog, architecture, troubleshooting. |
| `content/docs/meta.json` | Sidebar order with section separators (Getting Started / Core Concepts / Reference). |
| `public/install.sh` | POSIX CLI installer (downloads release binary from GitHub, `HUN_REPO` overridable). |
| `public/install-macos-beta.sh` | macOS beta app installer (downloads zip from a pinned GitHub release, SHA-256 verified, installs `/Applications/hun.app`). |
| `public/favicon.svg` | Tiny inline SVG: dark rounded square with a monospace "h". |
| `public/macos-image.png` | macOS app screenshot (~740 KB) used on `/macos` and its OG image. |
| `components.json` | shadcn config: style `base-nova`, phosphor icons, neutral base color, CSS variables. |
| `next.config.ts` | Wraps config with fumadocs `createMDX()`; allows remote images from `res.cloudinary.com`. |
| `postcss.config.mjs` | Single plugin: `@tailwindcss/postcss` (Tailwind v4). |
| `eslint.config.mjs` | Next.js core-web-vitals + TS flat config. |
| `tsconfig.json` | Strict TS, `@/*` path alias, alias for the generated `fumadocs-mdx:collections/*`. |
| `README.md` | Unmodified create-next-app boilerplate. |

---

## 2. Routing

File-based App Router. Full route map:

| Route | Source | Renders |
|---|---|---|
| `/` | `app/page.tsx` | Landing page (server component composing client components). |
| `/macos` | `app/macos/page.tsx` | macOS app beta page. |
| `/docs` and `/docs/{slug}` | `app/docs/[[...slug]]/page.tsx` | Fumadocs-rendered MDX; optional catch-all so `/docs` itself serves `index.mdx`. Statically generated via `generateStaticParams`. 11 pages: `/docs`, `/docs/install`, `/docs/getting-started`, `/docs/concepts`, `/docs/workflow`, `/docs/configuration`, `/docs/tui`, `/docs/commands`, `/docs/changelog`, `/docs/architecture`, `/docs/troubleshooting`. |
| `/api/og` | `app/api/og/route.tsx` | Dynamic OG image (home card, or docs card with `?type=docs&title=…&description=…`; `w`/`h`/`scale` resizing). |
| `/api/og/macos` | `app/api/og/macos/route.tsx` | Static-design OG image for the macOS page. |
| `/robots.txt`, `/sitemap.xml` | `app/robots.ts`, `app/sitemap.ts` | Metadata routes. |

No middleware, no rewrites/redirects, no other API routes.

---

## 3. Styling

- **Approach:** **Tailwind CSS v4** (CSS-first config — there is **no `tailwind.config.*` file**; everything lives in `app/globals.css` via `@import "tailwindcss"` + `@theme inline`). Utility classes inline in JSX throughout. `cn()` helper exists but the landing components mostly use template strings.
- **Extra CSS layers imported in `globals.css`:** `tw-animate-css`, `shadcn/tailwind.css`, `fumadocs-ui/css/neutral.css` + `preset.css`, and the two font packages.
- **Theme tokens:** full shadcn-style CSS variable set on `:root` in **oklch** — `--background: oklch(0.145 0 0)` (near-black), `--foreground: oklch(0.985 0 0)` (near-white), plus card/popover/primary/secondary/muted/accent/destructive/border/input/ring/chart-1..5/sidebar-* and `--radius: 0.625rem` (with sm→4xl derived radii). All greys are achromatic (chroma 0) except destructive and chart colors.
- **Fonts in theme:** `--font-sans: 'JetBrains Mono Variable', monospace` — i.e. **the site's "sans" is actually a monospace font**. `--font-serif: 'Instrument Serif', serif` (used for the `hun.sh` wordmark and macOS headings). Docs override to Geist Sans via `GeistSans.className` on `.docs-root`.
- **Base layer:** all elements get `border-border outline-ring/50`; custom thin scrollbar; inverted white-on-black `::selection`.
- **Docs overrides:** `.docs-root` bumps prose to 1rem/1.75 and makes the fumadocs sidebar match the page background with no border.
- **Dark mode:** effectively **dark-only**. `<html class="dark" style="color-scheme: dark">` is hard-coded in the root layout, `@custom-variant dark (&:is(.dark *))` is defined, fumadocs theme switch is disabled (`themeSwitch: {enabled: false}`, `theme: {enabled: false}`), and `theme-color`/`color-scheme` meta are set to dark. There is only one `:root` variable block — no light palette exists.
- Two hard-coded hex colors escape the token system: the terminal/TUI panels use `bg-[#12110f]` / `border-[#1f1d1a]` (a warm near-black distinct from the neutral background).

---

## 4. Components

### Landing components (`components/`)

| Component | Path | Renders | Props | Interactive? |
|---|---|---|---|---|
| `Reveal` | `components/reveal.tsx` | Motion div fading children in from `opacity: 0, blur(4px)` over 0.4s. | `children`, `delay?: number` | Client, animation-only (no user interaction). |
| `InstallButton` | `components/install-button.tsx` | Clipboard icon button; swaps to a green check for 2s after copying. | `copyText: string` | Yes — click to copy. |
| `Terminal` | `components/terminal.tsx` | Fake terminal panel with 3 tabs ("focus mode", "multitask mode", "status"); lines fade in sequentially at 200ms intervals, hard-coded output for `hun switch` / `hun run` / `hun status`. | none (data hard-coded in file) | Yes — tab buttons restart the animation. |
| `MiniTui` | `components/mini-tui.tsx` | Mock of the hun TUI: top bar with project tabs (letraz/novara), services sidebar with green status dots and ports, log pane with timestamped lines animating in, status bar with keybinding hints. | none (2 projects + all logs hard-coded in file) | Yes — click project tabs and services; focusable with keyboard nav (↑/↓/j/k select service, Tab cycles projects). The `/` search and `r` restart hints in the status bar are **decorative — not implemented**. |

Shared/reusable: `Reveal` and `InstallButton` (used on both `/` and `/macos`). One-off: `Terminal`, `MiniTui` (landing page only).

### `components/ui/` — 13 shadcn components, all dead code

alert-dialog, badge, button, card, combobox, dropdown-menu, field, input, input-group, label, select, separator, textarea (~1,585 lines total). A repo-wide grep finds **zero imports** of `@/components/ui/*` outside the folder itself. They were scaffolded via shadcn (base-nova style, Base UI primitives, phosphor icons) but never wired in. Safe to delete or ignore during the redesign; they pull in `@base-ui/react` and `class-variance-authority` as their only consumers.

---

## 5. Assets & content

- **Fonts:**
  - **JetBrains Mono Variable** (`@fontsource-variable/jetbrains-mono`) — self-hosted variable font, the site-wide body font.
  - **Instrument Serif 400** (`@fontsource/instrument-serif`) — self-hosted static weight, display/wordmark font.
  - **Geist Sans** (`geist` package) — docs section only.
  - Standalone binaries in `app/api/og/` (jetbrains-mono.ttf/.woff2, instrument-serif.woff) loaded off disk for OG rendering (satori can't use CSS fonts). All fonts are local; no external font requests.
- **Images/icons:** `public/favicon.svg` (inline "h" mark), `app/favicon.ico`, `public/macos-image.png` (~740 KB screenshot, rendered via `next/image` with blur placeholder). Icons come from `@phosphor-icons/react` (only `Clipboard` and `Check` are used). `next.config.ts` allows Cloudinary remote images — used by docs MDX content (e.g. `index.mdx` embeds an `<img>`), not by any page component.
- **Animation:** **framer-motion** only (`Reveal`, `Terminal`, `MiniTui` use `motion` + `AnimatePresence`). `tw-animate-css` is imported in globals but its classes aren't used by first-party code (shadcn components reference it).
- **Content storage:** landing and macOS page copy is **inline in JSX** (macOS page has a small `details` array constant). Terminal/TUI demo data is hard-coded constants inside the components. Docs content lives separately as MDX in `content/docs/`. Install scripts in `public/` are served as-is at `hun.sh/install.sh` and `hun.sh/install-macos-beta.sh`.

---

## 6. Dependencies

### dependencies

| Package | Used for | Status |
|---|---|---|
| `next` 16.1.6, `react` / `react-dom` 19.2.3 | Framework. | Current. |
| `fumadocs-core` / `fumadocs-mdx` / `fumadocs-ui` | Docs engine, MDX pipeline, docs UI. | Used. |
| `@types/mdx` | MDX typings for `mdx-components.tsx`. | Used (arguably a devDependency). |
| `framer-motion` | All animations. | Used. |
| `@fontsource-variable/jetbrains-mono`, `@fontsource/instrument-serif` | Self-hosted fonts. | Used. |
| `geist` | Docs font. | Used (docs only). |
| `@phosphor-icons/react` | Copy-button icons (2 icons). | Used, minimally. |
| `clsx`, `tailwind-merge` | `cn()` helper. | `cn()` is only consumed by the dead `components/ui/*` — effectively unused by live code. |
| `tw-animate-css` | Animation utilities imported in globals. | **Unused by live code** (shadcn-only). |
| `@base-ui/react` | Primitives for `components/ui/*`. | **Unused** (dead code only). |
| `class-variance-authority` | Variants in `components/ui/*`. | **Unused** (dead code only). |
| `shadcn` | The shadcn CLI **installed as a runtime dependency**, plus `shadcn/tailwind.css` import in globals. | Misplaced — CLI belongs in devDependencies (or run via `bunx`); the CSS import only matters for the dead ui components. |

### devDependencies

`@tailwindcss/postcss` + `tailwindcss` v4, `typescript` 5, `eslint` 9 + `eslint-config-next`, `@types/*` — all used, all current.

### Flags

- **Removable if you delete `components/ui/`:** `@base-ui/react`, `class-variance-authority`, `shadcn`, `tw-animate-css`, and possibly `clsx`/`tailwind-merge` (keep `cn()` if the redesign will use it).
- **packageManager field says yarn, lockfile is bun** — worth fixing to avoid CI/deploy ambiguity.
- README is untouched boilerplate.

---

## 7. Build & deploy

- **Scripts:** `dev` → `next dev`, `build` → `next build` (fumadocs-mdx generates `.source/` as part of the MDX plugin), `start` → `next start`, `lint` → `eslint`.
- **Environment variables:** **none** referenced anywhere in app code (`process.env` appears nowhere in `app/`, `components/`, `lib/`, or configs). The shell scripts in `public/` read `HUN_REPO`, `HUN_MACOS_BETA_URL`, `HUN_MACOS_BETA_SHA256` — but those are consumed by the end user's shell, not the build.
- **Deployment target:** nothing pins it explicitly (no `vercel.json`, no `.vercel/` dir; `.gitignore` has a `.vercel` entry from the create-next-app template). Absolute URLs are hard-coded to `https://hun.sh`. The OG routes use `runtime = "nodejs"` with `fs.readFile`, so the host must support Node serverless functions — Vercel-shaped, and everything else is static/SSG.
- **Server-side surface:** the only runtime code is the two OG image routes. Everything else pre-renders.

---

## 8. Current landing page anatomy (`app/page.tsx`)

Single centered column, `max-w-xl` (~576 px), dark background, 14–15 px monospace body text. Every section is wrapped in `<Reveal>` with staggered delays (0, 0.1, 0.2, … 1.0 s), so the page fades in top-to-bottom with a blur effect on load. Order:

1. **Header / install** (`Reveal` delay 0) — `hun.sh` wordmark in Instrument Serif (30–42 px), then `brew tap hundotsh/tap` as plain text and a highlighted `brew install hun` code chip with an `InstallButton` that copies the combined tap+install command.
2. **One-line pitch** (0.1 s) — paragraph: CLI for seamless project context switching; services, ports, logs; one command.
3. **`<MiniTui />`** (0.2 s) — the interactive TUI mock (§4): two fake projects (letraz, novara), clickable services, animated log lines, keyboard navigation, keybinding hint bar.
4. **Scenario paragraph** (0.3 s) — the letraz/novara two-project story ("picture yourself ctrl+c-ing through six terminal tabs… you lose context, hun preserves it").
5. **`<Terminal />`** (0.4 s) — animated terminal with three tabs: *focus mode* (`hun switch letraz`), *multitask mode* (`hun run novara` with port offsets), *status* (`hun status` table). Lines type in at 200 ms intervals; switching tabs crossfades and replays.
6. **Commands paragraph** (0.5 s) — explains `hun init` / `hun switch` / `hun run` with inline code chips.
7. **Daemon paragraph** (0.6 s) — background daemon, process groups, output capture, "close your laptop, come back, everything's still there."
8. **Stack badges** (0.7 s) — bordered pill row: node, go, python, docker compose, monorepos, hybrid stacks (static).
9. **tmux disclaimer** (0.8 s) — "not a tmux replacement… use both."
10. **macOS beta card** (0.9 s) — bordered card linking to `/macos`, with the `curl … install-macos-beta.sh | sh` command and a copy button.
11. **Footer links** (1.0 s) — docs · macOS app beta · github (`github.com/sourabhrathourr/hun`) · built by sourabh rathour (`sourabh.fun`).

**Interactive elements on the page:** the two copy buttons, the Terminal's three tab buttons, and the MiniTui (project tabs, service list clicks, focus + arrow/j/k/Tab keys). Everything else is static prose. There is no nav/header on `/` — navigation exists only as footer links (the `/macos` page does have a small top nav).

### Redesign notes (things to be aware of before changing)

- The whole visual identity is: dark-only, monospace body, serif wordmark, near-invisible borders, low-contrast muted text with opacity modifiers (`text-muted-foreground/50` etc.) — tokens live entirely in `globals.css`.
- `sitemap.ts` only lists the homepage; `/macos` and docs pages should be added regardless of redesign.
- `components/ui/` (13 files) and 4–6 dependencies are dead weight you can drop or finally use.
- The OG image at `/api/og` visually mirrors the current landing design (wordmark + brew command + fake status panel) — a redesign should update it to match.
- Demo data (projects letraz/novara) is duplicated across `Terminal`, `MiniTui`, and the scenario paragraph — if the redesign keeps the narrative, consider a single shared data module.
