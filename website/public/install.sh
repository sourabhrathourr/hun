#!/bin/sh
set -eu

REPO="${HUN_REPO:-sourabhrathourr/hun}"
BIN_NAME="hun"

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$os" in
  darwin|linux) ;;
  *)
    echo "Unsupported operating system: $os" >&2
    exit 1
    ;;
esac

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64)
    arch="amd64"
    ;;
  arm64|aarch64)
    arch="arm64"
    ;;
  *)
    echo "Unsupported architecture: $arch" >&2
    exit 1
    ;;
esac

api_base="https://api.github.com/repos/$REPO"
version="${HUN_VERSION:-latest}"

if [ "$version" = "latest" ]; then
  release_api="$api_base/releases/latest"
else
  release_api="$api_base/releases/tags/$version"
fi

echo "Resolving hun release for $os/$arch..."
release_json="$(curl -fsSL \
  -H 'Accept: application/vnd.github+json' \
  -H 'User-Agent: hun-install-script' \
  "$release_api")"

tag="$(printf '%s\n' "$release_json" | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"

asset_url="$(printf '%s\n' "$release_json" \
  | sed 's#\\/#/#g' \
  | grep -Eo 'https://[^" ]+' \
  | grep '/releases/download/' \
  | grep "hun_${os}_${arch}" \
  | grep '\.tar\.gz$' \
  | head -n 1 || true)"

if [ -z "$asset_url" ]; then
  echo "Could not find release asset for $os/$arch in $REPO." >&2
  echo "Expected an archive like hun_${os}_${arch}*.tar.gz" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM

archive="$tmp_dir/hun.tar.gz"
echo "Downloading $asset_url"
curl -fL "$asset_url" -o "$archive"

tar -xzf "$archive" -C "$tmp_dir"
bin_path="$(find "$tmp_dir" -type f -name "$BIN_NAME" | head -n 1 || true)"

if [ -z "$bin_path" ]; then
  echo "Downloaded archive did not contain '$BIN_NAME'." >&2
  exit 1
fi

chmod +x "$bin_path"

install_dir="${HUN_INSTALL_DIR:-/usr/local/bin}"
install_target="$install_dir/$BIN_NAME"

need_sudo=0
if [ ! -d "$install_dir" ]; then
  if ! mkdir -p "$install_dir" 2>/dev/null; then
    need_sudo=1
  fi
fi

if [ $need_sudo -eq 0 ] && [ ! -w "$install_dir" ]; then
  need_sudo=1
fi

if [ $need_sudo -eq 1 ]; then
  if command -v sudo >/dev/null 2>&1; then
    echo "Installing to $install_target (sudo required)..."
    sudo install -m 0755 "$bin_path" "$install_target"
  else
    install_dir="$HOME/.local/bin"
    install_target="$install_dir/$BIN_NAME"
    mkdir -p "$install_dir"
    echo "Installing to $install_target"
    install -m 0755 "$bin_path" "$install_target"
    case ":$PATH:" in
      *":$install_dir:"*) ;;
      *)
        echo "Add $install_dir to your PATH:" >&2
        echo "  export PATH=\"$install_dir:\$PATH\"" >&2
        ;;
    esac
  fi
else
  echo "Installing to $install_target"
  install -m 0755 "$bin_path" "$install_target"
fi

echo "Installed hun ${tag:-latest}"
echo "Run: hun -v"
