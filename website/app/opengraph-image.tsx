import { OG_CONTENT_TYPE, OG_SIZE, sceneCard } from "@/lib/og/og";

// The home page's card, and the default for any page without its own.
export const alt = "Hun: always know what's running, and on which port.";
export const size = OG_SIZE;
export const contentType = OG_CONTENT_TYPE;

export default function Image() {
  return sceneCard({
    image: "/site/bg/license-hero.jpg",
    eyebrow: "For macOS",
    title: "Always know\nwhat’s running,\nand on which port.",
    description: "Every dev server you or your agents start, with its port and logs, in your menu bar.",
    address: "hun.sh",
  });
}
