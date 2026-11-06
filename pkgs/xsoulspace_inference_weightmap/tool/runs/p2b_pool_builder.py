#!/usr/bin/env python3
"""p2b_pool_builder.py - P-2b strictly-disjoint practice pool builder.

PREREG-D P-2b (FROZEN): the hygiene variant's practice pool is STRICTLY
DISJOINT from the evals - MATH train minus MATH-500 BY CONSTRUCTION, and
GSM8K train vs GSM8K test. The paper's pool claims disjointness in its
README ("Practice problems (none of them is in the evaluation)"); this
builder VERIFIES that claim mechanically instead of trusting it, removes
every literal overlap, and records what it removed. The P-2 vs P-2b runtime
delta then MEASURES the paper's contamination risk (p2_runner.py records
both; neither is a pass bar).

Honest scope note (recorded in the receipt): only LITERAL overlap is
removable here. Distributional overlap (same corpus lineage between MATH
train and MATH-500) is not a set operation - it is exactly what the P-2 vs
P-2b delta measures at runtime. The receipt therefore carries NAMED
DISTRIBUTIONAL_CONTAMINATION_NOT_MEASURED rather than claiming a clean pool.

INPUT SCHEMAS:
  --math-train / --gsm8k-train / --aime: the paper exp8 practice jsonl
    (one object per line; math/gsm8k rows carry a reference solution; the
    builder treats every row as OPAQUE DATA - original line bytes are
    preserved verbatim in the output so digests stay comparable upstream).
  --math500: MATH-500 eval jsonl, one object per line with a str "problem"
    (HuggingFaceHARB/MATH-500 layout; "question" also accepted).
  --gsm8k-test: GSM8K test jsonl, one object per line with str "question"
    (or "problem").

MATCH RULE (frozen): normalized text equality - all whitespace runs
collapsed to one space, stripped; case-SENSITIVE (math notation). Ids are
NOT compared (they differ across sources); text is the only key.

OUTPUT (into --out):
  p2b_math_train.jsonl    math_train rows minus every MATH-500 overlap
  p2b_gsm8k_train.jsonl   gsm8k_train rows minus every GSM8K-test overlap
                          (only when the gsm8k pair is supplied)
  p2b_aime.jsonl          aime passthrough (digest-recorded; AIME is not
                          among the P-2 eval suites) - only when supplied
  build_receipt.json      textual evidence: input/output paths, rows,
                          sha256 of every input and output, removed ids and
                          counts, the paper's kept/dropped stats (constants
                          with citation), disjointness verdict, and the
                          DISTRIBUTIONAL_CONTAMINATION_NOT_MEASURED note.
A POST-CHECK recomputes the overlap of each output against its eval set;
any survivor is NAMED OVERLAP_REMAINS (an internal invariant - it should be
unreachable, and if it ever fires the build is refused, not shipped).

Usage:
  python3 -I tool/runs/p2b_pool_builder.py \
      --math-train <math_train.jsonl> --math500 <math500.jsonl> \
      [--gsm8k-train <gsm8k_train.jsonl> --gsm8k-test <gsm8k_test.jsonl>] \
      [--aime <aime.jsonl>] --out <dir> [--dry-run]

--dry-run reads + validates the inputs, computes the overlap COUNTS (read-
only), and prints the plan as JSON on stdout, exit 0. Nothing is written.

Exit codes (errors are NAMED on stderr as 'CODE: detail', never silent):
  0  ok (dry-run plan printed, or pool + receipt written)
  1  named input/runtime error:
       USAGE_ERROR               bad argv
       POOL_INPUT_MISSING        --math-train/--gsm8k-train/--aime absent
       MATH500_MISSING           --math500 absent/unreadable
       GSM8K_PAIR_INCOMPLETE     exactly one of --gsm8k-train/--gsm8k-test
       INPUT_JSONL_MALFORMED     a row is not json / lacks the text key
                                 (detail names file + line)
       EMPTY_INPUT               a required input has no rows
       EMPTY_POOL                subtraction left zero rows (degenerate;
                                 recorded, never shipped as a pool)
       OVERLAP_REMAINS           post-check found a survivor (invariant)
       OUT_UNWRITABLE            --out cannot be created/written
       INTERNAL_ERROR            unexpected exception (class + message)
"""

