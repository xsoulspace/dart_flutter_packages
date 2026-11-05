#!/usr/bin/env python3 -I
"""sha256_verify.py — verify one file against an expected SHA-256 hex digest.

Usage: sha256_verify.py <file> <expected-hex>

Stdout (exactly one line):
    MATCH <sha256>                          exit 0
    SHA256_MISMATCH expected=<e> actual=<a> exit 1

Errors are NAMED on stderr with exit 2:
    USAGE_ERROR       bad argv
    FILE_MISSING      <file> absent or not a regular file
    BAD_EXPECTED_HEX  expected digest is not 64 hex chars
    READ_ERROR        <file> unreadable
    INTERNAL_ERROR    unexpected exception (class + message named)

No third-party deps. Streaming hash (4 MiB chunks); the file is data only,
never executed.
"""

from __future__ import annotations

import hashlib
import os
import sys

_CHUNK = 1 << 22


def _fail(name: str, detail: str, code: int = 2) -> "NoReturn":  # type: ignore[name-defined]
    if code == 2:
        print(f"{name}: {detail}", file=sys.stderr)
    else:
        print(f"{name} {detail}")
    raise SystemExit(code)


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        _fail("USAGE_ERROR", "usage: sha256_verify.py <file> <expected-hex>")
    path, expected = argv[1], argv[2].strip().lower()
    if len(expected) != 64 or any(c not in "0123456789abcdef" for c in expected):
        _fail("BAD_EXPECTED_HEX", f"expected 64 hex chars, got: {argv[2]!r}")
    if not os.path.isfile(path):
        _fail("FILE_MISSING", path)
    digest = hashlib.sha256()
    try:
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(_CHUNK), b""):
                digest.update(chunk)
    except OSError as exc:
        _fail("READ_ERROR", f"{path}: {exc}")
    actual = digest.hexdigest()
    if actual == expected:
        print(f"MATCH {actual}")
        return 0
    _fail("SHA256_MISMATCH", f"expected={expected} actual={actual}", code=1)
    return 1  # unreachable; _fail raises


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001 - house law: errors are NAMED, never silent
        print(f"INTERNAL_ERROR: {type(exc).__name__}: {exc}", file=sys.stderr)
        sys.exit(2)
