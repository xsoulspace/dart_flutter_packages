"""Train the slot-scoped permission head for PERM-GATE-1 attempt 2.

The trunk (a trained nursery checkpoint) stays the model contract; the
permission head is a SLOT artifact — a linear map [2, H] over the
normalized residual stream at the final real position, saved beside the
slot, never inside model.safetensors (param_names_and_shapes is the ONE
contract; pack_at_birth never sees this head).

Two arms:
  --mode head  freeze the trunk, train the linear head only (the honest
               first question: does the frozen trunk already linearly
               carry the ADR 0084 scope signal?)
  --mode full  fine-tune trunk + head at a small LR (the second question:
               was the signal absent, or just unread?)

Metrics per epoch are computed on the corpus eval split (model_def.split_of
law, ~10%). The FROZEN harness cases are never read here — only run_harness
scores the candidate, and its verdict is the acceptance. Corpus val numbers
are engineering evidence, and the all-abstain majority baseline is printed
beside them (the number to beat; attempt 1 measured exactly that baseline
on the frozen cases: 0.667).

Usage:
  ~/.venvs/mlx-ref/bin/python train_perm_head.py \
      --checkpoint ../../../bench/nursery/runs/rung1-scale-fast/checkpoint \
      --data ../../../bench/nursery/data/perm_corpus.jsonl \
      --out perm_head_rung1 --mode head
"""

import argparse
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
NURSERY = os.path.dirname(os.path.dirname(HERE))  # tool/nursery
sys.path.insert(0, NURSERY)

import model_def  # noqa: E402
import power_snapshot  # noqa: E402
from perm_dataset import ANSWERS, case_text  # noqa: E402


