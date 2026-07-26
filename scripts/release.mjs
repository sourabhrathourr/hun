#!/usr/bin/env node

import { execFileSync, spawnSync } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import readline from "node:readline/promises";
import { fileURLToPath } from "node:url";

import {
  buildChangelogEntry,
  chooseReleaseVersion,
  compareVersions,
  updateProjectVersions,
} from "./release-lib.mjs";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const fallbackRoot = path.resolve(scriptDirectory, "..");

function usage() {
  console.log(`Usage:
  ./scripts/release.sh [patch|minor|major|X.Y.Z] [--dry-run] [--skip-tests] [--yes]

The default chooses the next safe version automatically:
  - the first release uses the version already in Xcode
  - later releases increment the latest published patch version

Examples:
  ./scripts/release.sh --dry-run
  ./scripts/release.sh
  ./scripts/release.sh minor --dry-run
  ./scripts/release.sh 1.0.0`);
}

function parseArguments(arguments_) {
  let requested = "auto";
  let dryRun = false;
  let skipTests = false;
  let yes = false;

  for (let index = 0; index < arguments_.length; index += 1) {
    const argument = arguments_[index];
    if (argument === "--dry-run") dryRun = true;
    else if (argument === "--skip-tests") skipTests = true;
    else if (argument === "--yes" || argument === "-y") yes = true;
    else if (argument === "--version") {
      requested = arguments_[index + 1] ?? "";
      index += 1;
    } else if (argument === "--help" || argument === "-h") {
      usage();
      process.exit(0);
    } else if (!argument.startsWith("-") && requested === "auto") {
      requested = argument;
    } else {
      throw new Error(`Unknown argument: ${argument}`);
    }
  }

  if (!requested) throw new Error("Missing value after --version");
  return { requested, dryRun, skipTests, yes };
}

function capture(command, arguments_, options = {}) {
  return execFileSync(command, arguments_, {
    cwd: options.cwd,
    encoding: "utf8",
    stdio: ["ignore", "pipe", options.allowStderr ? "inherit" : "pipe"],
  }).trim();
}

