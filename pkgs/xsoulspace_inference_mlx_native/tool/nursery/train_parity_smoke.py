"""Equivalence oracle for the fast training path (TRAIN-GATES discipline:
the fast path may not train until this passes).

Pins model_def.forward_sequence_fast / losses_fast / topk_ids_vec against
the PINNED stepwise definitions (forward_sequence / losses /
top_k_experts — the form the Rust runtime mirrors and decode uses):

  1. TOP-K CONTRACT with exact ties: random matrices + crafted duplicate
     maxima and duplicate k-th values; every row must match
     model_def.top_k_experts exactly (k largest, ties to lower index,
     ascending).
  2. ROUTES + LOGITS + LOSSES on real clause examples with TRAINED
     weights (rung0-first checkpoint — the frozen margin law applies:
     gaps 7-16 dwarf cross-path float noise, so routes must match
     EXACTLY per position per layer), lm/label logits max-abs-diff
     <= 1e-2, each loss part equal within 1e-2.
  3. Same on FRESH INIT weights (seed 0) for logits/losses only —
     reported, not asserted for routes: at init some router gaps are
     ~1e-5, below cross-path noise, so exact routes are not a fair
     demand there (the margin law is precisely what buys exactness).

Exit 0 only if every asserted check passes.

Usage:
  ~/.venvs/mlx-ref/bin/python tool/nursery/train_parity_smoke.py \
      [--checkpoint bench/nursery/runs/rung0-first/checkpoint] \
      [--data bench/nursery/data/clause_dataset.jsonl]
"""

import argparse
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import model_def  # noqa: E402

TOL = 1e-2


def load_checkpoint_params(ckpt_dir):
    import mlx.core as mx
    import safetensors.numpy
    arrays = safetensors.numpy.load_file(
        os.path.join(ckpt_dir, "model.safetensors"))
    return {k: mx.array(np.asarray(v)) for k, v in arrays.items()}


def mx_to_numpy(a):
    import mlx.core as mx
    return np.asarray(a)


def check_topk_contract():
    import mlx.core as mx
    failures = 0
    rng = np.random.default_rng(0)
    mats = [rng.normal(0, 3, size=(64, 8)).astype(np.float32)]
    crafted = np.zeros((6, 8), dtype=np.float32)
    crafted[0] = [5, 5, 1, 1, 0, 0, 0, 0]          # duplicate max
    crafted[1] = [3, 1, 3, 1, 3, 1, 0, 0]          # interleaved exact ties
    crafted[2] = [9, 9, 9, 9, 9, 9, 9, 9]          # all equal
    crafted[3] = [-1, -1, -2, -2, -3, -3, -4, -4]  # negative ties
    crafted[4] = [0, 0, 0, 0, 0, 0, 0, 1]          # single max at the END
    crafted[5] = [2, 2, 2, 2, 2, 2, 2, 2]          # all equal, no winner
    mats.append(crafted)
    for m in mats:
        got = np.asarray(model_def.topk_ids_vec(mx.array(m), 2))
        for r in range(m.shape[0]):
            want = model_def.top_k_experts([float(v) for v in m[r]], 2)
            if [int(x) for x in got[r]] != want:
                failures += 1
                print(f"FAIL topk row {r}: fast {[int(x) for x in got[r]]} "
                      f"vs stepwise {want} (logits {m[r].tolist()})")
    print(f"top-k contract: {'PASS' if failures == 0 else 'FAIL'} "
          f"({sum(m.shape[0] for m in mats)} rows incl. exact-tie cases)")
    return failures


