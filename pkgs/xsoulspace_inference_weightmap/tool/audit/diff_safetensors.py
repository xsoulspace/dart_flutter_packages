#!/usr/bin/env python3 -I
"""diff_safetensors.py — mechanical edit audit of two safetensors checkpoints.

PREREG-A arm A1 tooling. Streaming tensor diff of two checkpoint dirs:
compares tensor inventory (names, shapes, dtypes) and, per tensor, the COUNT
of differing elements (raw bit-pattern comparison; F16/BF16 compare on their
16-bit patterns, F32 on its 32-bit pattern — byte-identity semantics, never
numeric tolerance, so NaN payloads and denormals are exact).

Usage:
    diff_safetensors.py <dirA> <dirB> [--receipt OUT.jsonl]

Shard discovery per dir: model.safetensors.index.json weight_map when
present, else every *.safetensors in the dir. numpy is used only when
importable (fast path); otherwise a pure-python mmap/memoryview path with no
third-party deps.

Exit codes:
    0  RESULT_IDENTICAL          no differing tensors, inventory matches
    1  RESULT_DIFF               tensors differ and/or inventory mismatch
                                 (an inventory mismatch is a RESULT, not an
                                 error)
    2  a NAMED error, printed to stderr as `NAME: detail`:
         USAGE_ERROR        bad argv
         DIR_MISSING        dirA/dirB absent or not a directory
         NO_SHARDS          no safetensors shards discoverable in a dir
         MALFORMED_INDEX    model.safetensors.index.json unreadable/invalid
         SHARD_MISSING      shard named by the index is absent on disk
         MALFORMED_HEADER   bad 8-byte prefix, bad JSON header, missing
                            fields, or inconsistent data_offsets
         SHARD_TRUNCATED    tensor data region extends past end of file
         UNSUPPORTED_DTYPE  dtype outside {F32, F16, BF16}
         RECEIPT_WRITE_ERROR cannot write the --receipt path
         INTERNAL_ERROR     unexpected exception (class + message named)

Receipt (jsonl, textual evidence): one line per differing tensor
    {"tensor", "shape", "dtype", "differing_elements", "reason"}
where reason is ELEMENT_DIFF | SHAPE_MISMATCH | DTYPE_MISMATCH | ONLY_IN_A |
ONLY_IN_B (differing_elements is the full element count for ONLY_IN_*, null
for SHAPE/DTYPE mismatches), then one final summary line
    {"tensors_differing", "elements_differing", "inventory_match",
     "files": [{"file", "sha256_a", "sha256_b"}]}
which is also printed to stdout (stdout carries ONLY that line).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import mmap
import os
import struct
import sys
from typing import Any

try:  # fast path, optional
    import numpy as _np
except Exception:  # pragma: no cover - numpy absent is the supported default
    _np = None

# dtype -> element size in bytes. Comparison is restricted to the float
# dtypes the program's checkpoints use; everything else is a NAMED refusal.
ELEMENT_BYTES = {"F32": 4, "F16": 2, "BF16": 2}
# memoryview cast formats (little-endian native) per element size.
_CAST_FMT = {1: "B", 2: "H", 4: "I", 8: "Q"}
_CHUNK = 1 << 22  # 4 MiB comparison chunks


class NamedError(Exception):
    def __init__(self, name: str, detail: str) -> None:
        super().__init__(f"{name}: {detail}")
        self.name = name


def _raise(name: str, detail: str) -> Any:
    raise NamedError(name, detail)


# ---------------------------------------------------------------- shards

def _discover_shards(directory: str, side: str) -> list[str]:
    """Return sorted shard file names for one checkpoint dir."""
    if not os.path.isdir(directory):
        _raise("DIR_MISSING", f"{side} dir not found: {directory}")
    index_path = os.path.join(directory, "model.safetensors.index.json")
    if os.path.isfile(index_path):
        try:
            with open(index_path, "rb") as f:
                index = json.load(f)
            weight_map = index["weight_map"]
            shards = sorted({str(v) for v in weight_map.values()})
        except (OSError, ValueError, KeyError, TypeError) as exc:
            _raise("MALFORMED_INDEX", f"{side} {index_path}: {exc}")
        for shard in shards:
            if not os.path.isfile(os.path.join(directory, shard)):
                _raise("SHARD_MISSING", f"{side} index names absent shard: {shard}")
        if not shards:
            _raise("NO_SHARDS", f"{side} index weight_map is empty: {index_path}")
        return shards
    shards = sorted(
        name for name in os.listdir(directory) if name.endswith(".safetensors")
    )
    if not shards:
        _raise("NO_SHARDS", f"{side} has no index and no *.safetensors: {directory}")
    return shards


class Shard:
    """One parsed safetensors shard: header tensors + mmap of the file."""

    def __init__(self, directory: str, name: str, side: str) -> None:
        self.path = os.path.join(directory, name)
        self.side = side
        try:
            self._fh = open(self.path, "rb")
        except OSError as exc:
            _raise("SHARD_MISSING", f"{side} {self.path}: {exc}")
        size = os.fstat(self._fh.fileno()).st_size
        if size < 8:
            self._close()
            _raise("MALFORMED_HEADER", f"{side} {name}: file shorter than 8-byte prefix")
        prefix = self._fh.read(8)
        (header_len,) = struct.unpack("<Q", prefix)
        if header_len == 0 or header_len > size - 8 or header_len > (1 << 27):
            self._close()
            _raise(
                "MALFORMED_HEADER",
                f"{side} {name}: implausible header length {header_len} (file size {size})",
            )
        raw = self._fh.read(header_len)
        if len(raw) != header_len:
            self._close()
            _raise("MALFORMED_HEADER", f"{side} {name}: header truncated")
        try:
            header = json.loads(raw)
        except ValueError as exc:
            self._close()
            _raise("MALFORMED_HEADER", f"{side} {name}: header is not JSON: {exc}")
        if not isinstance(header, dict):
            self._close()
            _raise("MALFORMED_HEADER", f"{side} {name}: header is not a JSON object")
        self.data_start = 8 + header_len
        self.data_size = size - self.data_start
        self.tensors: dict[str, dict[str, Any]] = {}
        for tensor_name, entry in header.items():
            if tensor_name == "__metadata__":
                continue
            if not isinstance(entry, dict):
                self._close()
                _raise("MALFORMED_HEADER", f"{side} {name}: entry {tensor_name} is not an object")
            dtype = entry.get("dtype")
            shape = entry.get("shape")
            offsets = entry.get("data_offsets")
            if (
                not isinstance(dtype, str)
                or not isinstance(shape, list)
                or not all(isinstance(d, int) and d >= 0 for d in shape)
                or not isinstance(offsets, list)
                or len(offsets) != 2
                or not all(isinstance(o, int) for o in offsets)
            ):
                self._close()
                _raise("MALFORMED_HEADER", f"{side} {name}: bad entry fields for {tensor_name}")
            begin, end = offsets
            if begin < 0 or end < begin or end > self.data_size:
                self._close()
                if end > self.data_size or begin > self.data_size:
                    _raise(
                        "SHARD_TRUNCATED",
                        f"{side} {name}: tensor {tensor_name} data_offsets [{begin},{end}) "
                        f"exceed data region ({self.data_size} bytes)",
                    )
                _raise("MALFORMED_HEADER", f"{side} {name}: bad data_offsets for {tensor_name}")
            if dtype not in ELEMENT_BYTES:
                self._close()
                _raise("UNSUPPORTED_DTYPE", f"{side} {name}: tensor {tensor_name} dtype {dtype}")
            numel = 1
            for dim in shape:
                numel *= dim
            expected = numel * ELEMENT_BYTES[dtype]
            if end - begin != expected:
                self._close()
                _raise(
                    "MALFORMED_HEADER",
                    f"{side} {name}: tensor {tensor_name} byte span {end - begin} != "
                    f"shape {shape} x dtype {dtype} ({expected} bytes)",
                )
            self.tensors[tensor_name] = {
                "dtype": dtype,
                "shape": shape,
                "begin": self.data_start + begin,
                "end": self.data_start + end,
                "numel": numel,
            }
        try:
            self.mm = mmap.mmap(self._fh.fileno(), 0, access=mmap.ACCESS_READ)
        except (OSError, ValueError) as exc:
            self._close()
            _raise("MALFORMED_HEADER", f"{side} {name}: cannot map file: {exc}")

    def _close(self) -> None:
        try:
            self._fh.close()
        except OSError:
            pass

    def close(self) -> None:
        try:
            self.mm.close()
        except (OSError, ValueError, AttributeError):
            pass
        self._close()

    def bytes_equal(self, a_begin: int, a_end: int, other: "Shard", b_begin: int) -> bool:
        """memcmp-style chunked equality of two same-length regions."""
        total = a_end - a_begin
        pos = 0
        while pos < total:
            stop = min(pos + _CHUNK, total)
            if self.mm[a_begin + pos : a_begin + stop] != other.mm[b_begin + pos : b_begin + stop]:
                return False
            pos = stop
        return True

    def count_differing_elements(
        self, tensor_a: dict[str, Any], other: "Shard", tensor_b: dict[str, Any]
    ) -> int:
        """Count elements whose raw bit patterns differ (shapes/dtypes equal)."""
        numel = tensor_a["numel"]
        if numel == 0:
            return 0
        if _np is not None:
            np_dtype = {4: "<u4", 2: "<u2", 1: "<u1"}[ELEMENT_BYTES[tensor_a["dtype"]]]
            view_a = _np.frombuffer(
                self.mm, dtype=np_dtype, count=numel, offset=tensor_a["begin"]
            )
            view_b = _np.frombuffer(
                other.mm, dtype=np_dtype, count=numel, offset=tensor_b["begin"]
            )
            return int(_np.count_nonzero(view_a != view_b))
        nbytes = numel * ELEMENT_BYTES[tensor_a["dtype"]]
        if sys.byteorder == "little":
            try:
                va = memoryview(self.mm)[tensor_a["begin"] : tensor_a["begin"] + nbytes].cast(
                    _CAST_FMT[ELEMENT_BYTES[tensor_a["dtype"]]]
                )
                vb = memoryview(other.mm)[
                    tensor_b["begin"] : tensor_b["begin"] + nbytes
                ].cast(_CAST_FMT[ELEMENT_BYTES[tensor_a["dtype"]]])
                return sum(1 for x, y in zip(va, vb) if x != y)
            except (ValueError, TypeError, NotImplementedError):
                pass  # fall through to struct path
        code = {4: "I", 2: "H", 1: "B"}[ELEMENT_BYTES[tensor_a["dtype"]]]
        raw_a = self.mm[tensor_a["begin"] : tensor_a["begin"] + nbytes]
        raw_b = other.mm[tensor_b["begin"] : tensor_b["begin"] + nbytes]
        return sum(
            1
            for (x,), (y,) in zip(
                struct.iter_unpack("<" + code, raw_a), struct.iter_unpack("<" + code, raw_b)
            )
            if x != y
        )


# ---------------------------------------------------------------- inventory

def _build_inventory(directory: str, side: str) -> tuple[dict[str, dict[str, Any]], list[Shard]]:
    shards: list[Shard] = []
    try:
        for name in _discover_shards(directory, side):
            shards.append(Shard(directory, name, side))
        inventory: dict[str, dict[str, Any]] = {}
        for shard in shards:
            for tensor_name, meta in shard.tensors.items():
                if tensor_name in inventory:
                    _raise(
                        "MALFORMED_HEADER",
                        f"{side}: tensor {tensor_name} appears in more than one shard",
                    )
                entry = dict(meta)
                entry["shard"] = shard
                inventory[tensor_name] = entry
    except NamedError:
        for s in shards:
            s.close()
        raise
    return inventory, shards


def _sha256_file(path: str) -> str | None:
    if not os.path.isfile(path):
        return None
    digest = hashlib.sha256()
    try:
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(_CHUNK), b""):
                digest.update(chunk)
    except OSError as exc:
        _raise("SHARD_MISSING", f"cannot read {path}: {exc}")
    return digest.hexdigest()


# ---------------------------------------------------------------- main

def _run(args: argparse.Namespace) -> int:
    inv_a, shards_a = _build_inventory(args.dir_a, "A")
    try:
        inv_b, shards_b = _build_inventory(args.dir_b, "B")
    except NamedError:
        for s in shards_a:
            s.close()
        raise
    try:
        lines: list[dict[str, Any]] = []
        inventory_match = True
        elements_differing = 0

        only_a = sorted(set(inv_a) - set(inv_b))
        only_b = sorted(set(inv_b) - set(inv_a))
        for name in only_a:
            inventory_match = False
            t = inv_a[name]
            lines.append(
                {
                    "tensor": name,
                    "shape": t["shape"],
                    "dtype": t["dtype"],
                    "differing_elements": t["numel"],
                    "reason": "ONLY_IN_A",
                }
            )
            elements_differing += t["numel"]
        for name in only_b:
            inventory_match = False
            t = inv_b[name]
            lines.append(
                {
                    "tensor": name,
                    "shape": t["shape"],
                    "dtype": t["dtype"],
                    "differing_elements": t["numel"],
                    "reason": "ONLY_IN_B",
                }
            )
            elements_differing += t["numel"]

        for name in sorted(set(inv_a) & set(inv_b)):
            ta, tb = inv_a[name], inv_b[name]
            if ta["shape"] != tb["shape"]:
                inventory_match = False
                lines.append(
                    {
                        "tensor": name,
                        "shape": [ta["shape"], tb["shape"]],
                        "dtype": ta["dtype"],
                        "differing_elements": None,
                        "reason": "SHAPE_MISMATCH",
                    }
                )
                continue
            if ta["dtype"] != tb["dtype"]:
                inventory_match = False
                lines.append(
                    {
                        "tensor": name,
                        "shape": ta["shape"],
                        "dtype": [ta["dtype"], tb["dtype"]],
                        "differing_elements": None,
                        "reason": "DTYPE_MISMATCH",
                    }
                )
                continue
            if ta["shard"].bytes_equal(ta["begin"], ta["end"], tb["shard"], tb["begin"]):
                continue
            differing = ta["shard"].count_differing_elements(ta, tb["shard"], tb)
            elements_differing += differing
            lines.append(
                {
                    "tensor": name,
                    "shape": ta["shape"],
                    "dtype": ta["dtype"],
                    "differing_elements": differing,
                    "reason": "ELEMENT_DIFF",
                }
            )

        shard_names = sorted(set(_shard_names(args.dir_a)) | set(_shard_names(args.dir_b)))
        files = []
        for shard_name in shard_names:
            files.append(
                {
                    "file": shard_name,
                    "sha256_a": _sha256_file(os.path.join(args.dir_a, shard_name)),
                    "sha256_b": _sha256_file(os.path.join(args.dir_b, shard_name)),
                }
            )
        summary = {
            "tensors_differing": len(lines),
            "elements_differing": elements_differing,
            "inventory_match": inventory_match,
            "files": files,
        }

        if args.receipt:
            try:
                with open(args.receipt, "w", encoding="utf-8") as f:
                    for line in lines:
                        f.write(json.dumps(line, separators=(",", ":")) + "\n")
                    f.write(json.dumps(summary, separators=(",", ":")) + "\n")
            except OSError as exc:
                _raise("RECEIPT_WRITE_ERROR", f"{args.receipt}: {exc}")

        print(json.dumps(summary, separators=(",", ":")))
        return 1 if lines else 0
    finally:
        for s in shards_a + shards_b:
            s.close()


def _shard_names(directory: str) -> list[str]:
    """Shard names for the summary files list (index if present, else glob)."""
    index_path = os.path.join(directory, "model.safetensors.index.json")
    if os.path.isfile(index_path):
        try:
            with open(index_path, "rb") as f:
                return sorted({str(v) for v in json.load(f)["weight_map"].values()})
        except (OSError, ValueError, KeyError, TypeError):
            return []  # already named by _discover_shards if truly malformed
    try:
        return sorted(n for n in os.listdir(directory) if n.endswith(".safetensors"))
    except OSError:
        return []


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="diff_safetensors.py",
        description="Streaming mechanical diff of two safetensors checkpoint dirs (PREREG-A A1).",
        epilog="exit: 0 RESULT_IDENTICAL, 1 RESULT_DIFF, 2 NAMED error (see module docstring).",
    )
    parser.add_argument("dir_a", metavar="dirA")
    parser.add_argument("dir_b", metavar="dirB")
    parser.add_argument("--receipt", metavar="OUT.jsonl", help="write jsonl receipt (tensor lines + summary)")
    args = parser.parse_args(argv[1:])
    try:
        return _run(args)
    except NamedError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    except Exception as exc:  # noqa: BLE001 - house law: errors are NAMED, never silent
        print(f"INTERNAL_ERROR: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
