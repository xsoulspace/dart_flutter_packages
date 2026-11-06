#!/usr/bin/env python3
"""v3_truth.py - V-3 arm delta specs + blind placement + control specs (CPU;
ORCHESTRATOR-ONLY setup step; runs once after the pilot fixed the scale and
the blinding plan was written; before any arm run).

Per pair k=1..4 (K reduced 8+8 -> 4+4 per PREREG-D addendum 2026-11-06b,
pre-run):
  plant v3-plant-k: direction = unit diff-of-means from the BASE capture
                    (base/directions_base.json), columns = pair_columns_v3(k),
                    scale = chosen pilot scale s*
  null  v3-null-k : direction = null_direction_v3(k) (unit Gaussian,
                    norm-matched), SAME columns, same s*

Null-3-style CONTRAST nulls are EXCLUDED on this cast (V-1 NULL_LEAK finding:
the constructor is confounded - a task-vs-neutral diff-of-means shares a
task-engagement component with the removal target; pointer: receipts/
V1-nulls.jsonl seq 5 + receipts/V12-summary.md). Recorded pre-run.

Also writes (orchestrator domain, never read by blind stages):
  truth/control/repair_ctrl_k.json  k=1,2: random-proposer CONTROL repair
      specs (tensors [{name, columns, direction(control_direction_v3(k)),
      scale: -s*}]) - must certify nothing (CONTROL_LEAK halt otherwise)
  truth/control/plan.json           which real ids carry control/ws3 + their
      blind labels (orchestrator-only; consumed once at mirror rebuild)
  gen/subset_neutral_24.txt / gen/subset_loop_12.txt
      WS-3 compute subsets (head-N rule identical to WS-3 live: first 24
      non-empty neutral lines + first 12 non-empty loop lines, file order)

Usage:
  python3 -I v3_truth.py --work $TMPDIR/wm-v3 --runs-dir <tool/runs> \
      --scale <s*> --layers 18,22 --labelmap <truth/labelmap.json>
"""

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from v3_design import (LAYERS, control_direction_v3, null_direction_v3,  # noqa: E402
                       pair_columns_v3, tensor_name)

K_PAIRS = 4
CONTROL_KS = (1, 2)          # pre-registered: control on plant pairs 1,2
WS3_PLANT_K = 1              # pre-registered: WS-3 prior on plant pair 1


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_floats(vals):
    return hashlib.sha256(
        json.dumps([round(v, 10) for v in vals]).encode()).hexdigest()


