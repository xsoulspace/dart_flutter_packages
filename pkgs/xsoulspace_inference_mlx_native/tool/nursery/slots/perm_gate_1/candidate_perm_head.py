"""The PERM-GATE-1 attempt-2 candidate: permission-trained slot head.

Transport: the frozen cases JSONL on stdin, one {"id", "answer"} JSON
object per gated case on stdout — the same contract a real RUNG-1 decision
model will serve through the Dart/laya adapter. Reads (kind=="read") get
no answer, ever (ADR 0084 law 3).

Decision rule (attempt 2, FIXED BEFORE that harness run, recorded in
attempt-2 RUN-NOTES): the case's text (perm_dataset.case_text — operation,
then the path/command payload, then context, exactly the corpus assembly)
goes through the trunk; the 2-way argmax over ["abstain", "allow_once"]
is the answer. Ties fall to the lower index = abstain (fail closed). No
thresholds, no hand rules — the corpus law is the only teacher the head
ever saw.

Decision rule (attempt 5, PRE-REGISTERED in dense-perm-c/PREDICTION.md
BEFORE any attempt-5 frozen case was scored): margin rule — answer
`allow_once` iff `logit(allow_once) − logit(abstain) > TAU` (strict),
else `abstain`. TAU is chosen on the CORPUS EVAL SPLIT ONLY, never the
frozen 20 cases, by the pre-registered selection rule (zero unsafe on
eval, then max agreement, ties → smallest TAU). At TAU=0 the rule IS
attempt 2's argmax (a tie has margin exactly 0, not > 0, so it abstains
— byte-identical). Rationale: the gate's own law makes the errors
asymmetric — one unsafe allow is a hard fail, an extra abstain costs a
human interruption — so the operating point may legitimately sit right
of argmax. This is an operating-point choice on the SAME trained model,
not a re-grade of a verdict.

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
from perm_dataset import case_text  # noqa: E402
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
    ap.add_argument("--margin", type=float, default=0.0,
                    help="attempt-5 margin rule: allow_once iff "
                         "logit(allow_once) - logit(abstain) > MARGIN "
                         "(strict); 0 = attempt 2's argmax (byte-identical "
                         "— a tie is not > 0 and abstains). MARGIN is "
                         "chosen on the corpus eval split only "
                         "(dense-perm-c/PREDICTION.md).")
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
        # label_kinds=[abstain, allow_once]; the margin rule above carries
        # the tie law (margin is not > TAU on a tie, so it abstains).
        pass
    else:
        with open(os.path.join(args.head, "perm_meta.json")) as fh:
            meta = json.load(fh)
        readout, arch = meta["readout"], meta["arch"]
        head = {k: mx.array(np.asarray(v)) for k, v in
                safetensors.numpy.load_file(
                    os.path.join(args.head, "head.safetensors")).items()}

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
            logits = out["label_logits"]
            margin = float(logits[1]) - float(logits[0])
            answer = "allow_once" if margin > args.margin else "abstain"
        else:
            # Pool the head scores exactly as training did (the recorded
            # readout and arch, no re-derivation) over the stepwise states.
            hidden = mx.array([out["hidden_all"]])            # [1, T, H]
            lengths = mx.array([len(tokens)], mx.int32)
            logits = head_logits(hidden, lengths, head, readout, arch)
            margin = float(logits[0][1]) - float(logits[0][0])
            answer = "allow_once" if margin > args.margin else "abstain"
        print(json.dumps({"id": case["id"], "answer": answer,
                          "kind": answer}), flush=True)


if __name__ == "__main__":
    main()
