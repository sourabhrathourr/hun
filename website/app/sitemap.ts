import type { MetadataRoute } from "next";
import { source } from "@/lib/source";

export default function sitemap(): MetadataRoute.Sitemap {
  const docsEntries: MetadataRoute.Sitemap = source.getPages().map((page) => ({
    url: `https://hun.sh${page.url}`,
    lastModified: new Date(),
    changeFrequency: "weekly",
    priority: 0.8,
  }));

  return [
    {
      url: "https://hun.sh",
      lastModified: new Date(),
      changeFrequency: "weekly",
      priority: 1,
    },
    {
      url: "https://hun.sh/macos",
      lastModified: new Date(),
      changeFrequency: "weekly",
      priority: 0.9,
    },
    ...docsEntries,
  ];
}
