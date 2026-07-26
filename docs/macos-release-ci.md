# Automated macOS Release Pipeline

This note describes a safe first CI/CD design for Hun's website-distributed,
Apple-silicon macOS app. It complements
[`macos-sparkle-updates.md`](./macos-sparkle-updates.md) and
[`macos-direct-dmg-distribution.md`](./macos-direct-dmg-distribution.md).

The intended public endpoints are:

- Appcast: `https://hun.sh/appcast.xml`
- Changelog: `https://hun.sh/changelog`
- Versioned DMG:
  `https://github.com/sourabhrathourr/hun/releases/download/v<VERSION>/hun-<VERSION>-macos-arm64.dmg`

## Recommendation

Use two separate trust levels:

1. **CI** runs for pull requests and normal pushes. It runs Go and Swift tests
   and an unsigned macOS build. It receives no production secrets.
2. **Release CD** runs only for an existing, trusted `v*` tag. It enters a
   protected GitHub `Production` environment, imports the Developer ID
   certificate into a temporary keychain, builds and signs the app, creates and
   signs the DMG, notarizes and staples it, generates the Sparkle appcast from
   those final bytes, publishes the GitHub Release, and deploys the appcast
   last.

GitHub environment secrets are only exposed to a job that references that
environment, and approval rules can hold those secrets until a reviewer
approves the job. Environment deployment policies can also restrict which tags
may deploy. Availability of reviewers and environment controls depends on the
repository visibility and GitHub plan.
([GitHub environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments))

Hun's `.github/workflows/release.yml` uses one final publication job. It builds
and verifies the macOS artifacts first, creates a draft release, uploads every
expected asset, verifies the asset count, and only then publishes the release.
Standalone CLI archives are optional and do not block a Mac-only release.

## Runner and Xcode

Use the explicit Apple-silicon runner label `macos-26`, not `macos-latest`.
GitHub documents `macos-26` as an arm64 M1 runner and warns that `-latest` is
the latest stable image GitHub provides, not necessarily the newest Apple OS.
Pinning the OS label makes runner migrations deliberate.
([GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners))

Also select an explicit installed Xcode path with `DEVELOPER_DIR` and print
`xcodebuild -version` at the beginning of the job. Hun pins
`/Applications/Xcode_26.4.1.app` so CI and production releases use the same
known-good asset-catalog toolchain. GitHub's runner-image manifest is the source
of truth for currently installed Xcode paths.
([macOS 26 arm64 image manifest](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md))

