#!/usr/bin/env bash

set -euo pipefail

RUNTIME="${1:-}"
EXPECTED_VERSION="${2:-}"
EXPECTED_COMMIT="${3:-}"

if [ -z "$RUNTIME" ]; then
  echo "Usage: scripts/verify-macos-runtime.sh RUNTIME [VERSION] [COMMIT]" >&2
  exit 2
fi

if [ ! -x "$RUNTIME" ]; then
  echo "Bundled Hun runtime is missing or not executable: $RUNTIME" >&2
  exit 1
fi

ARCHITECTURES="$(lipo -archs "$RUNTIME")"
if [ "$ARCHITECTURES" != "arm64" ]; then
  echo "Bundled Hun runtime must contain only arm64, got: $ARCHITECTURES" >&2
  exit 1
fi

if ! otool -l "$RUNTIME" |
  grep -Eq '^[[:space:]]*cmd LC_UUID$'; then
  echo "Bundled Hun runtime is missing the Mach-O LC_UUID load command." >&2
  echo "Build the macOS runtime with Go 1.24 or later." >&2
  exit 1
fi

set +e
VERSION_OUTPUT="$("$RUNTIME" version 2>&1)"
VERSION_STATUS=$?
set -e

if [ "$VERSION_STATUS" -ne 0 ]; then
  echo "Bundled Hun runtime could not execute:" >&2
  echo "$VERSION_OUTPUT" >&2
  exit 1
fi

VERSION_PATTERN='^hun\.sh[[:space:]][^[:space:]]+[[:space:]]\(commit:[[:space:]][^)]+\)$'
if [[ ! "$VERSION_OUTPUT" =~ $VERSION_PATTERN ]]; then
  echo "Bundled Hun runtime returned invalid version information:" >&2
  echo "$VERSION_OUTPUT" >&2
  exit 1
fi

if [ -n "$EXPECTED_VERSION" ]; then
  EXPECTED_OUTPUT="hun.sh $EXPECTED_VERSION"
  if [ -n "$EXPECTED_COMMIT" ]; then
    EXPECTED_OUTPUT="$EXPECTED_OUTPUT (commit: $EXPECTED_COMMIT)"
  fi
  if [ "$VERSION_OUTPUT" != "$EXPECTED_OUTPUT" ]; then
    echo "Bundled Hun runtime version mismatch." >&2
    echo "Expected: $EXPECTED_OUTPUT" >&2
    echo "Actual:   $VERSION_OUTPUT" >&2
    exit 1
  fi
fi

echo "Bundled Hun runtime verified: $VERSION_OUTPUT"
