const VERSION_PATTERN = /^(\d+)\.(\d+)\.(\d+)$/;

function parseVersion(version) {
  const match = VERSION_PATTERN.exec(version);
  if (!match) {
    throw new Error(`Invalid semantic version: ${version}`);
  }
  return match.slice(1).map(Number);
}

function bumpVersion(version, kind) {
  const [major, minor, patch] = parseVersion(version);
  switch (kind) {
    case "patch":
      return `${major}.${minor}.${patch + 1}`;
    case "minor":
      return `${major}.${minor + 1}.0`;
    case "major":
      return `${major + 1}.0.0`;
    default:
      throw new Error(`Unsupported release bump: ${kind}`);
  }
}

export function compareVersions(left, right) {
  const leftParts = parseVersion(left);
  const rightParts = parseVersion(right);
  for (let index = 0; index < leftParts.length; index += 1) {
    if (leftParts[index] !== rightParts[index]) {
      return leftParts[index] - rightParts[index];
    }
  }
  return 0;
}

export function chooseReleaseVersion({
  currentVersion,
  latestVersion,
  requested,
}) {
  parseVersion(currentVersion);
  if (latestVersion) parseVersion(latestVersion);
  const baseVersion = latestVersion ?? currentVersion;

  if (requested === "auto") {
    if (!latestVersion) return currentVersion;
    const nextPatch = bumpVersion(latestVersion, "patch");
    return compareVersions(currentVersion, nextPatch) > 0
      ? currentVersion
      : nextPatch;
  }

  if (["patch", "minor", "major"].includes(requested)) {
    return bumpVersion(baseVersion, requested);
  }

  const explicitVersion = requested.replace(/^v/, "");
  parseVersion(explicitVersion);
  if (latestVersion && compareVersions(explicitVersion, latestVersion) <= 0) {
    throw new Error(
      `Requested version ${explicitVersion} must be newer than ${latestVersion}`,
    );
  }
  if (
    !latestVersion &&
    compareVersions(explicitVersion, currentVersion) < 0
  ) {
    throw new Error(
      `Requested version ${explicitVersion} cannot be older than ${currentVersion}`,
    );
  }
  return explicitVersion;
}

function sentence(text) {
  const trimmed = text.trim().replace(/[.!?]+$/, "");
  if (!trimmed) return "";
  return `${trimmed[0].toUpperCase()}${trimmed.slice(1)}.`;
}

export function buildChangelogEntry({ version, date, subjects }) {
  const groups = {
    New: [],
    Fixes: [],
    Improvements: [],
  };
  const fallback = [];

  for (const subject of subjects) {
    if (/^Merge\b/i.test(subject)) continue;

    const conventional = /^([a-z]+)(?:\([^)]+\))?!?:\s*(.+)$/i.exec(subject);
    if (!conventional) {
      const change = sentence(subject);
      if (change) fallback.push(change);
      continue;
    }

    const [, rawType, description] = conventional;
    const type = rawType.toLowerCase();
    if (["build", "chore", "ci", "docs", "style", "test"].includes(type)) {
      continue;
    }

    const change = sentence(description);
    if (!change) continue;
    if (type === "feat") groups.New.push(change);
    else if (type === "fix") groups.Fixes.push(change);
    else groups.Improvements.push(change);
  }

  if (Object.values(groups).every((changes) => changes.length === 0)) {
    groups.Improvements.push(...fallback);
  }
  if (Object.values(groups).every((changes) => changes.length === 0)) {
    groups.Improvements.push("Ship the latest Hun maintenance improvements.");
  }

  return {
    version,
    date,
    title: `Version ${version}`,
    summary: "A focused Hun update with the latest improvements and fixes.",
    groups: Object.entries(groups)
      .filter(([, changes]) => changes.length > 0)
      .map(([title, changes]) => ({ title, changes })),
  };
}

export function updateProjectVersions(project, { version, build }) {
  parseVersion(version);
  if (!Number.isInteger(build) || build < 1) {
    throw new Error(`Invalid build number: ${build}`);
  }

  const buildMatches = project.match(/CURRENT_PROJECT_VERSION = [^;]+;/g);
  const versionMatches = project.match(/MARKETING_VERSION = [^;]+;/g);
  if (!buildMatches?.length || !versionMatches?.length) {
    throw new Error("Could not find Xcode version settings");
  }

  function replaceFirstTwo(input, pattern, replacement) {
    let replacements = 0;
    return input.replace(pattern, (match) => {
      if (replacements >= 2) return match;
      replacements += 1;
      return replacement;
    });
  }

  return replaceFirstTwo(
    replaceFirstTwo(
      project,
      /CURRENT_PROJECT_VERSION = [^;]+;/g,
      `CURRENT_PROJECT_VERSION = ${build};`,
    ),
    /MARKETING_VERSION = [^;]+;/g,
    `MARKETING_VERSION = ${version};`,
  );
}
