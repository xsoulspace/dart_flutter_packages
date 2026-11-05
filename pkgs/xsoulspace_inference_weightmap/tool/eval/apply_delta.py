#!/usr/bin/env python3
"""apply_delta.py - sidecar low-rank delta writer (NEVER mutates the base).

Takes a frozen delta spec and writes the edit as a SIDECAR artifact plus a
receipt, so the base checkpoint directory stays byte-identical and the edit is
a typed, digest-keyed artifact (PROGRAM.md Phase B: "the edit is a typed
artifact"). The base dir is opened read-only ('rb') and nothing else.

Spec json (exact shape; missing/extra keys or wrong types are refused):
  {"tensor": "<name>", "columns": [int, ...], "direction": [float, ...],
   "scale": float}
Semantics: the delta for `tensor` (rows x cols) is zero except at the chosen
columns; each chosen column j receives `scale * direction`. len(direction)
must equal the tensor's row dimension - checked against the base safetensors
header at REAL RUN only. applied_rank = len(columns).

Outputs (written into --out):
  delta.npz    if numpy is importable: compact rank form (tensor_name,
               columns, direction, scale, rows)
  delta.json   otherwise: DENSE column deltas {tensor, rows, columns, scale,
               column_deltas: {col: [rows floats]}}
  receipt.json always: {base_dir, spec_digest (sha256 of spec bytes),
               out_files, applied_rank, artifact, numpy_available, tensor,
               tensor_shape, base_read_only, shard, created_utc}
numpy absence is NOT an error: it is a documented fallback and is NAMED in the
receipt (numpy_available: false) - never silent.

Usage:
  python3 -I tool/eval/apply_delta.py --base <model-dir> --spec <spec.json> \
      --out <dir> [--dry-run]

--dry-run validates the spec SHAPE only, prints the plan, exits 0 and writes
NOTHING. It SKIPS reading the base safetensors headers and says so:
TENSOR_NOT_FOUND and direction-vs-shape checks are real-run only.

Exit codes (errors are NAMED on stderr as 'CODE: detail', never silent):
  0  ok (dry-run plan printed, or sidecar + receipt written)
  1  named error:
       SPEC_READ_ERROR          spec file missing/unreadable/not valid json
       SPEC_SHAPE_MISMATCH      spec keys/types/lengths wrong (real run adds:
                                direction length vs tensor rows, columns out
                                of range, tensor not 2-D) - detail lists all
       BASE_DIR_MISSING         --base is not a directory (real run)
       TENSOR_NOT_FOUND         tensor absent from every base *.safetensors
                                header (real run; dry-run skips and says so)
       SAFETENSORS_HEADER_ERROR a base shard header is unreadable (real run)
       OUT_UNWRITABLE           --out cannot be created/written (real run)
"""

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone

EXIT_OK = 0
EXIT_INPUT = 1

REQUIRED_KEYS = ('columns', 'direction', 'scale', 'tensor')


def fail(code, detail):
    """Print a NAMED error to stderr; return the exit code for main."""
    print('%s: %s' % (code, detail), file=sys.stderr)
    return EXIT_INPUT


def _is_int(x):
    return isinstance(x, int) and not isinstance(x, bool)


def _is_num(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool)


def spec_shape_problems(spec):
    """Return the list of named shape problems; empty list = valid spec."""
    if not isinstance(spec, dict):
        return ['spec is not a json object']
    problems = []
    keys = set(spec)
    if keys != set(REQUIRED_KEYS):
        problems.append('keys mismatch (missing=%s extra=%s)'
                        % (sorted(set(REQUIRED_KEYS) - keys),
                           sorted(keys - set(REQUIRED_KEYS))))
    tensor = spec.get('tensor')
    if not isinstance(tensor, str) or not tensor:
        problems.append('tensor must be a non-empty string')
    columns = spec.get('columns')
    if (not isinstance(columns, list) or not columns
            or not all(_is_int(c) for c in columns)):
        problems.append('columns must be a non-empty list of ints')
    else:
        if len(set(columns)) != len(columns):
            problems.append('columns contain duplicate indices')
        if any(c < 0 for c in columns):
            problems.append('columns contain negative indices')
    direction = spec.get('direction')
    if (not isinstance(direction, list) or not direction
            or not all(_is_num(d) for d in direction)):
        problems.append('direction must be a non-empty list of numbers')
    if not _is_num(spec.get('scale')):
        problems.append('scale must be a number')
    return problems


def read_safetensors_header(path):
    """Parse a .safetensors header (pure stdlib: u64 LE length + json)."""
    with open(path, 'rb') as fh:
        length_bytes = fh.read(8)
        if len(length_bytes) < 8:
            raise ValueError('file shorter than the 8-byte header length')
        header_len = int.from_bytes(length_bytes, 'little')
        header_bytes = fh.read(header_len)
        if len(header_bytes) < header_len:
            raise ValueError('truncated header')
        header = json.loads(header_bytes)
    if not isinstance(header, dict):
        raise ValueError('header is not a json object')
    return header


