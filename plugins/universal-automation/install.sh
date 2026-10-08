#!/usr/bin/env bash
# Build the universal-automation AOT binary (with the native macOS
# driver dylib) and put it on PATH. The mcp_flutter install pattern.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "$SCRIPT_DIR/../../pkgs/universal_automation_toolkit" && pwd)"

if command -v dart >/dev/null 2>&1; then
  DART_BIN="$(command -v dart)"
else
  DART_BIN="/Users/antonio/fvm/default/bin/dart"
fi

cd "$PKG_DIR"
"$DART_BIN" pub get
"$DART_BIN" build cli

BIN="$(ls "$PKG_DIR"/build/cli/*/bundle/bin/universal_automation 2>/dev/null | head -1)"
if [ -z "$BIN" ]; then
  echo "build did not produce a binary; falling back to the dart-run launcher" >&2
  exit 0
fi

TARGET_DIR="${UNIVERSAL_AUTOMATION_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$TARGET_DIR"
ln -sf "$BIN" "$TARGET_DIR/universal-automation"
echo "universal-automation -> $TARGET_DIR/universal-automation ($(head -c 0 "$BIN"; du -h "$BIN" | cut -f1))"
echo "ensure $TARGET_DIR is on PATH for MCP clients that resolve bare commands"
