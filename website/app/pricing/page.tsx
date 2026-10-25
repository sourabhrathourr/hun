import {
  MarketingFooter,
  MarketingNav,
} from "@/components/marketing-shell";
import { Reveal } from "@/components/reveal";
import {
  HUN_MAC_LIMIT,
  HUN_PRICE,
  hunBetaEndDateLong,
  hunCheckoutURL,
} from "@/lib/dodo";
import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Pricing — Hun",
  description:
    `Hun is ${HUN_PRICE} once: a lifetime license for the complete macOS app on up to ${HUN_MAC_LIMIT} Macs. No subscription.`,
  alternates: { canonical: "/pricing" },
  openGraph: {
    title: "Hun pricing — simple by design",
    description: `${HUN_PRICE} once, a lifetime license for up to ${HUN_MAC_LIMIT} Macs.`,
    url: "https://hun.sh/pricing",
  },
};

const included = [
  {
    title: "The complete macOS app",
    body: "No reduced tier and no locked product areas.",
  },
  {
    title: `${HUN_MAC_LIMIT} Mac activations`,
    body: "Use the same license on every Mac you work on.",
  },
  {
    title: "Every local workflow",
    body: "Projects, services, Git, terminals, logs, and Docker Compose.",
  },
  {
    title: "Updates inside the app",
    body: "Signed releases delivered securely through Sparkle.",
  },
];

const questions = [
  {
    question: "Is it a subscription?",
    answer: `No. Hun is a one-time ${HUN_PRICE} payment for a lifetime license.`,
  },
  {
    question: "How many Macs can I use it on?",
    answer: `Up to ${HUN_MAC_LIMIT}. To move Hun to a new Mac, deactivate it on an old one from Hun's settings.`,
  },
  {
    question: "What happens to the free public beta?",
    answer: `Beta licenses expire on ${hunBetaEndDateLong}. After that, buy a license to keep using Hun; your projects and settings stay on your Mac.`,
  },
  {
    question: "How are payments handled?",
    answer:
      "Dodo Payments handles checkout, taxes, receipts and payment support. Your license key appears after checkout and in your purchase email.",
  },
];