def compare_on_weights(params, cfg, rows, assert_routes, tag):
    """Stepwise-per-example vs one fast batched call on the same weights.
    Returns failure count; asserts routes only when assert_routes."""
    import mlx.core as mx

    ids = [model_def.encode_text(t, cfg.max_seq_len) for (_, _, t) in rows]
    T = max(len(x) for x in ids)
    B = len(rows)
    tokens = mx.full([B, T], model_def.EOS, mx.int32)
    for b, x in enumerate(ids):
        tokens[b, :len(x)] = mx.array(x, mx.int32)
    lengths = mx.array([len(x) for x in ids], mx.int32)
    label_ids = mx.array([cfg.label_kinds.index(k) for (_, k, _) in rows],
                         mx.int32)

    fast = model_def.forward_sequence_fast(params, cfg, tokens, lengths)
    total_fast, parts_fast = model_def.losses_fast(params, cfg, tokens,
                                                   lengths, label_ids)

    failures = 0
    max_logit_diff = 0.0
    max_route_flips = 0
    # pooled stepwise references: the fast path means over ALL real
    # positions of the batch, so the stepwise side must weight each
    # example by its real position count (mean-of-means would diverge on
    # unequal lengths with IDENTICAL logits — a comparison artifact)
    parts_step = {"ce": [0.0, 0], "label_ce": [0.0, 0],
                  "margin": [0.0, 0], "smoothness": [0.0, 0]}
    for b in range(B):
        toks = ids[b]
        step = model_def.forward_sequence(params, cfg, toks)
        _, p = model_def.losses(params, cfg, toks,
                                cfg.label_kinds.index(rows[b][1]))
        T_real = len(toks)
        parts_step["ce"][0] += p["ce"] * (T_real - 1)
        parts_step["ce"][1] += T_real - 1
        parts_step["label_ce"][0] += p["label_ce"]
        parts_step["label_ce"][1] += 1
        parts_step["margin"][0] += p["margin"] * T_real * cfg.layers
        parts_step["margin"][1] += T_real * cfg.layers
        parts_step["smoothness"][0] += p["smoothness"] * (T_real - 1) * cfg.layers
        parts_step["smoothness"][1] += (T_real - 1) * cfg.layers
        sl = np.asarray(mx_to_numpy(step["lm_logits"]), dtype=np.float32)
        fl = np.asarray(mx_to_numpy(fast["lm_logits"][b, :len(toks)]),
                        dtype=np.float32)
        max_logit_diff = max(max_logit_diff,
                             float(np.abs(fl - sl).max()))
        for l in range(cfg.layers):
            for pos, want in enumerate(step["routes"][l]):
                got = [int(v) for v in fast["routes"][b, l, pos]]
                if got != want:
                    max_route_flips += 1
                    if assert_routes:
                        failures += 1
                        if failures <= 4:
                            print(f"FAIL route b{b} L{l} pos{pos}: "
                                  f"fast {got} vs stepwise {want}")
    step_labels = np.stack([
        np.asarray(mx_to_numpy(
            model_def.forward_sequence(params, cfg, ids[b])["label_logits"]),
            dtype=np.float32)
        for b in range(B)])
    ll_diff = float(np.abs(
        np.asarray(mx_to_numpy(fast["label_logits"])) - step_labels
    ).max()) if B else 0.0

    for key, (acc, count) in parts_step.items():
        step_pooled = acc / count if count else 0.0
        diff = abs(parts_fast[key] - step_pooled)
        ok = diff <= TOL
        if not ok:
            failures += 1
        print(f"  loss[{key}] fast {parts_fast[key]:.4f} vs stepwise-pooled "
              f"{step_pooled:.4f} (diff {diff:.4f}) "
              f"{'ok' if ok else 'FAIL'}")

    route_verdict = ("n/a (init weights: near-tie gaps < cross-path noise; "
                     f"{max_route_flips} flips observed)")
    if assert_routes:
        route_verdict = f"{max_route_flips} flips (must be 0)"
        if max_route_flips:
            failures += 1
    print(f"[{tag}] max |lm logit diff| {max_logit_diff:.5f}, "
          f"label diff {ll_diff:.5f}, routes: {route_verdict}")
    if max_logit_diff > TOL or ll_diff > TOL:
        failures += 1
    return failures


def check_windowed(params, cfg, rows, window=4):
    """The routing_window A/B arm's fast path: one expert SET per window.
    On trained weights the margin law applies to the window-START row too,
    so fast and stepwise must agree EXACTLY on every position's ids, and
    every position inside a window must carry identical ids on both paths."""
    import mlx.core as mx

    cfg_w = model_def.NurseryConfig(**{
        **{k: getattr(cfg, k) for k in
           ("hidden_size", "layers", "experts", "topk", "intermediate",
            "vocab_size", "rms_norm_eps", "max_seq_len", "seed")},
        "routing_window": window})
    ids = [model_def.encode_text(t, cfg_w.max_seq_len) for (_, _, t) in rows]
    T = max(len(x) for x in ids)
    B = len(rows)
    tokens = mx.full([B, T], model_def.EOS, mx.int32)
    for b, x in enumerate(ids):
        tokens[b, :len(x)] = mx.array(x, mx.int32)
    lengths = mx.array([len(x) for x in ids], mx.int32)
    fast = model_def.forward_sequence_fast(params, cfg_w, tokens, lengths)

    failures = 0
    flips = 0
    share = 0
    for b in range(B):
        step = model_def.forward_sequence(params, cfg_w, ids[b])
        for l in range(cfg_w.layers):
            for pos in range(len(ids[b])):
                got = [int(v) for v in fast["routes"][b, l, pos]]
                want = step["routes"][l][pos]
                if got != want:
                    flips += 1
                    failures += 1
                    if flips <= 4:
                        print(f"FAIL windowed route b{b} L{l} pos{pos}: "
                              f"fast {got} vs stepwise {want}")
                if pos % window and got != step["routes"][l][
                        (pos // window) * window]:
                    share += 1
                    failures += 1
    invar = ("PASS" if share == 0 else
             f"FAIL ({share} within-window disagreements)")
    print(f"windowed W={window}: routes {'PASS' if flips == 0 else 'FAIL'} "
          f"({flips} flips), within-window sharing {invar}")
    return failures


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--checkpoint",
                    default="bench/nursery/runs/rung0-first/checkpoint")
    ap.add_argument("--data",
                    default="bench/nursery/data/clause_dataset.jsonl")
    args = ap.parse_args(argv)

    failures = check_topk_contract()

    rows = []
    with open(args.data) as fh:
        for line in fh:
            r = json.loads(line)
            if r.get("kind") in model_def.LABEL_KINDS and r.get("text"):
                rows.append((r["id"], r["kind"], r["text"]))
            if len(rows) >= 8:
                break
    if len(rows) < 4:
        raise SystemExit("not enough rows for the smoke batch")
    cfg = model_def.NurseryConfig()

    print("trained weights (routes asserted — margin law applies):")
    failures += compare_on_weights(load_checkpoint_params(args.checkpoint),
                                   cfg, rows, assert_routes=True,
                                   tag="trained")
    print("fresh init weights (logits/losses only):")
    failures += compare_on_weights(model_def.init_params(cfg), cfg, rows,
                                   assert_routes=False, tag="init")
    print("windowed routing (A/B arm fast path, trained weights):")
    failures += check_windowed(load_checkpoint_params(args.checkpoint),
                               cfg, rows)

    print(f"TRAIN PARITY SMOKE: {'PASS' if failures == 0 else 'FAIL'} "
          f"({failures} failures)")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
