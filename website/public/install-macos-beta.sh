#!/bin/sh
set -eu

ZIP_URL="${HUN_MACOS_BETA_URL:-https://github.com/sourabhrathourr/hun/releases/download/v0.2.2/hun-macos-beta.zip}"
EXPECTED_SHA256="${HUN_MACOS_BETA_SHA256:-11f413ecf413fc782347cd6e6374cd818578b179a4a6dd1baa91be40dd498aaa}"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "hun macOS beta installer only supports macOS." >&2
  exit 1
fi

if [ "$ZIP_URL" = "__HUN_MACOS_BETA_ZIP_URL__" ] || [ -z "$ZIP_URL" ]; then
  cat >&2 <<'EOF'
This beta installer is not pointed at a build yet.

Upload hun-macos-beta.zip, then replace __HUN_MACOS_BETA_ZIP_URL__ and
__HUN_MACOS_BETA_SHA256__ in website/public/install-macos-beta.sh.
EOF
  exit 1
fi

if [ "$EXPECTED_SHA256" = "__HUN_MACOS_BETA_SHA256__" ] || [ -z "$EXPECTED_SHA256" ]; then
  echo "Missing expected SHA256 for hun-macos-beta.zip." >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM

zip_path="$tmp_dir/hun-macos-beta.zip"

remove_file() {
  path="$1"
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    return 0
  fi

  echo "Removing old hun CLI at $path..."
  if rm -f "$path" 2>/dev/null; then
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo rm -f "$path"
    return 0
  fi

  echo "Could not remove $path." >&2
  exit 1
}

is_hun_cli() {
  path="$1"
  [ -x "$path" ] || return 1
  version="$("$path" --version 2>/dev/null || true)"
  case "$version" in
    hun.sh*) return 0 ;;
    *) return 1 ;;
  esac
}

cleanup_existing_cli() {
  if [ "${HUN_MACOS_SKIP_CLI_CLEANUP:-0}" = "1" ]; then
    return 0
  fi

  echo "Checking for existing hun CLI installs..."

  removed=0
  if [ "${HUN_MACOS_SKIP_BREW_CLEANUP:-0}" != "1" ] && command -v brew >/dev/null 2>&1; then
    if brew list --formula hun >/dev/null 2>&1; then
      echo "Uninstalling Homebrew hun formula..."
      brew uninstall --formula --force hun
      removed=1
    fi
  fi

  candidate_file="$tmp_dir/hun-cli-candidates"
  {
    which -a hun 2>/dev/null || true
    printf '%s\n' \
      "/opt/homebrew/bin/hun" \
      "/usr/local/bin/hun" \
      "/opt/local/bin/hun" \
      "$HOME/go/bin/hun" \
      "$HOME/.local/bin/hun"
    if [ -n "${GOBIN:-}" ]; then
      printf '%s\n' "$GOBIN/hun"
    fi
  } | awk 'NF && !seen[$0]++' > "$candidate_file"

  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    if is_hun_cli "$candidate"; then
      remove_file "$candidate"
      removed=1
    fi
  done < "$candidate_file"

  if [ "$removed" = "0" ]; then
    echo "No old hun CLI binary found."
  fi
}

stop_existing_daemon() {
  if [ "${HUN_MACOS_SKIP_DAEMON_CLEANUP:-0}" = "1" ]; then
    return 0
  fi

  pid_file="$HOME/.hun/daemon.pid"
  socket_file="$HOME/.hun/daemon.sock"

  if [ -f "$pid_file" ]; then
    pid="$(tr -cd '0-9' < "$pid_file" | head -c 20 || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "Stopping existing hun daemon (pid $pid)..."
      kill "$pid" 2>/dev/null || true

      i=0
      while [ "$i" -lt 30 ]; do
        if ! kill -0 "$pid" 2>/dev/null; then
          break
        fi
        sleep 0.1
        i=$((i + 1))
      done

      if kill -0 "$pid" 2>/dev/null; then
        echo "Force stopping existing hun daemon (pid $pid)..."
        kill -KILL "$pid" 2>/dev/null || true
      fi
    fi
  fi

  rm -f "$pid_file" "$socket_file" 2>/dev/null || true
}

echo "Downloading hun macOS beta..."
curl -fL "$ZIP_URL" -o "$zip_path"

actual_sha256="$(shasum -a 256 "$zip_path" | awk '{print $1}')"
if [ "$actual_sha256" != "$EXPECTED_SHA256" ]; then
  echo "Checksum mismatch." >&2
  echo "Expected: $EXPECTED_SHA256" >&2
  echo "Actual:   $actual_sha256" >&2
  exit 1
fi

echo "Extracting..."
ditto -x -k "$zip_path" "$tmp_dir/extract"

app_path="$(find "$tmp_dir/extract" -maxdepth 2 -name 'hun.app' -type d | head -n 1 || true)"
if [ -z "$app_path" ]; then
  echo "hun.app was not found in the downloaded archive." >&2
  exit 1
fi

stop_existing_daemon
cleanup_existing_cli

install_dir="${HUN_MACOS_INSTALL_DIR:-/Applications}"
if [ ! -d "$install_dir" ] || [ ! -w "$install_dir" ]; then
  install_dir="$HOME/Applications"
  mkdir -p "$install_dir"
fi

target="$install_dir/hun.app"

echo "Installing hun to $target..."
rm -rf "$target"
ditto "$app_path" "$target"

echo "Removing quarantine for this beta app only..."
xattr -dr com.apple.quarantine "$target" 2>/dev/null || true

if [ "${HUN_MACOS_SKIP_OPEN:-0}" = "1" ]; then
  echo "Installed hun at $target"
  exit 0
fi

echo "Opening hun..."
open "$target"
