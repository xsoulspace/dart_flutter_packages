#!/usr/bin/env python3
"""p3_exp2_reader.py — PREREG-D §P-3 exp2 (diffusion shapes) weight-space reader.

BLIND READER: reads ONLY the .npz weight arrays. The answer key
(eval/answer_key.json) is opened ONLY after all three predictions are computed.
Rendered samples (eval/samples*) leak the labels and are NOT fetched by
p3_fetch.sh and NOT read here.

============================ FROZEN RULE (freeze-it-in-code) ==================
Written before any scoring run (2026-11-05). Same two pre-registered feature
families as exp1 (PREREG-D §P-3 "exp2 likewise"), instantiated on the published
DDPM layout (exp2_diffusion/networks/description.txt): 12x12 grayscale,
inputs 0..143 = pixels (i = row*12 + col), inputs 144..159 = step encoding;
W1 (160, H=64); output bias b3 (144,) = per-pixel bias of the predicted clean
image x0_hat, i.e. the network's UNCONDITIONAL MEAN IMAGE.

F1 input-layer spatial mass centroid:
   G(r,c) = sum_j |W1[r*12 + c, j]| over the 64 hidden units (pixel rows only).
   centroid_row / centroid_col = mass-weighted means over the 12x12 grid.

F2 output-layer bias image:
   M = b3 reshaped to 12x12; Mn = (M - min M)/(max M - min M)
   (max == min -> NAMED DEGENERATE_BIAS, prediction "none", scored as miss).
   bright = Mn >= 0.5; bbox = bounding box of bright cells;
   area_ratio = #bright / bbox_area  (no bright cells -> NAMED
   DEGENERATE_MASK, prediction "none", scored as miss).

Corroboration (computed + reported, NOT part of the decision):
   row_width monotonicity |pearson(w(r), r)| over bbox rows (triangle: high),
   width constancy 1 - std/mean (square: high),
   corner brightness = mean Mn over the four 2x2 corners (square: high),
   F1 centroid (all shapes rendered centered: ~5.5, ~5.5).

CLASSIFICATION RULE (decision order frozen; rationale = published geometry of
FILLED planar shapes as area fraction of the bounding box — square 1.0,
circle pi/4 ~= 0.785, triangle ~0.5 for ANY orientation — not the key):
   area_ratio >= 0.90            -> "square"
   area_ratio <= 0.62            -> "triangle"
   else (0.62 < ar < 0.90)       -> "circle"   (band centered on pi/4)
Thresholds sit ~0.11/0.12 away from the ideal constants on either side.
Orientation-agnostic: the bbox area fraction of a filled triangle is ~1/2
whether the apex points up, down or sideways.

Scoring: predicted shape vs eval/answer_key.json "shape" per net.
Chance = 1/3 per net (three shape classes). Summary reports matches, n, chance
and the exact one-sided binomial tail P(X >= matches | p0 = 1/3, n = 3).
If the key is absent at real-run time: record NAMED NO_KEY_EXP2 and skip
(a verdict, not a defect) with exit 0.
===============================================================================

NAMED refusals: ARTIFACTS_DIR_MISSING, EXP2_NETS_MISSING, NPZ_KEYS_MISSING,
NPZ_SHAPE_MISMATCH, DEGENERATE_BIAS / DEGENERATE_MASK (per-net, non-fatal),
KEY_PARSE_ERROR, VENV_MISSING, OUT_WRITE_ERROR. NO_KEY_EXP2 = named skip.

Usage:
  p3_exp2_reader.py [--artifacts DIR] [--out FILE] [--dry-run]
  --dry-run: stdlib-only plan + presence gate; NO numpy import, NO network,
             NO writes; exit 0 with plan JSON, or exit 1 with NAMED refusal.
Interpreter: any python3; REAL mode re-execs under
~/.local/share/wm-mlx/bin/python (poll <= 600 s, then NAMED VENV_MISSING).
"""

import argparse
import hashlib
import json
import math
import os
import sys
import time

NETS = ("246a5b58", "a6a9dfb7", "d88aba69")
W1_KEY = "W1"   # (160, 64)
B3_KEY = "b3"   # (144,)
SIDE = 12
PIXELS = SIDE * SIDE
HIDDEN = 64
INPUTS = PIXELS + 16
# Frozen thresholds (see FROZEN RULE above):
T_SQUARE = 0.90
T_TRIANGLE = 0.62
T_BRIGHT = 0.5

