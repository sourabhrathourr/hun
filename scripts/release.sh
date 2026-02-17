#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/release.sh --version <x.y.z|vX.Y.Z> [--dry-run] [--skip-tests] [--yes]

Examples:
  ./scripts/release.sh --version 0.1.0
  ./scripts/release.sh --version v0.1.0 --dry-run
EOF
}

VERSION=""
DRY_RUN=0
SKIP_TESTS=0
AUTO_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --skip-tests)
      SKIP_TESTS=1
      shift
      ;;
    --yes|-y)
      AUTO_YES=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  echo "Missing required --version argument." >&2
  usage
  exit 1
fi

if [[ "$VERSION" != v* ]]; then
  VERSION="v$VERSION"
fi

if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid version: $VERSION (expected semantic version like v0.1.0)" >&2
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not inside a git repository." >&2
  exit 1
fi

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" != "main" ]]; then
  echo "Release must be created from main branch (current: $BRANCH)." >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is not clean. Commit or stash changes first." >&2
  exit 1
fi

echo "Fetching latest refs from origin..."
git fetch origin main --tags --quiet

LOCAL_MAIN="$(git rev-parse HEAD)"
REMOTE_MAIN="$(git rev-parse origin/main)"
if [[ "$LOCAL_MAIN" != "$REMOTE_MAIN" ]]; then
  echo "Local main is not aligned with origin/main. Pull/push before release." >&2
  echo "local:  $LOCAL_MAIN" >&2
  echo "remote: $REMOTE_MAIN" >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null; then
  echo "Tag $VERSION already exists locally." >&2
  exit 1
fi

if git ls-remote --tags origin "refs/tags/$VERSION" | grep -q .; then
  echo "Tag $VERSION already exists on origin." >&2
  exit 1
fi

if [[ "$SKIP_TESTS" -eq 0 ]]; then
  echo "Running test suite..."
  go test ./...
  echo "Running race tests (core packages)..."
  go test -race ./internal/cli ./internal/daemon ./internal/detect ./internal/state ./internal/tui
fi

SHORT_SHA="$(git rev-parse --short HEAD)"
echo "Ready to release:"
echo "  version: $VERSION"
echo "  commit:  $SHORT_SHA"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Dry run complete. No tag was created."
  exit 0
fi

if [[ "$AUTO_YES" -ne 1 ]]; then
  read -r -p "Create and push tag $VERSION now? [y/N] " answer
  if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    echo "Release canceled."
    exit 1
  fi
fi

git tag -a "$VERSION" -m "$VERSION"
git push origin "$VERSION"

echo "Release tag pushed: $VERSION"
echo "Watch the GitHub Actions release workflow for publishing."
