import type { MetadataRoute } from "next";

export default function sitemap(): MetadataRoute.Sitemap {
  const lastModified = new Date();
  return [
    ["", "weekly", 1],
    ["/pricing", "monthly", 0.9],
    ["/changelog", "weekly", 0.8],
    ["/docs", "weekly", 0.8],
    ["/legacy", "monthly", 0.4],
    ["/terms", "yearly", 0.3],
    ["/privacy", "yearly", 0.3],
    ["/refund-policy", "yearly", 0.3],
  ].map(([path, changeFrequency, priority]) => ({
    url: `https://hun.sh${path}`,
    lastModified,
    changeFrequency,
    priority,
  })) as MetadataRoute.Sitemap;
}
