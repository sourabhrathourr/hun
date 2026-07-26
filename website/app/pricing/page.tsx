import {
  MarketingFooter,
  MarketingNav,
} from "@/components/marketing-shell";
import { hunBetaCheckoutURL } from "@/lib/dodo";
import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Pricing — Hun",
  description:
    "Use the complete Hun macOS app free during public beta. A $15 lifetime license is planned for the paid release.",
  alternates: { canonical: "/pricing" },
  openGraph: {
    title: "Hun pricing — one product, one honest price",
    description:
      "Free during public beta, then a planned $15 lifetime license for two Macs.",
    url: "https://hun.sh/pricing",
  },
};

const included = [
  "The complete native macOS app",
  "Project switching and service control",
  "Persistent project terminals and live logs",
  "Git status, diffs, branches, and commits",
  "Updates delivered inside the app",
  "Activation on up to two Macs",
];

const questions = [
  [
    "Is the beta feature-limited?",
    "No. The public beta includes the complete product. The time limit applies to the beta license, not to individual features.",
  ],
  [
    "When does the public beta end?",
    "All public beta licenses expire together on 31 August 2026. We will explain the paid transition inside the app before that date.",
  ],
  [
    "Is the paid license a subscription?",
    "No. The planned price is a one-time $15 payment for a lifetime Hun license on up to two Macs.",
  ],
  [
    "Will my projects or settings disappear after beta?",
    "No. Hun's project configuration and local state remain on your Mac. After the beta license expires, you will need a paid license to continue using the app.",
  ],
  [
    "How are payments handled?",
    "Dodo Payments will provide checkout, tax handling, receipts, and payment support when paid access launches.",
  ],
];

export default function PricingPage() {
  return (
    <div className="min-h-dvh bg-background px-5 py-8 text-foreground sm:px-6 sm:py-12">
      <main className="mx-auto w-full max-w-5xl">
        <MarketingNav />

        <header className="border-b border-border pb-12 pt-16 sm:pb-16 sm:pt-24">
          <p className="text-[11px] uppercase tracking-[0.18em] text-muted-foreground/40">
            Pricing
          </p>
          <h1 className="mt-4 max-w-4xl font-serif text-[52px] leading-[0.92] sm:text-[80px]">
            One product.
            <br />
            One honest price.
          </h1>
          <p className="mt-6 max-w-2xl text-[14px] leading-7 text-muted-foreground/65 sm:text-[15px]">
            Use every part of Hun free during the public beta. When beta ends,
            the plan is a single lifetime license—no feature ladder and no
            recurring subscription.
          </p>
        </header>

        <section
          aria-labelledby="pricing-options"
          className="grid border-b border-border sm:grid-cols-2"
        >
          <h2 id="pricing-options" className="sr-only">
            Pricing options
          </h2>
          <article className="border-b border-border py-10 sm:border-b-0 sm:border-r sm:pr-10">
            <p className="text-[10px] uppercase tracking-[0.18em] text-muted-foreground/40">
              Available now
            </p>
            <h3 className="mt-4 font-serif text-[36px]">Public beta</h3>
            <p className="mt-6 flex items-baseline gap-2">
              <span className="font-serif text-[64px] leading-none">$0</span>
              <span className="text-[12px] text-muted-foreground/50">
                through 31 Aug 2026
              </span>
            </p>
            <p className="mt-5 max-w-sm text-[13px] leading-6 text-muted-foreground/60">
              One shared beta period for everyone. A license key is required
              and expires when the public beta ends.
            </p>
            {hunBetaCheckoutURL ? (
              <a
                href={hunBetaCheckoutURL}
                className="mt-8 inline-flex h-11 items-center rounded-sm bg-foreground px-4 text-[12px] font-medium text-background transition-opacity hover:opacity-85 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground"
              >
                Get a beta license
              </a>
            ) : (
              <p className="mt-8 text-[12px] text-muted-foreground/50">
                Beta access will open after payment-account verification.
              </p>
            )}
          </article>

          <article className="py-10 sm:pl-10">
            <p className="text-[10px] uppercase tracking-[0.18em] text-muted-foreground/40">
              Planned after beta
            </p>
            <h3 className="mt-4 font-serif text-[36px]">Lifetime</h3>
            <p className="mt-6 flex items-baseline gap-2">
              <span className="font-serif text-[64px] leading-none">$15</span>
              <span className="text-[12px] text-muted-foreground/50">
                one time
              </span>
            </p>
            <p className="mt-5 max-w-sm text-[13px] leading-6 text-muted-foreground/60">
              Keep using Hun after the beta on up to two Macs. Paid checkout is
              not open yet; the final offer will be confirmed before launch.
            </p>
            <span className="mt-8 inline-flex h-11 items-center rounded-sm border border-border px-4 text-[12px] text-muted-foreground/50">
              Available after beta
            </span>
          </article>
        </section>

        <section className="grid gap-10 border-b border-border py-12 sm:grid-cols-[0.8fr_1.2fr] sm:py-16">
          <div>
            <p className="text-[10px] uppercase tracking-[0.18em] text-muted-foreground/40">
              Included
            </p>
            <h2 className="mt-4 font-serif text-[38px] leading-none sm:text-[48px]">
              The same complete app.
            </h2>
          </div>
          <ul className="grid gap-x-8 sm:grid-cols-2">
            {included.map((item) => (
              <li
                key={item}
                className="flex gap-3 border-t border-border py-4 text-[12px] leading-5 text-foreground/75"
              >
                <span aria-hidden="true" className="text-emerald-400/70">
                  ✓
                </span>
                {item}
              </li>
            ))}
          </ul>
        </section>

        <section className="grid gap-10 py-12 sm:grid-cols-[0.8fr_1.2fr] sm:py-16">
          <div>
            <p className="text-[10px] uppercase tracking-[0.18em] text-muted-foreground/40">
              Details
            </p>
            <h2 className="mt-4 font-serif text-[38px] leading-none sm:text-[48px]">
              Clear before checkout.
            </h2>
          </div>
          <div className="divide-y divide-border border-y border-border">
            {questions.map(([question, answer]) => (
              <article key={question} className="py-6">
                <h3 className="text-[14px] font-medium text-foreground/85">
                  {question}
                </h3>
                <p className="mt-2 text-[12px] leading-6 text-muted-foreground/60 sm:text-[13px]">
                  {answer}
                </p>
              </article>
            ))}
          </div>
        </section>

        <aside className="border border-border p-5 text-[11px] leading-5 text-muted-foreground/45">
          Prices are shown in USD. Taxes may be added at checkout where
          applicable. Review the{" "}
          <Link href="/terms" className="underline underline-offset-4">
            terms
          </Link>
          ,{" "}
          <Link href="/privacy" className="underline underline-offset-4">
            privacy policy
          </Link>
          , and{" "}
          <Link href="/refund-policy" className="underline underline-offset-4">
            refund policy
          </Link>{" "}
          before purchasing.
        </aside>

        <MarketingFooter />
      </main>
    </div>
  );
}
