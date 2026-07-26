"use client";

import { useState } from "react";

type BetaLicenseCardProps = {
  licenseKey: string;
};

export function BetaLicenseCard({ licenseKey }: BetaLicenseCardProps) {
  const [copied, setCopied] = useState(false);

  async function copyLicenseKey() {
    await navigator.clipboard.writeText(licenseKey);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1_600);
  }

  return (
    <div className="space-y-3 rounded-sm border border-border bg-muted/20 p-4">
      <p className="text-[11px] uppercase tracking-[0.16em] text-muted-foreground/45">
        your beta license
      </p>
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
        <code className="min-w-0 flex-1 overflow-x-auto whitespace-nowrap text-[13px] text-foreground/85">
          {licenseKey}
        </code>
        <button
          type="button"
          onClick={copyLicenseKey}
          className="h-8 shrink-0 rounded-sm border border-border px-3 text-[11px] text-foreground/75 transition-colors hover:bg-muted/40 hover:text-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground"
        >
          {copied ? "Copied" : "Copy key"}
        </button>
      </div>
    </div>
  );
}
