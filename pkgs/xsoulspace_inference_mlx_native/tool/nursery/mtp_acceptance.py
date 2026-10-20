"""MTP acceptance + effective-speed measurement (the RUNG-0 MTP gate).

Gate (frozen before the first MTP run, per TRAIN-GATES.md discipline):
  - acceptance >= 0.60 at depth 2 (one draft token ahead), AND
  - effective tok/s >= 1.5x the AR trunk.

Acceptance is measured two ways, and both are reported:

  accept_teacher  the draft head sees the TRUE x_{t+1}. This is the
                  training-time condition and the optimistic bound.
  accept_self     the draft head sees the TRUNK'S OWN argmax x_{t+1}.
                  This is the decode-time condition and the honest number.

Effective speed is derived from measured forward costs, not assumed:

  tokens_per_cycle = 1 + accept_self
  cost_per_cycle   = t_verify(k+1 positions) + t_draft(k heads)
  speedup          = tokens_per_cycle / cost_per_cycle  *  t_ar(1 position)

The verify forward is batched over k+1 positions, so on a memory-bound
device it costs about one weight read — that is the whole reason MTP can
pay where a separate draft model (measured 1.09x) did not. The python
timings here are compute-bound (a python loop), so the measured ratio is a
LOWER bound on the device's real speedup; the acceptance number is the
load-bearing result and is hardware-independent.

Usage:
  python tool/nursery/mtp_acceptance.py --checkpoint <dir> --data <jsonl> \
      [--out mtp.json] [--timing-reps 20]
"""

import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import model_def  # noqa: E402


def load_checkpoint(path):
    import mlx.core as mx
    import numpy as np
    import safetensors.numpy

    arrays = safetensors.numpy.load_file(os.path.join(path, "model.safetensors"))
    params = {k: mx.array(np.asarray(v)) for k, v in arrays.items()}
    with open(os.path.join(path, "config.json")) as fh:
        cfg = model_def.NurseryConfig.from_json(json.load(fh))
    return params, cfg


def load_rows(path, kinds):
    rows = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            d = json.loads(line)
            if d.get("kind") not in kinds:
                continue
            rows.append((d["id"], d["kind"], d["text"]))
    return rows


def measure_acceptance(params, cfg, rows):
    """Teacher-forced pass over the eval split; counts depth-2 hits."""
    import mlx.core as mx

    eval_rows = [r for r in rows if model_def.split_of(r[0]) == "eval"]
    n_teacher = n_self = n_pos = 0
    n_trunk_top1 = 0
    for _eid, _kind, text in eval_rows:
        toks = model_def.encode_text(text, cfg.max_seq_len)
        if len(toks) < 4:
            continue
        out = model_def.forward_sequence(params, cfg, toks)
        ml = out["mtp_logits"]
        if ml is None:
            continue
        lm = out["lm_logits"]
        # position t predicts t+1 (lm) and t+2 (mtp); valid t = 0..T-3
        for t in range(len(toks) - 2):
            true_next = toks[t + 1]
            true_next2 = toks[t + 2]
            trunk_pick = int(mx.argmax(lm[t]).item())
            draft_teacher = int(mx.argmax(ml[t]).item())
            n_pos += 1
            if trunk_pick == true_next:
                n_trunk_top1 += 1
            if draft_teacher == true_next2:
                n_teacher += 1
            # decode-time: the draft sees the trunk's own pick
            draft_self = int(
                mx.argmax(
                    model_def._mtp_logits(
                        params,
                        cfg,
                        out["hidden_all"][t : t + 1],
                        mx.array([trunk_pick], mx.int32),
                    )[0]
                ).item()
            )
            if draft_self == true_next2:
                n_self += 1
    return {
        "positions": n_pos,
        "accept_teacher": n_teacher / n_pos if n_pos else 0.0,
        "accept_self": n_self / n_pos if n_pos else 0.0,
        "trunk_top1": n_trunk_top1 / n_pos if n_pos else 0.0,
    }


def measure_costs(params, cfg, rows, reps):
    """Forward-cost ratio: AR (1 position) vs verify (2 positions) vs draft."""
    import mlx.core as mx

    text = rows[0][2]
    toks = model_def.encode_text(text, cfg.max_seq_len)
    if len(toks) < 8:
        toks = toks + [model_def.EOS] * (8 - len(toks))

    def timeit(fn, n):
        fn()  # warm
        mx.eval(mx.array([0.0]))
        t0 = time.perf_counter()
        for _ in range(n):
            fn()
        mx.eval(mx.array([0.0]))
        return (time.perf_counter() - t0) / n

    # AR: one position through the trunk
    def ar():
        model_def.forward_sequence(params, cfg, toks[:1])

    # verify: two positions through the trunk (the batched verify)
    def verify():
        model_def.forward_sequence(params, cfg, toks[:2])

    out = model_def.forward_sequence(params, cfg, toks)
    hidden = out["hidden_all"][0:1]
    nxt = mx.array([toks[1]], mx.int32)

    def draft():
        model_def._mtp_logits(params, cfg, hidden, nxt)

    t_ar = timeit(ar, reps)
    t_verify = timeit(verify, reps)
    t_draft = timeit(draft, reps)
    return {"t_ar_s": t_ar, "t_verify2_s": t_verify, "t_draft_s": t_draft}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--checkpoint", required=True)
    ap.add_argument("--data", required=True)
    ap.add_argument("--out")
    ap.add_argument("--timing-reps", type=int, default=20)
    args = ap.parse_args(argv)

    params, cfg = load_checkpoint(args.checkpoint)
    if cfg.mtp_depth <= 0:
        raise SystemExit("checkpoint has no MTP head (mtp_depth = 0)")
    rows = load_rows(args.data, cfg.label_kinds)

    acc = measure_acceptance(params, cfg, rows)
    costs = measure_costs(params, cfg, rows, args.timing_reps)

    tokens_per_cycle = 1.0 + acc["accept_self"]
    cost_per_cycle = costs["t_verify2_s"] + costs["t_draft_s"]
    speedup = tokens_per_cycle / cost_per_cycle * costs["t_ar_s"]

    verdict = {
        "contract": "nursery.mtp-gate.v1",
        "gate": {"acceptance_min": 0.60, "speedup_min": 1.5},
        "acceptance": acc,
        "costs": costs,
        "derived": {
            "tokens_per_cycle": tokens_per_cycle,
            "cost_per_cycle_s": cost_per_cycle,
            "speedup_vs_ar": speedup,
            "note": "python stepwise timings are compute-bound; the device's "
            "memory-bound verify is cheaper, so this ratio is a "
            "LOWER bound on real speedup",
        },
        "passed": acc["accept_self"] >= 0.60 and speedup >= 1.5,
    }
    text = json.dumps(verdict, indent=2, sort_keys=True)
    print(text)
    if args.out:
        with open(args.out, "w") as fh:
            fh.write(text + "\n")
    return 0 if verdict["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