def head_nonempty(path, n):
    out = []
    with open(path, encoding="utf-8") as fh:
        for ln in fh.read().splitlines():
            s = ln.strip()
            if s:
                out.append(s)
            if len(out) == n:
                break
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", required=True)
    ap.add_argument("--runs-dir", required=True)
    ap.add_argument("--scale", type=float, required=True)
    ap.add_argument("--layers", required=True)
    ap.add_argument("--labelmap", required=True)
    args = ap.parse_args()

    layers = [x.strip() for x in args.layers.split(",")]
    assert tuple(layers) == LAYERS, "layers must match v3_design.LAYERS"
    work = os.path.abspath(args.work)
    runs = os.path.abspath(args.runs_dir)
    truth_dir = os.path.join(work, "truth")
    blind_dir = os.path.join(work, "blind")
    directions = json.load(
        open(os.path.join(work, "base", "directions_base.json"),
             encoding="utf-8"))
    labelmap = json.load(open(args.labelmap, encoding="utf-8"))

    arms = {}
    table = []
    for k in range(1, K_PAIRS + 1):
        cols = pair_columns_v3(k)
        null_dirs = null_direction_v3(k)
        for kind in ("plant", "null"):
            real_id = "v3-%s-%d" % (kind, k)
            label = labelmap[real_id]
            specs = {}
            for layer in layers:
                if kind == "plant":
                    direction = directions["layers"][layer]["direction"]
                else:
                    direction = null_dirs[layer]
                spec = {
                    "tensor": tensor_name(layer),
                    "columns": cols,
                    "direction": direction,
                    "scale": args.scale,
                }
                tdir = os.path.join(truth_dir, "specs", real_id)
                os.makedirs(tdir, exist_ok=True)
                tp = os.path.join(tdir, "spec_L%s.json" % layer)
                with open(tp, "w", encoding="utf-8") as fh:
                    json.dump(spec, fh)
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
                          "specs_dir": os.path.join(blind_dir, label,
                                                    "specs")})

    table.sort(key=lambda r: r["label"])
    os.makedirs(truth_dir, exist_ok=True)
    with open(os.path.join(truth_dir, "arms.json"), "w",
              encoding="utf-8") as fh:
        json.dump({
            "created_utc": datetime.now(timezone.utc).isoformat(
                timespec="seconds"),
            "scale": args.scale,
            "layers": layers,
            "k_pairs": K_PAIRS,
            "direction_source": os.path.join(work, "base",
                                             "directions_base.json"),
            "direction_source_sha256": sha256_file(
                os.path.join(work, "base", "directions_base.json")),
            "null3_style_contrast_nulls":
                "EXCLUDED on this cast (V-1 NULL_LEAK: constructor "
                "confounded; pointer receipts/V1-nulls.jsonl seq 5)",
            "arms": arms,
        }, fh, indent=1)
    os.makedirs(blind_dir, exist_ok=True)
    with open(os.path.join(blind_dir, "arm-table.json"), "w",
              encoding="utf-8") as fh:
        json.dump({"note": "blind table: labels + spec dirs only",
                   "arms": table}, fh, indent=1)

    # --- random-proposer CONTROL repair specs (orchestrator domain) ---
    ctrl_dir = os.path.join(truth_dir, "control")
    os.makedirs(ctrl_dir, exist_ok=True)
    ctrl_rows = {}
    for k in CONTROL_KS:
        real_id = "v3-plant-%d" % k
        label = labelmap[real_id]
        cols = pair_columns_v3(k)
        dirs = control_direction_v3(k)
        tensors = [{"name": tensor_name(layer), "columns": cols,
                    "direction": dirs[layer], "scale": -args.scale}
                   for layer in layers]
        sp = os.path.join(ctrl_dir, "repair_ctrl_%d.json" % k)
        with open(sp, "w", encoding="utf-8") as fh:
            json.dump({"tensors": tensors}, fh)
        ctrl_rows["ctrl-%d" % k] = {
            "on_real_id": real_id, "label": label, "spec": sp,
            "spec_sha256": sha256_file(sp),
            "direction_sha256": {L: sha256_floats(dirs[L]) for L in layers},
            "columns_sha256": hashlib.sha256(
                json.dumps(cols).encode()).hexdigest(),
        }
    ws3_id = "v3-plant-%d" % WS3_PLANT_K
    plan = {
        "created_utc": datetime.now(timezone.utc).isoformat(
            timespec="seconds"),
        "law": "ORCHESTRATOR-ONLY: kind/label joins for control + ws3 mirror "
               "rebuilds; blind stages never read this file",
        "controls": ctrl_rows,
        "ws3": {"on_real_id": ws3_id, "label": labelmap[ws3_id],
                "layers_window": 24,
                "note": "frozen literal window (PREREG-D: 24 layers; chance "
                        "3/24); planted 18,22 inside 0..23; retired-backbone "
                        "status noted on rows (propose-only)"},
    }
    with open(os.path.join(ctrl_dir, "plan.json"), "w",
              encoding="utf-8") as fh:
        json.dump(plan, fh, indent=1)

    # --- WS-3 compute subsets (same head-N rule as WS-3 live) ---
    gen = os.path.join(work, "gen")
    os.makedirs(gen, exist_ok=True)
    subsets = {}
    for bank, n in (("neutral", 24), ("loop", 12)):
        src = os.path.join(runs, "prompts_localization_%s_A3.txt" % bank)
        lines = head_nonempty(src, n)
        assert len(lines) == n, "bank %s shorter than %d" % (bank, n)
        dst = os.path.join(gen, "subset_%s_%d.txt" % (bank, n))
        with open(dst, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
        subsets[os.path.basename(dst)] = {
            "path": dst, "sha256": sha256_file(dst),
            "source_sha256": sha256_file(src)}
    with open(os.path.join(gen, "subsets_receipt.json"), "w",
              encoding="utf-8") as fh:
        json.dump({"rule": "first N non-empty lines in file order (identical "
                           "to WS-3 live subset rule)",
                   "subsets": subsets}, fh, indent=1)

    print("TRUTH_OK %d arms (%d pairs); scale=%s; controls=%s; ws3=%s"
          % (K_PAIRS * 2, K_PAIRS, args.scale, sorted(ctrl_rows),
             plan["ws3"]["label"]))


if __name__ == "__main__":
    main()
