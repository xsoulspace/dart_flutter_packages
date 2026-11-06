#!/usr/bin/env python3
"""p3_exp1_reader.py — PREREG-D §P-3 exp1 (which game) weight-space reader.

BLIND READER: reads ONLY the .npz weight arrays. networks/meta/*.json contains
the "game" label per net and is NEVER opened by this script (label leak). The
answer key (eval/answer_key.json) is opened ONLY after all four predictions are
computed. Rendered/behavioral artifacts are not used.

============================ FROZEN RULE (freeze-it-in-code) ==================
Written before any scoring run (2026-11-05). Features are exactly the two
pre-registered in PREREG-D §P-3:

F1 input-layer spatial mass centroid.
   Grid layout per exp1_which_game/networks/description.txt (published):
   10x10 grid, 5 binary channels, input i = (row*10 + col)*5 + channel.
   W1 = actor/dense1/kernel, shape (500, 32); row i = weights from input i.
   G(r,c) = sum over channels ch in 0..4 and hidden units j in 0..31 of
            |W1[(r*10+c)*5 + ch, j]|
   centroid_row = sum_r r*G(r)/sum G ; centroid_col = sum_c c*G(c)/sum G.

F2 output-layer action bias vector.
   b3 = actor/logits/bias, shape (5,) = logits bias for
   [no-op, up(row 0-ward), down(row 9-ward), left(col 0-ward), right(col 9-ward)].

Corroboration features (computed + reported, NOT part of the decision):
   top_heaviness  = G(rows 1-3) / G(rows 6-8)   (breakout bricks sit top)
   side_heaviness = G(cols 1,2,7,8) / G(cols 4,5) (pong paddles sit at sides)

CLASSIFICATION RULE (decision order frozen; rationale = published game
mechanics from description.txt + general Atari knowledge + published
meta action_usage stats, NOT the answer key):
   Let z = z-score of [b3_up, b3_down, b3_left, b3_right] (population std;
   std == 0 -> NAMED DEGENERATE_BIAS, prediction "none", scored as a miss).
   R1  z_up is the strict maximum AND z_up - max(z_down,z_left,z_right) >= 1.0
         -> "freeway"
       (freeway is the only game whose reward lies in ONE direction: up toward
        row 0; cars move horizontally; published meta shows ~86% up actions.)
   R2  (z_left + z_right)/2 - (z_up + z_down)/2 >= 0.75
         -> "breakout"
       (breakout paddle slides horizontally only; vertical motion impossible.)
   R3  (z_up + z_down)/2 - (z_left + z_right)/2 >= 0.75
         -> "pong"
       (pong paddle slides vertically only.)
   R4  otherwise -> "pacman"
       (4-direction maze game; direction biases approximately balanced.)

Scoring: predicted label vs eval/answer_key.json game label per net.
Chance = 1/4 per net (PREREG-D). Summary reports matches, n, chance and the
exact one-sided binomial tail P(X >= matches | p0 = 1/4, n).
===============================================================================

NAMED refusals: ARTIFACTS_DIR_MISSING, EXP1_NETS_MISSING, EXP1_KEY_MISSING,
NPZ_KEYS_MISSING, NPZ_SHAPE_MISMATCH, DEGENERATE_BIAS (per-net, non-fatal),
KEY_PARSE_ERROR, VENV_MISSING, OUT_WRITE_ERROR.

Usage:
  p3_exp1_reader.py [--artifacts DIR] [--out FILE] [--dry-run]
  --dry-run: stdlib-only plan + presence gate; NO numpy import, NO network,
             NO writes; exit 0 with plan JSON, or exit 1 with NAMED refusal.
Interpreter: runs under any python3; for the REAL mode numpy is required and
the script re-execs under ~/.local/share/wm-mlx/bin/python, polling up to
600 s for that venv to appear, then refuses NAMED VENV_MISSING.
"""

import argparse
import hashlib
import json
import math
import os
import sys
import time