export default function PricingPage() {
  return (
    <div className="min-h-dvh bg-background px-5 py-8 text-foreground sm:px-6 sm:py-12">
      <main className="mx-auto w-full max-w-6xl">
        <Reveal>
          <MarketingNav />
        </Reveal>

        <header className="pb-12 pt-16 sm:pb-16 sm:pt-24">
          <Reveal delay={0.05}>
            <div className="grid gap-8 lg:grid-cols-[1fr_0.6fr] lg:items-end">
              <div>
                <p className="text-[11px] uppercase tracking-[0.18em] text-foreground/35">
                  Pricing
                </p>
                <h1 className="mt-4 max-w-4xl text-[42px] font-medium leading-[1.02] tracking-[-0.045em] sm:text-[64px]">
                  Everything in Hun.
                  <br />
                  One straightforward price.
                </h1>
              </div>
              <p className="max-w-xl text-[13px] leading-6 text-foreground/48 lg:justify-self-end sm:text-[14px]">
                One payment and Hun is yours: the complete app on up to{" "}
                {HUN_MAC_LIMIT} Macs. No subscription and no feature ladder.
              </p>
            </div>
          </Reveal>
        </header>

        <Reveal delay={0.1}>
          <section
            aria-labelledby="pricing-offer"
            className="marketing-surface rounded-[24px] p-2"
          >
            <h2 id="pricing-offer" className="sr-only">
              Hun pricing offer
            </h2>
            <div className="overflow-hidden rounded-[16px] bg-black/25">
              <div className="grid lg:grid-cols-[1.15fr_0.85fr]">
                <article className="p-6 sm:p-10 lg:border-r lg:border-white/[0.07] lg:p-12">
                  <div className="inline-flex items-center gap-2 rounded-full bg-emerald-400/[0.08] px-3 py-1.5 text-[11px] font-medium text-emerald-300/80 shadow-[0_0_0_1px_oklch(0.8_0.14_155/0.16)]">
                    <span className="size-1.5 rounded-full bg-emerald-300" />
                    Available now
                  </div>
                  <p className="mt-7 text-[12px] font-medium text-foreground/45">
                    Lifetime license
                  </p>
                  <div className="mt-3 flex flex-wrap items-end gap-x-4 gap-y-2">
                    <span className="text-[64px] font-medium leading-none tracking-[-0.055em] sm:text-[76px]">
                      {HUN_PRICE}
                    </span>
                    <span className="pb-2 text-[12px] leading-5 text-foreground/42">
                      one time
                      <br />
                      up to {HUN_MAC_LIMIT} Macs
                    </span>
                  </div>
                  <p className="mt-6 max-w-lg text-[12px] leading-6 text-foreground/48 sm:text-[13px]">
                    The complete app, with updates delivered inside Hun. Pay
                    once and keep using it.
                  </p>
                  <a
                    href={hunCheckoutURL}
                    className="mt-8 inline-flex h-11 items-center gap-2 rounded-lg bg-foreground pl-4 pr-3.5 text-[13px] font-medium text-background transition-[opacity,transform] duration-150 ease-out hover:opacity-[0.88] active:scale-[0.96] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground"
                  >
                    Buy Hun · {HUN_PRICE}
                    <ArrowIcon />
                  </a>
                </article>

                <article className="border-t border-white/[0.07] p-6 sm:p-10 lg:border-t-0 lg:p-12">
                  <p className="text-[10px] font-semibold uppercase tracking-[0.14em] text-foreground/32">
                    How it works
                  </p>
                  <ol className="mt-7 space-y-6">
                    {[
                      ["Buy", "Checkout takes a minute and shows your license key."],
                      ["Download", "Install Hun and move it to Applications."],
                      ["Activate", "Paste the key into Hun. It is also in your purchase email."],
                    ].map(([title, body], index) => (
                      <li key={title} className="flex gap-4">
                        <span className="pt-0.5 text-[10px] font-medium tabular-nums text-foreground/28">
                          0{index + 1}
                        </span>
                        <div>
                          <p className="text-[14px] font-medium tracking-[-0.02em] text-foreground/86">
                            {title}
                          </p>
                          <p className="mt-1 text-[11px] leading-5 text-foreground/42">
                            {body}
                          </p>
                        </div>
                      </li>
                    ))}
                  </ol>
                </article>
              </div>

              <div className="grid border-t border-white/[0.07] sm:grid-cols-2 lg:grid-cols-4">
                {included.map((item, index) => (
                  <article
                    key={item.title}
                    className={`p-5 sm:p-6 ${
                      index > 0
                        ? "border-t border-white/[0.07] sm:border-l sm:border-t-0"
                        : ""
                    } ${index === 2 ? "sm:border-t lg:border-t-0" : ""}`}
                  >
                    <div className="flex size-7 items-center justify-center rounded-full bg-emerald-400/[0.08] text-emerald-300/75 shadow-[0_0_0_1px_oklch(0.8_0.14_155/0.14)]">
                      <CheckIcon />
                    </div>
                    <h3 className="mt-4 text-[14px] font-medium tracking-[-0.02em] text-foreground/86">
                      {item.title}
                    </h3>
                    <p className="mt-2 text-[10px] leading-5 text-foreground/40">
                      {item.body}
                    </p>
                  </article>
                ))}
              </div>
            </div>
          </section>
        </Reveal>

        <section className="mt-28 grid gap-10 sm:mt-40 lg:grid-cols-[0.7fr_1.3fr]">
          <Reveal>
            <div>
              <p className="text-[11px] uppercase tracking-[0.18em] text-foreground/35">
                Questions
              </p>
              <h2 className="mt-4 text-[32px] font-medium leading-[1.04] tracking-[-0.035em] sm:text-[40px]">
                Clear before checkout.
              </h2>
            </div>
          </Reveal>
          <div className="divide-y divide-white/[0.07] border-y border-white/[0.07]">
            {questions.map((item, index) => (
              <Reveal
                key={item.question}
                delay={Math.min(index * 0.04, 0.12)}
              >
                <details className="marketing-faq group">
                  <summary className="flex min-h-16 cursor-pointer items-center justify-between gap-6 py-4 text-left focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-foreground">
                    <span className="text-[12px] font-medium text-foreground/72 sm:text-[13px]">
                      {item.question}
                    </span>
                    <span className="marketing-faq-icon flex size-8 shrink-0 items-center justify-center rounded-full bg-white/[0.04] text-[18px] font-light text-foreground/45 shadow-[0_0_0_1px_oklch(1_0_0/0.07)] transition-transform duration-150 ease-out">
                      +
                    </span>
                  </summary>
                  <p className="max-w-3xl pb-6 pr-12 text-[12px] leading-6 text-foreground/48 sm:text-[13px]">
                    {item.answer}
                  </p>
                </details>
              </Reveal>
            ))}
          </div>
        </section>

        <aside className="mt-16 rounded-xl bg-white/[0.025] p-5 text-[10px] leading-5 text-foreground/38 shadow-[0_0_0_1px_oklch(1_0_0/0.06)] sm:mt-24">
          Prices are shown in USD. Taxes may be added at checkout where
          applicable. Review the{" "}
          <Link
            href="/terms"
            className="inline-flex min-h-11 items-center text-foreground/62 underline underline-offset-4 transition-colors hover:text-foreground"
          >
            terms
          </Link>
          ,{" "}
          <Link
            href="/privacy"
            className="inline-flex min-h-11 items-center text-foreground/62 underline underline-offset-4 transition-colors hover:text-foreground"
          >
            privacy policy
          </Link>
          , and{" "}
          <Link
            href="/refund-policy"
            className="inline-flex min-h-11 items-center text-foreground/62 underline underline-offset-4 transition-colors hover:text-foreground"
          >
            refund policy
          </Link>{" "}
          before purchasing.
        </aside>

        <MarketingFooter />
      </main>
    </div>
  );
}

function ArrowIcon() {
  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 16 16"
      fill="none"
      className="size-3.5"
    >
      <path
        d="M3.5 8h9m-3.25-3.25L12.5 8l-3.25 3.25"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function CheckIcon() {
  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 16 16"
      fill="none"
      className="size-3.5"
    >
      <path
        d="m4 8.25 2.4 2.4L12.25 5"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