FROZEN_RULE = (
    "area_ratio = #bright(Mn>=0.5)/bbox_area of output-bias image b3(144)->12x12; "
    "ar>=0.90 -> square; ar<=0.62 -> triangle; else circle. "
    "F1 |W1[0:144]| pixel-grid mass centroid reported as corroboration. "
    "samples* never read; key opened only after all predictions computed."
)


def die(code, msg):
    sys.stderr.write(f"{code}: {msg}\n")
    sys.exit(1)


def ensure_numpy(poll_s=600, interval_s=10):
    try:
        import numpy as np  # noqa: PLC0415
        return np
    except ImportError:
        pass
    venv = os.path.expanduser("~/.local/share/wm-mlx/bin/python")
    if os.environ.get("WM_P3_REEXEC") == "1":
        die("VENV_MISSING",
            f"re-exec under {venv} already done but numpy import still fails "
            f"(interpreter: {sys.executable})")
    deadline = time.time() + poll_s
    while True:
        if os.path.exists(venv) and os.access(venv, os.X_OK):
            os.environ["WM_P3_REEXEC"] = "1"
            os.execv(venv, [venv, os.path.abspath(__file__), *sys.argv[1:]])
        if time.time() > deadline:
            die("VENV_MISSING",
                f"numpy absent under {sys.executable} and {venv} absent after "
                f"{poll_s}s poll")
        time.sleep(interval_s)


def exp2_paths(artifacts):
    nets = {n: os.path.join(artifacts, "exp2_diffusion", "networks", f"{n}.npz")
            for n in NETS}
    key = os.path.join(artifacts, "exp2_diffusion", "eval", "answer_key.json")
    return nets, key


def presence_report(artifacts):
    nets, key = exp2_paths(artifacts)
    present = {n: os.path.exists(p) for n, p in nets.items()}
    return {
        "artifacts_dir": artifacts,
        "artifacts_dir_exists": os.path.isdir(artifacts),
        "nets": present,
        "answer_key_present": os.path.exists(key),
        "missing_nets": [p for n, p in nets.items() if not present[n]],
    }


def gate_nets(artifacts):
    if not os.path.isdir(artifacts):
        die("ARTIFACTS_DIR_MISSING", artifacts)
    rep = presence_report(artifacts)
    if rep["missing_nets"]:
        die("EXP2_NETS_MISSING", "missing npz: " + ", ".join(sorted(rep["missing_nets"])))
    return rep


def spatial(np, w1):
    if w1.shape != (INPUTS, HIDDEN):
        die("NPZ_SHAPE_MISMATCH", f"{W1_KEY} shape {w1.shape}")
    g = np.abs(w1[:PIXELS].astype(np.float64)).sum(axis=1).reshape(SIDE, SIDE)
    total = float(g.sum())
    ax = np.arange(SIDE, dtype=np.float64)
    return {
        "centroid_row": float((g.sum(axis=1) * ax).sum() / total),
        "centroid_col": float((g.sum(axis=0) * ax).sum() / total),
        "mass_total": total,
    }


def bias_image(np, b3):
    if b3.shape != (PIXELS,):
        die("NPZ_SHAPE_MISMATCH", f"{B3_KEY} shape {b3.shape}")
    m = b3.astype(np.float64).reshape(SIDE, SIDE)
    lo, hi = float(m.min()), float(m.max())
    if hi <= lo:
        return None, {"reason": "DEGENERATE_BIAS"}
    mn = (m - lo) / (hi - lo)
    bright = mn >= T_BRIGHT
    if not bright.any():
        return None, {"reason": "DEGENERATE_MASK"}
    rs, cs = np.nonzero(bright)
    r0, r1, c0, c1 = rs.min(), rs.max(), cs.min(), cs.max()
    bbox_area = int((r1 - r0 + 1) * (c1 - c0 + 1))
    area_ratio = float(bright.sum()) / bbox_area
    widths = bright[r0:r1 + 1, :].sum(axis=1).astype(np.float64)
    mean_w = float(widths.mean())
    constancy = 1.0 - float(widths.std() / mean_w) if mean_w > 0 else 0.0
    if r1 > r0 and widths.std() > 0:
        x = np.arange(len(widths), dtype=np.float64)
        monotonic = abs(float(np.corrcoef(x, widths)[0, 1]))
    else:
        monotonic = 0.0
    corners = np.concatenate([mn[:2, :2].ravel(), mn[:2, -2:].ravel(),
                              mn[-2:, :2].ravel(), mn[-2:, -2:].ravel()])
    feats = {
        "area_ratio": area_ratio,
        "bbox": [int(r0), int(c0), int(r1), int(c1)],
        "bright_count": int(bright.sum()),
        "width_constancy": constancy,
        "width_monotonicity": monotonic,
        "corner_brightness": float(corners.mean()),
        "bias_min": lo,
        "bias_max": hi,
    }
    return area_ratio, feats


