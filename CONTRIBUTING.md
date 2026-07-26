# Contributing to Hun

Thank you for helping improve Hun.

Hun is a native macOS product backed by a Go service-management runtime. The
SwiftUI application is the primary user experience. The standalone CLI and TUI
are optional for users, but the Go daemon and shared packages remain core parts
of the macOS app.

## Repository map

| Path | Purpose |
| --- | --- |
| `apps/macos/hun/hun/` | SwiftUI application |
| `apps/macos/hun/hunTests/` | macOS unit tests |
| `cmd/hun/` | Go executable embedded in the app and published optionally as a CLI |
| `internal/daemon/` | Service lifecycle, logs, ports, Git operations, and API |
| `internal/client/` | Go daemon client |
| `internal/cli/` | Command-line commands |
| `internal/tui/` | Optional terminal interface |
| `internal/config/`, `internal/detect/`, `internal/state/` | Shared project configuration and runtime state |
| `website/` | Hun website and changelog |
| `assets/dmg/` | Branded macOS installer artwork and layout |
| `scripts/` | Development, packaging, release, and verification tools |

## Requirements

For macOS application work:

- An Apple silicon Mac
- macOS 15 or later
- Xcode 26.4.1
- Go 1.26 or later

For website work, install Bun 1.3.6. Production signing and notarization
credentials are not required for normal development or pull requests.

## Get started

Clone the repository and run the development watcher:

```sh
git clone https://github.com/sourabhrathourr/hun.git
cd hun
make dev-macos
```

The watcher builds an unsigned Debug app in `.build/xcode-dev`, launches it
with the development bundle identifier, and rebuilds when Swift or Go sources
change.

You can also open `apps/macos/hun/hun.xcodeproj` in Xcode. For isolated SwiftUI
changes, open a view such as `ContentView.swift` or `MenuBarView.swift`, show
the Canvas with Option-Command-Return, and start the preview. Use
`make dev-macos` when you need the bundled runtime, daemon connection, terminal,
menu-bar item, or full window lifecycle.

## Working on the macOS app

Keep the native app as the default user journey:

- Prefer familiar macOS controls, keyboard behavior, and accessibility.
- Keep service, terminal, log, and Git state consistent across project changes.
- Test both the main window and menu-bar experience when shared state changes.
- Avoid requiring a separately installed CLI; the release app must remain
  self-contained.

Run the same unsigned Apple silicon unit tests used by CI:

```sh
xcodebuild \
  -project apps/macos/hun/hun.xcodeproj \
  -scheme hun \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/local-macos \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  GO_BIN="$(command -v go)" \
  -only-testing:hunTests \
  test
```

Use the latest Xcode point release only after CI has been updated deliberately;
the repository currently pins Xcode 26.4.1.

## Working on the Go runtime

The Go code is both the engine behind the macOS app and the implementation of
the optional CLI/TUI. Run:

```sh
go test ./...
go test -race ./internal/cli ./internal/daemon ./internal/detect ./internal/state ./internal/tui
make build
```

Format Go changes with `gofmt`. Add tests alongside the package being changed,
especially for service lifecycle, port allocation, process cleanup, log
streaming, project detection, and persistent state.

Changes to daemon JSON payloads or behavior must remain compatible with both
the Swift client and Go clients. Update `internal/daemon/` and
`apps/macos/hun/hun/HunDaemonClient.swift` together. Increment
`CurrentProtocolVersion` only when an older client and newer daemon can no
longer communicate safely, and include compatibility tests for that boundary.

The release pipeline embeds the matching Go executable into the app and checks
its version, commit, protocol, and CPU architecture. Do not manually maintain a
separate bundled-runtime version.

## Working on the website

```sh
cd website
bun install --frozen-lockfile
bun run dev

# Before opening a pull request
bun run build
```

The website reads release information from `website/content/changelog.json`.
Do not manually edit download URLs to a versioned DMG; public download buttons
should continue following the latest published release.

## Commit messages and changelogs

The release command generates changelog entries from commit subjects since the
previous release. Write concise, user-facing commit messages:

```text
feat(macos): add workspace search
fix(daemon): recover stale service state
docs: clarify local development
```

`feat:` entries appear under **New**, `fix:` entries under **Fixes**, and other
user-facing commits under **Improvements**. Maintenance-only types such as
`build:`, `chore:`, `ci:`, `docs:`, `style:`, and `test:` are excluded.

## Pull requests

Keep pull requests focused and explain:

- What changed and why
- The user-facing effect
- Which macOS, Go, or website paths are affected
- How the change was tested
- Screenshots or recordings for visible interface changes
- Any daemon protocol or stored-state compatibility impact

Before requesting review:

```sh
go test ./...
git diff --check
```

Also run the macOS or website checks above when those areas change. CI repeats
the Go, race, website, and Apple silicon macOS checks.

## Releases

Releases are maintainer-owned. Do not manually change the Xcode marketing
version, numeric build, appcast, or Git tag in a feature pull request.

From a clean, up-to-date `main`:

```sh
./scripts/release.sh --dry-run
./scripts/release.sh
```

The command previews and then owns versioning, changelog metadata, the release
commit, the tag, and the GitHub Actions release pipeline.
