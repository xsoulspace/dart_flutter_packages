#!/usr/bin/env python3
"""make_mirror.py - A3 mirror builder: base store + sidecar deltas -> mirror.

House law: the BASE store is opened read-only and verified byte-identical
before/after; the mirror lives under $TMPDIR (probe scratch law); durable
evidence is the textual receipt (digests, counts, verdicts).

Merges apply_delta.py sidecars (delta.npz: tensor_name, columns, direction,
scale, rows) into a COPY of the base store, in fp32 then cast back to the
stored dtype (bf16), i.e. W[:, cols] += scale * direction per sidecar.

Verification (all-or-nothing; any failure = named error, mirror refused):
  V1 base store digests identical before vs after (BASE_MUTATED = fatal)
  V2 every UNEDITED tensor byte-identical between base and mirror
     (count must equal total - edited; UNEDITED_TENSOR_DRIFT)
  V3 every edited tensor equals bf16(f32(base) + scale*direction at columns)
     EXACTLY (deterministic rounding; EDIT_VALUE_MISMATCH)
  V4 the differing-element column mask of each edited tensor is a SUBSET of
     the sidecar columns (EDIT_OUTSIDE_COLUMNS); differing-element count and
     absorption count (bf16 round-to-same) recorded

Usage:
  python3 -I make_mirror.py --base <snapshot-dir> --out <mirror-dir> \
      --sidecar <dir-with-delta.npz+receipt.json> [--sidecar <dir2> ...] \
      [--receipt <path>]

Exit codes: 0 ok; 1 named error (stderr 'CODE: detail'):
  MIRROR_EXISTS BASE_MISSING SIDECAR_MISSING SIDECAR_MALFORMED
  TENSOR_MISSING_IN_STORE SHAPE_MISMATCH BASE_MUTATED
  UNEDITED_TENSOR_DRIFT EDIT_VALUE_MISMATCH EDIT_OUTSIDE_COLUMNS
  MLX_UNAVAILABLE OUT_UNWRITABLE
"""

import argparse
import hashlib
import json
import os
import shutil
import sys
from datetime import datetime, timezone

EXIT_OK = 0
EXIT_FAIL = 1


def fail(code, detail):
    print("%s: %s" % (code, detail), file=sys.stderr)
    return EXIT_FAIL


def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 22), b""):
            h.update(chunk)
    return h.hexdigest()


