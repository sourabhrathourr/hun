import type { MetadataRoute } from "next";

export default function sitemap(): MetadataRoute.Sitemap {
  const lastModified = new Date();
  return [
    ["", "weekly", 1],
    ["/macos", "weekly", 0.9],
    ["/changelog", "weekly", 0.8],
    ["/docs", "weekly", 0.8],
  ].map(([path, changeFrequency, priority]) => ({
    url: `https://hun.sh${path}`,
    lastModified,
    changeFrequency,
    priority,
  })) as MetadataRoute.Sitemap;
}
