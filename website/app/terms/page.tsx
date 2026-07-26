import { LegalPage } from "@/components/marketing-shell";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Terms of Use — Hun",
  description: "Terms governing access to and use of Hun.",
  alternates: { canonical: "/terms" },
};

export default function TermsPage() {
  return (
    <LegalPage
      eyebrow="Effective 26 July 2026"
      title="Terms of Use"
      summary="These terms govern your use of the Hun website, macOS application, bundled runtime, and related services."
    >
      <h2>1. Agreement</h2>
      <p>
        By downloading, activating, or using Hun, you agree to these terms. If
        you do not agree, do not use the product. “Hun,” “we,” and “us” refer to
        the Hun product developed and operated by Sourabh Rathour.
      </p>

      <h2>2. The product</h2>
      <p>
        Hun is a native macOS workspace for managing local development
        projects, processes, ports, terminals, logs, Docker Compose services,
        and Git workflows. Hun runs commands and modifies files only in
        response to features and actions you use. You remain responsible for
        your projects, source code, commands, services, and backups.
      </p>

      <h2>3. Beta access</h2>
      <p>
        The public beta is provided without charge and is scheduled to end on
        31 August 2026. A valid beta license key is required, may be activated
        on up to two Macs, and expires at the shared beta end date. Beta
        software may contain defects or change before general availability.
        We may modify, suspend, or end beta access when reasonably necessary.
      </p>

      <h2>4. Paid licenses</h2>
      <p>
        Paid licenses are not yet available. The currently planned offer is a
        $15 one-time license for use on up to two Macs. Final price, scope, and
        checkout terms will be displayed before any payment is taken. Dodo
        Payments will act as the checkout and payment provider for paid
        purchases.
      </p>

      <h2>5. License and acceptable use</h2>
      <p>
        Subject to these terms and a valid license, we grant you a limited,
        non-exclusive, non-transferable right to install and use the
        distributed Hun application for your own personal or business
        development work.
      </p>
      <p>You must not:</p>
      <ul>
        <li>share, sell, or sublicense a personal license key;</li>
        <li>circumvent activation, device, or access controls;</li>
        <li>use Hun to violate law or the rights of another person; or</li>
        <li>interfere with the website, licensing service, or other users.</li>
      </ul>
      <p>
        Source code and third-party components made available under open-source
        licenses remain governed by their respective licenses.
      </p>

      <h2>6. Updates and compatibility</h2>
      <p>
        Hun may install or offer signed application updates. We may change,
        add, or remove features as the product develops. Hun currently requires
        macOS 15 or later on Apple silicon. We do not promise compatibility
        with every project, dependency, command, or future operating-system
        release.
      </p>

      <h2>7. Availability and warranties</h2>
      <p>
        To the maximum extent allowed by law, Hun is provided “as is” and “as
        available,” without warranties of uninterrupted operation,
        merchantability, fitness for a particular purpose, or non-infringement.
        Nothing in these terms limits rights that cannot legally be excluded.
      </p>

      <h2>8. Limitation of liability</h2>
      <p>
        To the maximum extent allowed by law, we are not liable for indirect,
        incidental, special, consequential, or punitive losses, or for loss of
        code, data, revenue, or business opportunity arising from your use of
        Hun. You are responsible for reviewing commands and maintaining
        appropriate source control and backups.
      </p>

      <h2>9. Suspension and termination</h2>
      <p>
        We may suspend or revoke access where a license is fraudulent, shared
        in breach of these terms, used to evade technical controls, or
        associated with unlawful or abusive activity. You may stop using Hun
        at any time by removing the app and its local data.
      </p>

      <h2>10. Changes to these terms</h2>
      <p>
        We may update these terms as Hun develops. Material changes will be
        published here with a new effective date. Continued use after a change
        means you accept the updated terms.
      </p>

      <h2>11. Contact</h2>
      <p>
        Questions about these terms can be submitted through{" "}
        <a href="https://github.com/sourabhrathourr/hun/issues">
          Hun support on GitHub
        </a>
        .
      </p>
    </LegalPage>
  );
}
