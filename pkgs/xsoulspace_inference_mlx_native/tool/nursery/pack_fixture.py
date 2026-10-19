"""Generate the Rust nursery-reader parity fixture (cross-language oracle).

Builds a tiny synthetic checkpoint (f32/f16/bf16/u32, a quantized-shape
expert, an fp32 router — the PORTING-MOE law made concrete), packs it with
pack_at_birth.py, and writes:

  native/mlx_native/testdata/nursery/source_ckpt/   the source checkpoint
  native/mlx_native/testdata/nursery/store/          the packed store
  native/mlx_native/testdata/nursery/expectations.json

expectations.json pins, per tensor: sha256 of the packed bytes, shape,
dtype, role — plus exact f32 samples for the dtype-conversion paths. The
Rust test (tests/nursery_store_parity.rs) verifies every pinned digest, so
"a skipped check cannot hide" (SPEC-PAGED-EXPERT-STORE.md contract point 4).
The store carries no timestamp: re-running this script on an unchanged
numpy/safetensors reproduces byte-identical segments and manifest.

Values are fully deterministic (arange/bit patterns — no RNG). Synthetic
only: shapes are toys, nothing here is private.

Run: ~/.venvs/mlx-ref/bin/python tool/nursery/pack_fixture.py
     (needs numpy, safetensors, ml_dtypes)
"""

import hashlib
import json
import os
import platform
import subprocess
import sys

import numpy as np
import safetensors
import safetensors.numpy

HERE = os.path.dirname(os.path.abspath(__file__))
PKG_ROOT = os.path.dirname(os.path.dirname(HERE))          # package root
TESTDATA = os.path.join(PKG_ROOT, "native", "mlx_native", "testdata", "nursery")

H, V, E, LAYERS, INTER = 32, 64, 4, 2, 64
GROUP, BITS = 64, 4


