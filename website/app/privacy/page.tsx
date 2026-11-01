import type { Metadata } from "next";
import { LegalPage } from "@/components/site/legal";
import { pageMetadata } from "@/lib/og/meta";

export const metadata: Metadata = pageMetadata({
  title: "Privacy Policy · Hun",
  description: "How Hun handles product, website, and licensing data.",
  path: "/privacy",
});

export default function PrivacyPage() {
  return (
    <LegalPage
      title="Privacy Policy"
      page="Privacy"
      effective="1 November 2026"
      summary="Hun is designed around local development. This policy explains what stays on your Mac and what limited information leaves it."
      sections={[
        {
          id: "who",
          title: "Who operates Hun",
          body: (
            <p>
              Hun is developed and operated by Sourabh Rathour. This policy applies to hun.sh, the Hun macOS application,
              its licensing flow, and related support.
            </p>
          ),
        },
        {
          id: "local",
          title: "Data that stays local",
          body: (
            <p>
              Hun works with your local project folders, configuration, processes, ports, terminals, logs, Docker
              services, and Git repositories. This development data is processed on your Mac and is not uploaded to Hun by
              default. Hun does not currently include advertising or product analytics.
            </p>
          ),
        },
        {
          id: "licensing",
          title: "Licensing data",
          body: (
            <p>
              When you activate Hun, the app sends the license key and a device-identifying value to Dodo Payments to
              validate and activate the license. The app stores the license key in macOS Keychain and keeps limited
              activation state locally. Dodo Payments processes licensing, customer, checkout, tax, receipt, and payment
              information under its own privacy terms.
            </p>
          ),
        },
        {
          id: "website",
          title: "Website and download data",
          body: (
            <p>
              Hosting and infrastructure providers may process standard request information such as IP address, browser
              type, requested page, timestamp, and security logs. Application downloads are served through GitHub, which
              may process request information under its own terms.
            </p>
          ),
        },
        {
          id: "you-provide",
          title: "Information you provide",
          body: (
            <p>
              If you purchase a license or ask for support, we and our service providers may receive information such as
              your name, email address, license status, transaction reference, device activation status, and the content
              of your support request.
            </p>
          ),
        },
        {
          id: "use",
          title: "How information is used",
          body: (
            <ul>
              <li>to issue, validate, and manage licenses;</li>
              <li>to deliver downloads, updates, receipts, and support;</li>
              <li>to prevent fraud, misuse, and security incidents;</li>
              <li>to operate and improve the product; and</li>
              <li>to comply with legal and tax obligations.</li>
            </ul>
          ),
        },
        {
          id: "sharing",
          title: "Sharing and service providers",
          body: (
            <p>
              We do not sell personal information. Information may be shared with providers needed to operate Hun,
              including Dodo Payments for licensing and payments, GitHub for downloads and support, and website hosting
              providers. We may also disclose information when required by law or to protect users, the public, or the
              product.
            </p>
          ),
        },
        {
          id: "retention",
          title: "Retention and security",
          body: (
            <p>
              Information is retained only as long as needed for licensing, support, security, accounting, legal
              obligations, and legitimate product operations. We use reasonable technical and organizational safeguards,
              but no online system can guarantee absolute security.
            </p>
          ),
        },
        {
          id: "choices",
          title: "Your choices",
          body: (
            <p>
              You can stop local processing by quitting or uninstalling Hun. You may request access, correction, or
              deletion of personal information, subject to legal and transactional retention requirements, by emailing{" "}
              <a href="mailto:rathoursourabh5@gmail.com">rathoursourabh5@gmail.com</a>.
            </p>
          ),
        },
        {
          id: "changes",
          title: "Changes",
          body: (
            <p>
              We may update this policy as the product and its providers change. The effective date at the top of this
              page identifies the latest version.
            </p>
          ),
        },
      ]}
    />
  );
}