NETS = ("0bbcc3ea", "a9f535cc", "bdf99279", "dfc6cb65")
W1_KEY = "actor/dense1/kernel"   # (500, 32)
B3_KEY = "actor/logits/bias"     # (5,)
GRID = 10
CHANNELS = 5
HIDDEN = 32
NACTIONS = 5
# Frozen thresholds (see FROZEN RULE above):
T_UNI_DOMINANT = 1.0   # R1 freeway margin in z-units
T_GROUP_DOMINANT = 0.75  # R2/R3 horizontal/vertical margin in z-units

FROZEN_RULE = (
    "R1 freeway: z_up strict max and z_up-max(others)>=1.0; "
    "R2 breakout: (z_l+z_r)/2-(z_u+z_d)/2>=0.75; "
    "R3 pong: (z_u+z_d)/2-(z_l+z_r)/2>=0.75; R4 pacman: else. "
    "Features: F1 |W1| grid mass centroid (10x10x5 layout, description.txt); "
    "F2 b3=actor/logits/bias. meta/*.json NEVER read (label leak); key opened "
    "only after all predictions computed."
)


def die(code, msg):
    sys.stderr.write(f"{code}: {msg}\n")
    sys.exit(1)


def ensure_numpy(poll_s=600, interval_s=10):
    """numpy under the wm-mlx venv; poll up to poll_s, then NAMED VENV_MISSING."""
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


def exp1_paths(artifacts):
    nets = {n: os.path.join(artifacts, "exp1_which_game", "networks", f"{n}.npz")
            for n in NETS}
    key = os.path.join(artifacts, "exp1_which_game", "eval", "answer_key.json")
    return nets, key


def presence_report(artifacts):
    nets, key = exp1_paths(artifacts)
    present = {n: os.path.exists(p) for n, p in nets.items()}
    return {
        "artifacts_dir": artifacts,
        "artifacts_dir_exists": os.path.isdir(artifacts),
        "nets": present,
        "answer_key": os.path.exists(key),
        "missing": [p for n, p in nets.items() if not present[n]]
                   + ([] if os.path.exists(key) else [key]),
    }


def gate(artifacts):
    """NAMED refusal when required artifacts are absent (dry-run and real)."""
    if not os.path.isdir(artifacts):
        die("ARTIFACTS_DIR_MISSING", artifacts)
    rep = presence_report(artifacts)
    if not all(rep["nets"].values()):
        die("EXP1_NETS_MISSING",
            "missing npz: " + ", ".join(sorted(rep["missing"])))
    if not rep["answer_key"]:
        die("EXP1_KEY_MISSING", rep["missing"][-1])


def classify(b3):
    """Frozen R1-R4 over the 4 directional action biases. Returns
    (label, features-dict). Pure function; no key access."""
    dirs = [float(b3[1]), float(b3[2]), float(b3[3]), float(b3[4])]  # u,d,l,r
    mu = sum(dirs) / 4.0
    var = sum((x - mu) ** 2 for x in dirs) / 4.0
    if var <= 0.0:
        return "none", {"z": None, "reason": "DEGENERATE_BIAS"}
    sd = math.sqrt(var)
    zu, zd, zl, zr = ((x - mu) / sd for x in dirs)
    horiz = (zl + zr) / 2.0 - (zu + zd) / 2.0
    vert = -horiz
    if zu == max(zu, zd, zl, zr) and zu > max(zd, zl, zr) \
            and zu - max(zd, zl, zr) >= T_UNI_DOMINANT:
        label, rule = "freeway", "R1"
    elif horiz >= T_GROUP_DOMINANT:
        label, rule = "breakout", "R2"
    elif vert >= T_GROUP_DOMINANT:
        label, rule = "pong", "R3"
    else:
        label, rule = "pacman", "R4"
    return label, {"z": {"up": zu, "down": zd, "left": zl, "right": zr},
                   "horiz_minus_vert": horiz, "rule": rule}


