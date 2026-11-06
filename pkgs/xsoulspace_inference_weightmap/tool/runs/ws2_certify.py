#!/usr/bin/env python3
"""ws2_certify.py - WS-2 cross-engine certification glue (stdlib only).

Pure digest arithmetic over two pre-computed digest bundles: this script runs
NO engine, NO model, and NO heavy dependency - the frozen capture harness
produces the bundles; this tool only certifies and journals the verdict.

PYTHON-FIRST LAW (frozen): python_mlxlm is the REFERENCE (mlx_native
PYTHON-BOUNDARY law); rust is the CANDIDATE that must match it, never the
reverse. Roles are declared by the flags AND verified against each bundle's
`engine` field; a contradiction is a NAMED ENGINE_PAIR_INVALID refusal.

TOLERANCE LAW: the per-cell bound is pre-registered data (--tolerance), never
a default epsilon. The comparison mirrors patch_algebra.dart's Tolerance
exactly - edge-INCLUSIVE:

    |actual - expected| <= max(abs, rel * max(|expected|, |actual|))

DIGESTS KEY, NUMBERS DECIDE: logits_digest / behavior_digest are identity
evidence (V-6 keying; bit-equality is counted, never required); the criterion
is the per-cell numeric behavior_value under the registered tolerance. This
is the same rulebook lib/src/cross_engine.dart implements - one contract,
two implementations, and test/ws2_certify_test.dart pins them together.

Bundle json schema (strict key sets; same as cross_engine.dart):
  {"engine": "rust" | "python_mlxlm",
   "cells": [{"cell": "<name>", "logits_digest": "<non-empty str>",
              "behavior_digest": "<non-empty str>",
              "behavior_value": <finite number>}]}
Tolerance json schema (strict): {"abs": <finite num >= 0>, "rel": <same>}.

Output: ONE jsonl line is APPENDED to --out per run (denominator law: every
certification, including every mismatch, leaves a durable textual row; the
file is created with parents on first run) and echoed to stdout:
  {"tool": "ws2_certify.py", "created_utc": ...,
   "verdict": "AGREE" | "MISMATCH",
   "reference_engine": "python_mlxlm", "candidate_engine": "rust",
   "tolerance": {"abs": ..., "rel": ...},
   "cells_compared": N, "logits_bitwise_equal": K,
   "mismatches": [{"cell": ..., "reason": ..., "detail": ...}]}
Mismatch reason vocabulary (frozen, = cross_engine.dart):
  BEHAVIOR_DELTA_OUT_OF_TOLERANCE, CELL_MISSING_IN_CANDIDATE,
  CELL_MISSING_IN_REFERENCE.

Usage:
  python3 -I tool/runs/ws2_certify.py --rust-digest rust.json \
      --py-digest py.json --tolerance tol.json --out ws2.jsonl

Exit codes (errors are NAMED on stderr as 'CODE: detail', never silent):
  0  the certification RAN: verdict AGREE or MISMATCH (a mismatch is a
     measured finding, journaled in the record - not a tool failure)
  1  NAMED operational refusal, no record written:
       BUNDLE_READ_ERROR     bundle file missing/unreadable/not valid json
       MALFORMED_BUNDLE      bundle violates the frozen schema (detail names
                             MISSING_FIELD= / MALFORMED_FIELD= /
                             ENGINE_UNKNOWN= / EMPTY_CELLS /
                             CELL_NOT_OBJECT / DUPLICATE_CELL= / keys)
       TOLERANCE_READ_ERROR  tolerance file missing/unreadable/not valid json
       TOLERANCE_INVALID     tolerance violates {abs, rel} finite >= 0
       ENGINE_PAIR_INVALID   flags and engine fields are not exactly one
                             python_mlxlm reference + one rust candidate
       OUT_UNWRITABLE        --out cannot be created/appended
"""

import argparse
import json
import math
import os
import sys
from datetime import datetime, timezone

EXIT_OK = 0
EXIT_INPUT = 1

REFERENCE_ENGINE = 'python_mlxlm'
CANDIDATE_ENGINE = 'rust'
BUNDLE_KEYS = ('cells', 'engine')
CELL_KEYS = ('behavior_digest', 'behavior_value', 'cell', 'logits_digest')
TOLERANCE_KEYS = ('abs', 'rel')

BEHAVIOR_DELTA = 'BEHAVIOR_DELTA_OUT_OF_TOLERANCE'
MISSING_IN_CANDIDATE = 'CELL_MISSING_IN_CANDIDATE'
MISSING_IN_REFERENCE = 'CELL_MISSING_IN_REFERENCE'


def fail(code, detail):
    """Print a NAMED error to stderr; return the exit code for main."""
    print('%s: %s' % (code, detail), file=sys.stderr)
    return EXIT_INPUT


class ReadError(Exception):
    """File-level read/decode failure (NOT valid json).

    Kept distinct from ValueError so main can name it BUNDLE_READ_ERROR /
    TOLERANCE_READ_ERROR (mirroring apply_delta.py's SPEC_READ_ERROR, which
    covers missing/unreadable/not-valid-json) while schema violations stay
    MALFORMED_BUNDLE / TOLERANCE_INVALID.
    """


