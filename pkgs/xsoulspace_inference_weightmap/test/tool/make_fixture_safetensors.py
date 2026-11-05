#!/usr/bin/env python3 -I
"""make_fixture_safetensors.py — build two tiny 2-shard safetensors checkpoints.

Usage: make_fixture_safetensors.py <outA> <outB>

Writes F32 fixtures with hand-rolled safetensors headers (8-byte LE
header-length prefix + JSON header), an model.safetensors.index.json per dir,
and exactly ONE tensor ("mlp.down_proj.weight" in shard 2) differing between
A and B in exactly N known elements. N is printed to stdout as:

    diffing_elements=N

No third-party deps. Errors are NAMED on stderr with exit 2 (USAGE_ERROR,
WRITE_ERROR). Fixture values are deterministic — no RNG — so receipts and
digests are reproducible across runs.
"""

from __future__ import annotations

import json
import os
import struct
import sys

# The one differing tensor and the exact element indices that differ.
DIFF_TENSOR = "mlp.down_proj.weight"
DIFF_SHAPE = (8, 16)  # 128 elements
DIFF_INDICES = (0, 5, 17, 42, 63, 99, 127)  # N = 7 known elements

SHARD1 = "model-00001-of-00002.safetensors"
SHARD2 = "model-00002-of-00002.safetensors"
INDEX = "model.safetensors.index.json"


def _fail(name: str, detail: str) -> "NoReturn":  # type: ignore[name-defined]
    print(f"{name}: {detail}", file=sys.stderr)
    raise SystemExit(2)


def _tensor_values(name: str, numel: int) -> list[float]:
    """Deterministic base values: v[i] = i * 0.25 (exact in F32)."""
    return [i * 0.25 for i in range(numel)]


def _encode_shard(tensors: dict[str, tuple[tuple[int, ...], list[float]]]) -> bytes:
    """Encode {name: (shape, f32 values)} into a safetensors file blob."""
    header: dict[str, object] = {"__metadata__": {"format": "pt", "made_by": "make_fixture_safetensors"}}
    data = bytearray()
    for name in sorted(tensors):
        shape, values = tensors[name]
        begin = len(data)
        for v in values:
            data += struct.pack("<f", v)
        end = len(data)
        header[name] = {"dtype": "F32", "shape": list(shape), "data_offsets": [begin, end]}
    header_bytes = json.dumps(header, separators=(",", ":")).encode("utf-8")
    return struct.pack("<Q", len(header_bytes)) + header_bytes + bytes(data)


def _write(path: str, blob: bytes) -> None:
    try:
        with open(path, "wb") as f:
            f.write(blob)
    except OSError as exc:
        _fail("WRITE_ERROR", f"{path}: {exc}")


def _build_dir(root: str, *, edited: bool) -> None:
    try:
        os.makedirs(root, exist_ok=True)
    except OSError as exc:
        _fail("WRITE_ERROR", f"{root}: {exc}")

    # Shard 1: two identical-in-both tensors.
    shard1_tensors = {
        "alpha.weight": ((4, 4), _tensor_values("alpha.weight", 16)),
        "beta.weight": ((8,), _tensor_values("beta.weight", 8)),
    }

    # Shard 2: the diff tensor plus one more identical tensor.
    down = _tensor_values(DIFF_TENSOR, DIFF_SHAPE[0] * DIFF_SHAPE[1])
    if edited:
        # Adding 1.0 to a small exact float always changes the F32 bit
        # pattern, so exactly len(DIFF_INDICES) elements differ.
        for idx in DIFF_INDICES:
            down[idx] = down[idx] + 1.0
    shard2_tensors = {
        DIFF_TENSOR: (DIFF_SHAPE, down),
        "gamma.bias": ((4,), _tensor_values("gamma.bias", 4)),
    }

    _write(os.path.join(root, SHARD1), _encode_shard(shard1_tensors))
    _write(os.path.join(root, SHARD2), _encode_shard(shard2_tensors))

    weight_map = {
        "alpha.weight": SHARD1,
        "beta.weight": SHARD1,
        DIFF_TENSOR: SHARD2,
        "gamma.bias": SHARD2,
    }
    def _numel(shape: tuple[int, ...]) -> int:
        total = 1
        for dim in shape:
            total *= dim
        return total

    total_size = 4 * (
        sum(_numel(s) for s, _ in shard1_tensors.values())
        + sum(_numel(s) for s, _ in shard2_tensors.values())
    )
    index = {
        "metadata": {"total_size": total_size},
        "weight_map": weight_map,
    }
    _write(os.path.join(root, INDEX), json.dumps(index, indent=2).encode("utf-8"))


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        _fail("USAGE_ERROR", "usage: make_fixture_safetensors.py <outA> <outB>")
    out_a, out_b = argv[1], argv[2]
    _build_dir(out_a, edited=False)
    _build_dir(out_b, edited=True)
    n = len(DIFF_INDICES)
    print(f"diffing_elements={n}")
    print(f"fixture_a={out_a}")
    print(f"fixture_b={out_b}")
    print(f"diff_tensor={DIFF_TENSOR}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
