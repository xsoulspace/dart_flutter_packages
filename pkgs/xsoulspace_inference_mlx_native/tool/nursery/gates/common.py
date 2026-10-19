"""Shared gate plumbing for the TRAIN-GATES.md oracles.

Laws implemented here (TRAIN-GATES.md):
- a gate verdict is computed from recorded evidence and stamped with the
  sha256 of every input, so a verdict is reproducible and auditable;
- a gate whose deterministic self-test oracle does not pass may not run on
  a real candidate;
- gate outputs are plain JSON with contract "nursery.train-gates.v1";
  correctness gates are never power-conditioned, so no power law here —
  any timed number stays under POWER.md, outside these gates.
"""

import argparse
import hashlib
import json
import sys

CONTRACT = "nursery.train-gates.v1"


def sha256_file(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def read_jsonl(path):
    rows = []
    with open(path) as fh:
        for n, line in enumerate(fh, 1):
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError as e:
                raise SystemExit(f"{path}:{n}: unparsable JSON row: {e}")
    return rows


def stamp(gates, inputs, out_path=None):
    """gates: list of dicts {name, passed, metric, detail}. Writes (when
    out_path given) and returns the stamped verdict document."""
    verdict = {
        "contract": CONTRACT,
        "all_pass": all(g["passed"] for g in gates),
        "gates": gates,
        "inputs": {name: sha256_file(path) for name, path in sorted(inputs.items())},
    }
    if out_path:
        with open(out_path, "w") as fh:
            json.dump(verdict, fh, indent=2, sort_keys=True)
        print(f"verdict: {out_path}")
    print(f"ALL GATES {'PASS' if verdict['all_pass'] else 'FAIL'}")
    return verdict


def self_test_main(module, cases):
    """Shared --self-test runner: cases = [(case_name, expected_passed,
    actual_passed_bool_or_exception)] — an exception counts as a FAIL
    verdict only when the case expects failure-by-error."""
    ok = True
    for name, expected, actual in cases:
        good = actual == expected
        ok = ok and good
        print(f"  {'ok ' if good else 'BAD'} {name}: expected {expected}, "
              f"got {actual}")
    print(f"self-test {'PASS' if ok else 'FAIL'}: {module.__name__}")
    return 0 if ok else 1


def add_self_test_flag(ap):
    ap.add_argument("--self-test", action="store_true",
                    help="run the frozen synthetic oracle and exit")


def finish(argv, ap, self_test_fn):
    args = ap.parse_args(argv)
    if args.self_test:
        return self_test_fn(), None
    return None, args
