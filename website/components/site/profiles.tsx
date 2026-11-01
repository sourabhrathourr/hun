import type { ReactNode } from "react";
import { ProfileBoard } from "./scenes/ProfileBoard";

// Profiles: run just the part of a project you're working on. The picture is
// the window's profile menu, open, beside orbit's services.

const POINTS = [
  {
    title: "Only the difference",
    body: "Switching from ui to api stops the app and starts the backend. Nothing that stays gets restarted.",
  },
  {
    title: "Remembered",
    body: "Hun runs the last profile you picked, from the menu bar, the window or the terminal.",
  },
  {
    title: "Saved as you go",
    body: "Running a set of services you like? Save Running Services as Profile, and it’s in your .hun.yml.",
  },
];

function Code({ children }: { children: ReactNode }) {
  return <code className="hf-mono rounded-[5px] bg-[var(--code-bg)] px-[5px] py-[1px] text-[.86em]">{children}</code>;
}

export function ProfilesSection() {
  return (
    <section className="border-t border-[var(--line)] py-16 sm:py-40">
      <div className="mx-auto w-full max-w-[1248px] px-5 sm:px-8">
        <div className="grid gap-10 lg:grid-cols-12 lg:gap-8">
          <h2 className="hf-display text-balance text-[36px] font-bold leading-[1.02] tracking-[-0.03em] sm:text-[52px] lg:col-span-6">
            Run just the part you’re working on.
          </h2>
          <div className="min-w-0 max-w-[32rem] space-y-6 lg:col-span-5 lg:col-start-8 lg:pt-2">
            <p className="text-pretty text-[18px] leading-[1.6] text-[var(--ink-2)]">
              Most days you don’t need the whole stack. A profile is a named set of services. Pick one from the window, or
              run <Code>hun run orbit -p api</Code>, and Hun starts those services and whatever they depend on.
            </p>
            <pre className="hf-mono overflow-x-auto rounded-[14px] bg-[var(--raised)] px-5 py-4 text-[13px] leading-[1.75] shadow-[0_0_0_1px_var(--line)]">
              <span className="text-[var(--ink)]">profiles:</span>
              {"\n  "}
              <span className="text-[var(--ink)]">ui:</span> <span className="text-[var(--ink-3)]">[app]</span>
              {"\n  "}
              <span className="text-[var(--ink)]">api:</span> <span className="text-[var(--ink-3)]">[server, worker]</span>
              <span className="hidden text-[var(--ink-3)] opacity-70 sm:inline">{"   "}# postgres comes along</span>
              <span className="text-[var(--ink-3)] opacity-70 sm:hidden">{"\n  "}# postgres comes along</span>
            </pre>
          </div>
        </div>
      </div>

      <div className="mx-auto mt-14 w-full max-w-[1248px] px-5 sm:mt-20 sm:px-8">
        <figure
          aria-label="orbit's profiles: All services, ui and api. Choosing one stops and starts only the services that differ, postgres first."
          className="rounded-[22px] bg-[var(--tray)] bg-cover bg-center p-3 sm:rounded-[28px] sm:p-10 xl:p-16"
          style={{ backgroundImage: "var(--bg-wide, url(/site/bg/scene-wide.jpg))" }}
        >
          <ProfileBoard />
        </figure>
      </div>

      <div className="mx-auto w-full max-w-[1248px] px-5 sm:px-8">
        <dl className="mt-14 grid gap-10 sm:mt-16 md:grid-cols-3 md:gap-8">
          {POINTS.map((p) => (
            <div key={p.title} className="border-t border-[var(--line)] pt-6">
              <dt className="hf-display text-[19px] font-semibold tracking-[-0.01em]">{p.title}</dt>
              <dd className="mt-2 text-pretty text-[16px] leading-[1.55] text-[var(--ink-2)]">{p.body}</dd>
            </div>
          ))}
        </dl>
      </div>
    </section>
  );
}
