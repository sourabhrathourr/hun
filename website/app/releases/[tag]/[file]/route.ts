import { redirectTo, releaseFileURL } from "@/lib/releases";

/**
 * hun.sh/releases/<tag>/<file>: one release file, e.g.
 * /releases/v0.4.4/hun-0.4.4-macos-arm64.dmg or /releases/latest/checksums.txt.
 * The appcast, install.sh and the Homebrew formula all download through here.
 */
export async function GET(_req: Request, { params }: { params: Promise<{ tag: string; file: string }> }) {
  const { tag, file } = await params;
  const url = releaseFileURL(tag, file);
  if (!url) return new Response("Not found", { status: 404 });
  return redirectTo(url);
}
