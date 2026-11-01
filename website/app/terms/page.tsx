import type { Metadata } from "next";
import { LegalPage } from "@/components/site/legal";
import { HUN_MAC_LIMIT, HUN_PRICE } from "@/lib/dodo";
import { pageMetadata } from "@/lib/og/meta";

export const metadata: Metadata = pageMetadata({
  title: "Terms of Use · Hun",
  description: "Terms governing access to and use of Hun.",
  path: "/terms",
});

export default function TermsPage() {
  return (
    <LegalPage
      title="Terms of Use"
      page="Terms"
      effective="1 November 2026"
      summary="These terms govern your use of the Hun website, macOS application, bundled runtime, and related services."
      sections={[
        {
          id: "agreement",
          title: "Agreement",
          body: (
            <p>
              By downloading, activating, or using Hun, you agree to these terms. If you do not agree, do not use the
              product. “Hun,” “we,” and “us” refer to the Hun product developed and operated by Sourabh Rathour.
            </p>
          ),
        },
        {
          id: "product",
          title: "The product",
          body: (
            <p>
              Hun is a native macOS app for running and managing local development projects: their processes, ports,
              terminals, logs, Docker Compose services, and Git branches. Hun runs commands and modifies files only in
              response to features and actions you use. You remain responsible for your projects, source code, commands,
              services, and backups.
            </p>
          ),
        },
        {
          id: "paid-licenses",
          title: "Paid licenses",
          body: (
            <p>
              A paid license is a one-time purchase of {HUN_PRICE} (plus any applicable tax) for use on up to{" "}
              {HUN_MAC_LIMIT} Macs. The price and checkout terms are shown before any payment is taken. Dodo Payments acts
              as the checkout and payment provider for paid purchases.
            </p>
          ),
        },
        {
          id: "license",
          title: "License and acceptable use",
          body: (
            <>
              <p>
                Subject to these terms and a valid license, we grant you a limited, non-exclusive, non-transferable right
                to install and use the distributed Hun application for your own personal or business development work.
              </p>
              <p>You must not:</p>
              <ul>
                <li>share, sell, or sublicense a personal license key;</li>
                <li>circumvent activation, device, or access controls;</li>
                <li>use Hun to violate law or the rights of another person; or</li>
                <li>interfere with the website, licensing service, or other users.</li>
              </ul>
              <p>
                Source code and third-party components made available under open-source licenses remain governed by their
                respective licenses.
              </p>
            </>
          ),
        },
        {
          id: "updates",
          title: "Updates and compatibility",
          body: (
            <p>
              Hun may install or offer signed application updates. We may change, add, or remove features as the product
              develops. Hun currently requires macOS 15 or later on Apple silicon. We do not promise compatibility with
              every project, dependency, command, or future operating-system release.
            </p>
          ),
        },
        {
          id: "warranties",
          title: "Availability and warranties",
          body: (
            <p>
              To the maximum extent allowed by law, Hun is provided “as is” and “as available,” without warranties of
              uninterrupted operation, merchantability, fitness for a particular purpose, or non-infringement. Nothing in
              these terms limits rights that cannot legally be excluded.
            </p>
          ),
        },
        {
          id: "liability",
          title: "Limitation of liability",
          body: (
            <p>
              To the maximum extent allowed by law, we are not liable for indirect, incidental, special, consequential, or
              punitive losses, or for loss of code, data, revenue, or business opportunity arising from your use of Hun.
              You are responsible for reviewing commands and maintaining appropriate source control and backups.
            </p>
          ),
        },
        {
          id: "termination",
          title: "Suspension and termination",
          body: (
            <p>
              We may suspend or revoke access where a license is fraudulent, shared in breach of these terms, used to
              evade technical controls, or associated with unlawful or abusive activity. You may stop using Hun at any
              time by removing the app and its local data.
            </p>
          ),
        },
        {
          id: "changes",
          title: "Changes to these terms",
          body: (
            <p>
              We may update these terms as Hun develops. Material changes will be published here with a new effective
              date. Continued use after a change means you accept the updated terms.
            </p>
          ),
        },
        {
          id: "contact",
          title: "Contact",
          body: (
            <p>
              Questions about these terms can be sent to{" "}
              <a href="mailto:rathoursourabh5@gmail.com">rathoursourabh5@gmail.com</a>.
            </p>
          ),
        },
      ]}
    />
  );
}
