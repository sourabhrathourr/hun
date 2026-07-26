#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const changelogPath = path.join(root, "website/content/changelog.json");

const [version, outputPath] = process.argv.slice(2);
if (!version || !outputPath) {
  console.error(
    "Usage: scripts/render-macos-release-notes.mjs VERSION OUTPUT_PATH",
  );
  process.exit(1);
}

const releases = JSON.parse(await readFile(changelogPath, "utf8"));
const release = releases.find((candidate) => candidate.version === version);
if (!release) {
  console.error(`No changelog entry found for ${version} in ${changelogPath}`);
  process.exit(1);
}

const sections = release.groups
  .map(
    (group) =>
      `## ${group.title}\n\n${group.changes.map((change) => `- ${change}`).join("\n")}`,
  )
  .join("\n\n");

const markdown = `# Hun ${release.version} — ${release.title}\n\n${release.summary}\n\n${sections}\n\n[Read the full changelog](https://hun.sh/changelog#v${release.version})\n`;

await writeFile(outputPath, markdown);