def _is_num(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool)


def parse_bundle(obj):
    """Validate the frozen bundle schema; return (engine, cells-by-name, order).

    Raises ValueError with a 'MALFORMED_BUNDLE ...' detail on any violation
    (never a silent default).
    """
    if not isinstance(obj, dict):
        raise ValueError('bundle is not a json object (found %s)'
                         % type(obj).__name__)
    keys = set(obj)
    if keys != set(BUNDLE_KEYS):
        raise ValueError('keys mismatch (missing=%s extra=%s)'
                         % (sorted(set(BUNDLE_KEYS) - keys),
                            sorted(keys - set(BUNDLE_KEYS))))
    engine = obj['engine']
    if not isinstance(engine, str):
        raise ValueError('MALFORMED_FIELD=engine expected=String found=%s'
                         % type(engine).__name__)
    if engine not in (REFERENCE_ENGINE, CANDIDATE_ENGINE):
        raise ValueError('ENGINE_UNKNOWN=%s (allowed: %s, %s)'
                         % (engine, CANDIDATE_ENGINE, REFERENCE_ENGINE))
    raw_cells = obj['cells']
    if not isinstance(raw_cells, list):
        raise ValueError('MALFORMED_FIELD=cells expected=List found=%s'
                         % type(raw_cells).__name__)
    if not raw_cells:
        raise ValueError('EMPTY_CELLS')
    cells = {}
    order = []
    for i, raw in enumerate(raw_cells):
        if not isinstance(raw, dict):
            raise ValueError('cells[%d] CELL_NOT_OBJECT found=%s'
                             % (i, type(raw).__name__))
        cell_keys = set(raw)
        if cell_keys != set(CELL_KEYS):
            raise ValueError('cells[%d] keys mismatch (missing=%s extra=%s)'
                             % (i, sorted(set(CELL_KEYS) - cell_keys),
                                sorted(cell_keys - set(CELL_KEYS))))
        name = raw['cell']
        if not isinstance(name, str) or not name:
            raise ValueError('cells[%d] MALFORMED_FIELD=cell expected='
                             'non-empty String found=%s'
                             % (i, type(name).__name__))
        for field in ('logits_digest', 'behavior_digest'):
            v = raw[field]
            if not isinstance(v, str) or not v:
                raise ValueError('cells[%d] MALFORMED_FIELD=%s expected='
                                 'non-empty String found=%s'
                                 % (i, field, type(v).__name__))
        value = raw['behavior_value']
        if not _is_num(value) or not math.isfinite(value):
            raise ValueError('cells[%d] MALFORMED_FIELD=behavior_value '
                             'expected=finite number found=%r' % (i, value))
        if name in cells:
            raise ValueError('DUPLICATE_CELL=%s' % name)
        cells[name] = {
            'cell': name,
            'logits_digest': raw['logits_digest'],
            'behavior_digest': raw['behavior_digest'],
            'behavior_value': float(value),
        }
        order.append(name)
    return engine, cells, order


def load_bundle(path):
    """Read + parse one bundle file. Returns (engine, cells, order) or raises.

    Raises OSError/ReadError (BUNDLE_READ_ERROR) or ValueError
    (MALFORMED_BUNDLE).
    """
    with open(path, 'rb') as fh:  # OSError -> BUNDLE_READ_ERROR
        raw = fh.read()
    try:
        obj = json.loads(raw)
    except ValueError as exc:
        raise ReadError('not valid json (%s)' % exc)
    return parse_bundle(obj)


def load_tolerance(path):
    """Read + parse the tolerance file. Returns (abs, rel) or raises.

    Raises OSError/ReadError (TOLERANCE_READ_ERROR) or ValueError
    (TOLERANCE_INVALID).
    """
    with open(path, 'rb') as fh:
        raw = fh.read()
    try:
        obj = json.loads(raw)
    except ValueError as exc:
        raise ReadError('not valid json (%s)' % exc)
    if not isinstance(obj, dict):
        raise ValueError('tolerance is not a json object (found %s)'
                         % type(obj).__name__)
    keys = set(obj)
    if keys != set(TOLERANCE_KEYS):
        raise ValueError('keys mismatch (missing=%s extra=%s)'
                         % (sorted(set(TOLERANCE_KEYS) - keys),
                            sorted(keys - set(TOLERANCE_KEYS))))
    bounds = {}
    for field in TOLERANCE_KEYS:
        v = obj[field]
        if not _is_num(v) or not math.isfinite(v) or v < 0:
            raise ValueError('MALFORMED_FIELD=%s expected=finite number >= 0 '
                             'found=%r' % (field, v))
        bounds[field] = float(v)
    return bounds['abs'], bounds['rel']


def within_tolerance(expected, actual, abs_bound, rel_bound):
    """The pre-registered edge-INCLUSIVE rule (patch_algebra.dart Tolerance).

    NaN never passes (IEEE comparisons are false), which is the loud
    behavior we want.
    """
    delta = abs(actual - expected)
    return delta <= max(abs_bound, rel_bound * max(abs(expected), abs(actual)))


