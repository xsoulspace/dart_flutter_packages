"""RUNG-0 training loop (Phase 2, item 5) — pipeline-proven by a 3-step
smoke (bench/nursery/runs/smoke/, 2026-10-18: train → pack → run_gates →
record_run end-to-end; gates ruled ALL-FAIL as expected for an untrained
model). The REAL RUNG-0 run (full dataset, real step count) is still owed
and belongs to the operator, on real power, after the TRAIN-GATES.md
launch checklist (GATE-1/3 provisional targets set final) — the checklist
is recorded in rung0.json.

What one run does:
  1. reads rung0.json + the clause dataset (teacher labels ride IN the
     dataset from export_clause_dataset.py — never re-labeled here);
  2. trains model_def.losses (lm CE + label CE + router margin hinge +
     route smoothness) with Adam, batch = 1 example;
  3. saves the checkpoint (f32, pack_at_birth-ready) and runs the eval
     split, exporting the gate inputs:
       traces/routes.jsonl       GATE-2 rows {seq, pos, layer, experts}
       traces/activations.jsonl  GATE-1 rows {pole, label, value}
       traces/predictions.jsonl  GATE-3 rows {id, predicted, label}
       traces/margins.json       per-layer top1-top2 gap stats — the
                                 pre-registered sub-0.70 GATE-2 reading
                                 (TRAIN-GATES.md) consumes this
  4. writes meta.json (config, dataset sha256, final losses, power
     snapshot) — recording, not grading: the gates in tool/nursery/gates/
     read these files and decide. This script cannot pass anything.

Usage (first run, on real power):
  ~/.venvs/mlx-ref/bin/python tool/nursery/train_rung0.py \
      --rung tool/nursery/rung0.json \
      --data bench/nursery/data/clause_dataset.jsonl \
      --out bench/nursery/runs/rung0-first
Then:
  python tool/nursery/pack_at_birth.py --checkpoint <out>/checkpoint \
      --store <out>/store
  python tool/nursery/gates/run_gates.py --config tool/nursery/rung0.json \
      --store <out>/store --routes <out>/traces/routes.jsonl \
      --activations <out>/traces/activations.jsonl \
      --predictions <out>/traces/predictions.jsonl \
      --out <out>/gates.json
"""

import argparse
import hashlib
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import model_def  # noqa: E402
import power_snapshot  # noqa: E402


def load_dataset(path, kinds=None):
    """[(id, kind, text)] — teacher labels come from the dataset, stamped by
    export_clause_dataset.py's segmenter sha256. Rows without a known kind
    are skipped LOUDLY (a count in meta.json), never silently. `kinds`
    overrides the default clause kinds (the perm-e2e slot trains the label
    head on [abstain, allow_once])."""
    kinds = set(kinds or model_def.LABEL_KINDS)
    rows, skipped = [], 0
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            rec = json.loads(line)
            if rec.get("kind") not in kinds or not rec.get("text"):
                skipped += 1
                continue
            rows.append((rec["id"], rec["kind"], rec["text"]))
    if not rows:
        raise SystemExit(f"no usable rows in {path} — refusing to train on nothing")
    return rows, skipped


