#!/usr/bin/env python3
"""a3_propose.py - the pipeline's proposer stage (diff-of-means recovery).

Reads two capture_activations.py artifacts (loop-inducing prompts, neutral
prompts) over the SAME layers and computes, per layer:
    diff_L = mean_activation(loop) - mean_activation(neutral)
    direction_L = diff_L / ||diff_L||_2      (unit; frozen rule)
Writes recovered.json with the directions, diff norms and digests. This is a
blind-pipeline stage: it reads ONLY capture artifacts (never truth, never
labels, never planted directions).

Usage:
  python3 -I a3_propose.py --cap-loop cap_loop.json \
      --cap-neutral cap_neutral.json --out recovered.json

Exit codes: 0 ok; 1 named errors:
  CAPTURE_UNREADABLE CAPTURE_LAYER_MISMATCH ZERO_DIFF OUT_UNWRITABLE
"""

import argparse
import hashlib
import json
import math
import os
import sys
from datetime import datetime, timezone


def fail(code, detail):
    print("%s: %s" % (code, detail), file=sys.stderr)
    return 1


def load_capture(path):
    try:
        art = json.load(open(path, encoding="utf-8"))
        return art["per_layer"], art
    except (OSError, ValueError, KeyError) as exc:
        raise RuntimeError("CAPTURE_UNREADABLE: %s (%s)" % (path, exc))


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_floats(vals):
    return hashlib.sha256(
        json.dumps([round(v, 10) for v in vals]).encode()
    ).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cap-loop", required=True)
    ap.add_argument("--cap-neutral", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    try:
        loop_layers, loop_art = load_capture(args.cap_loop)
        neutral_layers, neutral_art = load_capture(args.cap_neutral)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    if set(loop_layers) != set(neutral_layers):
        return fail("CAPTURE_LAYER_MISMATCH",
                    "loop=%s neutral=%s" % (sorted(loop_layers),
                                             sorted(neutral_layers)))

    layers = {}
    for lname in sorted(loop_layers, key=int):
        a = loop_layers[lname]["mean_activation"]
        b = neutral_layers[lname]["mean_activation"]
        if len(a) != len(b):
            return fail("CAPTURE_LAYER_MISMATCH",
                        "layer %s len %d vs %d" % (lname, len(a), len(b)))
        diff = [x - y for x, y in zip(a, b)]
        norm = math.sqrt(sum(d * d for d in diff))
        if norm == 0.0:
            return fail("ZERO_DIFF", "layer %s" % lname)
        unit = [d / norm for d in diff]
        layers[lname] = {
            "direction": unit,
            "direction_sha256": sha256_floats(unit),
            "diff_l2_norm": norm,
            "hidden_dim": len(unit),
            "tokens_loop": loop_layers[lname]["tokens_averaged"],
            "tokens_neutral": neutral_layers[lname]["tokens_averaged"],
        }

    payload = {
        "tool": "a3_propose.py",
        "rule": "diff-of-means(loop, neutral) per layer, L2-normalized (frozen)",
        "created_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "inputs": {
            "cap_loop": {"path": os.path.abspath(args.cap_loop),
                         "sha256": sha256_file(args.cap_loop),
                         "model": loop_art.get("model")},
            "cap_neutral": {"path": os.path.abspath(args.cap_neutral),
                            "sha256": sha256_file(args.cap_neutral),
                            "model": neutral_art.get("model")},
        },
        "layers": layers,
    }
    try:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, indent=1)
    except OSError as exc:
        return fail("OUT_UNWRITABLE", str(exc))
    print("PROPOSE_OK %s layers=%s" % (args.out, sorted(layers)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
