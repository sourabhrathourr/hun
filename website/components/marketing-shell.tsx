import Link from "next/link";
import type { ReactNode } from "react";

const navItems = [
  { href: "/pricing", label: "pricing" },
  { href: "/changelog", label: "changelog" },
  { href: "/docs", label: "docs" },
];

export function MarketingNav() {
  return (
    <nav
      aria-label="Primary navigation"
      className="flex items-center justify-between gap-4"
    >
      <Link
        href="/"
        className="font-serif text-[26px] leading-none text-foreground transition-colors hover:text-foreground/75 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-foreground"
      >
        hun.sh
      </Link>
      <div className="flex items-center gap-1 text-[11px] text-muted-foreground/60 sm:gap-2 sm:text-[12px]">
        {navItems.map((item) => (
          <Link
            key={item.href}
            href={item.href}
            className="inline-flex h-11 items-center px-2 transition-colors hover:text-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground"
          >
            {item.label}
          </Link>
        ))}
        <a
          href="https://github.com/sourabhrathourr/hun"
          className="hidden h-11 items-center px-2 transition-colors hover:text-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground sm:inline-flex"
        >
          github
        </a>
      </div>
    </nav>
  );
}

export function MarketingFooter() {
  return (
    <footer className="mt-20 border-t border-border pb-6 pt-10 sm:mt-28">
      <div className="grid gap-10 sm:grid-cols-[1.4fr_repeat(3,1fr)]">
        <div className="max-w-xs space-y-3">
          <Link href="/" className="font-serif text-[24px] text-foreground">
            hun.sh
          </Link>
          <p className="text-[12px] leading-relaxed text-muted-foreground/55">
            A native macOS workspace for projects, services, terminals, Git,
            and logs.
          </p>
          <p className="text-[11px] leading-relaxed text-muted-foreground/35">
            Developed and operated by Sourabh Rathour.
          </p>
        </div>

        <FooterGroup
          title="Product"
          links={[
            ["/pricing", "Pricing"],
            ["/changelog", "Changelog"],
            ["/legacy", "CLI"],
          ]}
        />
        <FooterGroup
          title="Resources"
          links={[
            ["/docs", "Documentation"],
            ["https://github.com/sourabhrathourr/hun", "Source code"],
            [
              "https://github.com/sourabhrathourr/hun/issues",
              "Support",
            ],
          ]}
        />
        <FooterGroup
          title="Legal"
          links={[
            ["/terms", "Terms"],
            ["/privacy", "Privacy"],
            ["/refund-policy", "Refund policy"],
          ]}
        />
      </div>
      <div className="mt-10 flex flex-wrap items-center justify-between gap-3 border-t border-border/60 pt-5 text-[11px] text-muted-foreground/35">
        <span>© {new Date().getUTCFullYear()} hun.sh</span>
        <span>macOS 15+ · Apple silicon</span>
      </div>
    </footer>
  );
}

function FooterGroup({
  title,
  links,
}: {
  title: string;
  links: Array<[string, string]>;
}) {
  return (
    <div>
      <h2 className="text-[10px] font-semibold uppercase tracking-[0.16em] text-muted-foreground/40">
        {title}
      </h2>
      <ul className="mt-3 space-y-1 text-[12px] text-muted-foreground/55">
        {links.map(([href, label]) => (
          <li key={href}>
            {href.startsWith("http") ? (
              <a
                href={href}
                className="inline-flex min-h-8 items-center transition-colors hover:text-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground"
              >
                {label}
              </a>
            ) : (
              <Link
                href={href}
                className="inline-flex min-h-8 items-center transition-colors hover:text-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground"
              >
                {label}
              </Link>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}

export function LegalPage({
  eyebrow,
  title,
  summary,
  children,
}: {
  eyebrow: string;
  title: string;
  summary: string;
  children: ReactNode;
}) {
  return (
    <div className="min-h-dvh bg-background px-5 py-8 text-foreground sm:px-6 sm:py-12">
      <main className="mx-auto w-full max-w-5xl">
        <MarketingNav />
        <header className="border-b border-border pb-12 pt-16 sm:pb-16 sm:pt-24">
          <p className="text-[11px] uppercase tracking-[0.18em] text-muted-foreground/40">
            {eyebrow}
          </p>
          <h1 className="mt-4 max-w-3xl font-serif text-[48px] leading-[0.94] text-foreground sm:text-[72px]">
            {title}
          </h1>
          <p className="mt-6 max-w-2xl text-[14px] leading-7 text-muted-foreground/65 sm:text-[15px]">
            {summary}
          </p>
        </header>
        <article className="legal-copy mx-auto max-w-3xl py-12 sm:py-16">
          {children}
        </article>
        <MarketingFooter />
      </main>
    </div>
  );
}
