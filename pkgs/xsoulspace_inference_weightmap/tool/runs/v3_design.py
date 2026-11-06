#!/usr/bin/env python3
"""v3_design.py - V-3 (cross-cast replication, second cast) draw procedures.

V3-OWNED file (new; edits NOTHING frozen). Procedures mirror a3_design.py
with the second cast's shape parameters and the V-3 seed law, all recorded in
the V3 run-plan ledger row BEFORE any measurement:

  CAST            qwen3-1.7b (hub 4bit, losslessly dequantized to fp16 by
                  v3_dequant.py; frozen builders require a plain-float store)
  LAYERS_TOTAL    28
  LAYER MAP RULE  layer_i = round(f_i * LAYERS_TOTAL), f in {15/24, 19/24}
                  (round half-up; Python round() identical at these values):
                  15/24*28 = 17.5 -> 18 ; 19/24*28 = 22.166... -> 22
                  => LAYERS = ("18", "22")  (recorded PRE-RUN)
  HIDDEN          2048  (down_proj rows)
  N_COLS_TOTAL    6144  (down_proj columns = intermediate size)
  N_COLUMNS       64    (frozen run-plan rank, same as A3)

Seed law (task brief 2026-11-06):
  SEED_COLUMNS = 20261105 - the A3 pair_columns PROCEDURE and seed are pinned
      by the V-3 task brief for the 64-column draws ("pair_columns(k) seed
      20261105"); the sample RANGE is parameterized to this cast's 6144
      columns (adaptation recorded pre-run). Plant k and null k SHARE columns.
  SEED_V3 = 20261106 - the new V-3 blinding/design seed ("20261106-V3"; the
      20261105 seed belongs to A3's sealed plan and is used ONLY for the
      column draws above). Null directions: Random(SEED_V3*1000+100+k).
      Random-proposer control directions: Random(SEED_V3*1000+500+k).

  pair_columns_v3(k)   : sorted(Random(20261105*1000+k).sample(range(6144),64))
  null_direction_v3(k) : per layer in ("18","22"): 2048 sequential gauss(0,1)
                         draws from Random(20261106*1000+100+k), L2-normalized
                         (unit; norm-matched to the unit plant direction)
  control_direction_v3(k): same shape as null_direction_v3 with offset 500
                         (random-proposer CONTROL repairs; must certify
                         nothing - CONTROL_LEAK halt otherwise)
"""

import random

SEED_COLUMNS = 20261105   # frozen A3 pair_columns lineage (task-brief pinned)
SEED_V3 = 20261106        # new V-3 seed ("20261106-V3")
N_COLUMNS = 64            # FROZEN (run plan; matches the paper's 64-column edit)
N_COLS_TOTAL = 6144       # qwen3-1.7b down_proj columns (intermediate size)
HIDDEN = 2048             # qwen3-1.7b down_proj rows (hidden size)
LAYERS_TOTAL = 28
LAYERS = ("18", "22")     # round(15/24*28)=18, round(19/24*28)=22 (PRE-RUN)


def layer_map_rule(layers_total):
    """The pre-registered mapping rule, evaluated (recorded pre-run)."""
    out = []
    for f_num in (15, 19):
        exact = f_num / 24.0 * layers_total
        # round half-up (Python round() gives the same values here:
        # round(17.5)=18 via round-half-even to 18, round(22.166..)=22)
        r = int(exact + 0.5)
        out.append({"fraction": "%d/24" % f_num, "exact": exact,
                    "rounded_half_up": r, "python_round": round(exact)})
    return out


def pair_columns_v3(k):
    rng = random.Random(SEED_COLUMNS * 1000 + k)
    return sorted(rng.sample(range(N_COLS_TOTAL), N_COLUMNS))


def _unit_gauss_pair(k, offset):
    rng = random.Random(SEED_V3 * 1000 + offset + k)
    out = {}
    for layer in LAYERS:
        v = [rng.gauss(0.0, 1.0) for _ in range(HIDDEN)]
        norm = sum(x * x for x in v) ** 0.5
        out[layer] = [x / norm for x in v]
    return out


def null_direction_v3(k):
    return _unit_gauss_pair(k, 100)


def control_direction_v3(k):
    return _unit_gauss_pair(k, 500)


def tensor_name(layer):
    return "model.layers.%s.mlp.down_proj.weight" % layer
