#!/bin/bash
# Line LB — S2 driver: completion@N over the scoped-tool-task bank.
# One isolated temp store + fresh sandbox per trial (no live-world contact,
# no cross-trial state); the executor route is the REAL one: admit ->
# realm_actor --once (native qwen binding, DurableCodingExecutor at HEAD,
# including the tool_proposal_absent terminal) -> receipt dump.
#
# Usage: s2_drive.sh EVIDENCE_DIR [N_REP] [SMOKE_TASKS]
# Frozen by MTP-GATES Part 8: N_REP=3, bank = loop_bench/bank.json (sha in
# the Part), maxInferenceStarts is the executor default path — see the Part
# for the trial budget law. GPU-SERIAL: never run beside another GPU
# consumer (lane serial-battery law).
set -uo pipefail

EVID="${1:?usage: s2_drive.sh EVIDENCE_DIR [N_REP] [SMOKE_TASKS]}"
N_REP="${2:-3}"
SMOKE="${3:-0}"

# realm_actor refuses a non-absolute --store (actor_store_path_not_absolute)
# — the invalid 2026-11-04 run-1 leg paid for a relative EVID. Normalize.
case "$EVID" in
  /*) ;;
  *) EVID="$(pwd)/$EVID" ;;
esac

DFP="/Users/antonio/xs/storage_problem/dart_flutter_packages/pkgs/xsoulspace_inference_mlx_native"
HARNESS="/Users/antonio/xs/ecsai_harness"
DART="/Users/antonio/fvm/default/bin/dart"
BANK="$DFP/tool/nursery/loop_bench/bank.json"
BUILDER="$DFP/tool/nursery/loop_bench/bank_build.py"

mkdir -p "$EVID/s2"
TRIALS="$EVID/s2_trials.jsonl"
: > "$TRIALS"

TASK_IDS=$(python3 -c "
import json
bank = json.load(open('$BANK'))
ids = [t['id'] for t in bank['tasks']]
print(' '.join(ids[:$SMOKE] if $SMOKE else ids))
")

for task in $TASK_IDS; do
  for rep in $(seq 1 "$N_REP"); do
    dir="$EVID/s2/${task}_${rep}"
    mkdir -p "$dir/store"
    spec_out=$(python3 "$BUILDER" --emit-sandbox "$task" "$dir/sandbox")
    verify_sha=$(printf '%s' "$spec_out" | python3 -c "import json,sys; print(json.load(sys.stdin)['verify_sha256'])")
    printf '%s' "$spec_out" | python3 -c "
import json, sys
spec = json.load(sys.stdin)
spec['requestId'] = 'lb-s2-${task}-${rep}'
spec['model'] = 'qwen'
spec['projectRoot'] = '$dir/sandbox'
spec['modelConfigurationRoot'] = '$HARNESS'
json.dump(spec, open('$dir/spec.json', 'w'), indent=1)
"
    t0=$(date +%s)
    task_id=$(cd "$HARNESS" && "$DART" run tool/lb_task_ctl.dart admit \
      --store "$dir/store" --spec "$dir/spec.json" \
      | python3 -c "import json,sys; print(json.load(sys.stdin)['taskId'])")
    (cd "$HARNESS" && "$DART" run pkgs/xsoulspace_agentic_afm/bin/realm_actor.dart \
      --store "$dir/store" --actor-id lb-qwen-01 --scheduler-id lb-s2 \
      --once) > "$dir/run.log" 2>&1
    run_rc=$?
    t1=$(date +%s)
    (cd "$HARNESS" && "$DART" run tool/lb_task_ctl.dart receipt \
      --store "$dir/store" --task "$task_id") > "$dir/receipt.json" 2>&1
    sha_after=$(shasum -a 256 "$dir/sandbox/test/verify_test.dart" | cut -d' ' -f1)
    python3 - "$dir/receipt.json" "$task" "$rep" "$run_rc" "$((t1 - t0))" \
        "$verify_sha" "$sha_after" >> "$TRIALS" <<'PYEOF'
import json, sys
receipt_path, task, rep, rc, wall, sha_before, sha_after = sys.argv[1:8]
try:
    rec = json.load(open(receipt_path))
    t = rec.get('task') or {}
    state = t.get('state')
    terminal = t.get('terminal') or {}
    reason = terminal.get('reason') or t.get('reason')
    result = (rec.get('result') or {}).get('result') or {}
    decisions = result.get('decisions')
    moves = result.get('moves')
except Exception as e:  # noqa: BLE001 - a broken receipt is data, not a crash
    state, reason, decisions, moves = None, f'receipt_unreadable:{e}', None, None
if not reason:
    # the runner's own stdout line carries the terminal reason
    import re
    try:
        log = open(receipt_path.replace('receipt.json', 'run.log')).read()
        m = re.search(r'reason=(\S+)', log)
        reason = m.group(1) if m else reason
    except OSError:
        pass
row = {
    'task': task, 'rep': int(rep), 'run_rc': int(rc),
    'state': state, 'succeeded': state == 'succeeded',
    'reason': reason, 'decisions': decisions, 'moves': moves,
    'wall_s': int(wall),
    'verify_sha_intact': sha_before == sha_after,
}
print(json.dumps(row))
PYEOF
    echo "[s2] ${task} rep=${rep} rc=${run_rc} $(tail -1 "$TRIALS")"
  done
done

python3 - "$TRIALS" "$EVID/s2_receipts.json" "$SMOKE" <<'PYEOF'
import json, sys
trials_path, out_path, smoke = sys.argv[1:4]
bank_n = len(json.load(open(
    '/Users/antonio/xs/storage_problem/dart_flutter_packages/pkgs/'
    'xsoulspace_inference_mlx_native/tool/nursery/loop_bench/bank.json'
))['tasks'])
trials = [json.loads(l) for l in open(trials_path) if l.strip()]
json.dump({'n_bank': bank_n, 'smoke': int(smoke), 'trials': trials},
          open(out_path, 'w'), indent=1)
print(f'[s2] aggregated {len(trials)} trials -> {out_path}')
PYEOF
