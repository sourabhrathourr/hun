#!/bin/sh
set -eu

# Release files come through hun.sh, which points at the current host.
BASE_URL="${HUN_DOWNLOAD_BASE:-https://hun.sh/releases}"
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

version="${HUN_VERSION:-latest}"
asset="hun_${os}_${arch}.tar.gz"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM

archive="$tmp_dir/$asset"
echo "Downloading hun ($version) for $os/$arch..."
if ! curl -fsSL "$BASE_URL/$version/$asset" -o "$archive"; then
  echo "Could not download $asset for $version." >&2
  exit 1
fi

# Check the archive against the release's published checksums.
if curl -fsSL "$BASE_URL/$version/checksums.txt" -o "$tmp_dir/checksums.txt"; then
  expected="$(grep " $asset\$" "$tmp_dir/checksums.txt" | cut -d ' ' -f 1 || true)"
  if command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$archive" | cut -d ' ' -f 1)"
  else
    actual="$(sha256sum "$archive" | cut -d ' ' -f 1)"
  fi
  if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
    echo "Checksum mismatch for $asset; not installing." >&2
    exit 1
  fi
else
  echo "Could not fetch checksums for $version." >&2
  exit 1
fi

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

echo "Installed $("$install_target" -v 2>/dev/null || echo hun)"
echo
cat <<'EOF'
 _                     
| |__  _   _ _ __      
| '_ \| | | | '_ \     
| | | | |_| | | | |    
|_| |_|\__,_|_| |_|    
EOF
echo "Welcome to hun."
echo "Run: hun -v"
echo "Next: hun onboard"