def classify(area_ratio):
    """Frozen area-ratio rule. Returns (label, rule-tag)."""
    if area_ratio is None:
        return "none", "DEGENERATE"
    if area_ratio >= T_SQUARE:
        return "square", "area>=0.90"
    if area_ratio <= T_TRIANGLE:
        return "triangle", "area<=0.62"
    return "circle", "0.62<area<0.90"


def binom_tail_ge(k, n, p):
    return sum(math.comb(n, i) * p**i * (1 - p) ** (n - i) for i in range(k, n + 1))


def real_run(np, artifacts, out_path):
    nets, key_path = exp2_paths(artifacts)
    predictions = {}
    # ---- pass 1: features + frozen classification, key NOT opened ----
    for net in NETS:
        with np.load(nets[net]) as z:
            for k in (W1_KEY, B3_KEY):
                if k not in z.files:
                    die("NPZ_KEYS_MISSING", f"{net}: {k} not in {sorted(z.files)}")
            w1, b3 = z[W1_KEY], z[B3_KEY]
        f1 = spatial(np, w1)
        ar, f2 = bias_image(np, b3)
        label, rule = classify(ar)
        predictions[net] = {"net": net, "predicted": label, "rule": rule,
                            "features": {**f1, **f2}}
    # ---- NO_KEY_EXP2: named skip (verdict, not defect) ----
    if not os.path.exists(key_path):
        line = {"kind": "summary", "arm": "P-3", "bench": "exp2_diffusion",
                "status": "skipped", "reason": "NO_KEY_EXP2",
                "detail": f"answer key absent at {key_path}; predictions "
                          "computed but unscored",
                "predictions": [predictions[n] for n in NETS]}
        write_out(out_path, [line])
        return
    try:
        with open(key_path) as fh:
            key = json.load(fh)
    except (OSError, json.JSONDecodeError) as e:
        die("KEY_PARSE_ERROR", f"{key_path}: {e}")
    lines = []
    matches = 0
    for net in NETS:
        k = key.get(net)
        if not isinstance(k, dict) or "shape" not in k:
            die("KEY_PARSE_ERROR", f"{key_path}: no shape label for {net}")
        correct = predictions[net]["predicted"] == k["shape"]
        matches += int(correct)
        lines.append({**predictions[net], "key": k["shape"], "correct": correct})
    n = len(NETS)
    lines.append({
        "kind": "summary", "arm": "P-3", "bench": "exp2_diffusion",
        "status": "scored", "matches": matches, "n": n,
        "chance": 1.0 / 3.0,
        "binom_p_ge_matches": binom_tail_ge(matches, n, 1.0 / 3.0),
        "frozen_rule_sha256": hashlib.sha256(FROZEN_RULE.encode()).hexdigest(),
        "frozen_rule": FROZEN_RULE, "samples_read": False,
    })
    write_out(out_path, lines)


def write_out(out_path, lines):
    try:
        os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
        with open(out_path, "w") as fh:
            for ln in lines:
                fh.write(json.dumps(ln) + "\n")
    except OSError as e:
        die("OUT_WRITE_ERROR", f"{out_path}: {e}")
    for ln in lines:
        print(json.dumps(ln))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--artifacts",
                    default=os.path.join(os.environ.get("TMPDIR", "/tmp"),
                                         "p3-artifacts"))
    ap.add_argument("--out",
                    default=os.path.join(os.environ.get("TMPDIR", "/tmp"),
                                         "p3-results", "exp2.jsonl"))
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if args.dry_run:
        rep = gate_nets(args.artifacts)  # NAMED refusal when nets absent
        print(json.dumps({
            "mode": "dry-run",
            "script": "p3_exp2_reader.py",
            "network": False,
            "numpy_imported": False,
            "writes": [],
            "presence": rep,
            "key_present": rep["answer_key_present"],
            "no_key_plan": "NO_KEY_EXP2 named skip"
                           if not rep["answer_key_present"] else None,
            "frozen_rule": FROZEN_RULE,
            "frozen_rule_sha256":
                hashlib.sha256(FROZEN_RULE.encode()).hexdigest(),
            "plan": {"nets": list(NETS),
                     "features": ["F1_pixel_centroid", "F2_output_bias_image"],
                     "classify": "area-ratio rule frozen", "chance": 1.0 / 3.0,
                     "out": args.out},
        }))
        return

    gate_nets(args.artifacts)
    np = ensure_numpy()
    real_run(np, args.artifacts, args.out)


if __name__ == "__main__":
    main()
