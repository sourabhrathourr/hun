import { BetaLicenseCard } from "@/components/beta-license-card";
import type { Metadata } from "next";
import Link from "next/link";

const downloadURL =
  "https://github.com/sourabhrathourr/hun/releases/latest/download/hun-macos-arm64.dmg";

export const metadata: Metadata = {
  title: "Your Hun beta license",
  description: "Activate the free Hun public beta on your Mac.",
  robots: {
    index: false,
    follow: false,
  },
};

type BetaSuccessPageProps = {
  searchParams: Promise<{
    license_key?: string;
    status?: string;
  }>;
};

export default async function BetaSuccessPage({
  searchParams,
}: BetaSuccessPageProps) {
  const params = await searchParams;
  const licenseKey = params.license_key?.split(",")[0]?.trim();
  const succeeded =
    params.status === "succeeded" || params.status === "active";

  return (
    <div className="min-h-dvh bg-background px-5 py-10 text-foreground sm:px-6 sm:py-16">
      <main className="mx-auto w-full max-w-xl space-y-10">
        <nav className="flex items-center justify-between">
          <Link
            href="/"
            className="font-serif text-[24px] leading-none text-foreground hover:text-foreground/80"
          >
            hun.sh
          </Link>
          <span className="text-[11px] uppercase tracking-[0.16em] text-muted-foreground/40">
            public beta
          </span>
        </nav>

        <section className="space-y-6 border-t border-border pt-10">
          <div className="space-y-3">
            <h1 className="font-serif text-[42px] leading-[0.98] sm:text-[56px]">
              your beta access is ready.
            </h1>
            <p className="max-w-lg text-[14px] leading-relaxed text-muted-foreground/60">
              Download Hun, move it to Applications, then paste your license
              key into the activation screen. The public beta ends for everyone
              on 31 August 2026.
            </p>
          </div>

          {licenseKey ? (
            <BetaLicenseCard licenseKey={licenseKey} />
          ) : (
            <div className="rounded-sm border border-border bg-muted/20 p-4 text-[13px] leading-relaxed text-muted-foreground/60">
              {succeeded
                ? "Your key is being delivered. Check the email you used at checkout."
                : "We could not find a license key in this return link. Check your email for the Dodo Payments delivery message."}
            </div>
          )}

          <div className="flex flex-wrap items-center gap-3">
            <a
              href={downloadURL}
              className="inline-flex h-9 items-center rounded-sm bg-foreground px-3 text-[12px] font-medium text-background transition-opacity hover:opacity-85 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground"
            >
              Download Hun
            </a>
            <Link
              href="/"
              className="text-[12px] text-muted-foreground/50 underline underline-offset-2 hover:text-muted-foreground/75"
            >
              Back to hun.sh
            </Link>
          </div>
        </section>
      </main>
    </div>
  );
}
