#!/usr/bin/env python3
"""v12_nulls.py - PREREG-C V-1/V-2 spec builder (V12-OWNED helper).

Builds repair-spec JSON files ({tensors:[{name, columns, direction, scale}]},
the exact shape consumed by the FROZEN a3_battery.py --repair) for the V-1
matched nulls and the V-2 interventions on the A3 plant-1 (arm-002) certified
edit. This file NEVER scores, NEVER touches frozen tools, and only reads
archived arm-002 artifacts plus (for null3) a frozen-proposer output.

All constructions below are pre-registered in receipts/V1-nulls.jsonl
kind=v12-run-plan BEFORE any measurement.

V-1 nulls - same 64 columns as arm-002, layers {15,19}, scale = -4.8 (the A3
removal convention: subtract direction at plant scale s*), unit-norm
directions (norm-matched to ||d_hat|| = 1):
  null1 gaussian:    per layer, iid N(0,1) x1024 from Random(seed*10+1+layer),
                     L2-normalized to 1.
  null2 shuffle:     per layer, perm = Random(seed*10+2+layer).sample(
                     range(1024),1024); v[i] = d_hat_L[perm[i]]. Norm exactly
                     preserved (same component multiset = same spectrum,
                     wrong geometry).
  null3 unrelated:   per-layer direction from a3_propose.py (FROZEN rule:
                     unit-normalized diff-of-means) run on captures of
                     (G0-slugify bank, frozen neutral bank) taken on the
                     rebuilt plant-1 mirror; requires --slugify-recovered.
  null4 quantnoise:  per layer, sign_i = Random(seed*10+4+layer).choice(
                     (-1.0,1.0)) for i ascending; y_i = |scale_applied *
                     d_hat_i| with scale_applied = 4.8; halfULP_bf16(y) =
                     0 if y==0 else 2**(floor(log2(y))-8)  (bf16 = 1+7
                     mantissa bits => ULP(y) = 2**(floor(log2 y)-7));
                     p_i = sign_i * halfULP_bf16(y_i); then p L2-normalized
                     to 1 (scaled to the recovered direction's norm).

V-2 intervention specs (on the same rebuilt plant-1 mirror):
  ablate:   arm-002 repair_spec.json with scale := 0.0 on both tensors
            (zeroes the removal delta on the claimed L15/L19 64 columns).
  restore:  arm-002 repair_spec.json VERBATIM (scale -4.8, d_hat, columns).
  relocate: two entries BOTH naming model.layers.8.mlp.down_proj.weight,
            same 64 columns, scale -4.8 each, directions d_hat_15 then
            d_hat_19 (a3_battery.py applies entries sequentially: the full
            removal content relocated to control layer 8; L15/L19 stay
            planted, no removal there).

Usage:
  python3 -I -B v12_nulls.py --arm-dir <wm-a3/blind/arm-002> \
      --out-dir <wm-v12/specs> --seed 20261106 \
      [--slugify-recovered <recovered_slugify.json>]

Exit codes: 0 ok; 1 NAMED error on stderr ('CODE: detail'):
  ARM_INPUTS_MISSING D_HAT_MISMATCH NULL3_INPUT_MISSING
  QUANT_NULL_DEGENERATE SPEC_UNWRITABLE
"""

import argparse
import hashlib
import json
import math
import os
import random
import shutil
import sys
from datetime import datetime, timezone

LAYERS = ["15", "19"]
DIM = 1024
REMOVAL_SCALE = -4.8
RELOCATE_TENSOR = "model.layers.8.mlp.down_proj.weight"


def fail(code, detail):
    print("%s: %s" % (code, detail), file=sys.stderr)
    return 1


def sha256_json_list(vals):
    return hashlib.sha256(json.dumps(vals).encode()).hexdigest()


def l2norm(v):
    return math.sqrt(sum(x * x for x in v))


def unit(v):
    n = l2norm(v)
    if n == 0.0:
        raise ValueError("zero-norm vector")
    return [x / n for x in v]


def cosine(a, b):
    return sum(x * y for x, y in zip(a, b)) / (l2norm(a) * l2norm(b))


def half_ulp_bf16(y):
    """Half-ULP of bf16 at magnitude y >= 0 (bf16: 1 sign + 8 exp + 7 mantissa
    bits => ULP(y) = 2**(floor(log2(y)) - 7) for y > 0)."""
    if y == 0.0:
        return 0.0
    return 2.0 ** (math.floor(math.log2(y)) - 8)


