"""GATE-2 — route persistence >= 0.70 BY TRAINING (TRAIN-GATES.md).

Metric (frozen, identical contract to bench/stage1_paged_moe/
analyze_routes.py): over held-out routing traces, the fraction of
consecutive token pairs (per layer) whose top-k expert SETS are exactly
equal. The 0.70 threshold is inherited from Line C's gate — frozen, not a
knob. This gate is how Line I proves persistence was TRAINED in, answering
the 0.4% the 30B measured (stage1_paged_moe/RESULTS.md).

Input: routes JSONL rows {"pos": <int>, "layer": <int>, "experts": [ids]}
— the stage1 trace format, so a nursery trace is analyzable by both tools.

Usage:
  python gate2_route_persistence.py --routes r.jsonl
  python gate2_route_persistence.py --self-test
"""

import argparse
import json
import sys
from collections import defaultdict

from common import add_self_test_flag, finish, read_jsonl

TARGET = 0.70  # frozen (Line C's gate; TRAIN-GATES.md)


def persistence(rows):
    """Overall one-step set-equality fraction + per-layer breakdown.
    Rows may carry an optional "seq" id; without one, the whole file is
    one sequence (order = row order)."""
    per_layer = defaultdict(lambda: [0, 0])
    prev = {}
    for row in rows:
        layer = row["layer"]
        cur = frozenset(row["experts"])
        key = (row.get("seq", ""), layer)
        if key in prev:
            stat = per_layer[layer]
            stat[1] += 1
            if cur == prev[key]:
                stat[0] += 1
        prev[key] = cur
    total_eq = sum(s[0] for s in per_layer.values())
    total_n = sum(s[1] for s in per_layer.values())
    if total_n == 0:
        raise SystemExit("no consecutive route pairs — checks must RAN")
    per_layer_frac = {l: (s[0] / s[1] if s[1] else None)
                      for l, s in sorted(per_layer.items())}
    return total_eq / total_n, per_layer_frac, total_n


def run(routes_path, out_path=None, target=TARGET):
    rows = read_jsonl(routes_path)
    fraction, per_layer, n = persistence(rows)
    passed = fraction >= target
    verdict = {
        "name": "GATE-2 route persistence",
        "passed": passed,
        "metric": round(fraction, 6),
        "detail": f"{n} consecutive pairs; per-layer "
                  + json.dumps({str(k): round(v, 4) for k, v in per_layer.items()})
                  + f"; frozen target {target}",
    }
    print(json.dumps(verdict, indent=2))
    if out_path:
        with open(out_path, "w") as fh:
            json.dump(verdict, fh, indent=2)
    return verdict


def self_test():
    cases = []
    persistent = [
        {"pos": i, "layer": 0, "experts": [0, 1]} for i in range(10)
    ] + [{"pos": i, "layer": 1, "experts": [2, 3]} for i in range(10)]
    fraction, per_layer, n = persistence(persistent)
    cases.append(("constant routes -> 1.0", 1.0, round(fraction, 6)))

    churning = [
        {"pos": i, "layer": 0, "experts": [0, 1] if i % 2 == 0 else [2, 3]}
        for i in range(10)
    ]
    fraction2, _, n2 = persistence(churning)
    cases.append(("alternating routes -> 0.0", 0.0, round(fraction2, 6)))

    v_pass = run_rows_verdict(persistent)
    cases.append(("passes at frozen 0.70", True, v_pass["passed"]))
    v_fail = run_rows_verdict(churning)
    cases.append(("churn fails at frozen 0.70", False, v_fail["passed"]))

    # A 30B-shaped trace: the measured 0.4% must fail loudly.
    barely = [
        {"pos": i, "layer": 0,
         "experts": [2, 3] if i % 250 == 0 else ([0, 1] if i % 2 == 0 else [2, 3])}
        for i in range(1000)
    ]
    fraction3, _, _ = persistence(barely)
    cases.append(("~0.4%-class churn fails", False, fraction3 >= TARGET))
    # 7 equal pairs / 999: each of the four override points makes (i,i+1)
    # repeat, and 250/500/750 also make (i-1,i) repeat.
    cases.append(("and the number is exactly 7/999", 0.007,
                  round(fraction3, 3)))

    from common import self_test_main
    return self_test_main(sys.modules[__name__], cases)


def run_rows_verdict(rows):
    fraction, _, _ = persistence(rows)
    return {"passed": fraction >= TARGET}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    add_self_test_flag(ap)
    ap.add_argument("--routes")
    ap.add_argument("--out")
    result, args = finish(argv, ap, self_test)
    if result is not None:
        return result
    if not args.routes:
        ap.error("--routes is required")
    verdict = run(args.routes, args.out)
    return 0 if verdict["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
