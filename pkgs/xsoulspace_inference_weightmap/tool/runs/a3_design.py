#!/usr/bin/env python3
"""a3_design.py - frozen A3 draw procedures (columns + null directions).

These procedures are part of the pre-registered run plan (recorded in the
VERDICTS.md run-plan row BEFORE any plant): deterministic, seeded by the
frozen blinding seed 20261105, reproducible by anyone from this file.

  pair_columns(k)      : the 64 down_proj columns of pair k (plant k and
                         null k SHARE columns - matched control, task brief
                         "nulls = matched-norm random Gaussian directions,
                         same columns"). sorted(Random(SEED*1000+k)
                         .sample(range(3072), 64))
  null_direction(k)    : two independent unit-norm Gaussian vectors (one per
                         layer, length 1024 = down_proj rows), norm-matched
                         to the unit-norm plant direction.
                         Random(SEED*1000+100+k), sequential gauss draws:
                         first 1024 -> layer 15 vector, next 1024 -> layer 19
                         vector, each L2-normalized.
"""

import random

SEED = 20261105          # FROZEN (PREREG-A blinding seed)
N_COLUMNS = 64           # FROZEN (run plan; matches the paper's 64-column edit)
N_COLS_TOTAL = 3072      # down_proj columns (intermediate size)
HIDDEN = 1024            # down_proj rows (hidden size)
LAYERS = ("15", "19")    # two mid layers (paper-lineage choice, frozen)


def pair_columns(k):
    rng = random.Random(SEED * 1000 + k)
    return sorted(rng.sample(range(N_COLS_TOTAL), N_COLUMNS))


def null_direction(k):
    rng = random.Random(SEED * 1000 + 100 + k)
    out = {}
    for layer in LAYERS:
        v = [rng.gauss(0.0, 1.0) for _ in range(HIDDEN)]
        norm = sum(x * x for x in v) ** 0.5
        out[layer] = [x / norm for x in v]
    return out
