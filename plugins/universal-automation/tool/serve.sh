#!/usr/bin/env bash
# MCP stdio launcher for universal_automation_toolkit.
# Prefers an installed AOT binary; falls back to `dart run` from the
# package directory (this plugin lives inside the dart_flutter_packages
# workspace).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "$SCRIPT_DIR/../../../pkgs/universal_automation_toolkit" && pwd)"

if command -v universal-automation >/dev/null 2>&1; then
  exec universal-automation serve "$@"
fi
cd "$PKG_DIR"
exec dart run bin/universal_automation.dart serve "$@"