import argparse
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone

EXIT_OK = 0
EXIT_INPUT = 1

RECEIPT_SCHEMA = 'p2b-build-receipt/v1'

# The paper pool's own kept/dropped counts (exp8_math/practice/stats.json,
# digest-verified by p2_runner.py; recorded here as constants with citation).
THEIR_POOL_STATS = {
    'gsm8k_train': {'kept': 7469, 'dropped': 4},
    'math_train': {'kept': 7275, 'dropped': 225},
    'aime': {'kept': 714, 'dropped': 0},
}
THEIR_STATS_CITATION = ('RikiyaT/lm_understand-logs@main exp8_math/practice/'
                        'stats.json (retrieved 2026-11-05)')
DISTRIBUTIONAL_NOTE = (
    'DISTRIBUTIONAL_CONTAMINATION_NOT_MEASURED: this builder removes LITERAL '
    'text overlaps only. Distributional overlap (same corpus lineage between '
    'MATH train and MATH-500) is not a set operation - it is what the P-2 '
    'vs P-2b runtime delta MEASURES (PREREG-D). Recorded, never claimed '
    'away.'
)

_WS_RUN = re.compile(r'\s+')


def fail(code, detail, exit_code=EXIT_INPUT):
    print('%s: %s' % (code, detail), file=sys.stderr)
    return exit_code


def _now_utc():
    return datetime.now(timezone.utc).isoformat(timespec='seconds')


def normalize_problem(text):
    """Frozen match rule: collapse whitespace runs, strip; case-sensitive."""
    return _WS_RUN.sub(' ', text).strip()


def read_jsonl_lines(path, which, text_keys):
    """Read a jsonl as (raw_line, normalized_text, id) triples.

    Lines are kept as ORIGINAL bytes-as-text (byte preservation law); the
    text key must be present and a str. NAMED RuntimeError on any problem.
    """
    try:
        with open(path, 'r', encoding='utf-8') as fh:
            raw_lines = fh.read().splitlines()
    except OSError as exc:
        code = 'MATH500_MISSING' if which == 'math500' else 'POOL_INPUT_MISSING'
        raise RuntimeError('%s: %s %s (%s)' % (code, which, path, exc))
    except UnicodeDecodeError as exc:
        raise RuntimeError('INPUT_JSONL_MALFORMED: %s %s not utf-8 (%s)'
                           % (which, path, exc))
    out = []
    for lineno, line in enumerate(raw_lines, start=1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except ValueError as exc:
            raise RuntimeError('INPUT_JSONL_MALFORMED: %s %s line %d not '
                               'valid json (%s)' % (which, path, lineno, exc))
        if not isinstance(row, dict):
            raise RuntimeError('INPUT_JSONL_MALFORMED: %s %s line %d is not '
                               'an object' % (which, path, lineno))
        text = None
        for key in text_keys:
            if isinstance(row.get(key), str):
                text = row[key]
                break
        if text is None:
            raise RuntimeError('INPUT_JSONL_MALFORMED: %s %s line %d lacks a '
                               'str %s field'
                               % (which, path, lineno, list(text_keys)))
        rid = row.get('id')
        out.append((line, normalize_problem(text),
                    rid if isinstance(rid, str) else 'line-%d' % lineno))
    if not out:
        raise RuntimeError('EMPTY_INPUT: %s %s has no rows' % (which, path))
    return out


def sha256_path(path):
    h = hashlib.sha256()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(1 << 22), b''):
            h.update(chunk)
    return h.hexdigest()


def subtract(train_rows, eval_norm_set):
    """(kept_rows, removed_ids) under normalized-text membership."""
    kept = [r for r in train_rows if r[1] not in eval_norm_set]
    removed = [r[2] for r in train_rows if r[1] in eval_norm_set]
    return kept, removed


