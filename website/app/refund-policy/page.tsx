import { LegalPage } from "@/components/marketing-shell";
import { hunBetaEndDateLong } from "@/lib/dodo";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Refund Policy — Hun",
  description: "Refunds for Hun licenses: a full refund within 14 days of purchase.",
  alternates: { canonical: "/refund-policy" },
};

export default function RefundPolicyPage() {
  return (
    <LegalPage
      eyebrow="Effective 25 October 2026"
      title="Refund Policy"
      summary="If Hun isn't right for you, ask for a refund within 14 days of purchase and you'll get your money back. No questions asked."
    >
      <h2>1. Public beta</h2>
      <p>
        Hun&apos;s public beta is provided without charge through{" "}
        {hunBetaEndDateLong}. Because no payment is taken for beta access, there
        is no beta purchase to refund.
      </p>

      <h2>2. Paid licenses</h2>
      <p>
        You can ask for a full refund of a Hun license within 14 days of
        purchase, for any reason. You don&apos;t need to explain why. Refunds
        go back to the original payment method through Dodo Payments; how long
        they take to appear depends on your bank or card provider.
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
        To ask for a refund, email{" "}
        <a href="mailto:rathoursourabh5@gmail.com">rathoursourabh5@gmail.com</a>{" "}
        with the payment ID from your receipt. For other product questions, use{" "}
        <a href="https://github.com/sourabhrathourr/hun/issues">
          Hun support on GitHub
        </a>
        . Do not include a full license key, payment-card number, identity
        document, or other sensitive information in a public issue.
      </p>
    </LegalPage>
  );
}
