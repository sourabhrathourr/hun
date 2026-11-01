import type { Metadata } from "next";
import type { ReactNode } from "react";
import { Container, SitePage } from "@/components/site/chrome";
import { LicenseKey } from "@/components/site/license-key";
import { DOWNLOAD_URL } from "@/components/site/links";
import { HUN_MAC_LIMIT, HUN_PRICE, hunCheckoutURL } from "@/lib/dodo";
import Link from "next/link";

// Where Dodo's checkout returns after a purchase, with ?license_key= and
// ?status= on the URL. The key gets the stage: on a warm tray, copied for
// you, with the three steps to put it in Hun just below.

export const metadata: Metadata = {
  title: "Your Hun license",
  description: "Your Hun license key, and how to activate it on your Mac.",
  robots: { index: false, follow: false },
};

/** The tray's picture. */
const TRAY_IMAGE = "/site/bg/license-hero.jpg";
const SUPPORT_EMAIL = "rathoursourabh5@gmail.com";

type Props = { searchParams: Promise<{ license_key?: string; status?: string }> };

export default async function LicenseSuccessPage({ searchParams }: Props) {
  const params = await searchParams;
  const licenseKey = params.license_key?.split(",")[0]?.trim() || undefined;
  const status = params.status?.toLowerCase();
  const paid = Boolean(licenseKey) || status === "succeeded" || status === "active";
  const failed = !paid && (status === "failed" || status === "cancelled");

  return (
    <SitePage current="License">
      <main>
        <section className="pt-12 sm:pt-20">
          <Container className="text-center">
            {paid ? (
              <p className="inline-flex items-center gap-2 rounded-full bg-[rgba(62,123,79,.1)] px-3 py-1 text-[13.5px] font-medium text-[var(--run)]">
                <span className="size-1.5 rounded-full bg-[var(--run)]" aria-hidden />
                Payment received
              </p>
            ) : null}
            <h1 className="site-display mx-auto mt-6 max-w-[14ch] text-balance text-[48px] font-bold leading-[0.98] tracking-[-0.035em] sm:text-[72px] lg:text-[84px]">
              {failed ? "That didn’t go through." : paid ? "Hun is yours." : "Your Hun license."}
            </h1>
            <p className="mx-auto mt-6 max-w-[32rem] text-pretty text-[18px] leading-[1.55] text-[var(--ink-2)] sm:text-[20px]">
              {failed
                ? "Your payment wasn’t completed, so nothing was charged. You can try again whenever you like."
                : paid
                  ? "Thank you for buying Hun. Here’s your key. Three small steps and every dev server on your Mac is one click away."
                  : "Your license key is in the receipt email from Dodo Payments. Paste it into Hun when it asks."}
            </p>
          </Container>

          <Container className="mt-12 sm:mt-16">
            <div
              className="rounded-[22px] bg-[var(--tray)] bg-cover bg-center px-3 py-10 sm:rounded-[28px] sm:px-10 sm:py-24"
              style={{ backgroundImage: `url(${TRAY_IMAGE})` }}
            >
              <div className="site-card mx-auto max-w-[520px] rounded-[20px] bg-[var(--raised)] p-6 sm:p-9">
                {licenseKey ? (
                  <LicenseKey licenseKey={licenseKey} />
                ) : failed ? (
                  <Notice
                    title="Nothing was charged"
                    body="Checkout takes about a minute. Your key appears right here when it’s done."
                    action={
                      <a
                        href={hunCheckoutURL}
                        className="site-btn flex h-12 w-full items-center justify-center rounded-full bg-[var(--ink)] text-[15.5px] font-medium text-[var(--paper)]"
                      >
                        Try again · {HUN_PRICE}
                      </a>
                    }
                  />
                ) : (
                  <Notice
                    title={paid ? "Your key is on its way" : "Look for the receipt email"}
                    body={
                      <>
                        It comes from Dodo Payments to the email you used at checkout, usually within a minute. If it
                        isn’t in your inbox, check spam, or write to{" "}
                        <a href={`mailto:${SUPPORT_EMAIL}`} className="site-link font-medium text-[var(--ink)] underline decoration-[var(--line)]">
                          {SUPPORT_EMAIL}
                        </a>
                        .
                      </>
                    }
                  />
                )}
                <p className="mt-6 flex items-center justify-center gap-2 border-t border-[var(--line)] pt-5 text-center text-[13.5px] text-[var(--ink-3)]">
                  One key, up to {HUN_MAC_LIMIT} Macs. Every update included.
                </p>
              </div>
            </div>
          </Container>
        </section>

        {!failed && <Steps />}
        <Help />
      </main>
    </SitePage>
  );
}

