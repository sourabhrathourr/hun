import assert from "node:assert/strict";
import test from "node:test";

import {
  buildChangelogEntry,
  chooseReleaseVersion,
  updateProjectVersions,
} from "./release-lib.mjs";

test("an unpublished project version is released without another bump", () => {
  assert.equal(
    chooseReleaseVersion({
      currentVersion: "0.3.0",
      latestVersion: null,
      requested: "auto",
    }),
    "0.3.0",
  );
});

test("the default release is derived from the latest published version", () => {
  assert.equal(
    chooseReleaseVersion({
      currentVersion: "0.2.0",
      latestVersion: "0.3.7",
      requested: "auto",
    }),
    "0.3.8",
  );
});

test("the default preserves a newer unreleased marketing version", () => {
  assert.equal(
    chooseReleaseVersion({
      currentVersion: "0.4.0",
      latestVersion: "0.3.7",
      requested: "auto",
    }),
    "0.4.0",
  );
});

test("minor and explicit releases are resolved from published state", () => {
  assert.equal(
    chooseReleaseVersion({
      currentVersion: "0.2.0",
      latestVersion: "0.3.7",
      requested: "minor",
    }),
    "0.4.0",
  );
  assert.equal(
    chooseReleaseVersion({
      currentVersion: "0.2.0",
      latestVersion: "0.3.7",
      requested: "1.0.0",
    }),
    "1.0.0",
  );
  assert.throws(
    () =>
      chooseReleaseVersion({
        currentVersion: "0.3.7",
        latestVersion: "0.3.7",
        requested: "0.3.7",
      }),
    /must be newer than 0.3.7/,
  );
});

test("release notes group user-facing commits and omit maintenance noise", () => {
  assert.deepEqual(
    buildChangelogEntry({
      version: "0.3.1",
      date: "2026-07-26",
      subjects: [
        "feat: add automatic updates",
        "fix(macos): repair release signing",
        "refactor: simplify daemon startup",
        "docs: explain the pipeline",
        "chore: update generated files",
      ],
    }),
    {
      version: "0.3.1",
      date: "2026-07-26",
      title: "Version 0.3.1",
      summary: "A focused Hun update with the latest improvements and fixes.",
      groups: [
        {
          title: "New",
          changes: ["Add automatic updates."],
        },
        {
          title: "Fixes",
          changes: ["Repair release signing."],
        },
        {
          title: "Improvements",
          changes: ["Simplify daemon startup."],
        },
      ],
    },
  );
});

test("project metadata only updates the Hun app build configurations", () => {
  const project = `
    CURRENT_PROJECT_VERSION = 4;
    MARKETING_VERSION = 0.3.0;
    CURRENT_PROJECT_VERSION = 4;
    MARKETING_VERSION = 0.3.0;
    CURRENT_PROJECT_VERSION = 1;
    MARKETING_VERSION = 1.0;
  `;

  const updated = updateProjectVersions(project, {
    version: "0.3.1",
    build: 5,
  });

  assert.equal(updated.match(/CURRENT_PROJECT_VERSION = 5;/g)?.length, 2);
  assert.equal(updated.match(/MARKETING_VERSION = 0.3.1;/g)?.length, 2);
  assert.match(updated, /CURRENT_PROJECT_VERSION = 1;/);
  assert.match(updated, /MARKETING_VERSION = 1.0;/);
});
