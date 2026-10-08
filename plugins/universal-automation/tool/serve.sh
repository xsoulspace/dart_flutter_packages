#!/usr/bin/env bash
# MCP launcher for universal_automation_toolkit.
# Preference order: PATH binary → built AOT bundle (install.sh output,
# carries the native macOS dylib) → `dart run` (JIT; absolute dart
# fallback for GUI clients with a thin PATH).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "$SCRIPT_DIR/../../../pkgs/universal_automation_toolkit" && pwd)"

if command -v universal-automation >/dev/null 2>&1; then
  exec universal-automation serve "$@"
fi
for candidate in \
  "$PKG_DIR"/build/cli/*/bundle/bin/universal-automation \
  "$PKG_DIR"/build/cli/*/bundle/bin/universal_automation; do
  if [ -x "$candidate" ]; then
    exec "$candidate" serve "$@"
  fi
done
if command -v dart >/dev/null 2>&1; then
  DART_BIN="$(command -v dart)"
else
  DART_BIN="/Users/antonio/fvm/default/bin/dart"
fi
cd "$PKG_DIR"
exec "$DART_BIN" run bin/universal_automation.dart serve "$@"