def certify(ref_cells, ref_order, cand_cells, cand_order, abs_bound, rel_bound):
    """Cross-engine certification: reference (python_mlxlm) vs candidate (rust).

    Returns (cells_compared, logits_bitwise_equal, mismatches). ALL offending
    cells are listed - selective reporting is structurally impossible.
    """
    mismatches = []
    compared = 0
    logits_bitwise_equal = 0
    for name in ref_order:
        ref = ref_cells[name]
        cand = cand_cells.get(name)
        if cand is None:
            mismatches.append({
                'cell': name,
                'reason': MISSING_IN_CANDIDATE,
                'detail': 'cell present in reference (python_mlxlm) but '
                          'absent from candidate (rust)',
            })
            continue
        compared += 1
        if ref['logits_digest'] == cand['logits_digest']:
            logits_bitwise_equal += 1
        expected = ref['behavior_value']
        actual = cand['behavior_value']
        if not within_tolerance(expected, actual, abs_bound, rel_bound):
            mismatches.append({
                'cell': name,
                'reason': BEHAVIOR_DELTA,
                'detail': 'expected(python_mlxlm)=%r actual(rust)=%r '
                          'delta=%r tolerance abs=%r rel=%r'
                          % (expected, actual, abs(actual - expected),
                             abs_bound, rel_bound),
            })
    for name in cand_order:
        if name not in ref_cells:
            mismatches.append({
                'cell': name,
                'reason': MISSING_IN_REFERENCE,
                'detail': 'cell present in candidate (rust) but absent from '
                          'reference (python_mlxlm)',
            })
    return compared, logits_bitwise_equal, mismatches


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--rust-digest', required=True,
                    help='candidate (rust) digest bundle json file')
    ap.add_argument('--py-digest', required=True,
                    help='reference (python_mlxlm) digest bundle json file')
    ap.add_argument('--tolerance', required=True,
                    help='pre-registered {"abs": num, "rel": num} json file')
    ap.add_argument('--out', required=True,
                    help='jsonl record file (one line APPENDED per run)')
    args = ap.parse_args(argv)

    try:
        py_engine, py_cells, py_order = load_bundle(args.py_digest)
    except (OSError, ReadError) as exc:
        return fail('BUNDLE_READ_ERROR', '%s (%s)' % (args.py_digest, exc))
    except ValueError as exc:
        return fail('MALFORMED_BUNDLE', '%s (%s)' % (args.py_digest, exc))
    try:
        rust_engine, rust_cells, rust_order = load_bundle(args.rust_digest)
    except (OSError, ReadError) as exc:
        return fail('BUNDLE_READ_ERROR', '%s (%s)' % (args.rust_digest, exc))
    except ValueError as exc:
        return fail('MALFORMED_BUNDLE', '%s (%s)' % (args.rust_digest, exc))

    # Python-first law, mechanically: the --py-digest file MUST be the
    # python_mlxlm reference and --rust-digest the rust candidate; a
    # contradiction (swap, or two of one engine) refuses by name.
    if py_engine != REFERENCE_ENGINE or rust_engine != CANDIDATE_ENGINE:
        return fail('ENGINE_PAIR_INVALID',
                    'expected %s=engine %s and %s=engine %s, found %s and %s '
                    '(Python-first law: rust must match python_mlxlm, never '
                    'the reverse)'
                    % (args.py_digest, REFERENCE_ENGINE,
                       args.rust_digest, CANDIDATE_ENGINE,
                       py_engine, rust_engine))

    try:
        abs_bound, rel_bound = load_tolerance(args.tolerance)
    except (OSError, ReadError) as exc:
        return fail('TOLERANCE_READ_ERROR', '%s (%s)' % (args.tolerance, exc))
    except ValueError as exc:
        return fail('TOLERANCE_INVALID', '%s (%s)' % (args.tolerance, exc))

    compared, logits_equal, mismatches = certify(
        py_cells, py_order, rust_cells, rust_order, abs_bound, rel_bound)
    record = {
        'tool': 'ws2_certify.py',
        'created_utc': datetime.now(timezone.utc).isoformat(timespec='seconds'),
        'verdict': 'MISMATCH' if mismatches else 'AGREE',
        'reference_engine': REFERENCE_ENGINE,
        'candidate_engine': CANDIDATE_ENGINE,
        'tolerance': {'abs': abs_bound, 'rel': rel_bound},
        'cells_compared': compared,
        'logits_bitwise_equal': logits_equal,
        'mismatches': mismatches,
    }
    line = json.dumps(record)
    try:
        out_dir = os.path.dirname(args.out)
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        with open(args.out, 'a', encoding='utf-8') as fh:
            fh.write(line + '\n')
    except OSError as exc:
        return fail('OUT_UNWRITABLE', '%s (%s)' % (args.out, exc))
    print(line)
    return EXIT_OK


if __name__ == '__main__':
    sys.exit(main())