def sha256_file(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def make_batches(rows, cfg, batch_size, seed):
    """Length-bucketed batches: sort by token length, slice, shuffle the
    BATCH order (positions never pad beyond a bucket's max, and the shuffle
    decorrelates length from training progress). Returns (batches,
    steps_per_epoch); a batch is a list of (tokens, label_id)."""
    import random

    prepared = []
    for (eid, kind, text) in rows:
        if model_def.split_of(eid) != "train":
            continue
        toks = model_def.encode_text(text, cfg.max_seq_len)
        if len(toks) >= 2:
            prepared.append((toks, cfg.label_kinds.index(kind)))
    prepared.sort(key=lambda r: len(r[0]))
    batches = [prepared[i:i + batch_size]
               for i in range(0, len(prepared), batch_size)]
    random.Random(seed).shuffle(batches)
    return batches


def collate(batch, eos):
    """Right-pad with EOS; positions past each example's length are masked
    inside losses_fast, so pads never contribute (loss, margins, or
    gradients) and the real prefix is bit-for-bit the model's input."""
    import mlx.core as mx
    import numpy as np

    T = max(len(t) for t, _ in batch)
    B = len(batch)
    tokens = np.full((B, T), eos, dtype=np.int32)
    lengths = np.zeros(B, dtype=np.int32)
    label_ids = np.zeros(B, dtype=np.int32)
    for b, (toks, lab) in enumerate(batch):
        tokens[b, :len(toks)] = toks
        lengths[b] = len(toks)
        label_ids[b] = lab
    return (mx.array(tokens), mx.array(lengths), mx.array(label_ids))


def warm_start(params, init_from, log):
    """Load every name+shape-matching tensor from a checkpoint; leave the
    rest at their init (the perm-domain phase warm-starts clause trunks
    whose label head has a DIFFERENT shape — [4, H] kinds vs [2, H]
    answers — which must reinit, not crash, and must be visible)."""
    import numpy as np
    import safetensors.numpy
    import mlx.core as mx

    arrays = safetensors.numpy.load_file(
        os.path.join(init_from, "model.safetensors"))
    matched, skipped = [], []
    for k, v in arrays.items():
        if k in params and tuple(params[k].shape) == tuple(np.asarray(v).shape):
            params[k] = mx.array(np.asarray(v))
            matched.append(k)
        else:
            skipped.append(k)
    log(f"init-from {init_from}: {len(matched)} tensors warm, "
        f"{len(skipped)} left at init {sorted(skipped)}")
    return {"path": os.path.abspath(init_from), "warm": len(matched),
            "reinit": sorted(skipped)}


def train_fast(cfg, rung, rows, out_dir, log, init_from=None):
    """The batched fast path (model_def.losses_fast; equivalence pinned by
    train_parity_smoke.py). `steps` counts BATCH steps; eval stays on the
    pinned stepwise path."""
    import time
    import mlx.core as mx
    import mlx.optimizers as optimizers

    batch_size = int(rung["training"].get("batch_size", 16))
    save_every = int(rung["training"].get("save_every", 0))
    batches = make_batches(rows, cfg, batch_size, cfg.seed)
    if not batches:
        raise SystemExit("fast path produced no batches")
    log(f"fast path: {len(batches)} batches/epoch at batch {batch_size}")

    params = model_def.init_params(cfg)
    init_meta = None
    if init_from:
        init_meta = warm_start(params, init_from, log)
    optimizer = optimizers.Adam(learning_rate=rung["training"]["learning_rate"])

    def loss_fn(p, tokens, lengths, label_ids):
        total, _ = model_def.losses_fast(p, cfg, tokens, lengths, label_ids)
        return total

    value_and_grad = mx.value_and_grad(loss_fn)
    steps = int(rung["training"]["steps"])
    log_every = int(rung["training"]["log_every"])
    cursor, epoch = 0, 0
    running, t0 = 0.0, time.time()
    window = []
    for step in range(1, steps + 1):
        if cursor >= len(batches):
            cursor = 0
            epoch += 1
        batch = batches[cursor]
        cursor += 1
        tokens, lengths, label_ids = collate(batch, model_def.EOS)
        total, grads = value_and_grad(params, tokens, lengths, label_ids)
        # A NaN/inf loss must not poison the weights (phase B v1 diverged
        # mid-run at lr 3e-3 and every later periodic checkpoint carried
        # it): skip the update, say so, keep going.
        if not bool(mx.isfinite(total).item()):
            log(f"step {step}: NON-FINITE loss — update skipped")
            continue
        optimizer.update(params, grads)
        mx.eval(total, params)
        running += float(total.item())
        window.append(time.time())
        if save_every and step % save_every == 0:
            model_def.save_checkpoint(
                params, cfg, os.path.join(out_dir, "checkpoint-latest"))
            log(f"step {step}: periodic checkpoint saved")
        if step % log_every == 0:
            dt = window[-1] - window[0]
            per_step = dt / max(1, len(window) - 1)
            log(f"step {step}/{steps} loss {running / log_every:.4f} "
                f"epoch {epoch} ({per_step * 1000:.0f} ms/step, "
                f"{time.time() - t0:.0f}s)")
            running = 0.0
            window = []
    return params, len(batches), batch_size, init_meta


def train(cfg, rung, rows, out_dir, log):
    import mlx.core as mx
    import mlx.optimizers as optimizers

    train_rows = [(i, k, t) for (i, k, t) in rows if model_def.split_of(i) == "train"]
    if not train_rows:
        raise SystemExit("split produced an empty train set — check split_of")
    label_id = {k: n for n, k in enumerate(cfg.label_kinds)}

    params = model_def.init_params(cfg)
    optimizer = optimizers.Adam(
        learning_rate=rung["training"]["learning_rate"])

    def loss_fn(p, tokens, lab):
        total, _ = model_def.losses(p, cfg, tokens, lab)
        return total

    value_and_grad = mx.value_and_grad(loss_fn)
    steps = int(rung["training"]["steps"])
    log_every = int(rung["training"]["log_every"])
    t0 = time.time()
    running = 0.0
    for step in range(1, steps + 1):
        eid, kind, text = train_rows[(step - 1) % len(train_rows)]
        tokens = model_def.encode_text(text, cfg.max_seq_len)
        if len(tokens) < 2:
            continue
        total, grads = value_and_grad(params, tokens, label_id[kind])
        optimizer.update(params, grads)
        mx.eval(total, params)
        running += float(total.item())
        if step % log_every == 0:
            log(f"step {step}/{steps} loss {running / log_every:.4f} "
                f"({time.time() - t0:.0f}s)")
            running = 0.0
    return params, len(train_rows)


def export_traces(params, cfg, rows, out_dir, log):
    """Eval-split pass -> the gate input files. Recording, not grading: no
    threshold is consulted here. Besides the three trace files this writes
    traces/margins.json — the per-layer top-1/top-2 router-gap distribution
    the pre-registered sub-0.70 GATE-2 reading (TRAIN-GATES.md) consumes."""
    import mlx.core as mx

    trace_dir = os.path.join(out_dir, "traces")
    os.makedirs(trace_dir, exist_ok=True)
    eval_rows = [(i, k, t) for (i, k, t) in rows if model_def.split_of(i) == "eval"]
    if not eval_rows:
        raise SystemExit("split produced an empty eval set — GATE-2/3 would "
                         "have nothing to measure; refusing")
    label_id = {k: n for n, k in enumerate(cfg.label_kinds)}
    n_routes = n_poles = 0
    gaps = {l: [] for l in range(cfg.layers)}   # top1 - top2 per position
    with open(os.path.join(trace_dir, "routes.jsonl"), "w") as fr, \
            open(os.path.join(trace_dir, "activations.jsonl"), "w") as fa, \
            open(os.path.join(trace_dir, "predictions.jsonl"), "w") as fp:
        for n, (eid, kind, text) in enumerate(eval_rows):
            tokens = model_def.encode_text(text, cfg.max_seq_len)
            if len(tokens) < 2:
                continue
            out = model_def.forward_sequence(params, cfg, tokens)
            for l in range(cfg.layers):
                for pos, sel in enumerate(out["routes"][l]):
                    fr.write(json.dumps({"seq": eid, "pos": pos, "layer": l,
                                         "experts": sel}) + "\n")
                    n_routes += 1
                rl_rows = out["router_logits"][l].tolist()
                for row in rl_rows:
                    if len(row) >= 2:  # dense (E=1) has no top-2 gap
                        top2 = sorted(row, reverse=True)[:2]
                        gaps[l].append(top2[0] - top2[1])
                # GATE-1 pole v2 (TRAIN-GATES amendment): mean PRE-SOFTMAX
                # router logit per expert — survives margin-saturated
                # one-hot routing, unlike v1's combine weights.
                for e in range(cfg.experts):
                    mean_logit = sum(row[e] for row in rl_rows) / len(rl_rows)
                    fa.write(json.dumps({
                        "pole": f"L{l}.E{e}", "label": kind,
                        "value": mean_logit}) + "\n")
                    n_poles += 1
            predicted = model_def.predicted_label(
                [float(v) for v in out["label_logits"]], cfg)
            fp.write(json.dumps({"id": eid, "predicted": predicted,
                                 "label": kind}) + "\n")
            if (n + 1) % 50 == 0:
                mx.eval(params)
                log(f"  traced {n + 1}/{len(eval_rows)} eval examples")

    def pct(sorted_vals, p):
        idx = min(len(sorted_vals) - 1, int(p * len(sorted_vals)))
        return sorted_vals[idx]

    margins = {}
    for l in range(cfg.layers):
        vals = sorted(gaps[l])
        if not vals:
            continue
        margins[l] = {
            "n": len(vals),
            "min_gap": round(vals[0], 6),
            "p50_gap": round(pct(vals, 0.5), 6),
            "p95_gap": round(pct(vals, 0.95), 6),
            "frac_ge_margin_target": round(
                sum(1 for v in vals if v >= cfg.router_margin_target)
                / len(vals), 6),
        }
    with open(os.path.join(trace_dir, "margins.json"), "w") as fh:
        json.dump({"router_margin_target": cfg.router_margin_target,
                   "per_layer": margins}, fh, indent=2, sort_keys=True)
    return {"eval_examples": len(eval_rows), "route_rows": n_routes,
            "activation_rows": n_poles, "margins": margins}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--rung", required=True, help="rung json (rung0.json)")
    ap.add_argument("--data", required=True, help="clause dataset jsonl")
    ap.add_argument("--out", required=True, help="run output dir")
    ap.add_argument("--eval-only", metavar="CHECKPOINT_DIR",
                    help="skip training; load a saved checkpoint and only "
                         "run the eval trace export")
    ap.add_argument("--fast", action="store_true",
                    help="batched chunked training path (model_def."
                         "losses_fast; gated on train_parity_smoke.py "
                         "PASS); `steps` counts BATCH steps; eval stays "
                         "on the pinned stepwise path")
    ap.add_argument("--batch-size", type=int,
                    help="override rung training.batch_size (fast path)")
    ap.add_argument("--init-from", metavar="CHECKPOINT_DIR",
                    help="warm-start all name+shape-matching tensors; the "
                         "rest (e.g. a differently-shaped label head) stay "
                         "at init and are logged")
    args = ap.parse_args(argv)

    rung = json.load(open(args.rung))
    cfg = model_def.NurseryConfig.from_json(rung["config"])
    rows, skipped = load_dataset(args.data, kinds=cfg.label_kinds)
    os.makedirs(args.out, exist_ok=True)

    def log(msg):
        print(msg, flush=True)

    power = power_snapshot.snapshot()
    log(f"power: {json.dumps(power)}")
    log(f"dataset: {len(rows)} rows ({skipped} unusable skipped), "
        f"params: {model_def.param_count(cfg)}")

    training_mode = "stepwise"
    n_train = 0
    if args.eval_only:
        import mlx.core as mx
        import numpy as np
        import safetensors.numpy
        arrays = safetensors.numpy.load_file(
            os.path.join(args.eval_only, "model.safetensors"))
        params = {k: mx.array(np.asarray(v)) for k, v in arrays.items()}
        n_train = 0
        log(f"eval-only: checkpoint loaded from {args.eval_only}")
    elif args.fast:
        if args.batch_size:
            rung["training"]["batch_size"] = args.batch_size
        training_mode = "fast-batched"
        params, steps_per_epoch, batch_size, init_meta = train_fast(
            cfg, rung, rows, args.out, log, init_from=args.init_from)
        model_def.save_checkpoint(params, cfg,
                                  os.path.join(args.out, "checkpoint"))
        log("checkpoint saved (f32, pack_at_birth-ready)")
        rung["training"]["_steps_per_epoch"] = steps_per_epoch
        rung["training"]["_batch_size"] = batch_size
        if init_meta:
            rung["training"]["_init_from"] = init_meta
    else:
        params, n_train = train(cfg, rung, rows, args.out, log)
        model_def.save_checkpoint(params, cfg,
                                  os.path.join(args.out, "checkpoint"))
        log("checkpoint saved (f32, pack_at_birth-ready)")
    trace_stats = export_traces(params, cfg, rows, args.out, log)

    meta = {
        "rung": rung["rung"],
        "config": cfg.to_json(),
        "dataset": {"path": os.path.abspath(args.data),
                    "sha256": sha256_file(args.data),
                    "rows": len(rows), "skipped": skipped},
        "train_examples": n_train,
        "training_mode": training_mode,
        "traces": trace_stats,
        "power": power,
        "status": "trained — gates NOT run here; run_gates.py decides",
    }
    with open(os.path.join(args.out, "meta.json"), "w") as fh:
        json.dump(meta, fh, indent=2, sort_keys=True)
    log(f"meta: {os.path.join(args.out, 'meta.json')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