def build_checkpoint(ckpt_dir):
    os.makedirs(ckpt_dir, exist_ok=True)
    tensors = {}
    tensors["model.embed_tokens.weight"] = (
        (np.arange(V * H) % 97) / 4.0).astype(np.float32).reshape(V, H)
    tensors["model.norm.weight"] = ((np.arange(H) % 8) + 1).astype(np.float16)
    tensors["model.lm_head.weight"] = (
        (np.arange(V * H) % 53) / 8.0).astype(np.float32).reshape(V, H)
    for l in range(LAYERS):
        tensors[f"model.layers.{l}.input_layernorm.weight"] = \
            ((np.arange(H) % 6) + 1).astype(np.float16)
        # The router is fp32 BY LAW (PORTING-MOE.md) — pinned here.
        tensors[f"model.layers.{l}.mlp.gate.weight"] = \
            ((np.arange(E * H) % 41) / 16.0).astype(np.float32).reshape(E, H)
        for e in range(E):
            if l == 0 and e == 1:
                # Quantized-shape expert gate_proj: u32 packed weights plus
                # f16 scales/biases at group 64 (== the whole input dim).
                packed = np.array(
                    [(i * 2654435761) % (2 ** 32) for i in range(INTER * 4)],
                    dtype=np.uint32).reshape(INTER, H // 8)
                tensors[f"model.layers.{l}.mlp.experts.{e}.gate_proj.weight"] = packed
                tensors[f"model.layers.{l}.mlp.experts.{e}.gate_proj.scales"] = \
                    ((np.arange(INTER) % 5) + 1).astype(np.float16).reshape(INTER, 1)
                tensors[f"model.layers.{l}.mlp.experts.{e}.gate_proj.biases"] = \
                    ((np.arange(INTER) % 3) - 1).astype(np.float16).reshape(INTER, 1)
                continue
            if l == 1 and e == 2:
                # The bf16 path: a real packed bf16 tensor, exercised
                # end-to-end through the store into the Rust reader.
                tensors[f"model.layers.{l}.mlp.experts.{e}.down_proj.weight"] = \
                    ((np.arange(H * INTER) % 11) - 5).astype(np.float16).astype(
                        ml_dtypes_bfloat16()).reshape(H, INTER)
                continue
            tensors[f"model.layers.{l}.mlp.experts.{e}.gate_proj.weight"] = \
                ((np.arange(INTER * H) % 13) - 6).astype(np.float16).reshape(INTER, H)
            tensors[f"model.layers.{l}.mlp.experts.{e}.up_proj.weight"] = \
                ((np.arange(INTER * H) % 17) - 8).astype(np.float16).reshape(INTER, H)
            tensors[f"model.layers.{l}.mlp.experts.{e}.down_proj.weight"] = \
                ((np.arange(H * INTER) % 19) - 9).astype(np.float16).reshape(H, INTER)
    safetensors.numpy.save_file(
        tensors, os.path.join(ckpt_dir, "model.safetensors"))
    config = {
        "model_type": "nursery_fixture",
        "num_hidden_layers": LAYERS,
        "hidden_size": H,
        "vocab_size": V,
        "num_experts": E,
        "num_experts_per_tok": 2,
        "moe_intermediate_size": INTER,
        "quantization": {"bits": BITS, "group_size": GROUP},
    }
    with open(os.path.join(ckpt_dir, "config.json"), "w") as fh:
        json.dump(config, fh)
    return tensors


def ml_dtypes_bfloat16():
    import ml_dtypes
    return ml_dtypes.bfloat16


def f32_of_bf16_u16(u16_rows):
    """The exact conversion the Rust reader implements: bf16 is the top
    half of an f32."""
    u32 = u16_rows.astype(np.uint32) << np.uint32(16)
    return u32.view(np.float32) if u32.dtype.byteorder in ("<", "=") else \
        u32.byteswap().view(np.float32)


def tensor_bytes_from_store(manifest, store_dir):
    """name -> raw bytes, read back through the store's own offsets."""
    out = {}
    for key, seg in manifest["segments"].items():
        with open(os.path.join(store_dir, seg["file"]), "rb") as fh:
            data = fh.read()
        assert hashlib.sha256(data).hexdigest() == seg["digest"], key
        for name, t in seg["tensors"].items():
            out[name] = data[t["offset"]:t["offset"] + t["nbytes"]]
    return out


def main() -> int:
    sys.path.insert(0, HERE)
    import pack_at_birth

    ckpt_dir = os.path.join(TESTDATA, "source_ckpt")
    store_dir = os.path.join(TESTDATA, "store")
    tensors = build_checkpoint(ckpt_dir)

    manifest, stats = pack_at_birth.pack_checkpoint(ckpt_dir, store_dir)

    # Store determinism: repack onto the finished store must be a no-op with
    # a byte-identical manifest (no timestamps inside the store).
    manifest_before = open(os.path.join(store_dir, "manifest.json"), "rb").read()
    pack_at_birth.pack_checkpoint(ckpt_dir, store_dir)
    manifest_after = open(os.path.join(store_dir, "manifest.json"), "rb").read()
    assert manifest_before == manifest_after, "repack was not a no-op"

    # The router law is checkable at birth.
    assert stats["router_dtypes"] == ["float32"], \
        f"router must be fp32, got {stats['router_dtypes']}"

    raw = tensor_bytes_from_store(manifest, store_dir)

    expectations = {
        "contract": pack_at_birth.CONTRACT,
        "generator": "tool/nursery/pack_fixture.py",
        "command": " ".join(["~/.venvs/mlx-ref/bin/python"] + sys.argv),
        "generated_utc": subprocess.run(
            ["date", "-u", "+%Y-%m-%dT%H:%M:%SZ"], capture_output=True,
            text=True).stdout.strip(),
        "provenance": {
            "python": platform.python_version(),
            "numpy": np.__version__,
            "safetensors": safetensors.__version__,
            "ml_dtypes": sys.modules["ml_dtypes"].__version__
            if "ml_dtypes" in sys.modules else "absent",
            "platform": platform.platform(),
        },
        "segments": len(manifest["segments"]),
        "tensors": {
            name: {
                "sha256": hashlib.sha256(raw[name]).hexdigest(),
                "shape": seg_t["shape"],
                "dtype": seg_t["dtype"],
                "role": seg_t["role"],
            }
            for seg in manifest["segments"].values()
            for name, seg_t in seg["tensors"].items()
        },
        "f32_samples": {},
    }

    embed = tensors["model.embed_tokens.weight"].reshape(-1)
    expectations["f32_samples"]["model.embed_tokens.weight"] = [
        float(x) for x in embed[:8]]
    expectations["f32_samples"]["model.norm.weight"] = [
        float(x) for x in tensors["model.norm.weight"].astype(np.float32)]
    bf16 = tensors["model.layers.1.mlp.experts.2.down_proj.weight"]
    via_shift = f32_of_bf16_u16(np.frombuffer(bf16.tobytes(), dtype=np.uint16))
    via_ml_dtypes = bf16.astype(np.float32).reshape(-1)
    assert np.array_equal(via_shift, via_ml_dtypes), \
        "bf16->f32: shift conversion and ml_dtypes disagree"
    expectations["f32_samples"]["model.layers.1.mlp.experts.2.down_proj.weight"] = \
        [float(x) for x in via_ml_dtypes[:8]]
    u32 = tensors["model.layers.0.mlp.experts.1.gate_proj.weight"].reshape(-1)
    expectations["f32_samples"]["model.layers.0.mlp.experts.1.gate_proj.weight"] = \
        [float(x) for x in u32[:4].astype(np.float32)]
    router = tensors["model.layers.0.mlp.gate.weight"].reshape(-1)
    expectations["f32_samples"]["model.layers.0.mlp.gate.weight"] = [
        float(x) for x in router[:8]]

    out_path = os.path.join(TESTDATA, "expectations.json")
    with open(out_path, "w") as fh:
        json.dump(expectations, fh, indent=2, sort_keys=True)

    print(f"checkpoint: {ckpt_dir} ({len(tensors)} tensors)")
    print(f"store:      {store_dir} ({len(manifest['segments'])} segments, "
          f"{stats['total_bytes']} bytes)")
    print(f"manifest sha256: "
          f"{hashlib.sha256(manifest_after).hexdigest()}")
    print(f"expectations: {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
