import { OG_CONTENT_TYPE, OG_SIZE, sceneCard } from "@/lib/og/og";

export const alt = "Privacy Policy · Hun";
export const size = OG_SIZE;
export const contentType = OG_CONTENT_TYPE;

export default function Image() {
  return sceneCard({
    image: "/site/bg/hero-e.jpg",
    eyebrow: "Legal",
    title: "Privacy Policy",
    description: "What stays on your Mac, and the little that leaves it.",
    address: "hun.sh/privacy",
  });
}
