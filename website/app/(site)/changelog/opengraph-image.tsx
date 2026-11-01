import releases from "@/content/changelog.json";
import { OG_CONTENT_TYPE, OG_SIZE, sceneCard } from "@/lib/og/og";

export const alt = "What's new in Hun.";
export const size = OG_SIZE;
export const contentType = OG_CONTENT_TYPE;

export default function Image() {
  const [latest] = releases;
  return sceneCard({
    image: "/site/bg/changelog-hero.jpg",
    eyebrow: "Changelog",
    badge: `v${latest.version} · Latest`,
    title: "What’s new in Hun.",
    description: latest.title,
    address: "hun.sh/changelog",
  });
}
