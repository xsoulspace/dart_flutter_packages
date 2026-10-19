"""GATE-3 — label-vs-behavior agreement (TRAIN-GATES.md).

Metric (frozen): agreement = matched_ids / joined_ids between the
candidate's predicted labels on held-out clause data and the deterministic
teacher's labels. The teacher is canonical — ecsly_context's segmentText
marker tables, imported (never re-implemented) by the dataset exporter
(tool/nursery/export_clause_dataset.py). Threshold is per-rung config
(provisional >= 0.90 — set final before the first RUNG-0 run).

Missing ids on either side are a hard error: coverage must be complete, a
gate cannot pass on absent evidence ("checks RAN" law).

Inputs: --predictions rows {"id", "predicted"}; --labels rows {"id", "label"}
(one file with both sides is fine if --labels is omitted and predictions
carry "label").

Usage:
  python gate3_label_agreement.py --predictions p.jsonl --labels l.jsonl \
      --target 0.90
  python gate3_label_agreement.py --self-test
"""

import argparse
import json
import sys
from collections import Counter

from common import add_self_test_flag, finish, read_jsonl


def agreement(pred_rows, label_rows):
    labels = {}
    for row in label_rows:
        if "id" not in row or "label" not in row:
            raise SystemExit(f"label row missing id/label: {row}")
        if row["id"] in labels:
            raise SystemExit(f"duplicate label id: {row['id']}")
        labels[row["id"]] = row["label"]
    preds = {}
    for row in pred_rows:
        if "id" not in row or "predicted" not in row:
            raise SystemExit(f"prediction row missing id/predicted: {row}")
        if row["id"] in preds:
            raise SystemExit(f"duplicate prediction id: {row['id']}")
        preds[row["id"]] = row["predicted"]
    missing_preds = sorted(set(labels) - set(preds))
    missing_labels = sorted(set(preds) - set(labels))
    if missing_preds or missing_labels:
        raise SystemExit(
            f"incomplete coverage: {len(missing_preds)} id(s) without "
            f"predictions {missing_preds[:8]}, {len(missing_labels)} "
            f"prediction(s) without labels {missing_labels[:8]}")
    if not labels:
        raise SystemExit("no rows — checks must RAN, not skipped")
    confusion = Counter()
    matches = 0
    for cid, label in labels.items():
        pred = preds[cid]
        confusion[(label, pred)] += 1
        if pred == label:
            matches += 1
    return matches / len(labels), matches, len(labels), confusion


def run(pred_path, label_path, target, out_path=None):
    pred_rows = read_jsonl(pred_path)
    label_rows = read_jsonl(label_path) if label_path else [
        {"id": r["id"], "label": r["label"]}
        for r in pred_rows if "label" in r]
    if not label_rows:
        raise SystemExit("no labels: pass --labels or embed labels in the "
                         "prediction rows")
    frac, matches, total, confusion = agreement(pred_rows, label_rows)
    passed = frac >= target
    worst = ", ".join(f"{gold}->{pred}:{n}" for (gold, pred), n
                      in confusion.most_common(4) if gold != pred)
    verdict = {
        "name": "GATE-3 label agreement",
        "passed": passed,
        "metric": round(frac, 6),
        "detail": (f"{matches}/{total} agreed; teacher = deterministic "
                   f"segmentText; worst confusions: {worst or 'none'}; "
                   f"target {target}"),
    }
    print(json.dumps(verdict, indent=2))
    if out_path:
        with open(out_path, "w") as fh:
            json.dump(verdict, fh, indent=2)
    return verdict


def self_test():
    cases = []
    labels = [{"id": str(i), "label": "done" if i % 2 else "open"}
              for i in range(10)]
    preds9 = [{"id": str(i),
               "predicted": "done" if i % 2 else "open"} for i in range(10)]
    preds9[3]["predicted"] = "action"  # one disagreement
    frac, matches, total, confusion = agreement(preds9, labels)
    cases.append(("9/10 -> 0.9", 0.9, round(frac, 6)))
    cases.append(("confusion counts the miss", 1,
                  confusion.get(("done", "action"), 0)))

    v_pass = {"passed": frac >= 0.9}
    cases.append(("passes at target 0.9", True, v_pass["passed"]))
    v_strict = {"passed": frac >= 0.95}
    cases.append(("fails at target 0.95", False, v_strict["passed"]))

    # Coverage law: a missing prediction is a hard error, not a silent miss.
    preds_missing = preds9[:-1]
    errored = False
    try:
        agreement(preds_missing, labels)
    except SystemExit:
        errored = True
    cases.append(("missing id is a hard error", True, errored))

    from common import self_test_main
    return self_test_main(sys.modules[__name__], cases)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    add_self_test_flag(ap)
    ap.add_argument("--predictions")
    ap.add_argument("--labels")
    ap.add_argument("--target", type=float)
    ap.add_argument("--out")
    result, args = finish(argv, ap, self_test)
    if result is not None:
        return result
    if not args.predictions or args.target is None:
        ap.error("--predictions and --target are required")
    verdict = run(args.predictions, args.labels, args.target, args.out)
    return 0 if verdict["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