def sha256_file(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def load_corpus(path):
    rows = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if line:
                rec = json.loads(line)
                rows.append((rec["id"], case_text(rec), rec["answer"]))
    if not rows:
        raise SystemExit(f"empty corpus: {path}")
    return rows


def make_batches(rows, cfg, batch_size, seed, split):
    import random
    prepared = []
    for (eid, text, answer) in rows:
        if model_def.split_of(eid) != split:
            continue
        toks = model_def.encode_text(text, cfg.max_seq_len)
        if len(toks) >= 2:
            prepared.append((toks, ANSWERS.index(answer)))
    prepared.sort(key=lambda r: len(r[0]))
    batches = [prepared[i:i + batch_size]
               for i in range(0, len(prepared), batch_size)]
    random.Random(seed).shuffle(batches)
    return batches


def collate(batch):
    import mlx.core as mx
    import numpy as np
    T = max(len(t) for t, _ in batch)
    B = len(batch)
    tokens = np.full((B, T), model_def.EOS, dtype=np.int32)
    lengths = np.zeros(B, dtype=np.int32)
    ys = np.zeros(B, dtype=np.int32)
    for b, (toks, y) in enumerate(batch):
        tokens[b, :len(toks)] = toks
        lengths[b] = len(toks)
        ys[b] = y
    return mx.array(tokens), mx.array(lengths), mx.array(ys)


def final_features(out, lengths):
    """Normalized residual stream at each row's last REAL position —
    the same position the label head reads."""
    import mlx.core as mx
    final = out["final_hidden"]                       # [B,T,H]
    idx = mx.reshape(lengths - 1, [-1, 1, 1])
    return mx.take_along_axis(final, idx, axis=1)[:, 0, :]   # [B,H]


HEAD_HIDDEN = 64


def init_head(H, seed):
    """Head params for the recorded arch: linear [2,H] or MLP H->64->2.
    The scope law is a CONJUNCTION (grant AND in-workspace AND no veto);
    the linear arms measurably could not fit it (train CE plateau ~0.67),
    so the MLP is the third, mechanism-driven readout — still slot-scoped,
    still outside the model contract."""
    import mlx.core as mx
    mx.random.seed(seed)
    s = 1.0 / H ** 0.5
    lin = {"head.weight": (mx.random.normal([2, H]) * s).astype(mx.float32)}
    mlp = {
        "fc1.weight": (mx.random.normal([HEAD_HIDDEN, H]) * s).astype(mx.float32),
        "fc1.bias": mx.zeros([HEAD_HIDDEN], mx.float32),
        "fc2.weight": (mx.random.normal([2, HEAD_HIDDEN])
                       * (1.0 / HEAD_HIDDEN ** 0.5)).astype(mx.float32),
        "fc2.bias": mx.zeros([2], mx.float32),
    }
    return {"linear": lin, "mlp": mlp}


def head_logits(hidden, lengths, head, readout, arch):
    """Per-position head scores pooled to [B, 2] — shared by the trainer
    AND the candidate so the served rule cannot drift from the trained
    one. 'mean' pools over REAL positions (the init decay 0.27/token
    washes early path bytes out of the last position; pooling gives every
    byte a local vote)."""
    import mlx.core as mx
    if arch == "mlp":
        z = hidden @ head["fc1.weight"].T + head["fc1.bias"]
        # this mlx build has no mx.relu — maximum-with-zero, the same
        # idiom model_def uses for silu
        z = mx.maximum(z, mx.zeros_like(z))
        logits = z @ head["fc2.weight"].T + head["fc2.bias"]
    else:
        logits = hidden @ head["head.weight"].T            # [B,T,2]
    B, T, _ = logits.shape
    mask = (mx.arange(T)[None, :] < mx.reshape(lengths, [B, 1]))
    if readout == "last":
        idx = mx.reshape(lengths - 1, [-1, 1, 1])
        return mx.take_along_axis(logits, idx, axis=1)[:, 0, :]
    if readout == "mean":
        s = mx.sum(logits * mask[:, :, None], axis=1)
        return s / mx.sum(mask, axis=1)[:, None]
    if readout == "max":
        neg = mx.where(mask[:, :, None], logits,
                       mx.array(-1e30, logits.dtype))
        return mx.max(neg, axis=1)
    raise SystemExit(f"unknown readout: {readout}")


def evaluate(params, head, cfg, batches, readout, arch):
    import mlx.core as mx
    conf = {(a, b): 0 for a in ANSWERS for b in ANSWERS}
    for batch in batches:
        tokens, lengths, ys = collate(batch)
        out = model_def.forward_sequence_fast(params, cfg, tokens, lengths)
        logits = head_logits(out["final_hidden"], lengths, head,
                             readout, arch)
        pred = [int(v) for v in mx.argmax(logits, axis=1)]
        gold = [int(v) for v in ys]
        for p, g in zip(pred, gold):
            conf[(ANSWERS[g], ANSWERS[p])] += 1
    n = sum(conf.values())
    agreed = conf[("allow_once", "allow_once")] + conf[("abstain", "abstain")]
    unsafe = conf[("abstain", "allow_once")]
    n_allow = sum(conf[("allow_once", b)] for b in ANSWERS)
    return {
        "n": n,
        "agreement": round(agreed / n, 4) if n else None,
        "unsafe_allows": unsafe,
        "allow_rate": round(n_allow / n, 4) if n else None,
        "confusion": {"->".join(k): v for k, v in conf.items() if v},
    }


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--checkpoint", required=True)
    ap.add_argument("--data", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--mode", choices=["head", "full"], default="head")
    ap.add_argument("--epochs", type=int, default=10)
    ap.add_argument("--batch-size", type=int, default=16)
    ap.add_argument("--lr", type=float,
                    help="default: 5e-3 for head, 5e-5 for full")
    ap.add_argument("--readout", choices=["last", "mean", "max"],
                    default="mean",
                    help="pool per-position head scores over real "
                         "positions; 'last' matches the clause label head, "
                         "mean/max answer the decay-washout finding")
    ap.add_argument("--arch", choices=["linear", "mlp"], default="mlp",
                    help="linear head (attempts 1-2; could not fit the "
                         "law) or H->64->2 MLP readout")
    args = ap.parse_args(argv)

    import mlx.core as mx
    import mlx.optimizers as optimizers
    import numpy as np
    import safetensors.numpy

    lr = args.lr if args.lr is not None else (5e-3 if args.mode == "head"
                                              else 5e-5)
    arrays = safetensors.numpy.load_file(
        os.path.join(args.checkpoint, "model.safetensors"))
    params = {k: mx.array(np.asarray(v)) for k, v in arrays.items()}
    with open(os.path.join(args.checkpoint, "config.json")) as fh:
        cfg = model_def.NurseryConfig.from_json(json.load(fh))
    rows = load_corpus(args.data)

    H = cfg.hidden_size
    head = init_head(H, cfg.seed)[args.arch]

    train_batches = make_batches(rows, cfg, args.batch_size, cfg.seed,
                                 "train")
    val_batches = make_batches(rows, cfg, args.batch_size, cfg.seed, "eval")
    print(f"corpus: {len(train_batches)} train batches, "
          f"{sum(len(b) for b in val_batches)} val rows; mode={args.mode} "
          f"lr={lr}")

    base_val = evaluate(params, head, cfg, val_batches, args.readout,
                        args.arch)
    print(f"init (untrained head): {json.dumps(base_val)}")

    if args.mode == "head":
        def loss_fn(tree, tokens, lengths, ys):
            out = model_def.forward_sequence_fast(params, cfg, tokens,
                                                  lengths)
            return model_def.cross_entropy_mean(
                head_logits(out["final_hidden"], lengths, tree,
                            args.readout, args.arch), ys)

        # mlx optimizers demand a pytree (a bare array has no .update) —
        # the head travels as its own dict in this arm.
        trainable = dict(head)
    else:
        def loss_fn(tree, tokens, lengths, ys):
            hp = {k: tree[k] for k in head}
            out = model_def.forward_sequence_fast(tree, cfg, tokens,
                                                  lengths)
            return model_def.cross_entropy_mean(
                head_logits(out["final_hidden"], lengths, hp,
                            args.readout, args.arch), ys)

        params = dict(params)
        params.update(head)
        trainable = params

    vg = mx.value_and_grad(loss_fn)

    opt = optimizers.Adam(learning_rate=lr)
    import time
    t0 = time.time()
    for epoch in range(1, args.epochs + 1):
        running = 0.0
        for batch in train_batches:
            tokens, lengths, ys = collate(batch)
            total, grads = vg(trainable, tokens, lengths, ys)
            opt.update(trainable, grads)
            mx.eval(total, trainable)
            running += float(total.item())
        # opt.update mutates the tree in place — always read the head from
        # the tree, never the captured init array.
        cur = {k: trainable[k] for k in head}
        trunk = params if args.mode == "head" else trainable
        val = evaluate(trunk, cur, cfg, val_batches, args.readout,
                       args.arch)
        print(f"epoch {epoch}/{args.epochs} loss {running / len(train_batches):.4f}"
              f" val {json.dumps(val)} ({time.time() - t0:.0f}s)")

    final_head = {k: trainable[k] for k in head}
    val = evaluate(params, final_head, cfg, val_batches, args.readout,
                   args.arch)
    train_fit = evaluate(params, final_head, cfg,
                         train_batches[:max(1, len(train_batches) // 8)],
                         args.readout, args.arch)
    majority = max(
        sum(1 for (eid, _text, ans) in rows
            if model_def.split_of(eid) == "eval" and ans == cand)
        for cand in ANSWERS)
    n_eval = sum(1 for (eid, _, _) in rows
                 if model_def.split_of(eid) == "eval")

    os.makedirs(args.out, exist_ok=True)
    safetensors.numpy.save_file(
        {k: np.asarray(mx.astype(v, mx.float32))
         for k, v in final_head.items()},
        os.path.join(args.out, "head.safetensors"))
    meta = {
        "contract": "nursery.perm-head.v1",
        "checkpoint": os.path.abspath(args.checkpoint),
        "checkpoint_sha256": sha256_file(
            os.path.join(args.checkpoint, "model.safetensors")),
        "corpus": os.path.abspath(args.data),
        "corpus_sha256": sha256_file(args.data),
        "mode": args.mode, "lr": lr, "epochs": args.epochs,
        "batch_size": args.batch_size,
        "answers": ANSWERS,
        "readout": args.readout,
        "arch": args.arch,
        "val": val,
        "train_fit_sample": train_fit,
        "majority_baseline": {"agreement": round(majority / max(1, n_eval), 4),
                              "n": n_eval},
        "power": power_snapshot.snapshot(),
    }
    with open(os.path.join(args.out, "perm_meta.json"), "w") as fh:
        json.dump(meta, fh, indent=2, sort_keys=True)
    print(json.dumps({k: meta[k] for k in
                      ("val", "majority_baseline", "power")}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
