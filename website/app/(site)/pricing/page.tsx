import type { Metadata } from "next";
import type { ReactNode } from "react";
import { HUN_MAC_LIMIT, HUN_PRICE, hunCheckoutURL } from "@/lib/dodo";
import { Container, SitePage } from "@/components/site/chrome";
import { DOWNLOAD_URL } from "@/components/site/links";
import { HunMark } from "@/components/site/hun-mark";
import { pageMetadata } from "@/lib/og/meta";

// Direction F's pricing page: one price on a warm tray, how you get it, and
// the questions people ask before paying. Same paper, type and colour as F.

export const metadata: Metadata = pageMetadata({
  title: "Pricing · Hun",
  description: `Hun is ${HUN_PRICE}, once. One key works on ${HUN_MAC_LIMIT} Macs, and every update is included.`,
  path: "/pricing",
});

const css = `
.hp {
  --paper: #F5F0E6;
  --raised: #FFFCF6;
  --ink: #1F1B16;
  --ink-2: #4F483F;
  --ink-3: #6E675C;
  --line: rgba(31, 27, 22, .1);
  --accent: #C24A1F;
  --run: #3E7B4F;
  --tray: #EAE2D2;
  --code-bg: rgba(31, 27, 22, .06);
  background: var(--paper);
  color: var(--ink);
  font-family: var(--f-text), ui-sans-serif, system-ui, sans-serif;
  -webkit-font-smoothing: antialiased;
}
.hp ::selection { background: rgba(194, 74, 31, .18); }
.hp-display { font-family: var(--f-display), ui-sans-serif, system-ui, sans-serif; font-variation-settings: "opsz" 96; }
.hp-mono { font-family: var(--f-mono), ui-monospace, monospace; font-variant-ligatures: none; }
.hp-btn { transition: transform 160ms cubic-bezier(.23, 1, .32, 1), opacity 160ms ease; }
.hp-btn:active { transform: scale(.97); }
@media (hover: hover) { .hp-btn:hover { opacity: .9; } }
.hp-link { text-decoration-line: underline; text-decoration-color: transparent; text-underline-offset: 4px; transition: text-decoration-color 160ms ease, color 160ms ease; }
@media (hover: hover) { .hp-link:hover { text-decoration-color: currentColor; color: var(--ink); } }
.hp-card { box-shadow: 0 0 0 .5px rgba(31, 27, 22, .2), 0 1px 2px rgba(31, 27, 22, .05), 0 40px 80px -36px rgba(64, 44, 16, .45), 0 14px 28px -18px rgba(64, 44, 16, .2); }
.hp-faq summary { list-style: none; cursor: pointer; }
.hp-faq summary::-webkit-details-marker { display: none; }
.hp-faq .hp-plus { transition: transform 200ms cubic-bezier(.23, 1, .32, 1); }
.hp-faq[open] .hp-plus { transform: rotate(45deg); }
@media (prefers-reduced-motion: reduce) { .hp-faq .hp-plus, .hp-btn { transition: none; } }
`;

const INCLUDED = [
  `Use it on up to ${HUN_MAC_LIMIT} Macs`,
  "Every update, delivered in the app",
  "The menu bar app and the full window",
  "A skill for Claude Code, Codex and Cursor",
  "Your money back within 14 days",
];

const STEPS: { title: string; body: ReactNode }[] = [
  { title: "Buy", body: "Checkout takes a minute. Your license key appears right after, and in your email." },
  { title: "Install", body: <><a href={DOWNLOAD_URL} className="hp-link font-medium text-[var(--ink)] underline decoration-[var(--line)]">Download Hun</a> and move it to Applications. Hun lives in your menu bar from then on.</> },
  { title: "Paste the key", body: "Open Hun, paste the key, and add your first project. Your agent can write its .hun.yml." },
];

const FAQ: { q: string; a: ReactNode }[] = [
  { q: "Is it a subscription?", a: <>No. You pay {HUN_PRICE} once and the license is yours. Updates are included.</> },
  {
    q: `Can I use it on more than one Mac?`,
    a: <>Yes, on up to {HUN_MAC_LIMIT}. To move Hun to a new Mac, deactivate it on an old one from Hun’s settings.</>,
  },
  {
    q: "Does Hun need the internet?",
    a: "Only to check your license now and then. If you’re offline, Hun keeps working for three days before it asks to check again. Your projects and logs never leave your Mac.",
  },
  {
    q: "Can I get a refund?",
    a: (
      <>
        Yes. Ask within 14 days of purchase and you’ll get a full refund, no questions asked. See the{" "}
        <a href="/refund-policy" className="hp-link underline decoration-[var(--line)]">
          refund policy
        </a>
        .
      </>
    ),
  },
  {
    q: "I was in the beta. What now?",
    a: "The beta ended on 31 October. Buy a license and paste the new key into Hun; your projects and settings are still there. If you’re on an older version, update Hun first (Hun menu → Check for Updates…).",
  },
  {
    q: "Who handles the payment?",
    a: "Dodo Payments runs the checkout and handles taxes, receipts and payment support. Your license key appears after checkout and in your purchase email.",
  },
  { q: "Which Macs does it run on?", a: "Macs with Apple silicon (M1 or later) running macOS 15 or later." },
];

export default function PricingF() {
  return (
    <SitePage current="Pricing" className="hp">
      <style>{css}</style>
      <main>
        <Hero />
        <HowYouGetIt />
        <Questions />
      </main>
    </SitePage>
  );
}



