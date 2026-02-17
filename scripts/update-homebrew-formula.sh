#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/update-homebrew-formula.sh \
    --version <x.y.z|vX.Y.Z> \
    --checksums <path-to-checksums.txt> \
    --source-repo <owner/repo> \
    --tap-repo <owner/repo>

Required env:
  HOMEBREW_TAP_GITHUB_TOKEN
EOF
}

VERSION=""
CHECKSUMS=""
SOURCE_REPO=""
TAP_REPO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --checksums)
      CHECKSUMS="${2:-}"
      shift 2
      ;;
    --source-repo)
      SOURCE_REPO="${2:-}"
      shift 2
      ;;
    --tap-repo)
      TAP_REPO="${2:-}"
      shift 2
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

if [[ -z "$VERSION" || -z "$CHECKSUMS" || -z "$SOURCE_REPO" || -z "$TAP_REPO" ]]; then
  echo "Missing required arguments." >&2
  usage
  exit 1
fi

if [[ -z "${HOMEBREW_TAP_GITHUB_TOKEN:-}" ]]; then
  echo "Missing HOMEBREW_TAP_GITHUB_TOKEN environment variable." >&2
  exit 1
fi

if [[ "$VERSION" != v* ]]; then
  VERSION="v$VERSION"
fi
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid version: $VERSION (expected vX.Y.Z)" >&2
  exit 1
fi
VERSION_NO_V="${VERSION#v}"

if [[ ! -f "$CHECKSUMS" ]]; then
  echo "Checksums file not found: $CHECKSUMS" >&2
  exit 1
fi

checksum_for() {
  local file="$1"
  local sum
  sum="$(awk -v target="$file" '
    {
      name=$2
      sub(/^\*/, "", name)
      if (name == target) {
        print $1
        exit
      }
    }
  ' "$CHECKSUMS")"
  if [[ -z "$sum" ]]; then
    echo "Missing checksum for artifact: $file" >&2
    exit 1
  fi
  echo "$sum"
}

DARWIN_AMD64="hun_darwin_amd64.tar.gz"
DARWIN_ARM64="hun_darwin_arm64.tar.gz"
LINUX_AMD64="hun_linux_amd64.tar.gz"
LINUX_ARM64="hun_linux_arm64.tar.gz"

SHA_DARWIN_AMD64="$(checksum_for "$DARWIN_AMD64")"
SHA_DARWIN_ARM64="$(checksum_for "$DARWIN_ARM64")"
SHA_LINUX_AMD64="$(checksum_for "$LINUX_AMD64")"
SHA_LINUX_ARM64="$(checksum_for "$LINUX_ARM64")"

BASE_URL="https://github.com/${SOURCE_REPO}/releases/download/${VERSION}"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

CLONE_URL="https://x-access-token:${HOMEBREW_TAP_GITHUB_TOKEN}@github.com/${TAP_REPO}.git"
git clone "$CLONE_URL" "$TMP_DIR/tap" >/dev/null 2>&1

cd "$TMP_DIR/tap"
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
mkdir -p Formula

cat > Formula/hun.rb <<EOF
class Hun < Formula
  desc "Seamless project context switching for developers"
  homepage "https://hun.sh"
  version "${VERSION_NO_V}"
  license "MIT"

  if OS.mac?
    if Hardware::CPU.arm?
      url "${BASE_URL}/${DARWIN_ARM64}"
      sha256 "${SHA_DARWIN_ARM64}"
    else
      url "${BASE_URL}/${DARWIN_AMD64}"
      sha256 "${SHA_DARWIN_AMD64}"
    end
  elsif OS.linux?
    if Hardware::CPU.arm?
      url "${BASE_URL}/${LINUX_ARM64}"
      sha256 "${SHA_LINUX_ARM64}"
    else
      url "${BASE_URL}/${LINUX_AMD64}"
      sha256 "${SHA_LINUX_AMD64}"
    end
  end

  def install
    bin.install "hun"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/hun --version")
  end
end
EOF

if git diff --quiet -- Formula/hun.rb; then
  echo "Formula already up to date; nothing to commit."
  exit 0
fi

git config user.name "hun-bot"
git config user.email "bots@hun.sh"
git add Formula/hun.rb
git commit -m "formula: hun ${VERSION}" >/dev/null
git push origin "HEAD:${CURRENT_BRANCH}" >/dev/null

echo "Updated ${TAP_REPO}: Formula/hun.rb for ${VERSION}"
