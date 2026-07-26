#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/apps/macos/hun/hun.xcodeproj"
SCHEME="hun"
CONFIGURATION="Release"
BUILD_ROOT="${HUN_MACOS_RELEASE_BUILD_DIR:-$ROOT/build/macos-release}"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
DIST_DIR="$BUILD_ROOT/dist"
APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/hun.app"
CLI="$APP/Contents/Resources/hun"
SPARKLE_FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
DMG_SETTINGS="$ROOT/assets/dmg/dmgbuild-settings.py"
DMG_BACKGROUND_1X="$ROOT/assets/dmg/background.png"
DMG_BACKGROUND_2X="$ROOT/assets/dmg/background@2x.png"
DMG_BACKGROUND="$BUILD_ROOT/dmg-background.tiff"
VERSION="${HUN_MACOS_VERSION:-}"
BUILD_NUMBER="${HUN_MACOS_BUILD_NUMBER:-}"
CLI_VERSION="${HUN_CLI_VERSION:-v$VERSION}"
CLI_COMMIT="${HUN_CLI_COMMIT:-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo none)}"
DMG="$DIST_DIR/hun-$VERSION-macos-arm64.dmg"
STABLE_DMG="$DIST_DIR/hun-macos-arm64.dmg"
SHA_FILE="$DMG.sha256"
APPCAST="$DIST_DIR/appcast.xml"
APPCAST_ROOT="$BUILD_ROOT/appcast"
NOTARY_PROFILE="${HUN_NOTARY_PROFILE:-}"
NOTARY_KEY_PATH="${HUN_NOTARY_KEY_PATH:-}"
NOTARY_KEY_ID="${HUN_NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${HUN_NOTARY_ISSUER_ID:-}"
SIGNING_IDENTITY="${HUN_DEVELOPER_ID_APPLICATION:-}"
SPARKLE_ACCOUNT="${HUN_SPARKLE_ACCOUNT:-hun}"
DMGBUILD_BIN="${HUN_DMGBUILD_BIN:-$(command -v dmgbuild || true)}"
GENERATE_APPCAST=0

usage() {
  cat <<'EOF'
Usage:
  scripts/package-macos-release.sh [--version X.Y.Z] [--build NUMBER]
    [--notary-profile PROFILE] [--generate-appcast]

Builds an Apple Silicon-only Release app, signs the bundled CLI and app with
Developer ID, creates and signs a DMG, and optionally notarizes and staples it.
When requested, it generates a Sparkle-signed appcast from the final stapled
DMG.

Environment:
  HUN_DEVELOPER_ID_APPLICATION  Developer ID Application identity name.
                                Auto-detected when exactly one is installed.
  HUN_NOTARY_PROFILE            Keychain profile created by notarytool.
  HUN_NOTARY_KEY_PATH           App Store Connect API private key path.
  HUN_NOTARY_KEY_ID             App Store Connect API key ID.
  HUN_NOTARY_ISSUER_ID          App Store Connect API issuer ID.
  HUN_MACOS_RELEASE_BUILD_DIR   Override the build output directory.
  HUN_MACOS_BUILD_NUMBER        Override CFBundleVersion.
  HUN_CLI_VERSION               Version embedded in the bundled CLI.
  HUN_CLI_COMMIT                Commit embedded in the bundled CLI.
  HUN_SPARKLE_ACCOUNT           Sparkle Keychain account (default: hun).
  HUN_SPARKLE_ED_PRIVATE_KEY    CI-only exported Sparkle private key contents.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      CLI_VERSION="v$VERSION"
      DMG="$DIST_DIR/hun-$VERSION-macos-arm64.dmg"
      SHA_FILE="$DMG.sha256"
      shift 2
      ;;
    --build)
      BUILD_NUMBER="${2:-}"
      shift 2
      ;;
    --notary-profile)
      NOTARY_PROFILE="${2:-}"
      shift 2
      ;;
    --generate-appcast)
      GENERATE_APPCAST=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid version: $VERSION (pass --version X.Y.Z)" >&2
  exit 1
fi

