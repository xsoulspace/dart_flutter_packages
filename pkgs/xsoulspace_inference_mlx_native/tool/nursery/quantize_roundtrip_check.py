"""Round-trip check for quantize-at-birth (pack_at_birth --quantize-experts).

Loads a quantized store and, for every expert weight with .scales/.biases,
dequantizes via mx.dequantize (the canonical reader) and compares against
the ORIGINAL checkpoint tensor the store was packed from.

Pass bound: 1.05 x max|scale| — one affine quanta. Calibrated 2026-10-18:
mx.quantize's own round-trip measures up to ~0.95 quanta on random-init
expert weights (boundary placement inside the canonical implementation —
NOT the f16 cast: f32-scales and f16-scales dequantize identically, probe
on layers.3.E7.gate_proj). A nibble-order, group-order, or sign-convention
bug lands MANY quanta off (typically 4-8x scale), so the bound separates
calibration noise from real convention failure by an order of magnitude.
Routers are checked to still be fp32 (the PORTING-MOE law).

Usage:
  ~/.venvs/mlx-ref/bin/python tool/nursery/quantize_roundtrip_check.py \
      --checkpoint <ckpt-dir> --store <store-dir>
Exit 0 = every expert weight round-trips within bound; nonzero = fail.
"""

import argparse
import json
import os
import sys

import numpy as np
from safetensors import safe_open

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)


def main(argv=None):
    import mlx.core as mx

    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--checkpoint", required=True)
    ap.add_argument("--store", required=True)
    args = ap.parse_args(argv)

    manifest = json.load(open(os.path.join(args.store, "manifest.json")))
    quant = manifest.get("quantization")
    if not quant:
        raise SystemExit("store manifest carries no quantization block — "
                         "nothing to check")
    bits, group = quant["bits"], quant["group_size"]

    originals = {}
    files = sorted(f for f in os.listdir(args.checkpoint)
                   if f.endswith(".safetensors"))
    for f in files:
        with safe_open(os.path.join(args.checkpoint, f), framework="np") as h:
            for k in h.keys():
                originals[k] = np.ascontiguousarray(h.get_tensor(k))

    # Re-read the store through its own offsets (the same bytes the Rust
    # reader would see).
    stored = {}
    for key, seg in manifest["segments"].items():
        with open(os.path.join(args.store, seg["file"]), "rb") as fh:
            data = fh.read()
        for name, t in seg["tensors"].items():
            stored[name] = np.frombuffer(
                data[t["offset"]:t["offset"] + t["nbytes"]],
                dtype=t["dtype"]).reshape(t["shape"])

    checked, failed, max_observed = 0, 0, 0.0
    routers_non_f32 = []
    for name in sorted(stored):
        role = next(seg["tensors"][name]["role"]
                    for seg in manifest["segments"].values()
                    if name in seg["tensors"])
        if role == "router" and stored[name].dtype != np.float32:
            routers_non_f32.append(name)
        if not name.endswith(".weight") or f"{name}.scales" not in stored:
            continue
        orig = originals[name].astype(np.float32)
        w = mx.array(stored[name])
        s = mx.array(stored[f"{name}.scales"].astype(np.float32))
        b = mx.array(stored[f"{name}.biases"].astype(np.float32))
        deq = np.asarray(mx.dequantize(w, s, b, group_size=group, bits=bits))
        bound = 1.05 * float(np.abs(np.asarray(s)).max())
        err = float(np.abs(deq - orig).max())
        max_observed = max(max_observed, err)
        ok = err <= bound
        checked += 1
        if not ok:
            failed += 1
            print(f"FAIL {name}: err {err:.4f} > bound {bound:.4f}")

    if routers_non_f32:
        failed += 1
        print(f"FAIL router law: non-fp32 routers {routers_non_f32[:4]}")
    if checked == 0:
        raise SystemExit("no quantized expert weights found — wrong store?")
    print(f"checked {checked} quantized expert weights; "
          f"max err {max_observed:.4f}; routers fp32: {not routers_non_f32}")
    print("ROUND-TRIP " + ("PASS" if failed == 0 else "FAIL"))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