function Hero() {
  return (
    <section className="pt-12 sm:pt-20">
      <Container>
        <h1 className="hp-display max-w-[14ch] text-balance text-[44px] font-bold leading-[0.98] tracking-[-0.035em] sm:text-[64px] lg:text-[80px]">
          One price. Yours to keep.
        </h1>
        <p className="mt-6 max-w-[34rem] text-pretty text-[18px] leading-[1.55] text-[var(--ink-2)] sm:text-[20px]">
          Hun is {HUN_PRICE}, once. One key works on {HUN_MAC_LIMIT} Macs, and every update is included. No subscription, no tiers.
        </p>
      </Container>

      <Container className="mt-12 sm:mt-16">
        <div
          className="rounded-[28px] bg-[var(--tray)] bg-cover bg-center px-5 py-10 sm:px-10 sm:py-20"
          style={{ backgroundImage: "url(/site/bg/pricing-hero.jpg)" }}
        >
          <div className="mx-auto max-w-[460px]">
            <PriceCard />
          </div>
        </div>
      </Container>
    </section>
  );
}

function PriceCard() {
  return (
    <div className="hp-card rounded-[20px] bg-[var(--raised)] p-7 sm:p-9">
      <div className="flex items-center gap-2.5">
        <HunMark size={26} />
        <p className="hp-display text-[17px] font-semibold tracking-[-0.01em]">Hun for Mac</p>
      </div>
      <p className="mt-8 flex items-baseline gap-3">
        <span className="hp-display text-[72px] font-bold leading-none tracking-[-0.045em]">{HUN_PRICE}</span>
        <span className="text-[15px] text-[var(--ink-3)]">once, not monthly</span>
      </p>
      <ul className="mt-8 space-y-3 border-t border-[var(--line)] pt-7">
        {INCLUDED.map((item) => (
          <li key={item} className="flex items-start gap-3 text-[15.5px] leading-[1.45]">
            <svg width="16" height="16" viewBox="0 0 16 16" aria-hidden className="mt-[3px] shrink-0 text-[var(--run)]">
              <path d="M3.5 8.4 6.6 11.4 12.5 4.8" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
            {item}
          </li>
        ))}
      </ul>
      <a
        href={hunCheckoutURL}
        className="hp-btn mt-9 flex h-12 w-full items-center justify-center rounded-full bg-[var(--ink)] text-[15.5px] font-medium text-[var(--paper)]"
      >
        Buy Hun · {HUN_PRICE}
      </a>
      <p className="mt-4 text-center text-[13px] text-[var(--ink-3)]">Apple silicon, macOS 15 or later. Checkout by Dodo Payments.</p>
      <p className="mt-6 border-t border-[var(--line)] pt-5 text-center text-[14px] text-[var(--ink-2)]">
        Already have a key?{" "}
        <a href={DOWNLOAD_URL} className="hp-link font-medium text-[var(--ink)] underline decoration-[var(--line)]">
          Download Hun
        </a>
      </p>
    </div>
  );
}

function HowYouGetIt() {
  return (
    <section className="py-28 sm:py-36">
      <Container>
        <h2 className="hp-display max-w-[18ch] text-balance text-[36px] font-bold leading-[1.02] tracking-[-0.03em] sm:text-[52px]">
          Running in three minutes.
        </h2>
        <ol className="mt-14 grid gap-10 md:grid-cols-3 md:gap-8">
          {STEPS.map((s, i) => (
            <li key={s.title} className="border-t border-[var(--line)] pt-6">
              <span className="hp-display inline-flex size-7 items-center justify-center rounded-full text-[13px] font-semibold text-[var(--accent)] shadow-[inset_0_0_0_1px_rgba(194,74,31,.4)]">
                {i + 1}
              </span>
              <h3 className="hp-display mt-4 text-[22px] font-semibold tracking-[-0.015em]">{s.title}</h3>
              <p className="mt-2 max-w-[30ch] text-pretty text-[16px] leading-[1.55] text-[var(--ink-2)]">{s.body}</p>
            </li>
          ))}
        </ol>
      </Container>
    </section>
  );
}

function Questions() {
  return (
    <section className="border-t border-[var(--line)] py-28 sm:py-36">
      <Container className="grid gap-12 lg:grid-cols-12 lg:gap-8">
        <div className="lg:col-span-4">
          <h2 className="hp-display text-balance text-[36px] font-bold leading-[1.02] tracking-[-0.03em] sm:text-[52px]">Questions</h2>
          <p className="mt-5 max-w-[22rem] text-pretty text-[16px] leading-[1.55] text-[var(--ink-2)]">
            Something else? Write to{" "}
            <a href="mailto:rathoursourabh5@gmail.com" className="hp-link underline decoration-[var(--line)]">
              support
            </a>{" "}
            and you’ll hear back from the person who builds Hun.
          </p>
        </div>
        <div className="border-t border-[var(--line)] lg:col-span-8">
          {FAQ.map((item) => (
            <details key={item.q} className="hp-faq border-b border-[var(--line)]">
              <summary className="flex items-center justify-between gap-6 py-5">
                <span className="hp-display text-[18px] font-semibold tracking-[-0.01em] sm:text-[19px]">{item.q}</span>
                <span className="hp-plus flex size-8 shrink-0 items-center justify-center rounded-full text-[20px] font-light text-[var(--ink-2)] shadow-[inset_0_0_0_1px_var(--line)]">
                  +
                </span>
              </summary>
              <div className="max-w-[40rem] pb-6 pr-12 text-pretty text-[16px] leading-[1.6] text-[var(--ink-2)]">{item.a}</div>
            </details>
          ))}
        </div>
      </Container>
    </section>
  );
}

