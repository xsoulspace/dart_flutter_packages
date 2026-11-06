#!/usr/bin/env python3
"""ws1_export_window.py - WS-1 helper: export one tensor (or column window).

Reads a safetensors store with mlx (the SAME environment the A3 builders
ran in), widens the stored values to f32 then f64 (both casts exact for
bf16 material), slices columns [col_start, col_end) when requested (omit
both flags to export the FULL tensor - the typed patch addresses carry
absolute column bounds, so the algebra materializes against full-tensor
coordinates), and writes the row-major window as raw little-endian
float64. Prints one line: `ROWS=<rows> WIDTH=<width>`.

This is a READ-ONLY export for the Dart patch algebra (patch_algebra.dart
materializes the typed patch against the REAL base values); it never writes
to the store and never edits anything. Durable evidence stays textual; the
raw window file is $TMPDIR scratch (probe scratch law).

Usage:
  <venv-python> -I ws1_export_window.py --store <mirror-dir> \
      --tensor <name> [--col-start <int> --col-end <int>] --out <file.f64>

Exit codes: 0 ok; 1 NAMED error on stderr ('CODE: detail'):
  STORE_MISSING TENSOR_MISSING SHAPE_MISMATCH MLX_UNAVAILABLE OUT_UNWRITABLE
"""

import argparse
import os
import sys

EXIT_OK = 0
EXIT_FAIL = 1


def fail(code, detail):
    print("%s: %s" % (code, detail), file=sys.stderr)
    return EXIT_FAIL


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--store", required=True)
    ap.add_argument("--tensor", required=True)
    ap.add_argument("--col-start", type=int, default=None)
    ap.add_argument("--col-end", type=int, default=None)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    try:
        import mlx.core as mx
        import numpy as np
    except ImportError as exc:
        return fail("MLX_UNAVAILABLE", str(exc))

    shard = os.path.join(args.store, "model.safetensors")
    if not os.path.isfile(shard):
        return fail("STORE_MISSING", shard)
    try:
        arrays = mx.load(shard)
    except Exception as exc:
        return fail("STORE_MISSING", "mx.load failed (%s)" % exc)
    if args.tensor not in arrays:
        return fail("TENSOR_MISSING", args.tensor)
    w = arrays[args.tensor]
    if w.ndim != 2:
        return fail("SHAPE_MISMATCH", "%s ndim=%d" % (args.tensor, w.ndim))
    rows = int(w.shape[0])
    cols = int(w.shape[1])
    col_start = 0 if args.col_start is None else args.col_start
    col_end = cols if args.col_end is None else args.col_end
    if (args.col_start is None) != (args.col_end is None):
        return fail("SHAPE_MISMATCH",
                    "--col-start and --col-end must be given together")
    if not (0 <= col_start < col_end <= cols):
        return fail("SHAPE_MISMATCH",
                    "window [%d,%d) vs cols=%d" % (col_start, col_end, cols))
    a = np.array(w.astype(mx.float32)).astype("<f8")
    window = np.ascontiguousarray(a[:, col_start:col_end])
    try:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        window.tofile(args.out)
    except OSError as exc:
        return fail("OUT_UNWRITABLE", str(exc))
    print("ROWS=%d WIDTH=%d" % (rows, window.shape[1]))
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
