#!/bin/sh
# Run the MTP arm matrix (A -> D -> B -> C) on the shared record cache.
# Each arm is a single-variable change from the one before it, so each
# delta is attributable. See tool/nursery/mtp_retarget.py and MTP-GATES.md.
set -e
cd "$(dirname "$0")/../../../.." || exit 1

PKG=pkgs/xsoulspace_inference_mlx_native
PY=~/.venvs/mlx-ref/bin/python
CACHE=${1:-/tmp/mtp_records_bf16.pkl}
OUT=${2:-/tmp/mtp_arms}
STEPS=${3:-800}
MODEL=${4:-mlx-community/Qwen3-0.6B-bf16}
COUNT=${5:-1}

mkdir -p "$OUT"
for ARM in A D B C; do
  echo "===================== ARM $ARM ====================="
  $PY "$PKG/tool/nursery/mtp_retarget.py" \
    --model "$MODEL" --arm "$ARM" --count "$COUNT" \
    --steps "$STEPS" --batch 256 \
    --n-prompts 48 --holdout 12 --gen-tokens 192 --prompt-tokens 96 \
    --cache "$CACHE" --out "$OUT/arm$ARM.json" 2>&1 | grep -E "arm |accept_self|accept_teacher|tokens/cycle"
done
echo "===================== DONE ====================="
