#!/usr/bin/env bash

set -euo pipefail

if [[ -z "${GITHUB_ENV:-}" ]]; then
  echo "GITHUB_ENV is required; this helper is intended for GitHub Actions." >&2
  exit 1
fi

xcode_path="$(
  find /Applications -maxdepth 1 -type d -name 'Xcode_26*.app' |
    sort |
    tail -1
)"
if [[ -z "$xcode_path" ]]; then
  echo "Xcode 26 is not installed on this runner." >&2
  ls -1 /Applications | grep '^Xcode' || true
  exit 1
fi

echo "DEVELOPER_DIR=$xcode_path/Contents/Developer" >> "$GITHUB_ENV"