def find_tensor(base_dir, tensor_name):
    """Locate tensor_name across base *.safetensors headers.

    Returns (shard_path, shape). Raises LookupError (TENSOR_NOT_FOUND) or
    RuntimeError (SAFETENSORS_HEADER_ERROR). Read-only.
    """
    try:
        entries = sorted(os.listdir(base_dir))
    except OSError as exc:
        raise RuntimeError('SAFETENSORS_HEADER_ERROR: %s (%s)' % (base_dir, exc))
    shards = [f for f in entries if f.endswith('.safetensors')]
    if not shards:
        raise LookupError('no *.safetensors shards in %s' % base_dir)
    for shard in shards:
        path = os.path.join(base_dir, shard)
        try:
            header = read_safetensors_header(path)
        except (OSError, ValueError) as exc:
            raise RuntimeError('SAFETENSORS_HEADER_ERROR: %s (%s)' % (path, exc))
        entry = header.get(tensor_name)
        if entry is not None:
            return path, entry.get('shape')
    raise LookupError('tensor %r absent from shards %s' % (tensor_name, shards))


def write_delta_artifact(out_dir, spec, rows):
    """Write delta.npz (numpy) or delta.json (dense fallback).

    Returns (artifact_name, numpy_available).
    """
    try:
        import numpy as np
    except ImportError:
        np = None
    if np is not None:
        artifact = 'delta.npz'
        np.savez(
            os.path.join(out_dir, artifact),
            tensor_name=np.array(spec['tensor']),
            columns=np.array(spec['columns'], dtype=np.int64),
            direction=np.array(spec['direction'], dtype=np.float64),
            scale=np.array(spec['scale'], dtype=np.float64),
            rows=np.array(rows, dtype=np.int64),
        )
    else:
        artifact = 'delta.json'
        column = [spec['scale'] * d for d in spec['direction']]
        payload = {
            'tensor': spec['tensor'],
            'rows': rows,
            'columns': spec['columns'],
            'scale': spec['scale'],
            'column_deltas': {str(c): list(column) for c in spec['columns']},
        }
        with open(os.path.join(out_dir, artifact), 'w', encoding='utf-8') as fh:
            json.dump(payload, fh, indent=2)
    return artifact, np is not None


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--base', required=True,
                    help='base model dir (read-only; NEVER mutated)')
    ap.add_argument('--spec', required=True, help='delta spec json')
    ap.add_argument('--out', required=True, help='sidecar output dir')
    ap.add_argument('--dry-run', action='store_true',
                    help='validate spec shape, print the plan, write nothing')
    args = ap.parse_args(argv)

    try:
        with open(args.spec, 'rb') as fh:
            spec_bytes = fh.read()
    except OSError as exc:
        return fail('SPEC_READ_ERROR', str(exc))
    try:
        spec = json.loads(spec_bytes)
    except ValueError as exc:
        return fail('SPEC_READ_ERROR', 'not valid json (%s)' % exc)
    spec_digest = hashlib.sha256(spec_bytes).hexdigest()

    problems = spec_shape_problems(spec)
    if problems:
        return fail('SPEC_SHAPE_MISMATCH', '; '.join(problems))

    applied_rank = len(spec['columns'])

    if args.dry_run:
        plan = {
            'mode': 'dry-run',
            'base_dir': args.base,
            'spec_digest': spec_digest,
            'tensor': spec['tensor'],
            'columns': spec['columns'],
            'direction_len': len(spec['direction']),
            'scale': spec['scale'],
            'applied_rank': applied_rank,
            'out_dir': args.out,
            'base_read': 'SKIPPED: dry-run does not read the base safetensors '
                         'headers; TENSOR_NOT_FOUND and direction-vs-shape '
                         'checks are real-run only',
            'writes': 'nothing',
        }
        print(json.dumps(plan, indent=2))
        return EXIT_OK

    # --- real run ---
    if not os.path.isdir(args.base):
        return fail('BASE_DIR_MISSING', args.base)
    try:
        shard_path, shape = find_tensor(args.base, spec['tensor'])
    except LookupError as exc:
        return fail('TENSOR_NOT_FOUND', str(exc))
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return EXIT_INPUT
    if (not isinstance(shape, list) or len(shape) != 2
            or not all(_is_int(s) for s in shape)):
        return fail('SPEC_SHAPE_MISMATCH',
                    'tensor %r shape %r is not a 2-D int shape'
                    % (spec['tensor'], shape))
    rows, cols = shape
    shape_problems = []
    if len(spec['direction']) != rows:
        shape_problems.append('direction length %d != tensor rows %d'
                              % (len(spec['direction']), rows))
    out_of_range = [c for c in spec['columns'] if c >= cols]
    if out_of_range:
        shape_problems.append('columns %s out of range for %d columns'
                              % (out_of_range, cols))
    if shape_problems:
        return fail('SPEC_SHAPE_MISMATCH', '; '.join(shape_problems))

    try:
        os.makedirs(args.out, exist_ok=True)
        artifact, numpy_available = write_delta_artifact(args.out, spec, rows)
        receipt = {
            'tool': 'apply_delta.py',
            'base_dir': args.base,
            'base_read_only': True,
            'shard': os.path.basename(shard_path),
            'tensor': spec['tensor'],
            'tensor_shape': shape,
            'spec_digest': spec_digest,
            'applied_rank': applied_rank,
            'artifact': artifact,
            'numpy_available': numpy_available,
            'out_files': sorted([artifact, 'receipt.json']),
            'created_utc': datetime.now(timezone.utc).isoformat(
                timespec='seconds'),
        }
        receipt_path = os.path.join(args.out, 'receipt.json')
        with open(receipt_path, 'w', encoding='utf-8') as fh:
            json.dump(receipt, fh, indent=2)
    except OSError as exc:
        return fail('OUT_UNWRITABLE', str(exc))
    print('wrote %s (rank %d, artifact %s, numpy=%s)'
          % (receipt_path, applied_rank, artifact, numpy_available))
    return EXIT_OK


if __name__ == '__main__':
    sys.exit(main())
