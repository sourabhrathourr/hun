import {
  MarketingFooter,
  MarketingNav,
} from "@/components/marketing-shell";
import { Reveal } from "@/components/reveal";
import { hunBetaCheckoutURL } from "@/lib/dodo";
import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Pricing — Hun",
  description:
    "Use the complete Hun macOS app free during public beta. A $15 lifetime license is planned for the paid release.",
  alternates: { canonical: "/pricing" },
  openGraph: {
    title: "Hun pricing — simple by design",
    description:
      "Free during public beta, then a planned $15 lifetime license for two Macs.",
    url: "https://hun.sh/pricing",
  },
};

const included = [
  {
    title: "The complete macOS app",
    body: "No reduced beta tier and no locked product areas.",
  },
  {
    title: "Two Mac activations",
    body: "Use the same license on your primary and secondary Mac.",
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
    question: "Is the beta feature-limited?",
    answer:
      "No. The public beta includes the complete product. The time limit applies to the beta license, not to individual features.",
  },
  {
    question: "When does the public beta end?",
    answer:
      "All public beta licenses expire together on 31 August 2026. We will explain the paid transition inside the app before that date.",
  },
  {
    question: "Is the paid license a subscription?",
    answer:
      "No. The planned price is a one-time $15 payment for a lifetime Hun license on up to two Macs.",
  },
  {
    question: "Will my projects or settings disappear after beta?",
    answer:
      "No. Hun's project configuration and local state remain on your Mac. After the beta license expires, you will need a paid license to continue using the app.",
  },
  {
    question: "How are payments handled?",
    answer:
      "Dodo Payments will provide checkout, tax handling, receipts, and payment support when paid access launches.",
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
                Use the complete app free during public beta. When beta ends,
                the plan is one affordable lifetime license—no recurring
                subscription and no feature ladder.
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
                    Public beta
                  </p>
                  <div className="mt-3 flex flex-wrap items-end gap-x-4 gap-y-2">
                    <span className="text-[64px] font-medium leading-none tracking-[-0.055em] sm:text-[76px]">
                      $0
                    </span>
                    <span className="pb-2 text-[12px] leading-5 text-foreground/42">
                      complete access
                      <br />
                      through 31 Aug 2026
                    </span>
                  </div>
                  <p className="mt-6 max-w-lg text-[12px] leading-6 text-foreground/48 sm:text-[13px]">
                    One shared beta period for everyone. Your free license works
                    on two Macs and unlocks the entire product until the public
                    beta ends.
                  </p>
                  {hunBetaCheckoutURL ? (
                    <a
                      href={hunBetaCheckoutURL}
                      className="mt-8 inline-flex h-11 items-center gap-2 rounded-lg bg-foreground pl-4 pr-3.5 text-[13px] font-medium text-background transition-[opacity,transform] duration-150 ease-out hover:opacity-[0.88] active:scale-[0.96] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground"
                    >
                      Get a free beta key
                      <ArrowIcon />
                    </a>
                  ) : (
                    <p className="mt-8 inline-flex min-h-11 items-center rounded-lg bg-white/[0.04] px-4 text-[12px] text-foreground/45 shadow-[0_0_0_1px_oklch(1_0_0/0.07)]">
                      Beta access opens after payment-account verification
                    </p>
                  )}
                </article>

                <article className="border-t border-white/[0.07] p-6 sm:p-10 lg:border-t-0 lg:p-12">
                  <p className="text-[10px] font-semibold uppercase tracking-[0.14em] text-foreground/32">
                    Planned after beta
                  </p>
                  <p className="mt-7 text-[12px] font-medium text-foreground/45">
                    Lifetime license
                  </p>
                  <div className="mt-3 flex flex-wrap items-end gap-x-4 gap-y-2">
                    <span className="text-[64px] font-medium leading-none tracking-[-0.055em] sm:text-[76px]">
                      $15
                    </span>
                    <span className="pb-2 text-[12px] leading-5 text-foreground/42">
                      one time
                      <br />
                      two Macs
                    </span>
                  </div>
                  <p className="mt-6 max-w-lg text-[12px] leading-6 text-foreground/48 sm:text-[13px]">
                    Keep the same complete app after beta. Paid checkout is not
                    open yet; the final offer will be confirmed before launch.
                  </p>
                  <span className="mt-8 inline-flex min-h-11 items-center rounded-lg bg-white/[0.04] px-4 text-[12px] text-foreground/42 shadow-[0_0_0_1px_oklch(1_0_0/0.07)]">
                    Available after beta
                  </span>
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

        <section className="mt-28 sm:mt-40">
          <Reveal>
            <div className="grid gap-8 lg:grid-cols-[0.75fr_1.25fr] lg:items-end">
              <div>
                <p className="text-[11px] uppercase tracking-[0.18em] text-foreground/35">
                  The transition
                </p>
                <h2 className="mt-4 max-w-xl text-[36px] font-medium leading-[1.02] tracking-[-0.04em] sm:text-[48px]">
                  Free now. Predictable later.
                </h2>
              </div>
              <p className="max-w-2xl text-[13px] leading-6 text-foreground/48 lg:justify-self-end sm:text-[14px]">
                The beta is for learning what Hun needs to become, not for
                hiding the price. Everyone receives the same access and the
                same deadline.
              </p>
            </div>
          </Reveal>

          <Reveal delay={0.06}>
            <ol className="mt-10 grid gap-px overflow-hidden rounded-[20px] bg-white/[0.07] shadow-[0_18px_60px_-40px_oklch(0_0_0/0.9)] sm:grid-cols-3">
              {[
                [
                  "01",
                  "Join the beta",
                  "Download Hun and activate a free key on up to two Macs.",
                ],
                [
                  "02",
                  "Use everything",
                  "No beta-only tier. Every current workflow is included.",
                ],
                [
                  "03",
                  "Choose at launch",
                  "Buy the planned lifetime license only if Hun earns its place.",
                ],
              ].map(([number, title, body]) => (
                <li key={number} className="bg-[#0a0a0a] p-6 sm:p-7">
                  <span className="text-[10px] font-medium text-foreground/28">
                    {number}
                  </span>
                  <h3 className="mt-10 text-[17px] font-medium tracking-[-0.025em] text-foreground/88">
                    {title}
                  </h3>
                  <p className="mt-3 text-[11px] leading-5 text-foreground/42">
                    {body}
                  </p>
                </li>
              ))}
            </ol>
          </Reveal>
        </section>

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
