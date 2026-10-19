"""Pack-at-birth: a nursery checkpoint becomes a weights-splat at birth.

Consumer #5 of the codemap fact-store segment pattern (contract shared with
bench/stage1_paged_moe/segment_store.py, consumer #4, and the in-crate Rust
reader native/mlx_native/src/nursery.rs): content-addressed packed segments,
offset-indexed point reads, sha256 digest verification on load. The model
ships AS a weights-splat from day one — every tensor (not just experts) is
addressable in the store, and each carries a semantic role so the runtime
and GATE-4 can reason about payload without knowing model families.

Store layout (contract "nursery.weights-splat.v1"):
  <store>/manifest.json
  <store>/seg_<key>.bin   raw tensor bytes back to back at recorded offsets

manifest = {
  "contract": "nursery.weights-splat.v1",
  "generator": "tool/nursery/pack_at_birth.py",
  "source": {"dir": ..., "files": [...], "config": {...}},
  "quantization": {"bits": b, "group_size": g} | null,
  "segments": {key: {"file": "seg_<key>.bin", "digest": <sha256hex>,
                     "size": n, "tensors": {name: {"offset", "nbytes",
                     "shape", "dtype", "role"}}}}}

No timestamp inside the manifest: re-packing a byte-identical checkpoint
reproduces the manifest and every segment digest byte-for-byte, so a store
is comparable by sha256(manifest.json) alone.

Roles (name-based rules, overridable): expert | router | embed | head |
norm | dense. Routers are expected fp32 (TRAIN-GATES / PORTING-MOE law);
the packer records their dtype so the law is checkable, not assumed.

Usage:
  python pack_at_birth.py --checkpoint DIR --store DIR
        [--experts-per-segment 8] [--role-override name_substring=role ...]

Resumable: a segment whose file digest matches the manifest is skipped.
"""

import argparse
import hashlib
import json
import os
import re
import sys

try:
    import ml_dtypes  # noqa: F401  (registers the numpy 'bfloat16' dtype)
except ImportError:
    ml_dtypes = None

CONTRACT = "nursery.weights-splat.v1"
GENERATOR = "tool/nursery/pack_at_birth.py"

_ROLE_RULES = [
    ("expert", re.compile(r"\.mlp\.experts\.")),
    ("expert", re.compile(r"switch_mlp")),
    ("router", re.compile(r"\.mlp\.gate\.")),
    ("router", re.compile(r"router|routing")),
    ("head", re.compile(r"lm_head")),
    ("embed", re.compile(r"embed_tokens|embeddings|\.wte$")),
    ("norm", re.compile(r"norm", re.I)),
]


def classify_role(name, overrides):
    for needle, role in overrides.items():
        if needle in name:
            return role
    for role, pattern in _ROLE_RULES:
        if pattern.search(name):
            return role
    return "dense"


def _n_experts(config):
    for key in ("num_experts", "num_local_experts", "n_routed_experts"):
        if config.get(key):
            return int(config[key])
    return None


_LAYER_RE = re.compile(r"model\.layers\.(\d+)\.")


def _tensor_layer(name):
    m = _LAYER_RE.search(name)
    return int(m.group(1)) if m else None


def _segment_key(role, name, layer, bucket):
    if role == "expert" and layer is not None:
        return f"L{layer:03d}_B{bucket:03d}"
    return "T_" + re.sub(r"[^A-Za-z0-9]", "_", name)


def _maybe_quantize(name, arr, quantize_experts):
    """Expert float weights -> (packed u32 weight, f16 scales, f16 biases)
    via mx.quantize — the canonical packing (mx's own affine convention,
    including its negative-scale order; hand-rolling nibble order is how
    byte-convention bugs are born). Scales/biases are cast to f16, the
    store convention the Rust reader and stage1 both use. Returns a list
    of (name, array) — one entry for pass-through, three for quantized.
    quantize_roundtrip_check.py validates what actually ships."""
    if quantize_experts is None:
        return [(name, arr)]
    bits, group = quantize_experts
    import mlx.core as mx
    if not (name.endswith(".weight") and arr.ndim == 2
            and arr.shape[1] % group == 0
            and str(arr.dtype) in ("float32", "float16")):
        raise ValueError(
            f"--quantize-experts: {name} shape {list(arr.shape)} dtype "
            f"{arr.dtype} is not quantizable (2-D float weight whose last "
            f"dim divides group {group})")
    import numpy as np
    w = mx.array(np.asarray(arr, dtype=np.float32))
    wq, scales, biases = mx.quantize(w, group_size=group, bits=bits)
    return [(name, np.asarray(wq)),
            (name + ".scales", np.asarray(scales).astype(np.float16)),
            (name + ".biases", np.asarray(biases).astype(np.float16))]