function Notice({ title, body, action }: { title: string; body: ReactNode; action?: ReactNode }) {
  return (
    <div className="text-center">
      <p className="site-display text-[24px] font-semibold tracking-[-0.015em]">{title}</p>
      <p className="mx-auto mt-3 max-w-[34ch] text-pretty text-[16px] leading-[1.55] text-[var(--ink-2)]">{body}</p>
      {action ? <div className="mt-7">{action}</div> : null}
    </div>
  );
}

const STEPS: { title: string; body: ReactNode }[] = [
  {
    title: "Download Hun",
    body: "Open the disk image and drag Hun into Applications.",
  },
  {
    title: "Open it",
    body: "Hun lives in your menu bar. The first time it opens, it asks for your key.",
  },
  {
    title: "Paste and activate",
    body: "Paste the key and click Activate Hun. Then add your first project, or let your agent write its .hun.yml.",
  },
];

function Steps() {
  return (
    <section className="py-24 sm:py-36">
      <Container className="text-center">
        <h2 className="site-display mx-auto max-w-[16ch] text-balance text-[36px] font-bold leading-[1.02] tracking-[-0.03em] sm:text-[52px]">
          Now put it in Hun.
        </h2>
        <ol className="mt-14 grid gap-10 md:grid-cols-3 md:gap-8">
          {STEPS.map((s, i) => (
            <li key={s.title} className="border-t border-[var(--line)] pt-6">
              <span className="site-display inline-flex size-7 items-center justify-center rounded-full text-[13px] font-semibold text-[var(--accent)] shadow-[inset_0_0_0_1px_rgba(194,74,31,.4)]">
                {i + 1}
              </span>
              <h3 className="site-display mt-4 text-[22px] font-semibold tracking-[-0.015em]">{s.title}</h3>
              <p className="mx-auto mt-2 max-w-[32ch] text-pretty text-[16px] leading-[1.55] text-[var(--ink-2)]">{s.body}</p>
            </li>
          ))}
        </ol>
        <div className="mt-12 flex flex-wrap items-center justify-center gap-x-6 gap-y-4">
          <a
            href={DOWNLOAD_URL}
            className="site-btn inline-flex h-12 items-center gap-2.5 rounded-full bg-[var(--ink)] px-6 text-[15.5px] font-medium text-[var(--paper)]"
          >
            <AppleLogo />
            Download for Mac
          </a>
          <Link href="/docs/getting-started" className="site-link text-[15px] font-medium text-[var(--ink-2)]">
            Quick start
          </Link>
        </div>
        <p className="mt-4 text-[13.5px] text-[var(--ink-3)]">Apple silicon, macOS 15 or later.</p>
      </Container>
    </section>
  );
}

function Help() {
  const items: { q: string; a: ReactNode }[] = [
    {
      q: "Lost the key?",
      a: "It’s in the receipt email from Dodo Payments. Search your inbox for “Hun”.",
    },
    {
      q: "Changed your mind?",
      a: (
        <>
          Ask within 14 days for a full refund, no questions asked. See the{" "}
          <a href="/refund-policy" className="site-link font-medium text-[var(--ink)] underline decoration-[var(--line)]">
            refund policy
          </a>
          .
        </>
      ),
    },
    {
      q: "Stuck on something?",
      a: (
        <>
          Write to{" "}
          <a href={`mailto:${SUPPORT_EMAIL}`} className="site-link font-medium text-[var(--ink)] underline decoration-[var(--line)]">
            {SUPPORT_EMAIL}
          </a>{" "}
          and a real person answers.
        </>
      ),
    },
  ];
  return (
    <section className="border-t border-[var(--line)] py-20 sm:py-28">
      <Container className="grid gap-10 text-center md:grid-cols-3 md:gap-8">
        {items.map((it) => (
          <div key={it.q}>
            <h3 className="site-display text-[19px] font-semibold tracking-[-0.01em]">{it.q}</h3>
            <p className="mx-auto mt-2 max-w-[34ch] text-pretty text-[15.5px] leading-[1.55] text-[var(--ink-2)]">{it.a}</p>
          </div>
        ))}
      </Container>
    </section>
  );
}

function AppleLogo() {
  return (
    <svg width="14" height="17" viewBox="0 0 814 1000" aria-hidden className="-mt-[2px] shrink-0">
      <path
        fill="currentColor"
        d="M788 340c-6 4-108 62-108 190 0 148 130 200 134 202-1 3-21 72-69 142-43 62-88 124-156 124s-86-40-164-40c-77 0-104 41-167 41s-106-58-156-128C44 788 0 668 0 554 0 371 119 274 236 274c62 0 114 41 153 41 37 0 95-43 166-43 27 0 124 2 188 93zM554 159c29-35 50-83 50-131 0-7-1-14-2-19-48 2-104 32-138 72-27 30-52 78-52 127 0 7 1 15 2 17 3 1 8 1 12 1 43 0 97-29 128-67z"
      />
    </svg>
  );
}
