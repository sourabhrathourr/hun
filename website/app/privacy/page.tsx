import { LegalPage } from "@/components/marketing-shell";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Privacy Policy — Hun",
  description: "How Hun handles product, website, and licensing data.",
  alternates: { canonical: "/privacy" },
};

export default function PrivacyPage() {
  return (
    <LegalPage
      eyebrow="Effective 26 July 2026"
      title="Privacy Policy"
      summary="Hun is designed around local development. This policy explains what stays on your Mac and what limited information leaves it."
    >
      <h2>1. Who operates Hun</h2>
      <p>
        Hun is developed and operated by Sourabh Rathour. This policy applies
        to hun.sh, the Hun macOS application, its licensing flow, and related
        support.
      </p>

      <h2>2. Data that stays local</h2>
      <p>
        Hun works with your local project folders, configuration, processes,
        ports, terminals, logs, Docker services, and Git repositories. This
        development data is processed on your Mac and is not uploaded to Hun by
        default. Hun does not currently include advertising or product
        analytics.
      </p>

      <h2>3. Licensing data</h2>
      <p>
        When you activate Hun, the app sends the license key and a
        device-identifying value to Dodo Payments to validate and activate the
        license. The app stores the license key in macOS Keychain and keeps
        limited activation state locally. Dodo Payments processes licensing,
        customer, checkout, tax, receipt, and payment information under its own
        privacy terms.
      </p>

      <h2>4. Website and download data</h2>
      <p>
        Hosting and infrastructure providers may process standard request
        information such as IP address, browser type, requested page, timestamp,
        and security logs. Application downloads are served through GitHub,
        which may process request information under its own terms.
      </p>

      <h2>5. Information you provide</h2>
      <p>
        If you request a beta license, purchase a license, or ask for support,
        we and our service providers may receive information such as your name,
        email address, license status, transaction reference, device activation
        status, and the content of your support request.
      </p>

      <h2>6. How information is used</h2>
      <ul>
        <li>to issue, validate, and manage licenses;</li>
        <li>to deliver downloads, updates, receipts, and support;</li>
        <li>to prevent fraud, misuse, and security incidents;</li>
        <li>to operate and improve the product; and</li>
        <li>to comply with legal and tax obligations.</li>
      </ul>

      <h2>7. Sharing and service providers</h2>
      <p>
        We do not sell personal information. Information may be shared with
        providers needed to operate Hun, including Dodo Payments for licensing
        and payments, GitHub for downloads and support, and website hosting
        providers. We may also disclose information when required by law or to
        protect users, the public, or the product.
      </p>

      <h2>8. Retention and security</h2>
      <p>
        Information is retained only as long as needed for licensing, support,
        security, accounting, legal obligations, and legitimate product
        operations. We use reasonable technical and organizational safeguards,
        but no online system can guarantee absolute security.
      </p>

      <h2>9. Your choices</h2>
      <p>
        You can stop local processing by quitting or uninstalling Hun. You may
        request access, correction, or deletion of personal information,
        subject to legal and transactional retention requirements, through{" "}
        <a href="https://github.com/sourabhrathourr/hun/issues">
          Hun support on GitHub
        </a>
        .
      </p>

      <h2>10. Changes</h2>
      <p>
        We may update this policy as the product and its providers change. The
        effective date at the top of this page identifies the latest version.
      </p>
    </LegalPage>
  );
}
