// Hun's release files live in a public, downloads-only repo; the source repo
// is private. Everything links through hun.sh (/download, /appcast.xml,
// /releases/<tag>/<file>), so the files can move hosts without an app update.

export const RELEASES_REPO = "hundotsh/hun-releases";

const TAG = /^v\d+\.\d+\.\d+$/;
const FILE = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

/** Where a release file really lives, or null for a malformed request. */
export function releaseFileURL(tag: string, file: string): string | null {
  if (!FILE.test(file)) return null;
  if (tag === "latest") return `https://github.com/${RELEASES_REPO}/releases/latest/download/${file}`;
  if (!TAG.test(tag)) return null;
  return `https://github.com/${RELEASES_REPO}/releases/download/${tag}/${file}`;
}

/** A short-lived redirect: hosts can change, so caches shouldn't hold on. */
export function redirectTo(url: string) {
  return new Response(null, {
    status: 307,
    headers: {
      Location: url,
      "Cache-Control": "public, max-age=300, stale-while-revalidate=3600",
    },
  });
}
