import { redirectTo, releaseFileURL } from "@/lib/releases";

/** hun.sh/download: the latest Hun for Mac. */
export function GET() {
  return redirectTo(releaseFileURL("latest", "hun-macos-arm64.dmg")!);
}
