import { OG_CONTENT_TYPE, OG_SIZE, sceneCard } from "@/lib/og/og";

export const alt = "Terms of Use · Hun";
export const size = OG_SIZE;
export const contentType = OG_CONTENT_TYPE;

export default function Image() {
  return sceneCard({
    image: "/site/bg/hero-e.jpg",
    eyebrow: "Legal",
    title: "Terms of Use",
    description: "These terms govern your use of the Hun website, macOS application, and related services.",
    address: "hun.sh/terms",
  });
}
