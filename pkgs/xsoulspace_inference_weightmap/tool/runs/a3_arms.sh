#!/bin/zsh
# a3_arms.sh - run the 16 blind arms SERIALLY (plants first per the compute
# priority instruction), appending one hash-chained ledger row per arm.
# The run ORDER below is the only place the setup-time label map is used;
# every measurement stage reads only the blind arm dirs.
set -u
PKG=/Users/antonio/xs/storage_problem/dart_flutter_packages/pkgs/xsoulspace_inference_weightmap
W="${TMPDIR:-/tmp}/wm-a3"
SNAP="$HOME/.cache/huggingface/hub/models--mlx-community--Qwen3-0.6B-bf16/snapshots/42096995f6402fde107068cf530136fe64b604f8"
LOCK="${TMPDIR:-/tmp}/wm-device.lock"
PY="$HOME/.local/share/wm-mlx/bin/python"

PLANTS=(arm-002 arm-007 arm-009 arm-005 arm-015 arm-011 arm-012 arm-006)
NULLS=(arm-010 arm-001 arm-014 arm-004 arm-008 arm-000 arm-003 arm-013)

cd "$PKG" || exit 1
rc_total=0
for A in "${PLANTS[@]}" "${NULLS[@]}"; do
  echo "=== ARM $A start $(date -u +%H:%M:%S)"
  "$PY" -I tool/runs/a3_arm.py --arm-dir "$W/blind/$A" --snapshot "$SNAP" \
      --mirror-root "$W/mirrors" --runs-dir tool/runs --lock-dir "$LOCK" \
      > "$W/blind/$A/run.log" 2>&1
  rc=$?
  echo "=== ARM $A exit=$rc $(date -u +%H:%M:%S)"
  tail -2 "$W/blind/$A/run.log"
  "$PY" -I tool/runs/a3_ledger_arm.py --work "$W" --label "$A" \
      --out "$W/blind/$A/ledger_payload.json" >> "$W/blind/$A/run.log" 2>&1
  dart run tool/runs/a3_ledger.dart receipts/A3-run.jsonl a3-arm \
      "$W/blind/$A/ledger_payload.json" 2>&1 | tail -1
  if [ $rc -ne 0 ]; then rc_total=1; echo "ARM_BLOCKED $A (continuing; denominator recorded)"; fi
done
echo "ARMS_DONE rc_total=$rc_total"