if [ -n "$BUILD_NUMBER" ] && [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid build number: $BUILD_NUMBER (expected a positive integer)" >&2
  exit 1
fi

if [ -n "$NOTARY_KEY_PATH$NOTARY_KEY_ID$NOTARY_ISSUER_ID" ]; then
  if [ -z "$NOTARY_KEY_PATH" ] || [ -z "$NOTARY_KEY_ID" ] || [ -z "$NOTARY_ISSUER_ID" ]; then
    echo "HUN_NOTARY_KEY_PATH, HUN_NOTARY_KEY_ID, and HUN_NOTARY_ISSUER_ID must be supplied together." >&2
    exit 1
  fi
fi

if [ "$GENERATE_APPCAST" -eq 1 ] &&
   [ -z "$NOTARY_PROFILE" ] &&
   [ -z "$NOTARY_KEY_PATH" ]; then
  echo "Appcast generation requires a notarized and stapled DMG." >&2
  echo "Provide --notary-profile or App Store Connect API key environment values." >&2
  exit 1
fi

if [ -z "$DMGBUILD_BIN" ] || [ ! -x "$DMGBUILD_BIN" ]; then
  echo "dmgbuild was not found. Install dmgbuild 1.6.7 or set HUN_DMGBUILD_BIN." >&2
  exit 1
fi
if [ ! -f "$DMG_SETTINGS" ] ||
   [ ! -f "$DMG_BACKGROUND_1X" ] ||
   [ ! -f "$DMG_BACKGROUND_2X" ]; then
  echo "DMG layout assets are missing from $ROOT/assets/dmg." >&2
  exit 1
fi

if [ -z "$SIGNING_IDENTITY" ]; then
  SIGNING_IDENTITIES="$(
    security find-identity -v -p codesigning |
      sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p'
  )"
  SIGNING_IDENTITY_COUNT="$(printf '%s\n' "$SIGNING_IDENTITIES" | awk 'NF { count++ } END { print count + 0 }')"

  if [ "$SIGNING_IDENTITY_COUNT" -ne 1 ]; then
    echo "Expected exactly one Developer ID Application identity; found $SIGNING_IDENTITY_COUNT." >&2
    echo "Set HUN_DEVELOPER_ID_APPLICATION to the identity to use." >&2
    security find-identity -v -p codesigning >&2
    exit 1
  fi

  SIGNING_IDENTITY="$SIGNING_IDENTITIES"
fi

echo "Using signing identity: $SIGNING_IDENTITY"
echo "Preparing release build directory: $BUILD_ROOT"
rm -rf "$DERIVED_DATA" "$DIST_DIR" "$APPCAST_ROOT"
mkdir -p "$DIST_DIR"

echo "Building Apple Silicon Release app..."
XCODE_OVERRIDES=(
  ARCHS=arm64
  ONLY_ACTIVE_ARCH=YES
  CODE_SIGNING_ALLOWED=NO
  "MARKETING_VERSION=$VERSION"
)
GO_BIN="${GO_BIN:-$(command -v go || true)}"
if [ -z "$GO_BIN" ] || [ ! -x "$GO_BIN" ]; then
  echo "Go toolchain not found. Install Go or set GO_BIN." >&2
  exit 1
fi
XCODE_OVERRIDES+=("GO_BIN=$GO_BIN")
if [ -n "$BUILD_NUMBER" ]; then
  XCODE_OVERRIDES+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
fi

HUN_CLI_VERSION="$CLI_VERSION" HUN_CLI_COMMIT="$CLI_COMMIT" xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA" \
  "${XCODE_OVERRIDES[@]}" \
  build

if [ ! -d "$APP" ]; then
  echo "Expected app was not produced: $APP" >&2
  exit 1
fi

if [ ! -x "$CLI" ]; then
  echo "Expected bundled hun CLI was not found or executable: $CLI" >&2
  exit 1
fi

if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
  echo "Expected Sparkle framework was not embedded: $SPARKLE_FRAMEWORK" >&2
  exit 1
fi

BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILT_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
BUILT_FEED_URL="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP/Contents/Info.plist")"
BUILT_PUBLIC_ED_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")"
BUILT_AUTOMATIC_CHECKS="$(/usr/libexec/PlistBuddy -c 'Print :SUEnableAutomaticChecks' "$APP/Contents/Info.plist")"
BUILT_AUTOMATIC_INSTALLS="$(/usr/libexec/PlistBuddy -c 'Print :SUAutomaticallyUpdate' "$APP/Contents/Info.plist")"
BUILT_CHECK_INTERVAL="$(/usr/libexec/PlistBuddy -c 'Print :SUScheduledCheckInterval' "$APP/Contents/Info.plist")"
if [ "$BUILT_VERSION" != "$VERSION" ]; then
  echo "Built app version mismatch: expected $VERSION, got $BUILT_VERSION" >&2
  exit 1
fi
if [[ ! "$BUILT_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "Built app has invalid CFBundleVersion: $BUILT_NUMBER" >&2
  exit 1
fi
if [ "$BUILT_FEED_URL" != "https://hun.sh/appcast.xml" ]; then
  echo "Built app has an unexpected Sparkle feed URL: $BUILT_FEED_URL" >&2
  exit 1
fi
if [ "$BUILT_PUBLIC_ED_KEY" != "rFCoDj0x69xciEJ/X/yO46HGdmdwd9YCR+3+H2c0pVk=" ]; then
  echo "Built app has an unexpected Sparkle public key." >&2
  exit 1
fi
if [ "$BUILT_AUTOMATIC_CHECKS" != "true" ] ||
   [ "$BUILT_AUTOMATIC_INSTALLS" != "false" ] ||
   [ "$BUILT_CHECK_INTERVAL" != "3600" ]; then
  echo "Built app has invalid Sparkle scheduling preferences." >&2
  echo "Automatic checks: $BUILT_AUTOMATIC_CHECKS" >&2
  echo "Automatic installs: $BUILT_AUTOMATIC_INSTALLS" >&2
  echo "Check interval: $BUILT_CHECK_INTERVAL" >&2
  exit 1
fi

APP_ARCHS="$(lipo -archs "$APP/Contents/MacOS/hun")"
CLI_ARCHS="$(lipo -archs "$CLI")"
if [ "$APP_ARCHS" != "arm64" ] || [ "$CLI_ARCHS" != "arm64" ]; then
  echo "Release contains unexpected architectures." >&2
  echo "App: $APP_ARCHS" >&2
  echo "CLI: $CLI_ARCHS" >&2
  exit 1
fi

echo "Signing bundled CLI..."
codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "$SIGNING_IDENTITY" \
  "$CLI"
"$ROOT/scripts/verify-macos-runtime.sh" \
  "$CLI" \
  "$CLI_VERSION" \
  "$CLI_COMMIT"

echo "Signing Sparkle helpers inside-out..."
SPARKLE_VERSION="$SPARKLE_FRAMEWORK/Versions/Current"
for helper in \
  "$SPARKLE_VERSION/XPCServices/Installer.xpc" \
  "$SPARKLE_VERSION/XPCServices/Downloader.xpc" \
  "$SPARKLE_VERSION/Autoupdate" \
  "$SPARKLE_VERSION/Updater.app"; do
  if [ ! -e "$helper" ]; then
    echo "Expected Sparkle signing target was not found: $helper" >&2
    exit 1
  fi
done
codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "$SIGNING_IDENTITY" \
  "$SPARKLE_VERSION/XPCServices/Installer.xpc"
codesign \
  --force \
  --options runtime \
  --timestamp \
  --preserve-metadata=entitlements \
  --sign "$SIGNING_IDENTITY" \
  "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "$SIGNING_IDENTITY" \
  "$SPARKLE_VERSION/Autoupdate"
codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "$SIGNING_IDENTITY" \
  "$SPARKLE_VERSION/Updater.app"
codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "$SIGNING_IDENTITY" \
  "$SPARKLE_FRAMEWORK"

echo "Signing app bundle..."
codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "$SIGNING_IDENTITY" \
  "$APP"

echo "Verifying app signature..."
codesign --verify --deep --strict --verbose=2 "$APP"

echo "Creating DMG..."
tiffutil \
  -cathidpicheck "$DMG_BACKGROUND_1X" "$DMG_BACKGROUND_2X" \
  -out "$DMG_BACKGROUND"
"$DMGBUILD_BIN" \
  -s "$DMG_SETTINGS" \
  -D "app=$APP" \
  -D "background=$DMG_BACKGROUND" \
  "Hun" \
  "$DMG"

echo "Signing DMG..."
codesign \
  --force \
  --timestamp \
  --identifier "sourabh.fun.hun.dmg" \
  --sign "$SIGNING_IDENTITY" \
  "$DMG"

hdiutil verify "$DMG"
codesign --verify --verbose=2 "$DMG"

if [ -n "$NOTARY_PROFILE" ] || [ -n "$NOTARY_KEY_PATH" ]; then
  echo "Submitting DMG for notarization..."
  if [ -n "$NOTARY_KEY_PATH" ]; then
    xcrun notarytool submit "$DMG" \
      --key "$NOTARY_KEY_PATH" \
      --key-id "$NOTARY_KEY_ID" \
      --issuer "$NOTARY_ISSUER_ID" \
      --wait
  else
    xcrun notarytool submit "$DMG" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait
  fi

  echo "Stapling notarization ticket..."
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
else
  cat <<EOF

The signed DMG is ready for notarization.
After storing notary credentials, run:

  scripts/package-macos-release.sh --version "$VERSION" --notary-profile PROFILE
EOF
fi

SHA256="$(shasum -a 256 "$DMG" | awk '{print $1}')"
printf '%s  %s\n' "$SHA256" "$(basename "$DMG")" > "$SHA_FILE"
ditto "$DMG" "$STABLE_DMG"

if [ "$GENERATE_APPCAST" -eq 1 ]; then
  SPARKLE_BIN="${HUN_SPARKLE_BIN:-$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin}"
  GENERATE_APPCAST_TOOL="$SPARKLE_BIN/generate_appcast"
  RELEASE_NOTES="$APPCAST_ROOT/$(basename "${DMG%.dmg}").md"
  APPCAST_DMG="$APPCAST_ROOT/$(basename "$DMG")"

  if [ ! -x "$GENERATE_APPCAST_TOOL" ]; then
    echo "Sparkle generate_appcast tool not found: $GENERATE_APPCAST_TOOL" >&2
    exit 1
  fi

  mkdir -p "$APPCAST_ROOT"
  ditto "$DMG" "$APPCAST_DMG"
  node "$ROOT/scripts/render-macos-release-notes.mjs" "$VERSION" "$RELEASE_NOTES"

  APPCAST_ARGUMENTS=(
    --download-url-prefix "https://github.com/sourabhrathourr/hun/releases/download/v$VERSION/"
    --embed-release-notes
    --full-release-notes-url "https://hun.sh/changelog"
    --link "https://hun.sh/changelog#v$VERSION"
    --maximum-deltas 0
    -o "$APPCAST"
    "$APPCAST_ROOT"
  )

  echo "Generating Sparkle appcast..."
  if [ -n "${HUN_SPARKLE_ED_PRIVATE_KEY:-}" ]; then
    printf '%s\n' "$HUN_SPARKLE_ED_PRIVATE_KEY" |
      "$GENERATE_APPCAST_TOOL" --ed-key-file - "${APPCAST_ARGUMENTS[@]}"
  else
    "$GENERATE_APPCAST_TOOL" \
      --account "$SPARKLE_ACCOUNT" \
      "${APPCAST_ARGUMENTS[@]}"
  fi

  if ! grep -q "sparkle:edSignature=" "$APPCAST"; then
    echo "Generated appcast does not contain an EdDSA archive signature." >&2
    exit 1
  fi
  if ! grep -q "hun-$VERSION-macos-arm64.dmg" "$APPCAST"; then
    echo "Generated appcast does not reference the expected DMG." >&2
    exit 1
  fi
fi

cat <<EOF

Release artifact:
  DMG:        $DMG
  Stable DMG: $STABLE_DMG
  SHA256:     $SHA256
  Checksum:   $SHA_FILE
  App arch:   $APP_ARCHS
  CLI arch:   $CLI_ARCHS
  Version:    $BUILT_VERSION ($BUILT_NUMBER)
EOF

if [ "$GENERATE_APPCAST" -eq 1 ]; then
  echo "  Appcast:    $APPCAST"
fi
