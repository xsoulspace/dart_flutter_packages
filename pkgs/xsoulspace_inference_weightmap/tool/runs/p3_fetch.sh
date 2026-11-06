#!/usr/bin/env bash
# p3_fetch.sh — P-3 localization-bench artifact fetch (PREREG-D §P-3).
#
# Fetches the released ground-truth artifacts of github.com/RikiyaT/lm_understand-logs
# into $TMPDIR/p3-artifacts/ (NEVER the repo tree — probe scratch law) and writes a
# textual FETCH-RECEIPT.sha256 with one sha256 line per fetched file.
#
# Scope (deliberate non-fetches, recorded here so silence is never read as absence):
#   - exp3_language/networks/*/blocks.npz (3 x ~28 MB): model reading of the published
#     transformers is OUT OF SCOPE for this run (task scope = detector validation on a
#     synthetic toy + claimed-heads parse), so the weights are not fetched.
#   - exp3_language/runs/** (conversation logs): eval/heads.json is the distilled,
#     README-documented ground-truth log artifact; raw turn logs not needed.
#   - exp2_diffusion/eval/samples*.{txt,png}: rendered samples would leak the labels
#     the exp2 reader must recover from weights; deliberately not fetched.
#
# Usage:
#   p3_fetch.sh [--dry-run] [dest-dir]
#   --dry-run : print the plan JSON (files, urls, dest), NO network, exit 0.
#   dest-dir  : default ${TMPDIR:-/tmp}/p3-artifacts
#
# NAMED failures: FETCH_FAILED <path> (curl, non-optional), RECEIPT_WRITE_FAILED.
set -euo pipefail

BASE="https://raw.githubusercontent.com/RikiyaT/lm_understand-logs/main"
dry=0
dest=""
for a in "$@"; do
  case "$a" in
    --dry-run) dry=1 ;;
    *) dest="$a" ;;
  esac
done
dest="${dest:-${TMPDIR:-/tmp}/p3-artifacts}"

# Required artifact list (repo-relative paths under $BASE).
FILES=(
  # exp1 — which game: 4 tiny PPO policies + published key + layout description + meta
  exp1_which_game/README.md
  exp1_which_game/networks/description.txt
  exp1_which_game/networks/0bbcc3ea.npz
  exp1_which_game/networks/a9f535cc.npz
  exp1_which_game/networks/bdf99279.npz
  exp1_which_game/networks/dfc6cb65.npz
  exp1_which_game/networks/meta/0bbcc3ea.json
  exp1_which_game/networks/meta/a9f535cc.json
  exp1_which_game/networks/meta/bdf99279.json
  exp1_which_game/networks/meta/dfc6cb65.json
  exp1_which_game/eval/answer_key.json
  # exp2 — diffusion shapes: 3 tiny DDPMs + published key + description
  exp2_diffusion/networks/description.txt
  exp2_diffusion/networks/246a5b58.npz
  exp2_diffusion/networks/a6a9dfb7.npz
  exp2_diffusion/networks/d88aba69.npz
  exp2_diffusion/networks/training/circle_s0.json
  exp2_diffusion/networks/training/square_s0.json
  exp2_diffusion/networks/training/triangle_s0.json
  exp2_diffusion/eval/answer_key.json
  # exp3 — language: corpus manifest + THEIR rebuild script chain + claimed-heads log
  exp3_language/README.md
  exp3_language/python_dataset/corpus_sha256.txt
  exp3_language/python_dataset/files.tsv
  exp3_language/python_dataset/packages.txt
  exp3_language/python_dataset/rebuild_from_manifest.py
  exp3_language/python_dataset/stats.json
  exp3_language/python_dataset/scripts/tinylm/data.py
  exp3_language/python_dataset/scripts/tinylm2/data_big.py
  exp3_language/eval/heads.json
  exp3_language/eval/key.json
)

if [ "$dry" -eq 1 ]; then
  # Plan only. No network, no writes. JSON on stdout.
  printf '{"mode":"dry-run","script":"p3_fetch.sh","dest":"%s","base":"%s","network":false,"file_count":%d,"files":[' "$dest" "$BASE" "${#FILES[@]}"
  for i in "${!FILES[@]}"; do
    [ "$i" -gt 0 ] && printf ','
    printf '"%s"' "${FILES[$i]}"
  done
  printf ']}\n'
  exit 0
fi

mkdir -p "$dest"
fail=0
for f in "${FILES[@]}"; do
  mkdir -p "$dest/$(dirname "$f")"
  if curl -L -f --retry 3 --retry-all-errors -sS -o "$dest/$f" "$BASE/$f"; then
    echo "fetched $f"
  else
    echo "FETCH_FAILED $f" >&2
    fail=1
  fi
done
[ "$fail" -eq 0 ] || { echo "FETCH_FAILED: one or more required artifacts" >&2; exit 1; }

receipt="$dest/FETCH-RECEIPT.sha256"
{
  echo "# P-3 fetch receipt — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# source: $BASE"
  echo "# dest: $dest"
  ( cd "$dest" && find . -type f ! -name 'FETCH-RECEIPT.sha256' -print0 \
      | sort -z | xargs -0 shasum -a 256 ) | sed 's|\./||'
} > "$receipt" || { echo "RECEIPT_WRITE_FAILED $receipt" >&2; exit 1; }

echo "receipt: $receipt"
echo "files: $(grep -c . "$receipt" || true) lines (incl. 3 header lines)"
