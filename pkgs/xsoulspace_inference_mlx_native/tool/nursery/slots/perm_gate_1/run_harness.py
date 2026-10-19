"""Drive a candidate through PERM-GATE-1 and score it.

Two ways to supply answers:
1. --answers FILE — pre-recorded answers JSONL rows {"id", "answer"}.
2. --command '<cmd>' — a candidate transport: the frozen cases JSONL goes
   to the command's stdin; the command writes one answer JSON object per
   line to stdout, in case order: {"id": "pg-001", "answer": "allow_once"}.
   (The Dart/laya-serve adapter for a real RUNG-1 model lands with the
   model — Phase 2. This transport is the harness-side contract.)

Usage:
  python run_harness.py --command './my_candidate --decide' --out verdict.json
  python run_harness.py --answers answers.jsonl
"""

import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))  # tool/nursery
from gates.common import read_jsonl, sha256_file, stamp  # noqa: E402
from scorer import load_acceptance, score  # noqa: E402


def run_command(command, cases, excluded_kinds):
    case_payload = "".join(json.dumps(c, sort_keys=True) + "\n" for c in cases)
    result = subprocess.run(
        ["/bin/zsh", "-c", command], input=case_payload,
        capture_output=True, text=True, timeout=1800)
    if result.returncode != 0:
        raise SystemExit(
            f"candidate command failed ({result.returncode}): "
            f"{result.stderr[-800:]}")
    answers = []
    # The candidate answers every GATED case, in order — excluded kinds
    # (reads) get no answer, matching the scorer's contract. (Found by the
    # first real --command exercise, 2026-10-18: this path demanded one
    # answer per case while the scorer bounces excluded-read answers.)
    expected_ids = [c["id"] for c in cases
                    if c.get("kind") not in excluded_kinds]
    rows = [ln for ln in result.stdout.splitlines() if ln.strip()]
    if len(rows) != len(expected_ids):
        raise SystemExit(
            f"candidate emitted {len(rows)} answers for {len(expected_ids)} "
            f"gated cases ({len(cases) - len(expected_ids)} excluded reads "
            "get no answer) — one JSON object per gated case, in order")
    for cid, line in zip(expected_ids, rows):
        try:
            row = json.loads(line)
        except json.JSONDecodeError as e:
            raise SystemExit(f"unparsable candidate answer for {cid}: {line!r} ({e})")
        row.setdefault("id", cid)
        answers.append(row)
    return answers


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--cases", default=os.path.join(HERE, "cases.jsonl"))
    ap.add_argument("--acceptance", default=os.path.join(HERE, "acceptance.json"))
    ap.add_argument("--answers")
    ap.add_argument("--command")
    ap.add_argument("--out")
    args = ap.parse_args(argv)
    if bool(args.answers) == bool(args.command):
        ap.error("exactly one of --answers or --command is required")

    acceptance = load_acceptance(args.acceptance)
    cases = read_jsonl(args.cases)
    if args.command:
        answers = run_command(args.command, cases,
                              acceptance["excluded_kinds"])
        answers_path = os.path.join(
            os.path.dirname(os.path.abspath(args.out or "verdict.json")),
            "answers.jsonl")
        with open(answers_path, "w") as fh:
            for row in answers:
                fh.write(json.dumps(row, sort_keys=True) + "\n")
        print(f"answers recorded: {answers_path}")
    else:
        answers = read_jsonl(args.answers)
        answers_path = args.answers

    verdict = score(cases, answers, acceptance)
    print(json.dumps(verdict, indent=2))
    stamp([verdict], {"cases": args.cases, "answers": answers_path}, args.out)
    return 0 if verdict["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
