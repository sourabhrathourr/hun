#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/apps/macos/hun/hun.xcodeproj"
SCHEME="hun"
CONFIGURATION="Release"
BUILD_ROOT="${HUN_MACOS_BETA_BUILD_DIR:-$ROOT/build/macos-beta}"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
DIST_DIR="$BUILD_ROOT/dist"
APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/hun.app"
CLI="$APP/Contents/Resources/hun"
CLI_VERSION="${HUN_CLI_VERSION:-v0.2.2}"
CLI_COMMIT="${HUN_CLI_COMMIT:-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo none)}"
EXPECTED_MIN_MACOS_VERSION="${HUN_MACOS_MIN_VERSION:-15.0}"
ZIP="$DIST_DIR/hun-macos-beta.zip"
SHA_FILE="$ZIP.sha256"
INSTALLER="$DIST_DIR/install-macos-beta.sh"
DOWNLOAD_URL="${HUN_MACOS_BETA_URL:-}"

usage() {
  cat <<'EOF'
Usage: scripts/package-macos-beta.sh [--url DOWNLOAD_URL]

Builds a Release hun.app, ad-hoc signs it, zips it with ditto, and writes a
SHA256 file. If --url is provided, also writes a ready-to-share installer script
to build/macos-beta/dist/install-macos-beta.sh.

Environment:
  HUN_MACOS_BETA_BUILD_DIR  Override the local build output directory.
  HUN_MACOS_BETA_URL        Same as --url.
  HUN_CLI_VERSION           Version embedded in the bundled CLI. Defaults to v0.2.2.
  HUN_CLI_COMMIT            Commit embedded in the bundled CLI. Defaults to git short SHA.
  HUN_MACOS_MIN_VERSION     Expected LSMinimumSystemVersion. Defaults to 15.0.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --url)
      if [ "$#" -lt 2 ]; then
        echo "Missing value for --url" >&2
        exit 1
      fi
      DOWNLOAD_URL="$2"
      shift 2
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

echo "Preparing beta build directory: $BUILD_ROOT"
rm -rf "$DERIVED_DATA" "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "Building $SCHEME ($CONFIGURATION)..."
echo "Bundled CLI version: $CLI_VERSION ($CLI_COMMIT)"
HUN_CLI_VERSION="$CLI_VERSION" HUN_CLI_COMMIT="$CLI_COMMIT" xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [ ! -d "$APP" ]; then
  echo "Expected app was not produced: $APP" >&2
  exit 1
fi

if [ ! -x "$CLI" ]; then
  echo "Expected bundled hun CLI was not found or executable: $CLI" >&2
  exit 1
fi

MIN_SYSTEM_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [ "$MIN_SYSTEM_VERSION" != "$EXPECTED_MIN_MACOS_VERSION" ]; then
  echo "App minimum macOS version mismatch." >&2
  echo "Expected: $EXPECTED_MIN_MACOS_VERSION" >&2
  echo "Actual:   ${MIN_SYSTEM_VERSION:-missing}" >&2
  exit 1
fi

CLI_REPORTED_VERSION="$("$CLI" --version 2>/dev/null | tr -d '\r')"
if [ "$CLI_REPORTED_VERSION" != "hun.sh $CLI_VERSION" ]; then
  echo "Bundled CLI version mismatch." >&2
  echo "Expected: hun.sh $CLI_VERSION" >&2
  echo "Actual:   $CLI_REPORTED_VERSION" >&2
  exit 1
fi

echo "Ad-hoc signing bundled CLI..."
codesign --force --sign - "$CLI"

echo "Ad-hoc signing app bundle..."
codesign --force --deep --sign - "$APP"

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP"

echo "Creating zip..."
ditto -c -k --keepParent "$APP" "$ZIP"

SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
printf '%s  %s\n' "$SHA256" "$(basename "$ZIP")" > "$SHA_FILE"

if [ -n "$DOWNLOAD_URL" ]; then
  sed \
    -e "s|^ZIP_URL=.*|ZIP_URL=\"\${HUN_MACOS_BETA_URL:-$DOWNLOAD_URL}\"|" \
    -e "s|^EXPECTED_SHA256=.*|EXPECTED_SHA256=\"\${HUN_MACOS_BETA_SHA256:-$SHA256}\"|" \
    "$ROOT/website/public/install-macos-beta.sh" > "$INSTALLER"
  chmod +x "$INSTALLER"
fi

cat <<EOF

Beta package is ready.

App:      $APP
Zip:      $ZIP
SHA256:   $SHA256
Checksum: $SHA_FILE
EOF

if [ -n "$DOWNLOAD_URL" ]; then
  cat <<EOF
Installer: $INSTALLER
EOF
else
  cat <<EOF

After uploading the zip, run this again with:
  scripts/package-macos-beta.sh --url "https://download-url/hun-macos-beta.zip"

Or update website/public/install-macos-beta.sh with:
  URL:    https://download-url/hun-macos-beta.zip
  SHA256: $SHA256
EOF
fi
