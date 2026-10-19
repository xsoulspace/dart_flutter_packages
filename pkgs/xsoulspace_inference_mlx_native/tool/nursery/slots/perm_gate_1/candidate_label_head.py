"""The first model-driven PERM-GATE-1 candidate (rung0-first label head).

Transport: reads the frozen cases JSONL on stdin, writes one
{"id", "answer"} JSON object per line to stdout — the same contract a real
RUNG-1 decision model will serve through the Dart/laya adapter.

Decision rule (FIXED BEFORE SCORING, the conservative bridge from a
clause-kind head to the permission candidate set {allow_once, abstain}):
encode the case's `operation + path + context` text through the trained
model; label-head argmax kind; "action" -> allow_once, every other kind ->
abstain. The model was trained on memo-tree clause kinds, NOT permission
requests — nobody expects this to pass; the point is the first measured
acceptance attempt and the honest size of the gap (the scorer names every
miss).

Usage (via the harness):
  python run_harness.py --command
    '~/.venvs/mlx-ref/bin/python tool/nursery/slots/perm_gate_1/candidate_label_head.py --checkpoint <dir>'
"""

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))  # tool/nursery

import model_def  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--checkpoint", required=True,
                    help="checkpoint dir (model.safetensors)")
    args = ap.parse_args()

    import mlx.core as mx
    import numpy as np
    import safetensors.numpy

    arrays = safetensors.numpy.load_file(
        os.path.join(args.checkpoint, "model.safetensors"))
    params = {k: mx.array(np.asarray(v)) for k, v in arrays.items()}
    cfg = model_def.NurseryConfig()  # rung0 shape; label_kinds order fixed
    label_id = {k: n for n, k in enumerate(cfg.label_kinds)}

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        case = json.loads(line)
        if case.get("kind") == "read":
            # Reads are never gated (ADR 0084): a candidate that answers a
            # read is a wiring error — emit nothing for it.
            continue
        text = " ".join([
            str(case.get("request", {}).get("operation", "")),
            str(case.get("request", {}).get("path", "")),
            str(case.get("request", {}).get("context", "")),
        ])
        tokens = model_def.encode_text(text, cfg.max_seq_len)
        out = model_def.forward_sequence(params, cfg, tokens)
        vals = [float(v) for v in out["label_logits"]]
        kind = model_def.predicted_label(vals, cfg)
        answer = "allow_once" if kind == "action" else "abstain"
        print(json.dumps({"id": case["id"], "answer": answer,
                          "kind": kind}), flush=True)


if __name__ == "__main__":
    main()