def features(np, w1, b3):
    """F1 spatial mass centroid + corroboration (frozen definitions)."""
    if w1.shape != (GRID * GRID * CHANNELS, HIDDEN):
        die("NPZ_SHAPE_MISMATCH", f"{W1_KEY} shape {w1.shape}")
    if b3.shape != (NACTIONS,):
        die("NPZ_SHAPE_MISMATCH", f"{B3_KEY} shape {b3.shape}")
    abs_w = np.abs(w1.astype(np.float64))
    # input i = (r*10+c)*5+ch  ->  reshape (10, 10, 5, 32), sum ch+j
    g = abs_w.reshape(GRID, GRID, CHANNELS, HIDDEN).sum(axis=(2, 3))  # (10,10)
    total = float(g.sum())
    rows = np.arange(GRID, dtype=np.float64)
    cent_row = float((g.sum(axis=1) * rows).sum() / total)
    cent_col = float((g.sum(axis=0) * rows).sum() / total)
    top = float(g[1:4, :].sum())
    bottom = float(g[6:9, :].sum())
    sides = float(g[:, [1, 2, 7, 8]].sum())
    middle = float(g[:, [4, 5]].sum())
    return {
        "centroid_row": cent_row,
        "centroid_col": cent_col,
        "top_heaviness": top / bottom if bottom > 0 else None,
        "side_heaviness": sides / middle if middle > 0 else None,
        "mass_total": total,
    }


def binom_tail_ge(k, n, p):
    return sum(math.comb(n, i) * p**i * (1 - p) ** (n - i) for i in range(k, n + 1))


def real_run(np, artifacts, out_path):
    nets, key_path = exp1_paths(artifacts)
    predictions = {}
    # ---- pass 1: features + frozen classification, key NOT opened ----
    for net in NETS:
        with np.load(nets[net]) as z:
            for k in (W1_KEY, B3_KEY):
                if k not in z.files:
                    die("NPZ_KEYS_MISSING", f"{net}: {k} not in {sorted(z.files)}")
            w1, b3 = z[W1_KEY], z[B3_KEY]
        f1 = features(np, w1, b3)
        label, f2 = classify(b3)
        predictions[net] = {
            "net": net,
            "predicted": label,
            "action_bias": [round(float(x), 6) for x in b3],
            "features": {**f1, **f2},
        }
    # ---- pass 2: score against the published key ----
    try:
        with open(key_path) as fh:
            key = json.load(fh)
    except (OSError, json.JSONDecodeError) as e:
        die("KEY_PARSE_ERROR", f"{key_path}: {e}")
    lines = []
    matches = 0
    for net in NETS:
        k = key.get(net)
        if not isinstance(k, dict) or "game" not in k:
            die("KEY_PARSE_ERROR", f"{key_path}: no game label for {net}")
        correct = predictions[net]["predicted"] == k["game"]
        matches += int(correct)
        lines.append({**predictions[net], "key": k["game"], "correct": correct})
    n = len(NETS)
    summary = {
        "kind": "summary",
        "arm": "P-3",
        "bench": "exp1_which_game",
        "matches": matches,
        "n": n,
        "chance": 0.25,
        "binom_p_ge_matches": binom_tail_ge(matches, n, 0.25),
        "frozen_rule_sha256": hashlib.sha256(FROZEN_RULE.encode()).hexdigest(),
        "frozen_rule": FROZEN_RULE,
        "meta_json_read": False,
    }
    lines.append(summary)
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
                                         "p3-results", "exp1.jsonl"))
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if args.dry_run:
        gate(args.artifacts)  # NAMED refusal when artifacts absent
        rep = presence_report(args.artifacts)
        print(json.dumps({
            "mode": "dry-run",
            "script": "p3_exp1_reader.py",
            "network": False,
            "numpy_imported": False,
            "writes": [],
            "required_present": True,
            "presence": rep,
            "frozen_rule": FROZEN_RULE,
            "frozen_rule_sha256":
                hashlib.sha256(FROZEN_RULE.encode()).hexdigest(),
            "plan": {"nets": list(NETS), "features": ["F1_centroid", "F2_action_bias"],
                     "classify": "R1..R4 frozen", "score_vs": "eval/answer_key.json",
                     "out": args.out},
        }))
        return

    gate(args.artifacts)
    np = ensure_numpy()
    real_run(np, args.artifacts, args.out)


if __name__ == "__main__":
    main()