Use Go 1.26 or later for every CI and release job. Go 1.24 added the Mach-O
`LC_UUID` load command to binaries produced by its internal linker. Older Go
binaries can be rejected by `dyld` on macOS 26 before Hun can inspect or launch
its bundled runtime. The macOS CI job and release packager therefore verify the
load command and execute the hardened runtime before publishing.
([Go 1.24 release notes](https://go.dev/doc/go1.24))

The workflow should fail unless the app executable and every bundled executable
(including the Go `hun` CLI) are `arm64`. If Hun later ships Intel support,
every nested executable must gain the matching `x86_64` slice; making only the
Swift app universal is insufficient.

## Branded DMG installer

Hun's release DMG is assembled with the pinned `dmgbuild==1.6.7` package. The
layout is defined in `assets/dmg/dmgbuild-settings.py` and uses committed 1x and
2x artwork from `assets/dmg/`. This keeps the Finder window size, icon size,
icon positions, hidden chrome, `/Applications` symlink, and volume icon
deterministic in local builds and GitHub Actions.

The editable artwork source is `scripts/render-dmg-background.swift`. Regenerate
both PNGs after changing the design:

```sh
swift scripts/render-dmg-background.swift assets/dmg/background.png 1
swift scripts/render-dmg-background.swift assets/dmg/background@2x.png 2
```

During packaging, `scripts/package-macos-release.sh` combines those files into
a Retina TIFF with `tiffutil`, asks `dmgbuild` to create the compressed image,
and then continues with Developer ID signing, verification, notarization, and
stapling. Developers can install the pinned builder locally with:

```sh
python3 -m pip install "dmgbuild==1.6.7"
```

## Production secrets and variables

Create a GitHub environment named `Production`.

Environment **secrets**:

| Name | Contents |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Base64 of the exported Developer ID Application certificate and private key (`.p12`) |
| `DEVELOPER_ID_P12_PASSWORD` | Password used when exporting that `.p12` |
| `NOTARY_KEY_P8_BASE64` | Base64 of an App Store Connect API private key (`.p8`) |
| `SPARKLE_ED_PRIVATE_KEY` | Contents of Sparkle's exported Ed25519 private-key file |

Environment **variables**:

| Name | Example |
| --- | --- |
| `APPLE_TEAM_ID` | Personal Apple Developer team ID |
| `NOTARY_KEY_ID` | App Store Connect API key ID |
| `NOTARY_ISSUER_ID` | App Store Connect API issuer UUID |

The team ID, key ID, and issuer ID are identifiers, not private key material.
Keeping them as environment variables makes that distinction visible.

At repository scope, `PUBLISH_STANDALONE_CLI` is an optional variable. Leave it
unset or set it to `false` for the normal Mac-first pipeline. Set it to `true`
only when the same tag should also publish GoReleaser archives and update the
Homebrew tap; those releases additionally require
`HOMEBREW_TAP_GITHUB_TOKEN` in the `release` environment.

GitHub recommends secrets for the Apple `.p12` and its password, documents
base64 as the transport for the binary certificate, and provides a reference
temporary-keychain script. Base64 is encoding, not encryption, and GitHub
secrets are limited to 48 KB.
([GitHub Apple certificate guide](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications),
[GitHub secret handling](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets),
[secret limits](https://docs.github.com/en/actions/reference/security/secrets))

Generate a random temporary keychain password during the job. Decode private
files only under `$RUNNER_TEMP`, restrict their permissions, never print them,
and delete the files and keychain in an `if: always()` cleanup step. GitHub-hosted
runners are destroyed after a job, but explicit cleanup makes a future move to
a self-hosted runner safer; GitHub explicitly requires cleanup on self-hosted
runners.
([GitHub Apple certificate guide](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications))

## Developer ID signing

Export the existing **Developer ID Application** identity and private key from
Keychain Access as a password-protected `.p12`. A Developer ID Installer
certificate is for a flat `.pkg`; it is not needed for Hun's DMG.

In the protected job:

1. Decode the `.p12` into `$RUNNER_TEMP`.
2. Create and unlock an ephemeral keychain.
3. Import the `.p12`.
4. Set its partition list to `apple-tool:,apple:` so noninteractive `codesign`
   can use it.
5. Verify that exactly the expected Developer ID Application identity exists.

GitHub's official example uses this temporary-keychain pattern.
([GitHub Apple certificate guide](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications))

Prefer Xcode's archive/export distribution flow when possible. Sparkle explains
that Xcode's archive/export workflow re-signs its nested XPC services and
helpers, preserves Hardened Runtime, and strips development entitlements. If
Hun continues using a custom packaging script, it must sign Sparkle's nested
`Installer.xpc`, `Downloader.xpc`, `Autoupdate`, `Updater.app`, and
`Sparkle.framework` from the inside out before signing `hun.app`. Do not use
`codesign --deep` to perform signing.
([Sparkle code-signing guidance](https://sparkle-project.org/documentation/sandboxing/))

Apple requires all distributed executables to have valid signatures, a
Developer ID identity, Hardened Runtime, and a secure timestamp. The release
must not contain `com.apple.security.get-task-allow=true`.
([Apple notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution))

Before creating the DMG, verify the app with `codesign --verify --strict`. Then:

1. Create the DMG from the signed app and `/Applications` symlink.
2. Sign the DMG with the Developer ID Application identity and secure timestamp.
3. Run `hdiutil verify`.

## Notarization authentication

`notarytool` supports two official credential forms:

- Apple ID + app-specific password + Team ID.
- App Store Connect API `.p8` key + key ID + issuer ID.

For unattended CI, prefer the API key. This is a project recommendation: it
avoids coupling the release to a user's Apple ID password and gives Apple a
dedicated credential that can be revoked. Apple documents the exact
`--key`, `--key-id`, and `--issuer` arguments. The app-specific password Hun
already uses locally remains a valid fallback.
([Apple TN3147](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool))

Keep the `.p8` private key out of the repository. Apple says it can be
downloaded only as private credential material, must be stored securely, and
must be revoked immediately if compromised.
([Apple API key security](https://developer.apple.com/documentation/notaryapi/submitting-software-for-notarization-over-the-web))

Submit the final signed DMG with `notarytool submit --wait`. Fail the workflow
unless the result is `Accepted`; always download and retain the notarization
log, even for successful submissions, because Apple says accepted submissions
may still contain warnings. Then staple and validate the exact DMG.
([Apple custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow))

## Sparkle signing and appcast generation

Sparkle's key pair is separate from the Apple Developer ID certificate:

- `SUPublicEDKey` is public and must be embedded in every Hun app build.
- The Ed25519 private key signs update archives and must never ship in the app
  or be committed to Git.

Generate the pair once with Sparkle's `generate_keys`. Keep the original
Keychain item, export a backup with `generate_keys -x`, and store the exported
file's contents as `SPARKLE_ED_PRIVATE_KEY`. Sparkle documents both export and
import and warns that the private key must not be lost.
([Sparkle key setup](https://sparkle-project.org/documentation/))

In CI, pass the private key over standard input:

```sh
printf '%s\n' "$SPARKLE_ED_PRIVATE_KEY" |
  generate_appcast \
    --ed-key-file - \
    --download-url-prefix "$SPARKLE_DOWNLOAD_PREFIX" \
    --full-release-notes-url "https://hun.sh/changelog" \
    "$APPCAST_STAGING_DIRECTORY"
```

Do not pass the private key with Sparkle's old `-s` argument. Sparkle deprecated
that option as insecure and specifically recommends `--ed-key-file -` for CI.
([Sparkle security history](https://sparkle-project.org/documentation/security-and-reliability/),
[`generate_appcast` source](https://github.com/sparkle-project/Sparkle/blob/2.x/generate_appcast/main.swift))

Run `generate_appcast` **after** Apple notarization and stapling. This ordering
is required because stapling attaches a ticket to the DMG, while Sparkle's
signature and `length` describe the exact archive bytes. Generating the appcast
first would leave it describing a different file. This sequencing is an
inference from Apple's stapling operation and Sparkle's archive-signing
requirements.
([Apple stapling](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow),
[Sparkle publishing](https://sparkle-project.org/documentation/publishing/))

For the first release, ship full DMGs only. Hun's DMG is small, so delta updates
add state and failure modes without much benefit. Deltas can be added later by
retaining or downloading prior update archives before running
`generate_appcast`; Sparkle can then generate them automatically.
([Sparkle publishing](https://sparkle-project.org/documentation/publishing/))

Set the version-specific release-note link to the matching section of
`https://hun.sh/changelog`, and the full-release-notes URL to the top-level
changelog page. A release job should fail before signing if:

- the `v<VERSION>` tag does not match `CFBundleShortVersionString`;
- `CFBundleVersion` did not increase;
- the changelog has no entry for that version; or
- the app's embedded `SUPublicEDKey` or `SUFeedURL` is missing.

## Starting a release

Release preparation is intentionally one command from a clean, synchronized
`main` branch:

```sh
./scripts/release.sh --dry-run
./scripts/release.sh
```

The dry run calculates and displays the next version, numeric build, commit
range, artifact name, changelog, and every action without changing files or Git
refs. The confirmed command runs tests, derives version/build from the latest
published release, updates Xcode metadata, and generates a changelog entry from
user-facing conventional commits when one is missing. It then atomically pushes
the release commit and tag. The tag is the only trigger for the protected
release workflow. If the atomic push fails, rerun the same command.

Use `minor`, `major`, or an explicit semantic version only when the default
patch release is not appropriate.

## Safe publication order

Use a unique, versioned asset name. Never replace an already published DMG in
place: changing the file invalidates the `sparkle:edSignature` and can leave
clients with a cached URL for different bytes.

Publish in this order:

1. Finish all verification, Developer ID signing, notarization, and stapling.
2. Generate the Sparkle signature and appcast from that exact final DMG.
3. Create a **draft** GitHub Release for the existing tag.
4. Upload the DMG, checksums, and other release assets.
5. Publish the GitHub Release.
6. Confirm the appcast enclosure URL returns the final DMG.
7. Deploy `https://hun.sh/appcast.xml` **last**.
8. Confirm the live appcast, DMG, and changelog URLs.

Publishing the feed last prevents installed apps from seeing an update whose
archive is not yet available. This is a safety inference from Sparkle's appcast
model, in which clients download the enclosure URL.

`gh release create TAG FILE... --verify-tag` uses a draft internally, uploads
the assets, then publishes the release. GitHub also recommends drafts when
immutable releases are enabled so every asset exists before publication.
([GitHub CLI `gh release create`](https://cli.github.com/manual/gh_release_create),
[GitHub release management](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository))

Avoid `gh release upload --clobber` for shipped update assets. GitHub documents
that `--clobber` deletes the old asset before uploading the replacement, so a
failed upload can remove the working release.
([GitHub CLI `gh release upload`](https://cli.github.com/manual/gh_release_upload))

## GitHub permissions and controls

Use least privilege:

- CI/test jobs: `permissions: contents: read`.
- The single publication job: `permissions: contents: write`.
- No personal access token is required to create a release in the same
  repository; use the job-scoped `GITHUB_TOKEN`.

GitHub documents that `contents: write` permits release creation and that all
unspecified permissions become `none`.
([GitHub workflow permissions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax),
[`GITHUB_TOKEN`](https://docs.github.com/en/actions/concepts/security/github_token))

Protect the `production` environment with an allowed tag pattern and, where the
plan permits it, a required reviewer. Protect changes to `.github/workflows/**`
with repository rules or review, because anyone able to change a trusted
release workflow can instruct it to expose the signing keys.

Run signing only from trusted tag or manually dispatched events. Do not use
`pull_request_target` for a job that handles release secrets. GitHub normally
withholds secrets from fork pull requests and Dependabot, but separating CI
from release CD is still the safer design.
([GitHub secret handling](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets),
[workflow permission warning](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax))

Pin third-party actions to full commit SHAs and review updates. Prefer direct
Apple and Sparkle command-line tools for the sensitive signing steps so the
credential flow remains visible.
([GitHub secure-use reference](https://docs.github.com/en/actions/reference/security/secure-use))

Use a release concurrency group with `cancel-in-progress: false`. A second tag
must not cancel a job while it is signing, notarizing, or publishing its feed.

## Operational limitations

- A GitHub-hosted runner is ephemeral, but a malicious trusted workflow can
  still read every credential while the job runs. Environment approval and
  workflow review are the primary controls.
- Apple does not accept GitHub OIDC in place of a Developer ID private key or
  notarization credentials. Long-lived Apple and Sparkle signing material must
  be available to the protected job.
- Notarization is an external service and may be slow or temporarily
  unavailable. Apple says most submissions finish quickly but documents a
  daily limit of 75 submissions. A failed or timed-out notarization must not
  publish a release or appcast.
  ([Apple custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow))
- CI can verify signatures and the stapled ticket, but it does not fully
  reproduce a user's first browser download and quarantine flow. Before broad
  release, download the public DMG through a browser on another Mac, drag Hun
  to `/Applications`, launch it, and test an update from the previous version.
- Publishing an appcast is not an instant push. Installed copies discover it
  on their next hourly check or immediately when the user selects
  **Check for Updates…**.

## Release checklist

- [ ] Tag matches the app marketing version
- [ ] Build number increased
- [ ] Changelog entry exists
- [ ] Go and Swift tests passed without production secrets
- [ ] Release job approved in `production`
- [ ] App and bundled CLI are arm64
- [ ] Sparkle nested helpers and app have valid Developer ID signatures
- [ ] Hardened Runtime and secure timestamps are present
- [ ] DMG is signed and `hdiutil verify` passes
- [ ] Notarization status is `Accepted`; log reviewed
- [ ] Ticket is stapled and validates
- [ ] Appcast was generated from the stapled DMG via stdin key handling
- [ ] GitHub Release and versioned DMG are public
- [ ] Public DMG URL serves the expected checksum
- [ ] Appcast deployed last and enclosure URL is live
- [ ] Browser-download installation tested
- [ ] Previous installed Hun version successfully updates and relaunches
