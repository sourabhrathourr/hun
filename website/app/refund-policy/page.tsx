import { LegalPage } from "@/components/marketing-shell";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Refund Policy — Hun",
  description: "Refund information for Hun beta and future paid licenses.",
  alternates: { canonical: "/refund-policy" },
};

export default function RefundPolicyPage() {
  return (
    <LegalPage
      eyebrow="Effective 26 July 2026"
      title="Refund Policy"
      summary="The public beta is free. This page explains how refunds will work when paid Hun licenses become available."
    >
      <h2>1. Public beta</h2>
      <p>
        Hun&apos;s public beta is provided without charge through 31 August
        2026. Because no payment is taken for beta access, there is no beta
        purchase to refund.
      </p>

      <h2>2. Paid licenses</h2>
      <p>
        Paid checkout is not currently open. Before paid licenses launch, the
        checkout page and this policy will show the final price and any
        time-based refund eligibility that applies. You will be able to review
        those terms before paying.
      </p>

      <h2>3. Faulty or misdescribed product</h2>
      <p>
        If a paid version of Hun does not work as described, contact support
        with your transaction reference and a clear description of the issue.
        Requests will be reviewed in line with applicable consumer law and
        Dodo Payments&apos; checkout and refund process. This policy does not
        limit rights that cannot legally be excluded.
      </p>

      <h2>4. Effect of a refund</h2>
      <p>
        If a paid license is refunded, its license key and associated device
        activations may be revoked. You should stop using the paid product after
        the refund is completed.
      </p>

      <h2>5. Requesting help</h2>
      <p>
        Submit billing or product questions through{" "}
        <a href="https://github.com/sourabhrathourr/hun/issues">
          Hun support on GitHub
        </a>
        . Do not include a full license key, payment-card number, identity
        document, or other sensitive information in a public issue.
      </p>
    </LegalPage>
  );
}
