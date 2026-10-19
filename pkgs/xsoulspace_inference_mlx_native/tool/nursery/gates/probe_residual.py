"""Residual-stream separability probe at the label position (record-only).

The GATE-1 v2 re-target (TRAIN-GATES.md): the router's graded signal did
not separate clause kinds (2/64 poles at scale) while the label head reads
~0.83 from the residual stream — so the checklist now asks WHERE the
signal is. This tool measures it: for each label kind, the mean-difference
direction between that kind's final-position residual states and the rest,
and Cohen's d of the two classes' projections onto it, plus
nearest-centroid accuracy. Same d statistic as the pole gate, moved from
the router logits to the stream the label head actually reads.

This is a RECORDING probe, not a gate: it never passes or fails anything,
and any threshold for it must be written set-final in TRAIN-GATES.md
BEFORE the rung's first training run. In-sample by design (the pole gate's
d is in-sample too): separability, not generalization.

Usage:
  python probe_residual.py --checkpoint <ckpt-dir> \
      --data bench/nursery/data/clause_dataset.jsonl --out probe.json
  python probe_residual.py --self-test
"""

import argparse
import json
import os
import sys
import hashlib

sys.path.insert(0, os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))  # tool/nursery

import model_def  # noqa: E402
from common import add_self_test_flag, finish, read_jsonl, sha256_file  # noqa: E402

CONTRACT = "nursery.probe-residual.v1"


def md_direction_d(X, y, kind):
    """Cohen's d of kind-vs-rest along the mean-difference direction.
    X [N, D] float64, y [N] int labels. Returns (d, n_kind)."""
    import numpy as np
    a = X[y == kind]
    b = X[y != kind]
    if len(a) < 2 or len(b) < 2:
        return None, len(a)
    mu_a, mu_b = a.mean(axis=0), b.mean(axis=0)
    w = mu_a - mu_b
    norm = float(np.linalg.norm(w))
    if norm < 1e-12:
        return 0.0, len(a)
    w = w / norm
    pa, pb = a @ w, b @ w
    nu = len(a) + len(b) - 2
    if nu <= 0:
        return None, len(a)
    pooled = float(np.sqrt(
        ((len(a) - 1) * pa.var(ddof=1) + (len(b) - 1) * pb.var(ddof=1))
        / nu))
    if pooled < 1e-12:
        return float("inf"), len(a)
    return float((pa.mean() - pb.mean()) / pooled), len(a)


def nearest_centroid(X, y, kinds):
    import numpy as np
    centroids = {k: X[y == k].mean(axis=0) for k in kinds
                 if (y == k).sum() > 0}
    pred = np.array([min(centroids, key=lambda k: float(
        np.linalg.norm(x - centroids[k]))) for x in X])
    overall = float((pred == y).mean())
    recall = {}
    for k in kinds:
        m = y == k
        if m.sum():
            recall[int(k)] = round(float((pred[m] == k).mean()), 4)
    return round(overall, 4), recall


def self_test():
    import numpy as np
    rng = np.random.default_rng(0)
    cases = []
    n, D = 200, 32
    # Planted separation along dim 0. In-sample d on an ESTIMATED
    # direction is optimistically biased when the signal is small
    # relative to the D-1 noise dims (0.2 measures ~0.63 at D=32, n=200;
    # 1.5 measures ~1.64) — the bands below pin that behavior, and the
    # probe is read for ORDERINGS across checkpoints, not as an unbiased d.
    for delta, name, lo, hi in ((1.5, "planted d~1.5", 1.25, 2.0),
                                (0.2, "overlap stays sub-legible", 0.2, 0.9)):
        Xa = rng.normal(0, 1, (n, D))
        Xb = rng.normal(0, 1, (n, D))
        Xa[:, 0] += delta / 2.0
        Xb[:, 0] -= delta / 2.0
        X = np.concatenate([Xa, Xb])
        y = np.array([0] * n + [1] * n)
        d, nk = md_direction_d(X, y, 0)
        cases.append((f"{name}", True, d is not None and lo <= d <= hi))
    # Degenerate: one class only — recorded as "not enough data" (None),
    # never a crash and never a number.
    d_none, _ = md_direction_d(np.ones((10, 4)), np.zeros(10, int), 0)
    cases.append(("single-class -> d None", True, d_none is None))
    from common import self_test_main
    return self_test_main(sys.modules[__name__], cases)