def build_spec(names_cols, directions, scale):
    return {"tensors": [
        {"name": name, "columns": cols, "direction": directions[layer],
         "scale": scale}
        for (layer, (name, cols)) in names_cols.items()
    ]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--arm-dir", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--slugify-recovered", default=None)
    args = ap.parse_args()

    recovered_p = os.path.join(args.arm_dir, "recovered.json")
    repair_p = os.path.join(args.arm_dir, "repair_spec.json")
    for p in (recovered_p, repair_p):
        if not os.path.isfile(p):
            return fail("ARM_INPUTS_MISSING", p)
    recovered = json.load(open(recovered_p, encoding="utf-8"))
    repair = json.load(open(repair_p, encoding="utf-8"))

    d_hat = {L: list(recovered["layers"][L]["direction"]) for L in LAYERS}
    names_cols = {}
    for t in repair["tensors"]:
        layer = t["name"].split(".")[2]
        if layer not in LAYERS:
            return fail("D_HAT_MISMATCH", "unexpected tensor %s" % t["name"])
        names_cols[layer] = (t["name"], [int(c) for c in t["columns"]])
        if list(t["direction"]) != d_hat[layer]:
            return fail("D_HAT_MISMATCH",
                        "repair_spec direction != recovered.json layer %s"
                        % layer)
        if abs(float(t["scale"]) - REMOVAL_SCALE) > 1e-12:
            return fail("D_HAT_MISMATCH",
                        "repair_spec scale %s != %s" % (t["scale"],
                                                        REMOVAL_SCALE))
    for L in LAYERS:
        if L not in names_cols or len(d_hat[L]) != DIM:
            return fail("D_HAT_MISMATCH", "layer %s missing/wrong dim" % L)

    os.makedirs(args.out_dir, exist_ok=True)
    manifest = {
        "tool": "v12_nulls.py",
        "created_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "seed": args.seed,
        "d_hat_source": {
            "recovered_json": os.path.abspath(recovered_p),
            "recovered_json_sha256": hashlib.sha256(
                open(recovered_p, "rb").read()).hexdigest(),
            "repair_spec_sha256": hashlib.sha256(
                open(repair_p, "rb").read()).hexdigest(),
            "per_layer_direction_sha256": {
                L: sha256_json_list(d_hat[L]) for L in LAYERS},
            "per_layer_norm": {L: l2norm(d_hat[L]) for L in LAYERS},
        },
        "removal_scale": REMOVAL_SCALE,
        "columns_per_layer": {L: names_cols[L][1] for L in LAYERS},
        "nulls": {},
        "v2_specs": {},
    }

    def record(kind, key, directions, extra):
        spec = build_spec(names_cols, directions, REMOVAL_SCALE)
        path = os.path.join(args.out_dir, "%s_spec.json" % key)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(spec, fh)
        entry = {
            "spec_path": path,
            "spec_sha256": hashlib.sha256(
                open(path, "rb").read()).hexdigest(),
            "scale": REMOVAL_SCALE,
            "per_layer": {
                L: {
                    "direction_sha256": sha256_json_list(directions[L]),
                    "norm": l2norm(directions[L]),
                    "cos_with_d_hat": cosine(directions[L], d_hat[L]),
                } for L in LAYERS},
        }
        entry.update(extra)
        manifest[kind][key] = entry

    # --- null1: unit Gaussian, seeded per layer ---
    dirs1 = {}
    for L in LAYERS:
        rng = random.Random(args.seed * 10 + 1 + int(L))
        g = [rng.gauss(0.0, 1.0) for _ in range(DIM)]
        dirs1[L] = unit(g)
    record("nulls", "null1_gaussian", dirs1,
           {"construction": "iid N(0,1) x1024, Random(seed*10+1+layer), "
                            "L2-normalized"})

    # --- null2: seeded within-layer shuffle of d_hat ---
    dirs2 = {}
    perms = {}
    for L in LAYERS:
        rng = random.Random(args.seed * 10 + 2 + int(L))
        perm = rng.sample(range(DIM), DIM)
        perms[L] = perm[:8]  # first 8 indices as evidence, not the full perm
        dirs2[L] = [d_hat[L][perm[i]] for i in range(DIM)]
    record("nulls", "null2_shuffle", dirs2,
           {"construction": "v[i]=d_hat[perm[i]], perm=Random(seed*10+2+layer)"
                            ".sample(range(1024),1024); norm preserved exactly",
            "perm_head_evidence": perms})

    # --- null3: unrelated concept (slugify-vs-neutral on the plant mirror) ---
    if args.slugify_recovered:
        if not os.path.isfile(args.slugify_recovered):
            return fail("NULL3_INPUT_MISSING", args.slugify_recovered)
        rec3 = json.load(open(args.slugify_recovered, encoding="utf-8"))
        dirs3 = {L: list(rec3["layers"][L]["direction"]) for L in LAYERS}
        record("nulls", "null3_unrelated", dirs3,
               {"construction": "a3_propose.py (frozen diff-of-means rule) on "
                                "captures of G0-slugify bank vs frozen neutral "
                                "bank, both on the rebuilt plant-1 mirror",
                "slugify_recovered_path": os.path.abspath(
                    args.slugify_recovered),
                "slugify_recovered_sha256": hashlib.sha256(
                    open(args.slugify_recovered, "rb").read()).hexdigest(),
                "diff_l2_norm": {L: rec3["layers"][L]["diff_l2_norm"]
                                 for L in LAYERS}})

    # --- null4: bf16 half-ULP random-sign pattern, norm-matched ---
    dirs4 = {}
    raw_norms = {}
    for L in LAYERS:
        rng = random.Random(args.seed * 10 + 4 + int(L))
        p = []
        for i in range(DIM):
            sgn = rng.choice((-1.0, 1.0))
            y = abs(REMOVAL_SCALE) * abs(d_hat[L][i])
            p.append(sgn * half_ulp_bf16(y))
        raw_norms[L] = l2norm(p)
        if raw_norms[L] == 0.0:
            return fail("QUANT_NULL_DEGENERATE", "layer %s" % L)
        dirs4[L] = unit(p)
    record("nulls", "null4_quantnoise", dirs4,
           {"construction": "p_i = sign_i * halfULP_bf16(|4.8*d_hat_i|), "
                            "signs=Random(seed*10+4+layer).choice((-1,1)) "
                            "ascending i; L2-normalized to 1",
            "raw_pattern_norm_before_scaling": raw_norms,
            "zero_components": {
                L: sum(1 for x in d_hat[L] if x == 0.0) for L in LAYERS}})

    # --- V-2 specs ---
    ablate = {"tensors": [
        dict(t, scale=0.0) for t in repair["tensors"]]}
    p = os.path.join(args.out_dir, "ablate_spec.json")
    json.dump(ablate, open(p, "w", encoding="utf-8"))
    manifest["v2_specs"]["ablate"] = {
        "spec_path": p,
        "spec_sha256": hashlib.sha256(open(p, "rb").read()).hexdigest(),
        "construction": "arm-002 repair_spec.json with scale := 0.0 (removal "
                        "delta zeroed on the claimed L15/L19 64 columns)"}

    p = os.path.join(args.out_dir, "restore_spec.json")
    shutil.copyfile(repair_p, p)
    manifest["v2_specs"]["restore"] = {
        "spec_path": p,
        "spec_sha256": hashlib.sha256(open(p, "rb").read()).hexdigest(),
        "source_repair_spec_sha256": hashlib.sha256(
            open(repair_p, "rb").read()).hexdigest(),
        "construction": "arm-002 repair_spec.json VERBATIM"}

    reloc = {"tensors": [
        {"name": RELOCATE_TENSOR, "columns": names_cols["15"][1],
         "direction": d_hat["15"], "scale": REMOVAL_SCALE},
        {"name": RELOCATE_TENSOR, "columns": names_cols["19"][1],
         "direction": d_hat["19"], "scale": REMOVAL_SCALE},
    ]}
    p = os.path.join(args.out_dir, "relocate_spec.json")
    json.dump(reloc, open(p, "w", encoding="utf-8"))
    manifest["v2_specs"]["relocate"] = {
        "spec_path": p,
        "spec_sha256": hashlib.sha256(open(p, "rb").read()).hexdigest(),
        "construction": "both removal components (d_hat_15, d_hat_19) applied "
                        "sequentially to %s, same 64 columns, scale -4.8 each; "
                        "L15/L19 stay planted" % RELOCATE_TENSOR}

    out = os.path.join(args.out_dir, "nulls_manifest.json")
    try:
        with open(out, "w", encoding="utf-8") as fh:
            json.dump(manifest, fh, indent=1)
    except OSError as exc:
        return fail("SPEC_UNWRITABLE", str(exc))
    print("NULLS_OK %s nulls=%s v2=%s" % (
        out, sorted(manifest["nulls"]), sorted(manifest["v2_specs"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
