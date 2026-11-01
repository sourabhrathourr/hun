import type { Metadata } from "next";

/**
 * A page's title and description, also as its link preview. The preview
 * image comes from the page's opengraph-image file (or the home page's).
 */
export function pageMetadata({ title, description, path }: { title: string; description: string; path: string }): Metadata {
  return {
    title,
    description,
    alternates: { canonical: path },
    openGraph: { type: "website", siteName: "Hun", url: path, title, description },
    twitter: { card: "summary_large_image", title, description },
  };
}