def write_jsonl(path, rows):
    with open(path, 'w', encoding='utf-8') as fh:
        for raw_line, _norm, _rid in rows:
            fh.write(raw_line + '\n')


def build(args):
    """Shared read + subtract for dry-run and real run (never writes)."""
    math_train = read_jsonl_lines(args.math_train, 'math_train',
                                  ('problem', 'question'))
    math500 = read_jsonl_lines(args.math500, 'math500',
                               ('problem', 'question'))
    math500_norms = {r[1] for r in math500}
    p2b_math, removed_math = subtract(math_train, math500_norms)

    gsm8k = None
    if args.gsm8k_train:
        gsm8k_train = read_jsonl_lines(args.gsm8k_train, 'gsm8k_train',
                                       ('question', 'problem'))
        gsm8k_test = read_jsonl_lines(args.gsm8k_test, 'gsm8k_test',
                                      ('question', 'problem'))
        test_norms = {r[1] for r in gsm8k_test}
        p2b_gsm8k, removed_gsm8k = subtract(gsm8k_train, test_norms)
        gsm8k = {'train_rows': len(gsm8k_train),
                 'test_rows': len(gsm8k_test),
                 'p2b_rows': len(p2b_gsm8k),
                 'removed_ids': removed_gsm8k,
                 'kept_rows': p2b_gsm8k}

    aime = None
    if args.aime:
        aime_rows = read_jsonl_lines(args.aime, 'aime', ('problem',))
        aime = {'rows': len(aime_rows), 'kept_rows': aime_rows}

    return {
        'math': {'train_rows': len(math_train),
                 'math500_rows': len(math500),
                 'p2b_rows': len(p2b_math),
                 'removed_ids': removed_math,
                 'kept_rows': p2b_math},
        'gsm8k': gsm8k,
        'aime': aime,
        'inputs': {
            'math_train': {'path': os.path.abspath(args.math_train),
                           'sha256': sha256_path(args.math_train)},
            'math500': {'path': os.path.abspath(args.math500),
                        'sha256': sha256_path(args.math500)},
        },
    }


def run_dry(args, state):
    if args.gsm8k_train:
        state['inputs']['gsm8k_train'] = {
            'path': os.path.abspath(args.gsm8k_train),
            'sha256': sha256_path(args.gsm8k_train)}
        state['inputs']['gsm8k_test'] = {
            'path': os.path.abspath(args.gsm8k_test),
            'sha256': sha256_path(args.gsm8k_test)}
    if args.aime:
        state['inputs']['aime'] = {'path': os.path.abspath(args.aime),
                                   'sha256': sha256_path(args.aime)}
    plan = {
        'mode': 'dry-run',
        'tool': 'p2b_pool_builder.py',
        'receipt_schema': RECEIPT_SCHEMA,
        'match_rule': ('normalized text equality (whitespace runs collapsed, '
                       'stripped, case-SENSITIVE); ids never compared'),
        'inputs': {k: {**v, 'rows': None} for k, v in state['inputs'].items()},
        'overlap_counts': {
            'math500_removed_from_math_train':
                len(state['math']['removed_ids']),
            'gsm8k_test_removed_from_gsm8k_train':
                (len(state['gsm8k']['removed_ids'])
                 if state['gsm8k'] else None),
        },
        'row_counts': {
            'math_train': state['math']['train_rows'],
            'math500': state['math']['math500_rows'],
            'p2b_math_train': state['math']['p2b_rows'],
            'gsm8k_train': (state['gsm8k']['train_rows']
                            if state['gsm8k'] else None),
            'p2b_gsm8k_train': (state['gsm8k']['p2b_rows']
                                if state['gsm8k'] else None),
            'aime_passthrough': (state['aime']['rows']
                                 if state['aime'] else None),
        },
        'outputs_planned': ['p2b_math_train.jsonl']
        + (['p2b_gsm8k_train.jsonl'] if state['gsm8k'] else [])
        + (['p2b_aime.jsonl'] if state['aime'] else [])
        + ['build_receipt.json'],
        'byte_preservation': ('output rows are the ORIGINAL input line bytes '
                              '(no re-serialization) so digests stay '
                              'comparable upstream'),
        'their_pool_stats': {'values': THEIR_POOL_STATS,
                             'citation': THEIR_STATS_CITATION},
        'distributional_note': DISTRIBUTIONAL_NOTE,
        'out': os.path.abspath(args.out),
        'note': 'plan only; nothing written (overlap computed read-only)',
    }
    print(json.dumps(plan, indent=2))
    return EXIT_OK


