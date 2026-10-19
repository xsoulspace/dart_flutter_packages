"""Scale decision (Phase 2, item 6) — RUN 2026-10-18: the table's rung-0
bytes/token (3.15 MB) was confirmed to the byte by GATE-4 on the real
packed smoke store (3,145,728 B).

The payload-must-fit-RAM arithmetic for the whole rung ladder, from shapes
alone (no mlx, no model, no store): parameter counts by role, resident
bytes, and bytes/token = topk x sum(mean expert bytes per layer) — the same
shape math GATE-4 computes from a real manifest, applied HERE to candidate
configs before any training pays for them.

The physics anchor this tool reasons against (FINDINGS-AND-DISCUSSION §7,
stage1_paged_moe/RESULTS.md): 30B-A3B at fp16 was a 16.3 GB payload against
~10 GB usable back-room RAM -> 0.33 tok/s, the physics STOP. "Fits the back
room" is the model-selection metric; tok/s is measured later, on real power
(POWER.md).

Usage:
  python tool/nursery/scale_decision.py                 # the whole ladder
  python tool/nursery/scale_decision.py --config my.json  # one candidate
Output: a decision table + a JSON blob (for the run record).
"""

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import model_def  # noqa: E402

BYTES_PER_ELEM = {"float32": 4, "float16": 2, "bfloat16": 2}

BACK_ROOM_GB = 10.0            # M1 Air 16 GB usable back room (B-STOP anchor)
RUNG3_BYTES_PER_TOKEN_MB = 25.0  # frozen rung-3 target (TRAIN-GATES.md)

# The ladder (TRAIN-GATES.md rung table). Params are targets, not promises:
# each entry names the config knobs that produce it (expert params dominate:
# E x 3 x F x H per layer; the presets land ~3.5M / ~43M / ~165M / ~945M —
# inside the 1–5M / 15–50M / 100–300M / 0.5–1B bands).
RUNG_PRESETS = {
    "RUNG-0": {"hidden_size": 128, "layers": 4, "experts": 8, "topk": 2,
               "intermediate": 256},
    "RUNG-1": {"hidden_size": 320, "layers": 8, "experts": 8, "topk": 2,
               "intermediate": 640},
    "RUNG-2": {"hidden_size": 512, "layers": 12, "experts": 8, "topk": 2,
               "intermediate": 1024},
    "RUNG-3": {"hidden_size": 768, "layers": 16, "experts": 16, "topk": 2,
               "intermediate": 1536},
}


def expert_bytes_by_layer(cfg, elem_bytes=4):
    """Total expert bytes per layer, from param names alone (all experts
    summed; scale_report divides by cfg.experts for the GATE-4 mean)."""
    per_layer = {}
    for name, shape, _dtype in model_def.param_names_and_shapes(cfg):
        if ".mlp.experts." not in name:
            continue
        layer = int(name.split("layers.")[1].split(".")[0])
        n = 1
        for d in shape:
            n *= d
        per_layer[layer] = per_layer.get(layer, 0) + n * elem_bytes
    return per_layer


def scale_report(cfg, elem_bytes=4, quant_note="unquantized f32"):
    total_params = model_def.param_count(cfg)
    per_layer = expert_bytes_by_layer(cfg, elem_bytes)
    # GATE-4's exact formula (pack_at_birth.payload_stats): bytes/token =
    # topk x SUM over layers of the MEAN expert's bytes in that layer.
    mean_per_layer = [b / cfg.experts for b in per_layer.values()]
    bytes_per_token = cfg.topk * sum(mean_per_layer)
    total_bytes = total_params * elem_bytes
    return {
        "quantization": quant_note,
        "params": total_params,
        "resident_mb": round(total_bytes / 1e6, 1),
        "expert_payload_mb": round(sum(per_layer.values()) / 1e6, 1),
        "bytes_per_token_mb": round(bytes_per_token / 1e6, 2),
        "fits_back_room": total_bytes <= BACK_ROOM_GB * 1e9,
        "meets_rung3_bytes_per_token": bytes_per_token <= RUNG3_BYTES_PER_TOKEN_MB * 1e6,
    }


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--config", help="one candidate config JSON (model keys)")
    args = ap.parse_args(argv)

    rows = []
    if args.config:
        cfg = model_def.NurseryConfig.from_json(json.load(open(args.config)))
        rows.append(("custom", scale_report(cfg)))
    else:
        for rung, knobs in RUNG_PRESETS.items():
            cfg = model_def.NurseryConfig(**knobs)
            rows.append((rung, scale_report(cfg)))

    hdr = (f"{'rung':>8} {'params':>12} {'resident':>10} {'expertMB':>9} "
           f"{'MB/token':>9} {'backroom':>9} {'25MB/tok':>9}")
    print(hdr)
    print("-" * len(hdr))
    for name, r in rows:
        print(f"{name:>8} {r['params']:>12,} {r['resident_mb']:>8}MB "
              f"{r['expert_payload_mb']:>9} {r['bytes_per_token_mb']:>9} "
              f"{'fits' if r['fits_back_room'] else 'NO':>9} "
              f"{'yes' if r['meets_rung3_bytes_per_token'] else 'no':>9}")
    print(f"\nback room {BACK_ROOM_GB:.0f} GB (B-STOP anchor); "
          f"25 MB/token binds at rung-3 (TRAIN-GATES.md)")
    print(json.dumps({name: r for name, r in rows}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
