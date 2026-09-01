#!/usr/bin/env bash
# Stage M2 — real-history replay miner (LLM-free).
#
# Mines this repo's own bugfix history into a delegation manifest (JSONL):
# one row per candidate task = {commit, sentence, package, files, tier}.
# The task sentence comes from the commit subject; the CHECK is NOT mined —
# D8/M0: the runner resolves the workspace convention itself (dart test /
# dart analyze / dart run main.dart), so the manifest carries intent, not
# per-task checker code.
#
# Usage: tool/mine_delegations.sh [count] [out.jsonl]
#   count  how many bugfix commits to mine (default 5)
#   out    manifest path (default benchmark/runs/delegation_manifest.jsonl)
#
# Honest boundary: the manifest is the problems-discovery artifact. Jail
# seeding (checking out the parent tree of each touched package into a
# disposable worktree) is the M2 follow-up — rows carry the parent hash so
# the seeder can be built without re-mining.

set -euo pipefail
cd "$(dirname "$0")/../../.."

COUNT="${1:-5}"
OUT="${2:-pkgs/xsoulspace_agentic_harness/benchmark/runs/delegation_manifest.jsonl}"
mkdir -p "$(dirname "$OUT")"

# Bugfix-class commits only; merge commits are not delegable tasks.
git log --no-merges --grep='^fix\|^bug\|^wip: fix' -i --format='%H|%P|%s' -n "$COUNT" |
while IFS='|' read -r hash parent subject; do
  [ -n "$hash" ] || continue
  files=$(git diff-tree --no-commit-id --name-only -r "$hash" | tr '\n' ' ')
  # Tier proposal from the diff shape (mechanical, advisory only):
  # a touched *_test.dart or a runs-checker suggests dart test; otherwise
  # analyze — the runner still resolves the authoritative convention.
  tier="dart_analyze"
  case "$files" in
    *_test.dart*|*test/*) tier="dart_test" ;;
  esac
  pkg=$(echo "$files" | tr ' ' '\n' | grep -o '^pkgs/[^/]*' | head -1)
  printf '{"commit":"%s","parent":"%s","sentence":%s,"package":"%s","files":"%s","proposed_tier":"%s"}\n' \
    "$hash" "$parent" \
    "$(printf '%s' "$subject" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')" \
    "$pkg" "$files" "$tier"
done > "$OUT"

echo "mined $(wc -l < "$OUT" | tr -d ' ') delegation candidate(s) → $OUT"
