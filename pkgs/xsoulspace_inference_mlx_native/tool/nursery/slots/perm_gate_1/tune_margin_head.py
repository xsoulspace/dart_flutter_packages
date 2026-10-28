"""Choose the attempt-7 slot-head margin TAU on the CORPUS EVAL SPLIT ONLY.

The attempt-5 law (dense-perm-c/PREDICTION.md), reused verbatim for the
slot-head arm: among TAU values with ZERO unsafe allows on eval, the one
with maximum agreement; ties -> the SMALLEST TAU. The frozen 20 harness
cases are never read here.

Difference from tune_margin.py: the margin comes from the SLOT HEAD (the
candidate's --head arm), not the trunk's label head — the trunk forward,
the recorded readout/arch, and the pooling in train_perm_head.head_logits
are the candidate's own code paths, so the sweep cannot drift from what
the candidate will serve.

Usage:
  ~/.venvs/mlx-ref/bin/python tune_margin_head.py \
      --checkpoint ../../../bench/nursery/runs/dense-perm-b/checkpoint \
      --head ../../../bench/nursery/runs/perm-slot-dense \
      --data ../../../bench/nursery/data/perm_domain_corpus_v3.jsonl
"""

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
NURSERY = os.path.dirname(os.path.dirname(HERE))  # tool/nursery
sys.path.insert(0, NURSERY)

import model_def  # noqa: E402
from perm_dataset import ANSWERS, case_text  # noqa: E402
from train_perm_head import head_logits  # noqa: E402


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--checkpoint", required=True)
    ap.add_argument("--head", required=True,
                    help="dir with head.safetensors + perm_meta.json "
                         "(train_perm_head output)")
    ap.add_argument("--data", required=True,
                    help="the CORPUS jsonl (not clause) — rows carry "
                         "id/request/answer")
    args = ap.parse_args(argv)

    import mlx.core as mx
    import numpy as np
    import safetensors.numpy

    arrays = safetensors.numpy.load_file(
        os.path.join(args.checkpoint, "model.safetensors"))
    params = {k: mx.array(np.asarray(v)) for k, v in arrays.items()}
    with open(os.path.join(args.checkpoint, "config.json")) as fh:
        cfg = model_def.NurseryConfig.from_json(json.load(fh))
    with open(os.path.join(args.head, "perm_meta.json")) as fh:
        meta = json.load(fh)
    readout, arch = meta["readout"], meta["arch"]
    head = {k: mx.array(np.asarray(v)) for k, v in
            safetensors.numpy.load_file(
                os.path.join(args.head, "head.safetensors")).items()}

    margins, golds = [], []
    with open(args.data) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            rec = json.loads(line)
            if model_def.split_of(rec["id"]) != "eval":
                continue
            toks = model_def.encode_text(case_text(rec), cfg.max_seq_len)
            out = model_def.forward_sequence(params, cfg, toks)
            hidden = mx.array([out["hidden_all"]])       # [1, T, H]
            lengths = mx.array([len(toks)], mx.int32)
            logits = head_logits(hidden, lengths, head, readout, arch)
            margins.append(float(logits[0][1]) - float(logits[0][0]))
            golds.append(ANSWERS.index(rec["answer"]))

    n_allow_gold = sum(1 for g in golds if g == 1)
    print(f"eval rows: {len(golds)} (gold allow_once: {n_allow_gold}); "
          f"head readout={readout} arch={arch}")

    sweep = []
    tau = 0.0
    while tau <= 8.0 + 1e-9:
        agreed = 0
        unsafe = 0
        for m, g in zip(margins, golds):
            pred = 1 if m > tau else 0
            if pred == g:
                agreed += 1
            elif pred == 1:
                unsafe += 1  # gold abstain, answered allow_once
        sweep.append({"tau": round(tau, 2),
                      "agreement": round(agreed / len(golds), 4),
                      "unsafe_allows": unsafe})
        tau += 0.25

    print("tau    agreement  unsafe")
    for row in sweep:
        print(f"{row['tau']:<6} {row['agreement']:<10} {row['unsafe_allows']}")

    feasible = [r for r in sweep if r["unsafe_allows"] == 0]
    if not feasible:
        print(json.dumps({"selected_tau": None,
                          "note": "NO zero-unsafe TAU on eval — the "
                                  "pre-registered rule selects nothing; "
                                  "the candidate fails its own recipe"},
                         indent=2))
        return 1
    best = max(feasible, key=lambda r: (r["agreement"], -r["tau"]))
    print(json.dumps({"selected_tau": best["tau"],
                      "eval_agreement": best["agreement"],
                      "eval_unsafe": best["unsafe_allows"],
                      "rule": "zero-unsafe on eval, then max agreement, "
                              "ties -> smallest TAU (attempt-5 law, "
                              "pre-registered)"},
                     indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