def run_real(args, state):
    if state['math']['p2b_rows'] == 0:
        return fail('EMPTY_POOL',
                    'MATH train minus MATH-500 left zero rows (degenerate; '
                    'recorded, never shipped)')
    if state['gsm8k'] and state['gsm8k']['p2b_rows'] == 0:
        return fail('EMPTY_POOL',
                    'GSM8K train minus test left zero rows (degenerate)')
    out_dir = os.path.abspath(args.out)
    try:
        os.makedirs(out_dir, exist_ok=True)
    except OSError as exc:
        return fail('OUT_UNWRITABLE', '%s (%s)' % (out_dir, exc))

    outputs = {}

    def ship(name, rows):
        path = os.path.join(out_dir, name)
        write_jsonl(path, rows)
        outputs[name] = {'path': path, 'rows': len(rows),
                         'sha256': sha256_path(path)}

    ship('p2b_math_train.jsonl', state['math']['kept_rows'])
    if state['gsm8k']:
        ship('p2b_gsm8k_train.jsonl', state['gsm8k']['kept_rows'])
    if state['aime']:
        ship('p2b_aime.jsonl', state['aime']['kept_rows'])

    # POST-CHECK (invariant): recompute overlap of each output vs eval set.
    math500 = read_jsonl_lines(args.math500, 'math500',
                               ('problem', 'question'))
    math500_norms = {r[1] for r in math500}
    survivors = [r[2] for r in state['math']['kept_rows']
                 if r[1] in math500_norms]
    if survivors:
        return fail('OVERLAP_REMAINS',
                    'p2b_math_train still overlaps MATH-500 at %s '
                    '(invariant violated; build refused, not shipped)'
                    % survivors[:10])
    if state['gsm8k']:
        gsm8k_test = read_jsonl_lines(args.gsm8k_test, 'gsm8k_test',
                                      ('question', 'problem'))
        test_norms = {r[1] for r in gsm8k_test}
        survivors = [r[2] for r in state['gsm8k']['kept_rows']
                     if r[1] in test_norms]
        if survivors:
            return fail('OVERLAP_REMAINS',
                        'p2b_gsm8k_train still overlaps GSM8K test at %s'
                        % survivors[:10])

    if args.gsm8k_train:
        state['inputs']['gsm8k_train'] = {
            'path': os.path.abspath(args.gsm8k_train),
            'sha256': sha256_path(args.gsm8k_train)}
        state['inputs']['gsm8k_test'] = {
            'path': os.path.abspath(args.gsm8k_test),
            'sha256': sha256_path(args.gsm8k_test)}
    if args.aime:
        state['inputs']['aime'] = {'path': os.path.abspath(args.aime),
                                   'sha256': sha256_path(args.aime)}

    receipt = {
        'schema': RECEIPT_SCHEMA,
        'created_utc': _now_utc(),
        'tool': 'p2b_pool_builder.py',
        'match_rule': ('normalized text equality (whitespace collapsed, '
                       'stripped, case-sensitive)'),
        'inputs': {k: {**v, 'rows': None} for k, v in state['inputs'].items()},
        'outputs': outputs,
        'removed': {
            'math500_overlap': {
                'count': len(state['math']['removed_ids']),
                'ids': state['math']['removed_ids'],
                'note': ('the paper README claims "none of them is in the '
                         'evaluation"; this count VERIFIES that claim '
                         'mechanically (0 = claim confirmed for MATH-500)')},
            'gsm8k_test_overlap': ({
                'count': len(state['gsm8k']['removed_ids']),
                'ids': state['gsm8k']['removed_ids']}
                if state['gsm8k'] else None),
        },
        'row_counts': {
            'math_train_in': state['math']['train_rows'],
            'math500_eval': state['math']['math500_rows'],
            'p2b_math_train_out': state['math']['p2b_rows'],
            'gsm8k_train_in': (state['gsm8k']['train_rows']
                               if state['gsm8k'] else None),
            'p2b_gsm8k_train_out': (state['gsm8k']['p2b_rows']
                                    if state['gsm8k'] else None),
            'aime_passthrough': (state['aime']['rows']
                                 if state['aime'] else None),
        },
        'disjointness': 'PASS',
        'their_pool_stats': {'values': THEIR_POOL_STATS,
                             'citation': THEIR_STATS_CITATION},
        'distributional_note': DISTRIBUTIONAL_NOTE,
        'pass_bar': False,
        'banner': ('P-2b pool construction evidence; the P-2 vs P-2b '
                   'runtime delta is COMPARABILITY DATA, never a pass bar '
                   '(PREREG-D)'),
    }
    receipt['inputs']['math_train']['rows'] = state['math']['train_rows']
    receipt['inputs']['math500']['rows'] = state['math']['math500_rows']
    receipt_path = os.path.join(out_dir, 'build_receipt.json')
    try:
        with open(receipt_path, 'w', encoding='utf-8') as fh:
            json.dump(receipt, fh, indent=2)
            fh.write('\n')
    except OSError as exc:
        return fail('OUT_UNWRITABLE', '%s (%s)' % (receipt_path, exc))
    print(json.dumps({
        'tool': 'p2b_pool_builder.py',
        'receipt': receipt_path,
        'outputs': {n: {'rows': o['rows'], 'sha256': o['sha256']}
                    for n, o in outputs.items()},
        'removed_math500_overlap': len(state['math']['removed_ids']),
        'disjointness': 'PASS',
        'pass_bar': False,
    }, indent=2))
    return EXIT_OK


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--math-train', required=True,
                    help='paper exp8 math_train.jsonl')
    ap.add_argument('--math500', required=True,
                    help='MATH-500 eval jsonl (problem/question per line)')
    ap.add_argument('--gsm8k-train', default=None,
                    help='paper exp8 gsm8k_train.jsonl (with --gsm8k-test)')
    ap.add_argument('--gsm8k-test', default=None,
                    help='GSM8K test jsonl (with --gsm8k-train)')
    ap.add_argument('--aime', default=None,
                    help='paper exp8 aime.jsonl (passthrough, digest only)')
    ap.add_argument('--out', required=True, help='output dir')
    ap.add_argument('--dry-run', action='store_true',
                    help='read-only plan incl. overlap counts; write nothing')
    args = ap.parse_args(argv)

    if bool(args.gsm8k_train) != bool(args.gsm8k_test):
        return fail('GSM8K_PAIR_INCOMPLETE',
                    '--gsm8k-train and --gsm8k-test must be supplied '
                    'together')
    for path, which in ((args.math_train, 'math_train'),):
        if not os.path.isfile(path):
            return fail('POOL_INPUT_MISSING', '%s %s absent' % (which, path))
    if args.gsm8k_train and not os.path.isfile(args.gsm8k_train):
        return fail('POOL_INPUT_MISSING',
                    'gsm8k_train %s absent' % args.gsm8k_train)
    if args.aime and not os.path.isfile(args.aime):
        return fail('POOL_INPUT_MISSING', 'aime %s absent' % args.aime)
    if not os.path.isfile(args.math500):
        return fail('MATH500_MISSING', args.math500)

    try:
        state = build(args)
        if args.dry_run:
            return run_dry(args, state)
        return run_real(args, state)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return EXIT_INPUT
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001 - named, never silent
        return fail('INTERNAL_ERROR', '%s: %s' % (type(exc).__name__, exc))


if __name__ == '__main__':
    sys.exit(main())
