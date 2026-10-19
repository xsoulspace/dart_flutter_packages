"""The PERM-GATE-1 attempt-2 candidate: permission-trained slot head.

Transport: the frozen cases JSONL on stdin, one {"id", "answer"} JSON
object per gated case on stdout — the same contract a real RUNG-1 decision
model will serve through the Dart/laya adapter. Reads (kind=="read") get
no answer, ever (ADR 0084 law 3).

Decision rule (FIXED BEFORE the harness run, recorded in attempt-2
RUN-NOTES): the case's text (perm_dataset.case_text — operation, then the
path/command payload, then context, exactly the corpus assembly) goes
through the trunk; the slot head's 2-way argmax over
["abstain", "allow_once"] is the answer. Ties fall to the lower index =
abstain (fail closed). No thresholds, no hand rules — the corpus law is
the only teacher the head ever saw.

Usage (via the harness):
  python run_harness.py --command
    '~/.venvs/mlx-ref/bin/python tool/nursery/slots/perm_gate_1/candidate_perm_head.py
       --checkpoint <ckpt-dir> --head <head-dir>' --out verdict.json
"""

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))  # tool/nursery

import model_def  # noqa: E402
from perm_dataset import ANSWERS, case_text  # noqa: E402
from train_perm_head import head_logits  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--checkpoint", required=True)
    ap.add_argument("--head",
                    help="dir with head.safetensors (train_perm_head "
                         "output); omit with --label-head")
    ap.add_argument("--label-head", action="store_true",
                    help="the end-to-end arm: the model's OWN label head "
                         "is the 2-way perm decision (label_kinds = "
                         "[abstain, allow_once]); no slot head exists")
    args = ap.parse_args()

    import mlx.core as mx
    import numpy as np
    import safetensors.numpy

    arrays = safetensors.numpy.load_file(
        os.path.join(args.checkpoint, "model.safetensors"))
    params = {k: mx.array(np.asarray(v)) for k, v in arrays.items()}
    with open(os.path.join(args.checkpoint, "config.json")) as fh:
        cfg = model_def.NurseryConfig.from_json(json.load(fh))
    if args.label_head:
        # End-to-end arm: the model's own label head decides over
        # label_kinds=[abstain, allow_once]; argmax ties fall to the lower
        # index (abstain).
        answer_kinds = cfg.label_kinds
    else:
        with open(os.path.join(args.head, "perm_meta.json")) as fh:
            meta = json.load(fh)
        readout, arch = meta["readout"], meta["arch"]
        head = {k: mx.array(np.asarray(v)) for k, v in
                safetensors.numpy.load_file(
                    os.path.join(args.head, "head.safetensors")).items()}
        answer_kinds = ANSWERS

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        case = json.loads(line)
        if case.get("kind") == "read":
            # Reads are never gated (ADR 0084): answering one is a wiring
            # error — emit nothing for it.
            continue
        tokens = model_def.encode_text(case_text(case), cfg.max_seq_len)
        out = model_def.forward_sequence(params, cfg, tokens)
        if args.label_head:
            idx = int(mx.argmax(out["label_logits"]))
        else:
            # Pool the head scores exactly as training did (the recorded
            # readout and arch, no re-derivation) over the stepwise states.
            hidden = mx.array([out["hidden_all"]])            # [1, T, H]
            lengths = mx.array([len(tokens)], mx.int32)
            logits = head_logits(hidden, lengths, head, readout, arch)
            idx = int(mx.argmax(logits[0]))
        print(json.dumps({"id": case["id"], "answer": answer_kinds[idx],
                          "kind": answer_kinds[idx]}), flush=True)


if __name__ == "__main__":
    main()
