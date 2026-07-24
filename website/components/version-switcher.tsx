import Link from "next/link";

/**
 * VersionSwitcher — fixed bottom pill for flipping between landing page
 * explorations. Design-review tooling, not product UI: v2/v3 are noindexed.
 */

const VERSIONS = [
  { id: "v1", href: "/", label: "1" },
  { id: "v2", href: "/v2", label: "2" },
  { id: "v3", href: "/v3", label: "3" },
] as const;

export function VersionSwitcher({ current }: { current: "v1" | "v2" | "v3" }) {
  return (
    <div className="fixed bottom-4 right-4 z-50 flex items-center gap-1 rounded-full border border-border bg-background/80 px-2 py-1.5 shadow-[0_8px_32px_-12px_rgba(0,0,0,0.7)] backdrop-blur-md">
      <span className="px-1.5 font-mono text-[10px] text-muted-foreground/50">
        version
      </span>
      {VERSIONS.map((v) => (
        <Link
          key={v.id}
          href={v.href}
          aria-current={v.id === current ? "page" : undefined}
          className={`flex h-6 w-6 items-center justify-center rounded-full font-mono text-caption transition-colors ${
            v.id === current
              ? "bg-primary text-primary-foreground"
              : "text-muted-foreground hover:bg-muted/50 hover:text-foreground"
          }`}
        >
          {v.label}
        </Link>
      ))}
    </div>
  );
}

export default VersionSwitcher;
