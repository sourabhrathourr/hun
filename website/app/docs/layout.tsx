import type { ReactNode } from "react";
import { display, mono, text } from "@/components/site/fonts";
import { DocsShell } from "@/components/docs/docs-shell";
import { DOCS_BANNER_IMAGE } from "@/components/docs/docs-page-parts";
import { HUN_PRICE, hunCheckoutURL } from "@/lib/dodo";
import { source } from "@/lib/source";

// Portalled UI (the search dialog) renders outside `.docs-root`, so the font
// variables and the banner image are also set on <body> while the docs are open.
const docsVars = `body:has(.docs-root){--f-display:${display.style.fontFamily};--f-text:${text.style.fontFamily};--f-mono:${mono.style.fontFamily};--docs-banner:url(${DOCS_BANNER_IMAGE});}`;

export default function Layout({ children }: { children: ReactNode }) {
  return (
    <div className={`docs-root ${display.variable} ${text.variable} ${mono.variable}`}>
      <DocsShell tree={source.getPageTree()} checkoutURL={hunCheckoutURL} price={HUN_PRICE} styles={docsVars}>
        {children}
      </DocsShell>
    </div>
  );
}