def store_digests(base_dir):
    out = {}
    for name in sorted(os.listdir(base_dir)):
        p = os.path.join(base_dir, name)
        if os.path.isfile(p):
            out[name] = sha256_file(p)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--sidecar", action="append", required=True)
    ap.add_argument("--receipt", default=None)
    args = ap.parse_args()

    try:
        import mlx.core as mx
        import numpy as np
    except ImportError as exc:
        return fail("MLX_UNAVAILABLE", str(exc))

    if not os.path.isdir(args.base):
        return fail("BASE_MISSING", args.base)
    if os.path.exists(args.out):
        return fail("MIRROR_EXISTS", args.out)

    # load sidecars (validated by apply_delta.py already; re-check shape here)
    edits = []
    for sc in args.sidecar:
        npz_path = os.path.join(sc, "delta.npz")
        receipt_path = os.path.join(sc, "receipt.json")
        if not os.path.isfile(npz_path) or not os.path.isfile(receipt_path):
            return fail("SIDECAR_MISSING", sc)
        try:
            z = np.load(npz_path, allow_pickle=False)
            edits.append({
                "tensor": str(z["tensor_name"]),
                "columns": [int(c) for c in z["columns"]],
                "direction": np.asarray(z["direction"], dtype=np.float64),
                "scale": float(z["scale"]),
                "rows": int(z["rows"]),
                "sidecar_dir": os.path.abspath(sc),
                "sidecar_receipt": json.load(open(receipt_path)),
            })
        except (ValueError, KeyError) as exc:
            return fail("SIDECAR_MALFORMED", "%s (%s)" % (sc, exc))

    base_digests_before = store_digests(args.base)
    shard_rel = "model.safetensors"
    base_shard = os.path.join(args.base, shard_rel)
    if not os.path.isfile(base_shard):
        return fail("BASE_MISSING", "no %s in base" % shard_rel)

    t0 = datetime.now(timezone.utc)
    try:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        shutil.copytree(args.base, args.out, symlinks=False)
        # HF content-addressed blobs are READ-ONLY (0444) and copytree
        # preserves modes; the mirror shard must be writable to merge deltas.
        for name in os.listdir(args.out):
            p = os.path.join(args.out, name)
            if os.path.isfile(p) and not os.access(p, os.W_OK):
                os.chmod(p, 0o644)
    except OSError as exc:
        return fail("OUT_UNWRITABLE", str(exc))
    copy_s = (datetime.now(timezone.utc) - t0).total_seconds()

    mirror_shard = os.path.join(args.out, shard_rel)
    try:
        base_arrays = mx.load(base_shard)          # read-only use
        mirror_arrays = mx.load(mirror_shard)
    except Exception as exc:
        return fail("SIDECAR_MALFORMED", "mx.load failed (%s)" % exc)

    edited_names = set()
    edited_receipts = []
    for e in edits:
        name = e["tensor"]
        if name not in mirror_arrays:
            return fail("TENSOR_MISSING_IN_STORE", name)
        w = mirror_arrays[name]
        if w.shape[0] != e["rows"] or len(e["direction"]) != w.shape[0]:
            return fail("SHAPE_MISMATCH",
                        "%s rows=%s direction=%d" % (name, w.shape, e["rows"]))
        cols = mx.array(e["columns"])
        if int(cols.max()) >= w.shape[1]:
            return fail("SHAPE_MISMATCH", "%s columns out of range" % name)
        delta = mx.array(e["direction"], dtype=mx.float32) * float(e["scale"])
        wf = w.astype(mx.float32).at[:, cols].add(delta[:, None])
        mirror_arrays[name] = wf.astype(w.dtype)
        edited_names.add(name)
        edited_receipts.append(e)
    mx.eval([mirror_arrays[n] for n in edited_names])

    try:
        mx.save_safetensors(mirror_shard, mirror_arrays,
                            metadata={"format": "mlx"})
    except Exception as exc:
        return fail("OUT_UNWRITABLE", "save_safetensors (%s)" % exc)

    # ---- verification ----
    base_digests_after = store_digests(args.base)
    if base_digests_before != base_digests_after:
        return fail("BASE_MUTATED",
                    "base store digests changed during mirror build")

    try:
        check_arrays = mx.load(mirror_shard)
    except Exception as exc:
        return fail("SIDECAR_MALFORMED", "mirror reload failed (%s)" % exc)

    unedited_identical = 0
    unedited_drift = []
    for name in base_arrays:
        if name in edited_names:
            continue
        eq = mx.array_equal(base_arrays[name], check_arrays[name])
        mx.eval(eq)
        if bool(eq.item()):
            unedited_identical += 1
        else:
            unedited_drift.append(name)
    if unedited_drift:
        return fail("UNEDITED_TENSOR_DRIFT",
                    "%d tensors differ: %s" % (len(unedited_drift),
                                               unedited_drift[:5]))

    def tensor_digest(arr):
        # value digest: sha256 over the f32-cast little-endian buffer
        # (bf16 has no numpy view; the cast is a deterministic function of
        # the stored values, labelled *_f32_sha256 in receipts)
        a = arr.astype(mx.float32)
        mx.eval(a)
        return sha256_bytes(np.array(a).tobytes())

    edited_rows = []
    for e in edited_receipts:
        name = e["tensor"]
        base_w = base_arrays[name]
        mir_w = check_arrays[name]
        cols = mx.array(e["columns"])
        delta = mx.array(e["direction"], dtype=mx.float32) * float(e["scale"])
        expected = base_w.astype(mx.float32).at[:, cols].add(
            delta[:, None]).astype(base_w.dtype)
        eq = mx.array_equal(expected, mir_w)
        mx.eval(eq)
        if not bool(eq.item()):
            return fail("EDIT_VALUE_MISMATCH", name)
        diff_mask = (base_w.astype(mx.float32) != mir_w.astype(mx.float32))
        diff_mask = diff_mask.astype(mx.uint8)
        mx.eval(diff_mask)
        diff_np = np.array(diff_mask).astype(bool)
        diff_cols = sorted(set(np.nonzero(diff_np)[1].tolist()))
        outside = [c for c in diff_cols if c not in set(e["columns"])]
        if outside:
            return fail("EDIT_OUTSIDE_COLUMNS",
                        "%s columns %s" % (name, outside[:8]))
        edited_rows.append({
            "tensor": name,
            "columns_planted": len(e["columns"]),
            "columns_differing": len(diff_cols),
            "elements_differing": int(diff_np.sum()),
            "elements_absorbed_by_bf16":
                len(e["columns"]) * int(base_w.shape[0]) - int(diff_np.sum()),
            "scale": e["scale"],
            "direction_sha256": sha256_bytes(
                np.asarray(e["direction"], dtype=np.float64).tobytes()),
            "base_tensor_f32_sha256": tensor_digest(base_w),
            "mirror_tensor_f32_sha256": tensor_digest(mir_w),
            "sidecar_receipt_spec_digest":
                e["sidecar_receipt"].get("spec_digest"),
        })

    receipt = {
        "tool": "make_mirror.py",
        "created_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "base_dir": os.path.abspath(args.base),
        "mirror_dir": os.path.abspath(args.out),
        "base_read_only": True,
        "base_unchanged": True,
        "base_file_digests": base_digests_after,
        "mirror_shard_sha256": sha256_file(mirror_shard),
        "tensors_total": len(base_arrays),
        "unedited_identical": unedited_identical,
        "edited": edited_rows,
        "copy_seconds": round(copy_s, 1),
        "verdict": "MIRROR_OK",
    }
    receipt_path = args.receipt or os.path.join(args.out, "_mirror_receipt.json")
    try:
        os.makedirs(os.path.dirname(os.path.abspath(receipt_path)), exist_ok=True)
        with open(receipt_path, "w", encoding="utf-8") as fh:
            json.dump(receipt, fh, indent=1)
    except OSError as exc:
        return fail("OUT_UNWRITABLE", str(exc))
    print("MIRROR_OK %s (edited %d tensors, unedited identical %d/%d)"
          % (args.out, len(edited_rows), unedited_identical,
             len(base_arrays) - len(edited_rows)))
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
