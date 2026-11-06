#!/usr/bin/env python3
"""a3_truth.py - build the 16 arm delta specs + blind placement (SETUP step).

ORCHESTRATOR-ONLY stage (runs once, after the pilot fixed the scale and the
blinding plan was written; before any arm run). It is the single place where
kind (plant/null) meets arm labels - it consumes the label map produced by
a3_blind.dart and afterwards NO blind-stage script ever sees kind again.

Per pair k=1..8 (frozen procedures in a3_design.py):
  plant arm a3-plant-k: direction = unit diff-of-means from the BASE capture
                        (base/directions_base.json), columns = pair_columns(k),
                        scale = chosen pilot scale s*
  null  arm a3-null-k : direction = null_direction(k) (unit Gaussian, norm-
                        matched), SAME columns pair_columns(k), same s*

Writes:
  truth/specs/<real-id>/spec_L{15,19}.json   (ground truth, retained)
  truth/arms.json                            (kind + digests + spec paths)
  blind/<arm-label>/specs/spec_L{15,19}.json (blind copies, no kind field)
  blind/arm-table.json                       (labels + spec dirs only)

Usage:
  python3 -I a3_truth.py --work $TMPDIR/wm-a3 --runs-dir tool/runs \
      --scale <s*> --labelmap <truth/labelmap.json>
"""

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from a3_design import LAYERS, pair_columns, null_direction  # noqa: E402


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_floats(vals):
    return hashlib.sha256(
        json.dumps([round(v, 10) for v in vals]).encode()).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", required=True)
    ap.add_argument("--runs-dir", required=True)
    ap.add_argument("--scale", type=float, required=True)
    ap.add_argument("--labelmap", required=True)
    args = ap.parse_args()

    work = os.path.abspath(args.work)
    truth_dir = os.path.join(work, "truth")
    blind_dir = os.path.join(work, "blind")
    directions = json.load(
        open(os.path.join(work, "base", "directions_base.json")))
    labelmap = json.load(open(args.labelmap, encoding="utf-8"))  # real->label

    arms = {}
    table = []
    for k in range(1, 9):
        cols = pair_columns(k)
        null_dirs = null_direction(k)
        for kind in ("plant", "null"):
            real_id = "a3-%s-%d" % (kind, k)
            label = labelmap[real_id]
            specs = {}
            for layer in LAYERS:
                if kind == "plant":
                    direction = directions["layers"][layer]["direction"]
                else:
                    direction = null_dirs[layer]
                spec = {
                    "tensor": "model.layers.%s.mlp.down_proj.weight" % layer,
                    "columns": cols,
                    "direction": direction,
                    "scale": args.scale,
                }
                # truth copy
                tdir = os.path.join(truth_dir, "specs", real_id)
                os.makedirs(tdir, exist_ok=True)
                tp = os.path.join(tdir, "spec_L%s.json" % layer)
                with open(tp, "w", encoding="utf-8") as fh:
                    json.dump(spec, fh)
                # blind copy (identical bytes; no kind anywhere in blind dir)
                bdir = os.path.join(blind_dir, label, "specs")
                os.makedirs(bdir, exist_ok=True)
                bp = os.path.join(bdir, "spec_L%s.json" % layer)
                with open(bp, "w", encoding="utf-8") as fh:
                    json.dump(spec, fh)
                specs[layer] = {
                    "truth_spec": tp,
                    "truth_spec_sha256": sha256_file(tp),
                    "blind_spec": bp,
                    "direction_sha256": sha256_floats(direction),
                }
            arms[real_id] = {
                "kind": kind,
                "pair": k,
                "label": label,
                "scale": args.scale,
                "columns_sha256": hashlib.sha256(
                    json.dumps(cols).encode()).hexdigest(),
                "layers": specs,
            }
            table.append({"label": label,
                          "specs_dir": os.path.join(blind_dir, label, "specs")})

    table.sort(key=lambda r: r["label"])
    os.makedirs(truth_dir, exist_ok=True)
    with open(os.path.join(truth_dir, "arms.json"), "w", encoding="utf-8") as fh:
        json.dump({
            "created_utc": datetime.now(timezone.utc).isoformat(
                timespec="seconds"),
            "scale": args.scale,
            "direction_source": os.path.join(work, "base",
                                             "directions_base.json"),
            "direction_source_sha256": sha256_file(
                os.path.join(work, "base", "directions_base.json")),
            "arms": arms,
        }, fh, indent=1)
    os.makedirs(blind_dir, exist_ok=True)
    with open(os.path.join(blind_dir, "arm-table.json"), "w",
              encoding="utf-8") as fh:
        json.dump({"note": "blind table: labels + spec dirs only",
                   "arms": table}, fh, indent=1)
    print("TRUTH_OK 16 arms; scale=%s; truth/arms.json + blind/arm-table.json"
          % args.scale)


if __name__ == "__main__":
    main()