def _iter_checkpoint_tensors(model_dir, files):
    """Yield (canonical_name, np_array) for every tensor, flattening stacked
    switch_mlp expert tensors into per-expert canonical names. numpy and
    safetensors are imported lazily so payload_stats() (GATE-4's math)
    stays dependency-free."""
    import numpy as np
    from safetensors import safe_open

    handles = [safe_open(os.path.join(model_dir, f), framework="np") for f in files]
    where = {}
    for i, h in enumerate(handles):
        for k in h.keys():
            where[k] = i
    config_path = os.path.join(model_dir, "config.json")
    config = json.load(open(config_path)) if os.path.exists(config_path) else {}
    n_exp = _n_experts(config)
    for name in sorted(where):
        arr = np.ascontiguousarray(handles[where[name]].get_tensor(name))
        m = re.search(r"\.mlp\.switch_mlp\.(gate_proj|up_proj|down_proj)\.(weight|scales|biases)$", name)
        if m:
            layer = _tensor_layer(name)
            if n_exp is None or arr.shape[0] != n_exp:
                raise ValueError(
                    f"{name}: stacked expert tensor has shape {arr.shape} but"
                    f" config n_experts={n_exp} — cannot split honestly")
            base = re.sub(r"\.mlp\.switch_mlp\.", ".mlp.experts.", name)
            for e in range(n_exp):
                yield base.replace(".mlp.experts.", f".mlp.experts.{e}."), np.ascontiguousarray(arr[e])
            continue
        m2 = re.search(r"\.mlp\.experts\.(\d+)\.", name)
        if m2:
            yield name, arr
            continue
        yield name, arr


