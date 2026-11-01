import { OG_CONTENT_TYPE, OG_SIZE, sceneCard } from "@/lib/og/og";

export const alt = "Refund Policy · Hun";
export const size = OG_SIZE;
export const contentType = OG_CONTENT_TYPE;

export default function Image() {
  return sceneCard({
    image: "/site/bg/hero-e.jpg",
    eyebrow: "Legal",
    title: "Refund Policy",
    description: "A full refund within 14 days of purchase. No questions asked.",
    address: "hun.sh/refund-policy",
  });
}