function run(command, arguments_, root) {
  const result = spawnSync(command, arguments_, {
    cwd: root,
    stdio: "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${command} failed with exit code ${result.status}`);
  }
}

function localTagCommit(tag, root) {
  try {
    return capture("git", ["rev-parse", "-q", "--verify", `${tag}^{commit}`], {
      cwd: root,
    });
  } catch {
    return "";
  }
}

function currentProjectMetadata(project) {
  const version = /MARKETING_VERSION = ([^;]+);/.exec(project)?.[1];
  const buildText = /CURRENT_PROJECT_VERSION = ([^;]+);/.exec(project)?.[1];
  const build = Number(buildText);
  if (!version || !Number.isInteger(build) || build < 1) {
    throw new Error("Could not read the Hun version and build from the Xcode project");
  }
  return { version, build };
}

function remoteMainCommit(root) {
  const output = capture(
    "git",
    ["ls-remote", "origin", "refs/heads/main"],
    { cwd: root },
  );
  const commit = output.split(/\s+/)[0];
  if (!commit) throw new Error("Could not find origin/main");
  return commit;
}

function remoteReleaseTags(root) {
  const output = capture(
    "git",
    ["ls-remote", "--tags", "origin", "refs/tags/v*"],
    { cwd: root },
  );
  const tags = new Map();
  for (const line of output.split("\n")) {
    if (!line) continue;
    const [commit, reference] = line.split(/\s+/);
    const match = /^refs\/tags\/(v\d+\.\d+\.\d+)(\^\{\})?$/.exec(reference);
    if (!match) continue;
    const [, tag, peeled] = match;
    if (peeled || !tags.has(tag)) tags.set(tag, commit);
  }
  return [...tags.entries()]
    .map(([tag, commit]) => ({
      tag,
      version: tag.slice(1),
      commit,
    }))
    .sort((left, right) => compareVersions(right.version, left.version));
}

function releaseSubjects(root, previousCommit) {
  const range = previousCommit ? `${previousCommit}..HEAD` : "HEAD";
  const output = capture("git", ["log", "--format=%s", range], { cwd: root });
  return output ? output.split("\n") : [];
}

function printPlan(plan) {
  const divider = "─".repeat(58);
  console.log(`\nHun release preview\n${divider}`);
  console.log(`Branch           ${plan.branch}`);
  console.log(`Version          v${plan.version}`);
  console.log(`Build            ${plan.build}`);
  console.log(`Previous release ${plan.previousTag || "none"}`);
  console.log(`Artifact         hun-${plan.version}-macos-arm64.dmg`);
  console.log(`Commit           ${plan.commit}`);
  console.log(`Changes          ${plan.subjectCount} commits`);
  console.log(
    `Changelog        ${plan.existingChangelog ? "existing entry" : "generated from commits"}`,
  );
  console.log(`\n${plan.entry.title}`);
  console.log(plan.entry.summary);
  for (const group of plan.entry.groups) {
    console.log(`\n${group.title}`);
    for (const change of group.changes) console.log(`  • ${change}`);
  }
  console.log(`\nWhat the release command will do\n${divider}`);
  if (plan.retryingAtomicPush) {
    console.log("Retry the already prepared release commit and tag.");
  }
  console.log("1. Run Go, race, and macOS unit tests.");
  if (plan.metadataChanges) {
    console.log("2. Update Xcode version/build and generate missing changelog metadata.");
    console.log(`3. Create "chore: release v${plan.version}" on main.`);
  } else {
    console.log("2. Reuse the version/build/changelog already prepared on main.");
    console.log("3. Confirm main is fully pushed.");
  }
  console.log(`4. Atomically push main and the v${plan.version} tag.`);
  console.log("5. GitHub Actions builds, signs, notarizes, staples, and publishes the DMG.");
  console.log("6. Sparkle discovers the published appcast within one hour.");
}

async function confirmRelease(version) {
  const interface_ = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  const answer = await interface_.question(
    `\nRelease v${version} now? This pushes main and the release tag. [y/N] `,
  );
  interface_.close();
  return /^y(es)?$/i.test(answer.trim());
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  const root = capture("git", ["rev-parse", "--show-toplevel"], {
    cwd: fallbackRoot,
  });
  const branch = capture("git", ["branch", "--show-current"], { cwd: root });
  if (branch !== "main" && !options.dryRun) {
    throw new Error(`Release must run from main (current branch: ${branch})`);
  }
  if (capture("git", ["status", "--porcelain"], { cwd: root })) {
    throw new Error("Working tree is not clean. Commit or stash changes first.");
  }

  const localMain = capture("git", ["rev-parse", "HEAD"], { cwd: root });
  const remoteMain = remoteMainCommit(root);
  if (branch !== "main") {
    console.log(
      `Previewing ${branch}. The confirmed release must run from main after merge.`,
    );
  }

  const projectPath = path.join(
    root,
    "apps/macos/hun/hun.xcodeproj/project.pbxproj",
  );
  const changelogPath = path.join(root, "website/content/changelog.json");
  const project = await readFile(projectPath, "utf8");
  const current = currentProjectMetadata(project);
  const remoteTags = remoteReleaseTags(root);
  const previousRelease = remoteTags[0] ?? null;
  const version = chooseReleaseVersion({
    currentVersion: current.version,
    latestVersion: previousRelease?.version ?? null,
    requested: options.requested,
  });
  const tag = `v${version}`;
  if (remoteTags.some((release) => release.tag === tag)) {
    throw new Error(`Release tag ${tag} already exists on GitHub`);
  }

  let build = current.build;
  if (previousRelease) {
    const previousProject = capture(
      "git",
      [
        "show",
        `${previousRelease.commit}:apps/macos/hun/hun.xcodeproj/project.pbxproj`,
      ],
      { cwd: root },
    );
    build = currentProjectMetadata(previousProject).build + 1;
  }
  const previousTag = previousRelease?.tag ?? "";
  const subjects = releaseSubjects(root, previousRelease?.commit);
  const changelog = JSON.parse(await readFile(changelogPath, "utf8"));
  const existingEntry = changelog.find((release) => release.version === version);
  const entry =
    existingEntry ??
    buildChangelogEntry({
      version,
      date: new Date().toISOString().slice(0, 10),
      subjects,
    });
  const metadataChanges =
    version !== current.version || build !== current.build || !existingEntry;
  const pendingTagCommit = localTagCommit(tag, root);
  const releaseCommitSubject = `chore: release ${tag}`;
  const localSubject = capture("git", ["log", "-1", "--format=%s"], {
    cwd: root,
  });
  const remoteIsAncestor =
    spawnSync("git", ["merge-base", "--is-ancestor", remoteMain, localMain], {
      cwd: root,
      stdio: "ignore",
    }).status === 0;
  const retryingAtomicPush =
    branch === "main" &&
    localMain !== remoteMain &&
    remoteIsAncestor &&
    pendingTagCommit === localMain &&
    localSubject === releaseCommitSubject &&
    !metadataChanges;

  if (pendingTagCommit && !retryingAtomicPush) {
    throw new Error(
      `Local tag ${tag} already exists and is not a retryable release`,
    );
  }
  if (
    branch === "main" &&
    localMain !== remoteMain &&
    !retryingAtomicPush &&
    !options.dryRun
  ) {
    throw new Error(
      "Local main is not aligned with origin/main. Pull or push your normal work first.",
    );
  }
  const plan = {
    branch,
    version,
    build,
    previousTag,
    commit: capture("git", ["rev-parse", "--short", "HEAD"], { cwd: root }),
    subjectCount: subjects.length,
    existingChangelog: Boolean(existingEntry),
    metadataChanges,
    retryingAtomicPush,
    entry,
  };

  printPlan(plan);
  if (options.dryRun) {
    if (branch === "main" && localMain !== remoteMain && !retryingAtomicPush) {
      console.log(
        "\nNote: align local main with origin/main before executing this plan.",
      );
    }
    console.log("\nDry run complete. No files, commits, or tags were changed.");
    console.log("Run ./scripts/release.sh to execute this plan.");
    return;
  }

  if (!options.yes && !(await confirmRelease(version))) {
    console.log("Release canceled.");
    return;
  }

  if (!options.skipTests) {
    console.log("\nRunning Go tests...");
    run("go", ["test", "./..."], root);
    console.log("\nRunning race tests...");
    run(
      "go",
      [
        "test",
        "-race",
        "./internal/cli",
        "./internal/daemon",
        "./internal/detect",
        "./internal/state",
        "./internal/tui",
      ],
      root,
    );
    console.log("\nRunning macOS unit tests...");
    run(
      "xcodebuild",
      [
        "-quiet",
        "-project",
        "apps/macos/hun/hun.xcodeproj",
        "-scheme",
        "hun",
        "-configuration",
        "Debug",
        "-destination",
        "platform=macOS,arch=arm64",
        "-only-testing:hunTests",
        "test",
        "CODE_SIGNING_ALLOWED=NO",
      ],
      root,
    );
  }

  if (metadataChanges) {
    const updatedProject = updateProjectVersions(project, { version, build });
    const originalChangelog = await readFile(changelogPath, "utf8");
    const updatedChangelog = existingEntry
      ? originalChangelog
      : `${JSON.stringify([entry, ...changelog], null, 2)}\n`;
    JSON.parse(updatedChangelog);
    let committed = false;
    try {
      await writeFile(projectPath, updatedProject);
      await writeFile(changelogPath, updatedChangelog);

      const temporaryDirectory = await mkdtemp(
        path.join(os.tmpdir(), "hun-release-"),
      );
      try {
        run(
          "node",
          [
            "scripts/render-macos-release-notes.mjs",
            version,
            path.join(temporaryDirectory, "release-notes.md"),
          ],
          root,
        );
      } finally {
        await rm(temporaryDirectory, { recursive: true, force: true });
      }

      run("git", ["diff", "--check"], root);
      run(
        "git",
        [
          "add",
          "apps/macos/hun/hun.xcodeproj/project.pbxproj",
          "website/content/changelog.json",
        ],
        root,
      );
      run("git", ["commit", "-m", releaseCommitSubject], root);
      committed = true;
    } catch (error) {
      if (!committed) {
        await writeFile(projectPath, project);
        await writeFile(changelogPath, originalChangelog);
        spawnSync(
          "git",
          [
            "restore",
            "--staged",
            "--",
            "apps/macos/hun/hun.xcodeproj/project.pbxproj",
            "website/content/changelog.json",
          ],
          { cwd: root, stdio: "ignore" },
        );
      }
      throw error;
    }
  }

  const releaseCommit = capture("git", ["rev-parse", "HEAD"], { cwd: root });
  const existingLocalTag = localTagCommit(tag, root);
  if (existingLocalTag && existingLocalTag !== releaseCommit) {
    throw new Error(
      `Local tag ${tag} points to a different commit. Remove or rename it before retrying.`,
    );
  }
  if (!existingLocalTag) run("git", ["tag", "-a", tag, "-m", tag], root);
  run(
    "git",
    [
      "push",
      "--atomic",
      "origin",
      "HEAD:refs/heads/main",
      `refs/tags/${tag}:refs/tags/${tag}`,
    ],
    root,
  );

  console.log(`\nRelease started: ${tag}`);
  console.log("GitHub Actions now owns signing, notarization, and publishing.");
  console.log(
    `Watch: https://github.com/sourabhrathourr/hun/actions/workflows/release.yml`,
  );
}

main().catch((error) => {
  console.error(`\nRelease stopped: ${error.message}`);
  process.exit(1);
});
