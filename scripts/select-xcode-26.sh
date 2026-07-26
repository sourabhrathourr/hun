#!/usr/bin/env bash

set -euo pipefail

if [[ -z "${GITHUB_ENV:-}" ]]; then
  echo "GITHUB_ENV is required; this helper is intended for GitHub Actions." >&2
  exit 1
fi

xcode_path="/Applications/Xcode_26.4.1.app"
if [[ ! -d "$xcode_path" ]]; then
  echo "Xcode 26.4.1 is not installed at $xcode_path." >&2
  ls -1 /Applications | grep '^Xcode' || true
  exit 1
fi

echo "DEVELOPER_DIR=$xcode_path/Contents/Developer" >> "$GITHUB_ENV"
