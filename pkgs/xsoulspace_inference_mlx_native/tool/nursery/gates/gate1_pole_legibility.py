"""GATE-1 — pole legibility (TRAIN-GATES.md).

Metric (frozen): a pole is LEGIBLE when its recorded activations separate
the label classes — the largest pairwise Cohen's d across class means is
>= 1.0. legibility = legible_poles / poles_with_data; the gate compares it
against the rung's target (per-rung config; provisional rung-0 >= 0.60 —
set final in TRAIN-GATES.md before the first RUNG-0 training run).

Input: activations JSONL rows {"pole": <id>, "label": <str>, "value": <num>}
— one row per (pole, example) on the labeled probe set. A pole needs >= 2
values in each of >= 2 classes to be judged; poles without enough data are
counted in the denominator and reported (a gate cannot pass on absent
evidence — the "checks RAN" law).

Usage:
  python gate1_pole_legibility.py --activations a.jsonl --target 0.60
  python gate1_pole_legibility.py --self-test
"""

import argparse
import json
import sys
from collections import defaultdict

from common import add_self_test_flag, finish, read_jsonl

MIN_D = 1.0  # frozen: Cohen's d threshold for one legible pole


def cohens_d(a, b):
    """Pooled-sd Cohen's d between two value lists (both non-empty)."""
    n1, n2 = len(a), len(b)
    m1, m2 = sum(a) / n1, sum(b) / n2
    var1 = sum((x - m1) ** 2 for x in a) / (n1 - 1) if n1 > 1 else 0.0
    var2 = sum((x - m2) ** 2 for x in b) / (n2 - 1) if n2 > 1 else 0.0
    pooled = ((n1 - 1) * var1 + (n2 - 1) * var2) / (n1 + n2 - 2)
    if pooled == 0:
        # Identical values in every class: no separation unless the means
        # differ, which they cannot here. d = 0 by definition.
        return 0.0 if m1 == m2 else float("inf")
    return abs(m1 - m2) / (pooled ** 0.5)


def legibility(rows, min_d=MIN_D):
    """Returns (fraction, {pole: max_d or None}) over activation rows."""
    by_pole = defaultdict(lambda: defaultdict(list))
    for row in rows:
        by_pole[row["pole"]][row["label"]].append(float(row["value"]))
    judged = {}
    insufficient = 0
    for pole, by_label in by_pole.items():
        classes = {k: v for k, v in by_label.items() if len(v) >= 2}
        if len(classes) < 2:
            insufficient += 1
            judged[pole] = None
            continue
        labels = sorted(classes)
        best = 0.0
        for i, a in enumerate(labels):
            for b in labels[i + 1:]:
                best = max(best, cohens_d(classes[a], classes[b]))
        judged[pole] = best if best >= min_d else 0.0
    total = len(by_pole)
    legible = sum(1 for d in judged.values() if d is not None and d >= min_d)
    fraction = legible / total if total else 0.0
    return fraction, judged, insufficient, total


def run(activations_path, target, out_path=None):
    rows = read_jsonl(activations_path)
    if not rows:
        raise SystemExit("no activation rows — checks must RAN, not skipped")
    fraction, judged, insufficient, total = legibility(rows)
    unlabeled = [p for p, d in judged.items() if d is None]
    passed = fraction >= target
    verdict = {
        "name": "GATE-1 pole legibility",
        "passed": passed,
        "metric": round(fraction, 6),
        "detail": (f"{sum(1 for d in judged.values() if d is not None and d >= MIN_D)}/"
                   f"{total} poles legible (Cohen's d >= {MIN_D}); "
                   f"{insufficient} pole(s) without enough data"
                   + (f": {unlabeled[:8]}" if unlabeled else ""))
                   + f"; target {target}",
    }
    print(json.dumps(verdict, indent=2))
    if out_path:
        with open(out_path, "w") as fh:
            json.dump(verdict, fh, indent=2)
    return verdict


def self_test():
    cases = []

    # 10 poles: 8 perfectly separated (d = inf), 2 identical across classes
    # (d = 0) -> legibility exactly 0.8.
    rows = []
    for p in range(8):
        for label, base in (("fact", 0.0), ("done", 10.0)):
            for v in (base, base + 1.0, base - 1.0):
                rows.append({"pole": p, "label": label, "value": v})
    for p in range(8, 10):
        for label in ("fact", "done"):
            for v in (5.0, 5.0):
                rows.append({"pole": p, "label": label, "value": v})
    fraction, judged, insuff, total = legibility(rows)
    cases.append(("8/10 separated -> 0.8", 0.8, round(fraction, 6)))

    v_pass = run_rows_verdict(rows, 0.7)
    cases.append(("passes at target 0.7", True, v_pass["passed"]))
    v_fail = run_rows_verdict(rows, 0.9)
    cases.append(("fails at target 0.9", False, v_fail["passed"]))

    # A pole with one value in a class is unjudgeable: counted, not hidden.
    rows2 = rows + [{"pole": "thin", "label": "fact", "value": 1.0}]
    fraction2, _, insuff2, total2 = legibility(rows2)
    cases.append(("insufficient-data pole counted in denominator",
                  round(8 / 11, 6), round(fraction2, 6)))
    cases.append(("insufficient-data pole reported", 1, insuff2))

    # d exactly at the frozen threshold counts as legible.
    rows3 = []
    for label, base in (("a", 0.0), ("b", 1.0)):
        for v in (base, base + 1.0, base - 1.0):
            rows3.append({"pole": "d1", "label": label, "value": v})
    _, judged3, _, _ = legibility(rows3)
    cases.append(("d == 1.0 is legible (frozen MIN_D)", 1.0, judged3["d1"]))

    from common import self_test_main
    return self_test_main(sys.modules[__name__], cases)


def run_rows_verdict(rows, target):
    fraction, judged, insuff, total = legibility(rows)
    return {"passed": fraction >= target}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    add_self_test_flag(ap)
    ap.add_argument("--activations")
    ap.add_argument("--target", type=float)
    ap.add_argument("--out")
    result, args = finish(argv, ap, self_test)
    if result is not None:
        return result
    if not args.activations or args.target is None:
        ap.error("--activations and --target are required (the target comes "
                 "from the rung's config, never a default)")
    verdict = run(args.activations, args.target, args.out)
    return 0 if verdict["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
