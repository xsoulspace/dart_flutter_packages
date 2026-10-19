"""Run record (Phase 2, item 7) — produced the 3-step smoke record
(bench/nursery/runs/smoke/RUN-RECORD.md, 2026-10-18).

Stamps one nursery run's RECORD: what was predicted, what was observed,
under which power, against which frozen gates. Recording is not grading —
the gates already ran (run_gates.py) and this tool quotes their verdicts;
it adds the provenance a later reader needs: code revision, dataset
digest, power truth (POWER.md charge-current law: Amperage, not pmset),
and the predicted-vs-observed discipline (ADR 0032 protocol).

Usage (after a real training run + pack + gates):
  python tool/nursery/record_run.py --run bench/nursery/runs/rung0-first \
      --config tool/nursery/rung0.json \
      --prediction "route persistence clears 0.70 once lam_route engages" \
      --observed "<what actually happened>"
Writes RUN-RECORD.md + record.json into the run dir.
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import power_snapshot  # noqa: E402


def sha256_file(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def git_rev(pkg_root):
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"], cwd=pkg_root,
            capture_output=True, text=True, timeout=10)
        return out.stdout.strip() or "unknown"
    except (OSError, subprocess.TimeoutExpired):
        return "unknown"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--run", required=True, help="run dir (train_rung0 output)")
    ap.add_argument("--config", required=True, help="rung json used")
    ap.add_argument("--prediction", required=True,
                    help="one-line prediction, made BEFORE the run (ADR 0032)")
    ap.add_argument("--observed", required=True,
                    help="what actually happened, honestly")
    ap.add_argument("--pkg-root", default=os.path.dirname(os.path.dirname(HERE)),
                    help="package root for git provenance")
    args = ap.parse_args(argv)

    meta_path = os.path.join(args.run, "meta.json")
    gates_path = os.path.join(args.run, "gates.json")
    if not os.path.exists(meta_path):
        raise SystemExit(f"{meta_path} missing — record_run quotes a real run")
    meta = json.load(open(meta_path))
    gates = json.load(open(gates_path)) if os.path.exists(gates_path) else None

    power_now = power_snapshot.snapshot()
    record = {
        "when_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "git_rev": git_rev(args.pkg_root),
        "rung": meta.get("rung"),
        "config": meta.get("config"),
        "dataset": meta.get("dataset"),
        "power_at_run": meta.get("power"),
        "power_at_record": power_now,
        "gates": gates,
        "prediction": args.prediction,
        "observed": args.observed,
        "non_claims": [
            "a gate PASS is eligibility for the next rung, not capability",
            "no tok/s or energy claim unless measured under real charge current",
        ],
    }
    record_path = os.path.join(args.run, "record.json")
    with open(record_path, "w") as fh:
        json.dump(record, fh, indent=2, sort_keys=True)

    gate_lines = "(gates.json absent — gates were not run)"
    if gates:
        gate_lines = "\n".join(
            f"- {g['name']}: {'PASS' if g['passed'] else 'FAIL'} — {g['metric']} "
            f"({g['detail']})" for g in gates.get("gates", []))
        gate_lines += f"\n- ALL: {'PASS' if gates.get('all_pass') else 'FAIL'}"

    md = f"""# Run record — {record['rung']} ({record['when_utc']})

- code: `{record['git_rev']}` | dataset `{meta.get('dataset', {}).get('sha256', '?')[:16]}...`
- power at run: `{json.dumps(meta.get('power'))}`
- power at record: `{json.dumps(power_now)}`
- **prediction (before):** {args.prediction}
- **observed (after):** {args.observed}

## Gates (frozen oracles; recording their verdicts, not re-grading)

{gate_lines}

## Non-claims

{chr(10).join('- ' + c for c in record['non_claims'])}
"""
    md_path = os.path.join(args.run, "RUN-RECORD.md")
    with open(md_path, "w") as fh:
        fh.write(md)
    print(f"record: {record_path}")
    print(f"record: {md_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
