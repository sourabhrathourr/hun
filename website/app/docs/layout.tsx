import { DocsLayout } from "fumadocs-ui/layouts/docs";
import { RootProvider } from "fumadocs-ui/provider/next";
import { source } from "@/lib/source";
import { GeistSans } from "geist/font/sans";
import type { ReactNode } from "react";

export default function Layout({ children }: { children: ReactNode }) {
  return (
    <div className={`${GeistSans.className} docs-root`}>
      <RootProvider theme={{ enabled: false }}>
        <DocsLayout
          tree={source.getPageTree()}
          nav={{
            title: "hun.sh",
          }}
          themeSwitch={{ enabled: false }}
        >
          {children}
        </DocsLayout>
      </RootProvider>
    </div>
  );
}
