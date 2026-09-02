#!/usr/bin/env bash
# Stage M2b — delegation jail seeder (LLM-free).
#
# Seeds a disposable jail from a PARENT commit so a mined delegation
# (tool/mine_delegations.sh) replays the pre-fix state:
#
#   tool/seed_delegation.sh <commit> <package-path> [out-jail]
#
# Example:
#   tool/seed_delegation.sh 310bd71d pkgs/xsoulspace_inference_openrouter /tmp/jail_or
#
# The jail contains ONLY the package subtree at the parent commit plus a
# minimal pubspec workspace root if the package needs one. The task sentence
# comes from the manifest; the CHECK comes from the workspace convention
# (D8/M0) or --check — never from this script.

set -euo pipefail
cd "$(dirname "$0")/../../.."

COMMIT="${1:?usage: seed_delegation.sh <commit> <package-path> [out-jail]}"
PKG="${2:?usage: seed_delegation.sh <commit> <package-path> [out-jail]}"
JAIL="${3:-/tmp/delegation_$(basename "$PKG")_${COMMIT:0:8}}"
PARENT=$(git rev-parse "${COMMIT}^")

if [ -e "$JAIL" ]; then
  echo "refusing to overwrite existing jail: $JAIL" >&2
  exit 65
fi
mkdir -p "$JAIL"

# Extract the package subtree at the parent commit.
git archive "$PARENT" "$PKG" | tar -x -C "$JAIL"

# The package lands at $JAIL/$PKG — hoist it to the jail root so the
# workspace convention (pubspec.yaml at jail root) resolves.
shopt -s dotglob
mv "$JAIL/$PKG"/* "$JAIL"/ 2>/dev/null || true
rmdir -p "$JAIL/$PKG" 2>/dev/null || rm -rf "$JAIL/$PKG"

echo "seeded $JAIL from ${PARENT:0:8} ($PKG)"
echo "next: dart pub get && delegate with coding_agent.dart --jail $JAIL"