def collect_features(checkpoint, data_path, split, batch_size, max_rows,
                     log):
    import mlx.core as mx
    import numpy as np
    import safetensors.numpy

    arrays = safetensors.numpy.load_file(
        os.path.join(checkpoint, "model.safetensors"))
    params = {k: mx.array(np.asarray(v)) for k, v in arrays.items()}
    with open(os.path.join(checkpoint, "config.json")) as fh:
        cfg = model_def.NurseryConfig.from_json(json.load(fh))

    rows = []
    for rec in read_jsonl(data_path):
        if rec.get("kind") not in model_def.LABEL_KINDS or not rec.get("text"):
            continue
        if model_def.split_of(rec["id"]) != split:
            continue
        rows.append((rec["id"], rec["kind"], rec["text"]))
    if max_rows:
        rows = rows[:max_rows]
    if not rows:
        raise SystemExit(f"no {split} rows in {data_path}")
    rows.sort(key=lambda r: len(model_def.encode_text(r[2], cfg.max_seq_len)))

    feats, labels = [], []
    label_id = {k: i for i, k in enumerate(cfg.label_kinds)}
    for i in range(0, len(rows), batch_size):
        chunk = rows[i:i + batch_size]
        T = max(len(model_def.encode_text(t, cfg.max_seq_len))
                for _, _, t in chunk)
        B = len(chunk)
        tokens = np.full((B, T), model_def.EOS, dtype=np.int32)
        lengths = np.zeros(B, dtype=np.int32)
        for b, (_, _, text) in enumerate(chunk):
            toks = model_def.encode_text(text, cfg.max_seq_len)
            tokens[b, :len(toks)] = toks
            lengths[b] = len(toks)
        out = model_def.forward_sequence_fast(
            params, cfg, mx.array(tokens), mx.array(lengths))
        idx = mx.reshape(mx.array(lengths) - 1, [-1, 1, 1])
        last = mx.take_along_axis(out["final_hidden"], idx, axis=1)[:, 0, :]
        feats.append(np.asarray(last))
        labels.extend(label_id[k] for _, k, _ in chunk)
        if (i // batch_size) % 5 == 0:
            log(f"  embedded {i + B}/{len(rows)}")
    return np.concatenate(feats), np.array(labels), cfg


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    add_self_test_flag(ap)
    ap.add_argument("--checkpoint")
    ap.add_argument("--data", default="bench/nursery/data/clause_dataset.jsonl")
    ap.add_argument("--split", choices=["eval", "train"], default="eval")
    ap.add_argument("--batch-size", type=int, default=16)
    ap.add_argument("--max-rows", type=int)
    ap.add_argument("--out")
    result, args = finish(argv, ap, self_test)
    if result is not None:
        return result
    if not args.checkpoint:
        ap.error("--checkpoint is required")

    report = {"contract": CONTRACT, "note": "record-only probe; "
              "thresholds live in TRAIN-GATES.md", "checkpoint":
              os.path.abspath(args.checkpoint), "data":
              os.path.abspath(args.data), "data_sha256":
              sha256_file(args.data), "split": args.split}

    def log(m):
        print(m, flush=True)

    X, y, cfg = collect_features(args.checkpoint, args.data, args.split,
                                 args.batch_size, args.max_rows, log)
    report["checkpoint_sha256"] = sha256_file(
        os.path.join(args.checkpoint, "model.safetensors"))
    report["n"] = int(len(y))
    report["hidden_size"] = cfg.hidden_size
    kinds = {}
    for i, k in enumerate(cfg.label_kinds):
        d, n_k = md_direction_d(X.astype("float64"), y, i)
        kinds[k] = {"d": None if d is None else round(d, 4),
                    "n": int(n_k)}
    report["per_kind_d"] = kinds
    ds = [v["d"] for v in kinds.values() if v["d"] is not None]
    if ds:
        report["d_min"] = round(min(ds), 4)
        report["d_p50"] = round(sorted(ds)[len(ds) // 2], 4)
    acc, recall = nearest_centroid(X, y, list(range(len(cfg.label_kinds))))
    report["nearest_centroid"] = {"accuracy": acc,
                                  "per_kind_recall": recall}
    text = json.dumps(report, indent=2, sort_keys=True)
    print(text)
    if args.out:
        with open(args.out, "w") as fh:
            fh.write(text + "\n")
        print(f"probe recorded: {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