def pack_checkpoint(checkpoint_dir, store_dir, experts_per_segment=8,
                    role_overrides=None, quantize_experts=None):
    """Pack every checkpoint tensor into digest-addressed segments.

    quantize_experts=(bits, group_size): affine-quantize EXPERT float
    weights at pack time via mx.quantize (routers stay fp32 BY LAW; embed/
    norms/heads untouched). Sets manifest["quantization"] so the Rust
    runtime can quantized_matmul with the right parameters. Refuses a
    checkpoint whose config already declares quantization (never double-
    quantize silently).

    Resumable; returns (manifest, stats) where stats carries the byte
    histogram GATE-4 reasons from.
    """
    overrides = dict(role_overrides or {})
    os.makedirs(store_dir, exist_ok=True)
    config_path = os.path.join(checkpoint_dir, "config.json")
    config = json.load(open(config_path)) if os.path.exists(config_path) else {}
    quant = config.get("quantization") or None
    if quantize_experts is not None and quant:
        raise ValueError(
            "checkpoint config already declares quantization "
            f"{quant} — refusing to double-quantize")
    if quantize_experts is not None:
        bits, group = quantize_experts
        quant = {"bits": int(bits), "group_size": int(group)}
    files = sorted(
        f for f in os.listdir(checkpoint_dir)
        if f.endswith(".safetensors"))
    if not files:
        raise FileNotFoundError(f"no safetensors shards in {checkpoint_dir}")

    manifest_path = os.path.join(store_dir, "manifest.json")
    manifest = {
        "contract": CONTRACT,
        "generator": GENERATOR,
        "source": {"dir": os.path.abspath(checkpoint_dir), "files": files,
                   "config": config},
        "quantization": quant,
        "segments": {},
    }
    if os.path.exists(manifest_path):
        old = json.load(open(manifest_path))
        if old.get("contract") == CONTRACT:
            old_q = old.get("quantization")
            new_q = manifest["quantization"]
            if old["segments"] and old_q != new_q:
                raise SystemExit(
                    f"store {store_dir} was packed with quantization "
                    f"{old_q} but this run says {new_q} — resumable skip "
                    "would mix conventions; pack into a fresh store dir "
                    "or pass the same --quantize-experts flags")
            manifest["segments"] = old["segments"]

    # Group expert tensors by (layer, bucket) first so one segment write
    # covers experts_per_segment experts, like the stage1 store.
    role_of = {}
    buckets = {}   # (layer, bucket) -> [(name, arr)]
    loose = []     # (name, arr)
    for name, arr in _iter_checkpoint_tensors(checkpoint_dir, files):
        role = classify_role(name, overrides)
        role_of[name] = role
        layer = _tensor_layer(name)
        m = re.search(r"\.mlp\.experts\.(\d+)\.", name)
        if role == "expert" and m and layer is not None:
            e = int(m.group(1))
            buckets.setdefault((layer, (e // experts_per_segment) * experts_per_segment), []).append((e, name, arr))
        else:
            loose.append((name, arr))

    total = len(buckets) + len(loose)
    done = 0
    for (layer, bucket), members in sorted(buckets.items()):
        key = _segment_key("expert", "", layer, bucket)
        fname = f"seg_{key}.bin"
        if _segment_is_packed(manifest, store_dir, key):
            done += 1
            continue
        tensors, offset, blobs = {}, 0, []
        for e, name, arr in sorted(members):
            for qname, qarr in _maybe_quantize(name, arr, quantize_experts):
                raw = qarr.tobytes()
                tensors[qname] = {"offset": offset, "nbytes": len(raw),
                                  "shape": list(qarr.shape),
                                  "dtype": str(qarr.dtype),
                                  "role": "expert"}
                blobs.append(raw)
                offset += len(raw)
        _write_segment(manifest, store_dir, key, fname, tensors, blobs)
        done += 1
        if done % 16 == 0:
            _flush(manifest_path, manifest, done, total)

    for name, arr in sorted(loose):
        key = _segment_key(role_of[name], name, None, 0)
        fname = f"seg_{key}.bin"
        if _segment_is_packed(manifest, store_dir, key):
            done += 1
            continue
        raw = arr.tobytes()
        tensors = {name: {"offset": 0, "nbytes": len(raw),
                          "shape": list(arr.shape), "dtype": str(arr.dtype),
                          "role": role_of[name]}}
        _write_segment(manifest, store_dir, key, fname, tensors, [raw])
        done += 1

    _flush(manifest_path, manifest, done, total)
    stats = payload_stats(manifest)
    return manifest, stats


def _segment_is_packed(manifest, store_dir, key):
    if key not in manifest["segments"]:
        return False
    path = os.path.join(store_dir, manifest["segments"][key]["file"])
    if not os.path.exists(path):
        return False
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest() == \
            manifest["segments"][key]["digest"]


def _write_segment(manifest, store_dir, key, fname, tensors, blobs):
    data = b"".join(blobs)
    digest = hashlib.sha256(data).hexdigest()
    with open(os.path.join(store_dir, fname), "wb") as fh:
        fh.write(data)
    manifest["segments"][key] = {"file": fname, "digest": digest,
                                 "size": len(data), "tensors": tensors}


def _flush(manifest_path, manifest, done, total):
    with open(manifest_path, "w") as fh:
        json.dump(manifest, fh)
    print(f"  packed {done}/{total} segments", flush=True)


def payload_stats(manifest):
    """GATE-4's shape math, shared with tool/nursery/gates/gate4_payload.py."""
    role_bytes = {}
    expert_by_layer = {}
    for seg in manifest["segments"].values():
        for name, t in seg["tensors"].items():
            role_bytes[t["role"]] = role_bytes.get(t["role"], 0) + t["nbytes"]
            if t["role"] == "expert":
                m = re.search(r"\.mlp\.experts\.(\d+)\.", name)
                layer = _tensor_layer(name)
                if m and layer is not None:
                    expert_by_layer.setdefault(layer, {}).setdefault(int(m.group(1)), 0)
                    expert_by_layer[layer][int(m.group(1))] += t["nbytes"]
    config = manifest["source"]["config"]
    topk = int(config.get("num_experts_per_tok", config.get("num_experts_used_per_tok", 2)))
    per_layer = {layer: sum(per_expert.values()) / len(per_expert)
                 for layer, per_expert in expert_by_layer.items()}
    bytes_per_token = sum(topk * mean_bytes for mean_bytes in per_layer.values())
    total_bytes = sum(seg["size"] for seg in manifest["segments"].values())
    router_dtypes = sorted({t["dtype"] for seg in manifest["segments"].values()
                            for t in seg["tensors"].values() if t["role"] == "router"})
    return {
        "total_bytes": total_bytes,
        "role_bytes": role_bytes,
        "expert_payload_bytes": role_bytes.get("expert", 0),
        "moe_layers": sorted(per_layer),
        "experts_per_tok": topk,
        "bytes_per_token": bytes_per_token,
        "router_dtypes": router_dtypes,
    }


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--checkpoint", required=True)
    ap.add_argument("--store", required=True)
    ap.add_argument("--experts-per-segment", type=int, default=8)
    ap.add_argument("--role-override", action="append", default=[],
                    help="name_substring=role (expert|router|embed|head|norm|dense)")
    ap.add_argument("--quantize-experts-bits", type=int,
                    help="quantize expert weights at pack time (2/3/4/6/8); "
                         "requires --quantize-experts-group")
    ap.add_argument("--quantize-experts-group", type=int,
                    help="quantization group size (e.g. 64); requires "
                         "--quantize-experts-bits")
    args = ap.parse_args(argv)
    overrides = {}
    for item in args.role_override:
        needle, _, role = item.partition("=")
        if not role or role not in {"expert", "router", "embed", "head", "norm", "dense"}:
            raise SystemExit(f"--role-override must be substring=role, got {item!r}")
        overrides[needle] = role
    quantize_experts = None
    if (args.quantize_experts_bits is None) != \
            (args.quantize_experts_group is None):
        ap.error("--quantize-experts-bits and --quantize-experts-group "
                 "must be given together")
    if args.quantize_experts_bits is not None:
        if args.quantize_experts_bits not in (2, 3, 4, 6, 8):
            ap.error("bits must be one of 2/3/4/6/8 (mlx affine)")
        quantize_experts = (args.quantize_experts_bits,
                            args.quantize_experts_group)
    manifest, stats = pack_checkpoint(args.checkpoint, args.store,
                                      args.experts_per_segment, overrides,
                                      quantize_experts)
    print(json.dumps(stats, indent=2))
    manifest_path = os.path.join(args.store, "manifest.json")
    print(f"store: {args.store} ({len(manifest['segments'])} segments)")
    print(f"manifest sha256: {hashlib.sha256(open(manifest_path, 'rb').read()).hexdigest()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
