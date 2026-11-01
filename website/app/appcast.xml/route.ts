import { redirectTo, releaseFileURL } from "@/lib/releases";

/** The Sparkle feed every installed Hun checks. Its download links point back at hun.sh/releases. */
export function GET() {
  return redirectTo(releaseFileURL("latest", "appcast.xml")!);
}
