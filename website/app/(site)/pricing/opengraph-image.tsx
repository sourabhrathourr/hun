import { HUN_MAC_LIMIT, HUN_PRICE } from "@/lib/dodo";
import { OG_CONTENT_TYPE, OG_SIZE, PriceFeature, sceneCard } from "@/lib/og/og";

export const alt = `Hun is ${HUN_PRICE}, once.`;
export const size = OG_SIZE;
export const contentType = OG_CONTENT_TYPE;

export default function Image() {
  return sceneCard({
    image: "/site/bg/pricing-hero.jpg",
    eyebrow: `${HUN_MAC_LIMIT} Macs · every update`,
    title: "One price.\nYours to keep.",
    feature: <PriceFeature price={HUN_PRICE} note="once, not monthly" />,
    address: "hun.sh/pricing",
  });
}
