#!/usr/bin/env python3
"""delta_merge.py - L4 python REFERENCE for the in-memory delta merge
(PREREG-SPEED.md, FROZEN 2026-11-10). Pure math on plain lists — the
semantics are the FROZEN apply_delta.py docstring verbatim:

  "the delta for `tensor` (rows x cols) is zero except at the chosen
   columns; each chosen column j receives `scale * direction`"

i.e. merged[:, j] = base[:, j] + scale * direction  (the SIGN lives in the
spec's direction values; scale is non-negative by convention).

This module is the parity anchor for native/mlx_native/src/delta_sidecar.rs:
the first live run receipts merged-tensor digests python == rust (the
qwen35_parity pattern) before the Rust path feeds any certification cell.
"""

import hashlib
import json


def merged_column(base_col, direction, scale):
    """base[:, j] + scale * direction; lengths must equal (rows)."""
    if len(base_col) != len(direction):
        raise ValueError('ROWS_MISMATCH: base %d != direction %d'
                         % (len(base_col), len(direction)))
    return [b + scale * d for b, d in zip(base_col, direction)]


def merged_tensor(base, columns, direction, scale):
    """Full-tensor merge: base is row-major [rows, cols]; returns a NEW
    row-major list with the chosen columns merged. Zero-copy semantics: the
    base list is never mutated. Direction must cover EVERY row (the frozen
    apply_delta.py checks direction-vs-rows at real-run; the silent-extra
    tolerance would hide spec authoring errors — the Rust twin refuses)."""
    if not base:
        raise ValueError('BASE_EMPTY')
    if len(direction) != len(base):
        raise ValueError('ROWS_MISMATCH: direction %d != tensor rows %d'
                         % (len(direction), len(base)))
    cols = len(base[0])
    for j in columns:
        if not (0 <= j < cols):
            raise ValueError('COLUMN_OUT_OF_RANGE: %d (cols %d)' % (j, cols))
    colset = set(columns)
    out = []
    for r, row in enumerate(base):
        new_row = list(row)
        for j in colset:
            new_row[j] = row[j] + scale * direction[r]
        out.append(new_row)
    return out


def spec_digest(merged, rows, cols):
    """sha256 of the canonical merged tensor (sorted-key JSON of rounded
    values, row-major) — the coarse parity anchor."""
    canon = json.dumps({'rows': rows, 'cols': cols,
                        'values': [round(v, 10) for v in
                                   (x for row in merged for x in row)]},
                       sort_keys=True, separators=(',', ':'))
    return hashlib.sha256(canon.encode('utf-8')).hexdigest()


def f32_parity_digest(merged, rows, cols):
    """EXACT f32 parity anchor (PREREG-SPEED L4 gate): every value is
    rounded through binary32 (struct pack/unpack) before digesting, so the
    python reference and the Rust twin (which computes in f32) compare
    byte-for-byte. A %.6f digest cannot serve here — f32 ulp exceeds 1e-6
    for weight magnitudes >= ~8."""
    import struct
    packed = b''.join(
        struct.pack('<f', x) for row in merged for x in row)
    canon = struct.pack('<QQ', rows, cols) + packed
    return hashlib.sha256(canon).hexdigest()


if __name__ == '__main__':
    print('delta_merge: pure python reference (see test_delta_merge.py)')
