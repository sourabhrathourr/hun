import type { Metadata } from "next";
import { LegalPage } from "@/components/site/legal";
import { pageMetadata } from "@/lib/og/meta";

export const metadata: Metadata = pageMetadata({
  title: "Refund Policy · Hun",
  description: "Refunds for Hun licenses: a full refund within 14 days of purchase.",
  path: "/refund-policy",
});

export default function RefundPolicyPage() {
  return (
    <LegalPage
      title="Refund Policy"
      page="Refunds"
      effective="1 November 2026"
      summary="If Hun isn't right for you, ask for a refund within 14 days of purchase and you'll get your money back. No questions asked."
      sections={[
        {
          id: "paid-licenses",
          title: "Paid licenses",
          body: (
            <p>
              You can ask for a full refund of a Hun license within 14 days of purchase, for any reason. You don&apos;t
              need to explain why. Refunds go back to the original payment method through Dodo Payments; how long they
              take to appear depends on your bank or card provider.
            </p>
          ),
        },
        {
          id: "faulty-product",
          title: "Faulty or misdescribed product",
          body: (
            <p>
              If a paid version of Hun does not work as described, contact support with your transaction reference and a
              clear description of the issue. Requests will be reviewed in line with applicable consumer law and Dodo
              Payments&apos; checkout and refund process. This policy does not limit rights that cannot legally be
              excluded.
            </p>
          ),
        },
        {
          id: "effect",
          title: "Effect of a refund",
          body: (
            <p>
              If a paid license is refunded, its license key and associated device activations may be revoked. You should
              stop using the paid product after the refund is completed.
            </p>
          ),
        },
        {
          id: "requesting",
          title: "Requesting a refund",
          body: (
            <p>
              To ask for a refund, email <a href="mailto:rathoursourabh5@gmail.com">rathoursourabh5@gmail.com</a> with the
              payment ID from your receipt. For other product questions, use{" "}
              <a href="https://github.com/sourabhrathourr/hun/issues">Hun support on GitHub</a>. Do not include a full
              license key, payment-card number, identity document, or other sensitive information in a public issue.
            </p>
          ),
        },
      ]}
    />
  );
}
