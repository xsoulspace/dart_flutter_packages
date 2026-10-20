"""Action-conditioned critic over tool-call transitions (the H-JEPA transfer).

H-JEPA's transferable idea is not its planner (100 TFLOPs/episode is
unaffordable here) — it is that a *predictor* over (state, action) can score
a candidate future cheaply, and that this is a regression/classification
task, which is where small models actually work.

The harness already records predictions as beats (the ADR 0032 protocol:
predict before non-trivial work, retain predicted-vs-observed). That is a
SYMBOLIC discipline. This script asks the narrower, falsifiable question a
learned critic would have to answer before it earns a place beside it:

    given the last few tool calls, can a tiny model predict whether the
    NEXT call will fail?

Why this question: a critic that can flag "this next step is likely to
break" is the cheap half of planning — it routes to escalation without
needing a rollout. It is also a binary classification, the nursery's proven
strength (GATE-3 0.86), not generation.

Gate (frozen before the run): held-out AUC >= 0.65, split BY TURN so no
record from a turn appears in both sides. The trivial baseline (always
predict the majority class) scores AUC 0.5 by construction and is reported
beside the model so the comparison is visible.

Usage:
  python tool/nursery/beat_critic.py --traces traces.jsonl [--out critic.json]
"""

import argparse
import json
import math
import random
import sys


def load(path):
    recs = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if line:
                recs.append(json.loads(line))
    return recs


def featurize(recs):
    """Per-turn sequences -> (features, label) rows.

    Features are deliberately small and interpretable: the previous tool,
    whether it failed, the run length of consecutive successes, and the
    position in the turn. A critic that needs more than this is not the
    cheap critic we are testing for.
    """
    by_turn = {}
    for r in recs:
        by_turn.setdefault(r["turn"], []).append(r)
    tools = sorted({r["tool"] for r in recs})
    tool_idx = {t: i for i, t in enumerate(tools)}

    rows = []
    for turn, items in by_turn.items():
        streak = 0
        for i, r in enumerate(items):
            if i == 0:
                streak = 0
                prev_tool = -1
                prev_fail = 0.0
            else:
                prev = items[i - 1]
                prev_tool = tool_idx[prev["tool"]]
                prev_fail = 0.0 if prev["verified"] else 1.0
            feat = [0.0] * (len(tools) + 4)
            if prev_tool >= 0:
                feat[prev_tool] = 1.0
            feat[len(tools)] = prev_fail
            feat[len(tools) + 1] = min(streak, 8) / 8.0
            feat[len(tools) + 2] = min(i, 20) / 20.0
            feat[len(tools) + 3] = 1.0 if r["tool"] == "Bash" else 0.0
            rows.append((turn, feat, 0.0 if r["verified"] else 1.0))
            streak = streak + 1 if r["verified"] else 0
    return rows, tools


def split_by_turn(rows, seed=0):
    turns = sorted({r[0] for r in rows})
    random.Random(seed).shuffle(turns)
    cut = int(len(turns) * 0.7)
    train_t = set(turns[:cut])
    train = [r for r in rows if r[0] in train_t]
    test = [r for r in rows if r[0] not in train_t]
    return train, test


def auc(scores, labels):
    """Rank-based AUC (Mann-Whitney), ties counted half."""
    pos = [s for s, y in zip(scores, labels) if y > 0.5]
    neg = [s for s, y in zip(scores, labels) if y <= 0.5]
    if not pos or not neg:
        return float("nan")
    wins = 0.0
    for p in pos:
        for n in neg:
            wins += 1.0 if p > n else 0.5 if p == n else 0.0
    return wins / (len(pos) * len(neg))


def train_logreg(rows, epochs=400, lr=0.5, l2=1e-3):
    """Plain batch gradient descent — no dependency, fully reproducible."""
    d = len(rows[0][1])
    w = [0.0] * d
    b = 0.0
    n = len(rows)
    # class balance: failures are ~6%, so weight them up or the model learns
    # to answer "success" and scores AUC 0.5
    pos = sum(1 for r in rows if r[2] > 0.5)
    neg = n - pos
    w_pos = (n / (2.0 * pos)) if pos else 1.0
    w_neg = (n / (2.0 * neg)) if neg else 1.0
    for _ in range(epochs):
        gw = [0.0] * d
        gb = 0.0
        for _turn, x, y in rows:
            z = b + sum(wi * xi for wi, xi in zip(w, x))
            p = 1.0 / (1.0 + math.exp(-max(-30.0, min(30.0, z))))
            cw = w_pos if y > 0.5 else w_neg
            err = (p - y) * cw
            for j in range(d):
                gw[j] += err * x[j]
            gb += err
        for j in range(d):
            w[j] -= lr * (gw[j] / n + l2 * w[j])
        b -= lr * gb / n
    return w, b


def score(w, b, x):
    z = b + sum(wi * xi for wi, xi in zip(w, x))
    return 1.0 / (1.0 + math.exp(-max(-30.0, min(30.0, z))))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--traces", required=True)
    ap.add_argument("--out")
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args(argv)

    recs = load(args.traces)
    rows, tools = featurize(recs)
    train, test = split_by_turn(rows, args.seed)
    if not train or not test:
        raise SystemExit("split produced an empty side — need more turns")

    w, b = train_logreg(train)
    test_scores = [score(w, b, x) for _t, x, _y in test]
    test_labels = [y for _t, _x, y in test]
    train_scores = [score(w, b, x) for _t, x, _y in train]
    train_labels = [y for _t, _x, y in train]

    # trivial baseline: constant score -> AUC 0.5 by construction
    base_scores = [0.0] * len(test_labels)

    verdict = {
        "contract": "nursery.beat-critic.v1",
        "gate": {"auc_min": 0.65, "split": "by turn, 70/30"},
        "data": {
            "records": len(recs),
            "turns": len({r["turn"] for r in recs}),
            "failures": sum(1 for r in recs if not r["verified"]),
            "failure_rate": sum(1 for r in recs if not r["verified"]) / len(recs),
            "tools": tools,
        },
        "train": {"n": len(train), "auc": auc(train_scores, train_labels)},
        "test": {"n": len(test), "auc": auc(test_scores, test_labels)},
        "baseline": {"n": len(test), "auc": auc(base_scores, test_labels)},
        "passed": auc(test_scores, test_labels) >= 0.65,
    }
    text = json.dumps(verdict, indent=2, sort_keys=True)
    print(text)
    if args.out:
        with open(args.out, "w") as fh:
            fh.write(text + "\n")
    return 0 if verdict["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
