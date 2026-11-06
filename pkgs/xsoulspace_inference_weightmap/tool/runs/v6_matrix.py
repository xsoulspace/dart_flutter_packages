#!/usr/bin/env python3
"""v6_matrix.py - V-6 drift re-certification matrix runner (PREREG-E, FROZEN).

PREREG-E V-6 axes (FROZEN): quant {bf16, 4bit-requant} x template {chat, raw}
x sampler {greedy, t=0.6} x engine {rust, python-mlx-lm}  = 16 cells.
KEY LAW (FROZEN): any certification-key field change => re-run the
pre-registered 3-cell subset; verdict stable within tolerance across the
matrix = PASS; else DRIFT_<field>_<cell> named per divergence. ENGINE AXIS:
runs only after the Rust qwen3_5 parity digest matches Python; if parity has
not landed, every rust cell is recorded PARITY_PENDING and the matrix runs
on the Python axis alone (PREREG-E). KILL CLAUSE: drift names never
invalidate the ledgered bf16/greedy/python certification - it stays keyed to
its receipt.

Cell id format (FROZEN): "<quant>__<template>__<sampler>__<engine>", e.g.
"bf16__chat__greedy__python-mlx-lm". Drift names: DRIFT_<FIELD>_<cell_id>.

FROZEN 3-CELL SUBSET (PREREG-E names the rule; THIS enumeration is its
machinery freeze - changing it requires a new prereg row, not an edit):
  1. bf16__chat__greedy__python-mlx-lm        (the reference certification)
  2. 4bit-requant__chat__greedy__python-mlx-lm (quant-axis neighbour)
  3. bf16__chat__t=0.6__python-mlx-lm          (sampler-axis neighbour)

Certification key (mirrors lib/src/receipts.dart CertificationKey, the
FROZEN Dart oracle; this comparison is planning machinery - the Dart
surface remains the reference): fields baseDigest, tokenizerDigest, quant,
samplerConfig (compared by canonical json: sorted keys, numeric TYPE
significant - 0 vs 0.0 is drift), engineRev, batteryDigest. Drifted-field
labels are the Dart fieldLabels verbatim: BASE_DIGEST, TOKENIZER_DIGEST,
QUANT, SAMPLER_CONFIG, ENGINE_REV, BATTERY_DIGEST.

DRIFT ATTRIBUTION (frozen): when the key law triggered (a key pair with
drifted fields was supplied), every divergence is named for EVERY drifted
key field x diverged cell (the cross product - a divergence cannot be
attributed to one of several simultaneous key changes, and under-naming
would hide drift). In sweep mode (no key pair / unchanged keys), FIELD is
the axis label(s) in which the cell differs from the reference cell
(QUANT / TEMPLATE / SAMPLER / ENGINE), same cross-product rule.

GENERATION CALLBACK (frozen contract = wm_qwen35_generate.py's actual
surface): per cell this runner invokes
  <generator-python> -I <generator> --model <model-dir-for-quant> \
      --prompts <prompts-file-for-template> --max-tokens <cap> \
      --sampler <"greedy" | cfg-json> --out <workdir>/cells/<cell>/gens.jsonl
Default generator path: the mlx_native nursery boundary script
pkgs/xsoulspace_inference_mlx_native/tool/nursery/wm_qwen35_generate.py
(PYTHON-BOUNDARY law; engine-side surface is owned there, never here).
Default generator-python: resolved via the sibling wm_pyenv.sh, fallback
$HOME/.local/share/wm-mlx/bin/python; override with --generator-python.
SAMPLER t=0.6 maps to {"temp": 0.6, "top_p": 0.95, "top_k": 20}; the
paper-protocol presence_penalty 1.5 has NO mlx-lm make_sampler key, so every
t=0.6 cell records NAMED protocol difference PRESENCE_PENALTY_UNSUPPORTED
(recorded, never silently dropped).

VERDICT CALLBACK (frozen battery delegation - this runner NEVER re-scores):
per cell, --verdict-cmd is executed under /bin/zsh -lc with env
  WM_CELL_ID, WM_CELL_SPEC, WM_CELL_GEN (generations jsonl),
  WM_CELL_VERDICT_OUT (path the command must write)
and must write {"cell": <id>, "verdict": "PASS"|"FAIL", "score": <finite
float>}. The frozen A4 battery/scorers live behind that command.

STABILITY CHECK (frozen; tolerance law identical to ws2_certify.py /
cross_engine.dart): a cell is STABLE iff its verdict EQUALS the reference
verdict for that cell AND |score - ref_score| <= max(abs, rel *
max(|score|, |ref_score|)). Cells absent from --reference-verdicts are
recorded UNREFERENCED (a new cell has no prior certification to be stable
against - recorded, never claimed PASS).

Usage:
  python3 -I tool/runs/v6_matrix.py --out <dir> [--dry-run] \
      [--key-before <key.json> --key-after <key.json>] \
      [--reference-verdicts <verdicts.jsonl>] [--tolerance <tol.json>] \
      [--prompts-chat <file> --prompts-raw <file>] \
      [--model-bf16 <dir> --model-4bit <dir>] \
      [--generator <path>] [--generator-python <path>] \
      [--rust-bin <path>] [--parity-receipt <json>] \
      [--verdict-cmd <shell>] [--max-tokens 32768] [--full-matrix]

--dry-run prints the plan (axes, selected cells + selection rule, key
comparison, generator/rust/parity status, per-cell command preview,
tolerance, drift-naming rule) as JSON on stdout, exit 0. Files are recorded
as exists true/false, never refused; supplied key/tolerance files ARE parsed
in dry-run (they select the cells). Nothing is written, no engine is run.

Exit codes (errors are NAMED on stderr as 'CODE: detail', never silent):
  0  ok (dry-run plan printed, or matrix run completed - a DRIFT finding is
     a measured verdict in the report, not a tool failure)
  1  named input/runtime error:
       USAGE_ERROR                 bad argv
       KEY_PAIR_INCOMPLETE         exactly one of --key-before/--key-after
       KEY_FILE_MALFORMED          key json unreadable / missing field /
                                   wrong type (MISSING_FIELD= / MALFORMED_)
       TOLERANCE_MISSING           real stability run without --tolerance
       TOLERANCE_INVALID           tolerance violates {abs, rel} finite >= 0
       REFERENCE_VERDICTS_MISSING  real run without --reference-verdicts
       REFERENCE_VERDICTS_MALFORMED bad verdict row schema
       VERDICT_CMD_MISSING         real run without --verdict-cmd
       GENERATOR_MISSING           generator script absent/not a file
       GENERATOR_PYTHON_MISSING    no generator python resolvable
       PROMPTS_FILE_MISSING        a template's prompts file is absent
       MODEL_DIR_MISSING           a quant's model dir is absent
       GENERATOR_FAILED            generator subprocess non-zero (cell, rc,
                                   stderr tail included)
       VERDICT_CMD_FAILED          verdict command non-zero (cell, rc)
       VERDICT_OUTPUT_MALFORMED    verdict json missing/invalid
       OUT_UNWRITABLE              --out cannot be created/written
       INTERNAL_ERROR              unexpected exception (class + message)
"""

import argparse
import hashlib
import json
import math
import os
import subprocess
import sys
from datetime import datetime, timezone

EXIT_OK = 0
EXIT_INPUT = 1

REPORT_SCHEMA = 'v6-matrix/v1'

# --- frozen axes (PREREG-E V-6) ---------------------------------------------
QUANTS = ('bf16', '4bit-requant')
TEMPLATES = ('chat', 'raw')
SAMPLERS = ('greedy', 't=0.6')
ENGINES = ('python-mlx-lm', 'rust')

SAMPLER_CONFIGS = {
    'greedy': 'greedy',
    't=0.6': {'temp': 0.6, 'top_p': 0.95, 'top_k': 20},
}
SAMPLER_PROTOCOL_NOTES = {
    't=0.6': ('PRESENCE_PENALTY_UNSUPPORTED: the paper protocol carries '
              'presence_penalty 1.5; mlx-lm make_sampler has no such key - '
              'recorded, never silently dropped'),
}

REFERENCE_CELL = 'bf16__chat__greedy__python-mlx-lm'
FROZEN_SUBSET_3 = (
    REFERENCE_CELL,
    '4bit-requant__chat__greedy__python-mlx-lm',
    'bf16__chat__t=0.6__python-mlx-lm',
)
FROZEN_SUBSET_NOTE = (
    'PREREG-E pre-registers the 3-cell subset rule; this enumeration is its '
    'machinery freeze (reference certification + quant neighbour + sampler '
    'neighbour). Changing it requires a new prereg row, not an edit.'
)

MAX_TOKENS_DEFAULT = 32768  # PREREG-D token cap (frozen)

KEY_FIELDS = ('baseDigest', 'tokenizerDigest', 'quant', 'samplerConfig',
              'engineRev', 'batteryDigest')
KEY_FIELD_LABELS = {
    'baseDigest': 'BASE_DIGEST',
    'tokenizerDigest': 'TOKENIZER_DIGEST',
    'quant': 'QUANT',
    'samplerConfig': 'SAMPLER_CONFIG',
    'engineRev': 'ENGINE_REV',
    'batteryDigest': 'BATTERY_DIGEST',
}
AXIS_FIELD_LABELS = {'quant': 'QUANT', 'template': 'TEMPLATE',
                     'sampler': 'SAMPLER', 'engine': 'ENGINE'}

KILL_CLAUSE = ('V-6 drift names do NOT invalidate the ledgered '
               'bf16/greedy/python certification - it stays keyed to its '
               'receipt (PREREG-E kill clauses)')

_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
_PKGS_DIR = os.path.dirname(os.path.dirname(os.path.dirname(_SCRIPT_DIR)))
GENERATOR_DEFAULT = os.path.join(
    _PKGS_DIR, 'xsoulspace_inference_mlx_native', 'tool', 'nursery',
    'wm_qwen35_generate.py')
WM_PYENV_DEFAULT = os.path.join(
    _PKGS_DIR, 'xsoulspace_inference_mlx_native', 'tool', 'nursery',
    'wm_pyenv.sh')
VENV_PYTHON_FALLBACK = os.path.expanduser('~/.local/share/wm-mlx/bin/python')


def fail(code, detail, exit_code=EXIT_INPUT):
    print('%s: %s' % (code, detail), file=sys.stderr)
    return exit_code


def _now_utc():
    return datetime.now(timezone.utc).isoformat(timespec='seconds')


def _sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(1 << 22), b''):
            h.update(chunk)
    return h.hexdigest()


def _canonical_json(obj):
    return json.dumps(obj, sort_keys=True, separators=(',', ':'))


def cell_id(quant, template, sampler, engine):
    return '__'.join((quant, template, sampler, engine))


def parse_cell(cid):
    parts = cid.split('__')
    if len(parts) != 4:
        raise ValueError('cell id %r is not quant__template__sampler__engine'
                         % cid)
    return dict(zip(('quant', 'template', 'sampler', 'engine'), parts))


def all_cells():
    return [cell_id(q, t, s, e)
            for q in QUANTS for t in TEMPLATES
            for s in SAMPLERS for e in ENGINES]


def sanitized(cid):
    return ''.join(ch if ch.isalnum() or ch in '-_' else '-' for ch in cid)


# --------------------------------------------------------------------------
# Certification key handling (mirrors receipts.dart CertificationKey)
# --------------------------------------------------------------------------

def load_key(path, which):
    """Load + shape-check a certification key json. NAMED RuntimeError."""
    try:
        with open(path, 'rb') as fh:
            raw = fh.read()
    except OSError as exc:
        raise RuntimeError('KEY_FILE_MALFORMED: %s key %s unreadable (%s)'
                           % (which, path, exc))
    try:
        key = json.loads(raw)
    except ValueError as exc:
        raise RuntimeError('KEY_FILE_MALFORMED: %s key %s not valid json '
                           '(%s)' % (which, path, exc))
    if not isinstance(key, dict):
        raise RuntimeError('KEY_FILE_MALFORMED: %s key %s is not an object'
                           % (which, path))
    for field in KEY_FIELDS:
        if field not in key:
            raise RuntimeError('KEY_FILE_MALFORMED: %s key MISSING_FIELD=%s'
                               % (which, field))
        v = key[field]
        if field == 'samplerConfig':
            if not isinstance(v, dict) \
                    or not all(isinstance(k, str) for k in v):
                raise RuntimeError('KEY_FILE_MALFORMED: %s key '
                                   'MALFORMED_FIELD=samplerConfig (object '
                                   'with string keys)' % which)
        elif not isinstance(v, str):
            raise RuntimeError('KEY_FILE_MALFORMED: %s key MALFORMED_FIELD='
                               '%s (expected String)' % (which, field))
    return key, raw


def key_drift(before, after):
    """NAMED drifted fields, in the frozen Dart fieldLabels order."""
    drifted = []
    for field in KEY_FIELDS:
        if field == 'samplerConfig':
            same = _canonical_json(before[field]) == _canonical_json(
                after[field])
        else:
            same = before[field] == after[field]
        if not same:
            drifted.append(KEY_FIELD_LABELS[field])
    return drifted


# --------------------------------------------------------------------------
# Tolerance (frozen law, identical to ws2_certify.py / cross_engine.dart)
# --------------------------------------------------------------------------

def load_tolerance(path):
    try:
        with open(path, 'rb') as fh:
            tol = json.loads(fh.read())
    except (OSError, ValueError) as exc:
        raise RuntimeError('TOLERANCE_INVALID: %s unreadable/not json (%s)'
                           % (path, exc))
    if not isinstance(tol, dict) or set(tol) != {'abs', 'rel'}:
        raise RuntimeError('TOLERANCE_INVALID: %s must have exactly keys '
                           '{abs, rel}' % path)
    for k in ('abs', 'rel'):
        v = tol[k]
        if not isinstance(v, (int, float)) or isinstance(v, bool) \
                or not math.isfinite(v) or v < 0:
            raise RuntimeError('TOLERANCE_INVALID: %s %s must be a finite '
                               'number >= 0' % (path, k))
    return {'abs': float(tol['abs']), 'rel': float(tol['rel'])}


def within_tolerance(actual, expected, tol):
    """Edge-INCLUSIVE ws2 law: |a-e| <= max(abs, rel*max(|a|,|e|))."""
    return abs(actual - expected) <= max(
        tol['abs'], tol['rel'] * max(abs(actual), abs(expected)))


# --------------------------------------------------------------------------
# Reference verdicts
# --------------------------------------------------------------------------

def load_reference_verdicts(path):
    try:
        with open(path, 'rb') as fh:
            text = fh.read().decode('utf-8')
    except (OSError, UnicodeDecodeError) as exc:
        raise RuntimeError('REFERENCE_VERDICTS_MISSING: %s (%s)'
                           % (path, exc))
    refs = {}
    for lineno, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except ValueError as exc:
            raise RuntimeError('REFERENCE_VERDICTS_MALFORMED: line %d not '
                               'valid json (%s)' % (lineno, exc))
        if not isinstance(row, dict) \
                or not isinstance(row.get('cell'), str) \
                or row.get('verdict') not in ('PASS', 'FAIL') \
                or not isinstance(row.get('score'), (int, float)) \
                or isinstance(row.get('score'), bool) \
                or not math.isfinite(row['score']):
            raise RuntimeError(
                'REFERENCE_VERDICTS_MALFORMED: line %d must be {"cell": str, '
                '"verdict": "PASS"|"FAIL", "score": finite number}' % lineno)
        refs[row['cell']] = {'verdict': row['verdict'],
                             'score': float(row['score'])}
    if not refs:
        raise RuntimeError('REFERENCE_VERDICTS_MISSING: %s has no rows'
                           % path)
    return refs


# --------------------------------------------------------------------------
# Cell selection (frozen key law)
# --------------------------------------------------------------------------

def select_cells(drifted_fields, full_matrix):
    if full_matrix:
        return list(all_cells()), (
            'full-matrix (16 cells; --full-matrix overrides the subset)')
    if drifted_fields:
        return list(FROZEN_SUBSET_3), (
            'key-change-3-cell-subset (KEY LAW: drifted fields %s => the '
            'pre-registered 3-cell subset re-runs)' % drifted_fields)
    return list(all_cells()), 'sweep (no key change supplied; full matrix)'


def axis_diff_fields(cid):
    """Axis labels in which a cell differs from the reference cell."""
    cell = parse_cell(cid)
    ref = parse_cell(REFERENCE_CELL)
    return [AXIS_FIELD_LABELS[axis] for axis in
            ('quant', 'template', 'sampler', 'engine')
            if cell[axis] != ref[axis]]


def resolve_generator_python(explicit):
    """--generator-python > wm_pyenv.sh resolution > venv fallback path."""
    if explicit:
        return explicit, 'explicit --generator-python'
    if os.path.isfile(WM_PYENV_DEFAULT):
        try:
            proc = subprocess.run(['bash', WM_PYENV_DEFAULT],
                                  capture_output=True, text=True, timeout=30)
            if proc.returncode == 0 and proc.stdout.strip():
                return proc.stdout.strip(), 'wm_pyenv.sh'
        except (OSError, subprocess.SubprocessError):
            pass
    return VENV_PYTHON_FALLBACK, 'fallback %s' % VENV_PYTHON_FALLBACK


def rust_engine_status(rust_bin, parity_path):
    """PREREG-E engine-axis gate: READY only with bin + matching parity."""
    if not rust_bin:
        return 'PARITY_PENDING', 'no --rust-bin supplied (rust engine is a placeholder path until parity lands)'
    if not os.path.isfile(rust_bin):
        return 'PARITY_PENDING', 'rust bin %s absent' % rust_bin
    if not parity_path:
        return 'PARITY_PENDING', 'no --parity-receipt supplied'
    try:
        with open(parity_path, 'rb') as fh:
            parity = json.loads(fh.read())
    except (OSError, ValueError) as exc:
        return 'PARITY_PENDING', 'parity receipt unreadable (%s)' % exc
    if not isinstance(parity, dict) or parity.get('match') is not True:
        return 'PARITY_PENDING', ('parity receipt does not record match=true '
                                  '(python_digest vs rust_digest)')
    return 'READY', 'parity digest matches python (receipt %s)' % parity_path


def cell_plan(cid, args, gen_python, gen_python_source):
    """The frozen per-cell invocation preview (dry-run + real share this)."""
    parts = parse_cell(cid)
    model = (args.model_bf16 if parts['quant'] == 'bf16'
             else args.model_4bit)
    prompts = (args.prompts_chat if parts['template'] == 'chat'
               else args.prompts_raw)
    sampler_arg = SAMPLER_CONFIGS[parts['sampler']]
    if not isinstance(sampler_arg, str):
        sampler_arg = json.dumps(sampler_arg, sort_keys=True)
    return {
        'cell': cid,
        'engine': parts['engine'],
        'model': model,
        'prompts': prompts,
        'max_tokens': args.max_tokens,
        'sampler': sampler_arg,
        'protocol_notes': ([SAMPLER_PROTOCOL_NOTES[parts['sampler']]]
                           if parts['sampler'] in SAMPLER_PROTOCOL_NOTES
                           else []),
        'generator_python': gen_python,
        'generator_python_source': gen_python_source,
    }


def run_dry(args, key_state):
    gen_python, gen_python_source = resolve_generator_python(
        args.generator_python)
    drifted = key_state['drifted_fields']
    cells, rule = select_cells(drifted or [], args.full_matrix)
    rust_status, rust_reason = rust_engine_status(args.rust_bin,
                                                  args.parity_receipt)
    tol = None
    if args.tolerance:
        try:
            tol = load_tolerance(args.tolerance)
        except RuntimeError as exc:
            print(str(exc), file=sys.stderr)
            return EXIT_INPUT
    plan = {
        'mode': 'dry-run',
        'tool': 'v6_matrix.py',
        'schema': REPORT_SCHEMA,
        'axes': {'quant': list(QUANTS), 'template': list(TEMPLATES),
                 'sampler': list(SAMPLERS), 'engine': list(ENGINES)},
        'cells_selected': {'rule': rule, 'count': len(cells),
                           'ids': cells},
        'frozen_subset_3': {'ids': list(FROZEN_SUBSET_3),
                            'note': FROZEN_SUBSET_NOTE},
        'reference_cell': REFERENCE_CELL,
        'key_comparison': key_state,
        'engine_policy': {
            'rule': ('rust cells run only after the parity digest matches '
                     'python; otherwise PARITY_PENDING and the matrix runs '
                     'on the python axis alone (PREREG-E)'),
            'rust_status': rust_status,
            'rust_reason': rust_reason,
            'rust_bin': args.rust_bin,
            'parity_receipt': args.parity_receipt,
        },
        'generator': {'path': args.generator,
                      'exists': os.path.isfile(args.generator)},
        'generator_python': {'path': gen_python, 'source': gen_python_source,
                             'exists': os.path.isfile(gen_python)},
        'tolerance': (tol if tol else
                      {'provided': False,
                       'law': '|a-e| <= max(abs, rel*max(|a|,|e|)) '
                              '(ws2_certify law; required for real runs)'}),
        'verdict_cmd': {'provided': args.verdict_cmd is not None,
                        'contract': ('zsh -lc with env WM_CELL_ID, '
                                     'WM_CELL_SPEC, WM_CELL_GEN, '
                                     'WM_CELL_VERDICT_OUT; must write '
                                     '{cell, verdict PASS|FAIL, score}')},
        'inputs': {
            'prompts_chat': {'path': args.prompts_chat,
                             'exists': bool(args.prompts_chat)
                             and os.path.isfile(args.prompts_chat)},
            'prompts_raw': {'path': args.prompts_raw,
                            'exists': bool(args.prompts_raw)
                            and os.path.isfile(args.prompts_raw)},
            'model_bf16': {'path': args.model_bf16,
                           'exists': bool(args.model_bf16)
                           and os.path.isdir(args.model_bf16)},
            'model_4bit': {'path': args.model_4bit,
                           'exists': bool(args.model_4bit)
                           and os.path.isdir(args.model_4bit)},
            'reference_verdicts': {
                'path': args.reference_verdicts,
                'exists': bool(args.reference_verdicts)
                and os.path.isfile(args.reference_verdicts)},
        },
        'max_tokens': args.max_tokens,
        'cell_invocations': [cell_plan(c, args, gen_python,
                                       gen_python_source) for c in cells],
        'drift_naming': ('DRIFT_<FIELD>_<cell_id>; FIELD = drifted key '
                         'fields (key law) or axis labels vs the reference '
                         'cell (sweep); cross product per divergence'),
        'stability_law': ('verdict equal AND score within tolerance vs the '
                          'reference verdicts; cells without a reference '
                          'row are UNREFERENCED, never claimed PASS'),
        'kill_clause': KILL_CLAUSE,
        'out': os.path.abspath(args.out),
        'note': 'plan only; no engine run; nothing written',
    }
    print(json.dumps(plan, indent=2))
    return EXIT_OK


def run_real(args, key_state):
    # --- refusals, in frozen order (each NAMED, none silent) ---------------
    if not os.path.isfile(args.generator):
        return fail('GENERATOR_MISSING',
                    'generation callback %s absent (default: the mlx_native '
                    'nursery boundary script; engine-side surface is owned '
                    'there)' % args.generator)
    gen_python, gen_python_source = resolve_generator_python(
        args.generator_python)
    if not os.path.isfile(gen_python):
        return fail('GENERATOR_PYTHON_MISSING',
                    'no generator python at %s (source: %s)'
                    % (gen_python, gen_python_source))
    if not args.reference_verdicts:
        return fail('REFERENCE_VERDICTS_MISSING',
                    'real runs compare against the ledgered certification; '
                    'pass --reference-verdicts <jsonl {cell, verdict, '
                    'score}>')
    if not args.verdict_cmd:
        return fail('VERDICT_CMD_MISSING',
                    'real runs delegate the frozen battery to --verdict-cmd '
                    '(this runner never re-scores)')
    if not args.tolerance:
        return fail('TOLERANCE_MISSING',
                    'stability needs the pre-registered tolerance json '
                    '{abs, rel} (never a default epsilon)')

    drifted = key_state['drifted_fields']
    cells, rule = select_cells(drifted or [], args.full_matrix)

    for cid in cells:
        parts = parse_cell(cid)
        if parts['engine'] == 'rust':
            continue  # gated separately below
        plan = cell_plan(cid, args, gen_python, gen_python_source)
        if not plan['prompts'] or not os.path.isfile(plan['prompts']):
            return fail('PROMPTS_FILE_MISSING',
                        'cell %s template %s prompts %r'
                        % (cid, parts['template'], plan['prompts']))
        if not plan['model'] or not os.path.isdir(plan['model']):
            return fail('MODEL_DIR_MISSING',
                        'cell %s quant %s model dir %r'
                        % (cid, parts['quant'], plan['model']))

    try:
        tol = load_tolerance(args.tolerance)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return EXIT_INPUT
    try:
        refs = load_reference_verdicts(args.reference_verdicts)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return EXIT_INPUT

    out_dir = os.path.abspath(args.out)
    try:
        os.makedirs(os.path.join(out_dir, 'cells'), exist_ok=True)
    except OSError as exc:
        return fail('OUT_UNWRITABLE', '%s (%s)' % (out_dir, exc))

    rust_status, rust_reason = rust_engine_status(args.rust_bin,
                                                  args.parity_receipt)

    cell_results = []
    for cid in cells:
        parts = parse_cell(cid)
        work = os.path.join(out_dir, 'cells', sanitized(cid))
        os.makedirs(work, exist_ok=True)
        result = {'cell': cid, **parts}

        if parts['engine'] == 'rust' and rust_status != 'READY':
            result.update({'status': 'PARITY_PENDING',
                           'parity_pending_reason': rust_reason,
                           'note': ('recorded, not run; matrix proceeds on '
                                    'the python axis alone (PREREG-E)')})
            cell_results.append(result)
            continue

        plan = cell_plan(cid, args, gen_python, gen_python_source)
        spec_path = os.path.join(work, 'spec.json')
        gens_path = os.path.join(work, 'gens.jsonl')
        verdict_path = os.path.join(work, 'verdict.json')
        spec = {'cell': cid, 'quant': parts['quant'],
                'template': parts['template'], 'sampler': parts['sampler'],
                'engine': parts['engine'], 'model': plan['model'],
                'prompts': plan['prompts'],
                'max_tokens': plan['max_tokens'],
                'sampler_config': SAMPLER_CONFIGS[parts['sampler']],
                'protocol_notes': plan['protocol_notes']}
        with open(spec_path, 'w', encoding='utf-8') as fh:
            json.dump(spec, fh, indent=2)

        if parts['engine'] == 'rust':
            gen_cmd = [args.rust_bin, '--spec', spec_path, '--out', gens_path]
        else:
            gen_cmd = [gen_python, '-I', args.generator,
                       '--model', plan['model'],
                       '--prompts', plan['prompts'],
                       '--max-tokens', str(plan['max_tokens']),
                       '--sampler', plan['sampler'],
                       '--out', gens_path]
        proc = subprocess.run(gen_cmd, capture_output=True, text=True)
        if proc.returncode != 0 or not os.path.isfile(gens_path):
            return fail('GENERATOR_FAILED',
                        'cell %s rc=%d stderr-tail=%r'
                        % (cid, proc.returncode, proc.stderr[-400:]))

        env = dict(os.environ)
        env.update({'WM_CELL_ID': cid, 'WM_CELL_SPEC': spec_path,
                    'WM_CELL_GEN': gens_path,
                    'WM_CELL_VERDICT_OUT': verdict_path})
        vproc = subprocess.run(['/bin/zsh', '-lc', args.verdict_cmd],
                               capture_output=True, text=True, env=env)
        if vproc.returncode != 0:
            return fail('VERDICT_CMD_FAILED',
                        'cell %s rc=%d stderr-tail=%r'
                        % (cid, vproc.returncode, vproc.stderr[-400:]))
        try:
            with open(verdict_path, 'rb') as fh:
                vj = json.loads(fh.read())
            if not isinstance(vj, dict) or vj.get('cell') != cid \
                    or vj.get('verdict') not in ('PASS', 'FAIL') \
                    or not isinstance(vj.get('score'), (int, float)) \
                    or isinstance(vj.get('score'), bool) \
                    or not math.isfinite(vj['score']):
                raise ValueError('bad shape %r' % (vj,))
        except (OSError, ValueError) as exc:
            return fail('VERDICT_OUTPUT_MALFORMED',
                        'cell %s verdict json %s (%s)'
                        % (cid, verdict_path, exc))

        ref = refs.get(cid)
        if ref is None:
            stability = 'UNREFERENCED'
        else:
            stable = (vj['verdict'] == ref['verdict']
                      and within_tolerance(float(vj['score']),
                                           ref['score'], tol))
            stability = 'STABLE' if stable else 'DIVERGED'
        result.update({
            'status': 'RUN',
            'verdict': vj['verdict'],
            'score': float(vj['score']),
            'reference': ref,
            'stability': stability,
            'protocol_notes': plan['protocol_notes'],
            'artifacts': {'spec': spec_path, 'generations': gens_path,
                          'verdict': verdict_path},
        })
        cell_results.append(result)

    # --- drift naming (frozen cross-product rule) --------------------------
    drift_names = []
    for res in cell_results:
        if res.get('stability') != 'DIVERGED':
            continue
        if drifted:
            fields = drifted
        else:
            fields = axis_diff_fields(res['cell']) or ['MATRIX']
        for field in fields:
            drift_names.append('DRIFT_%s_%s' % (field, res['cell']))

    diverged = [r['cell'] for r in cell_results
                if r.get('stability') == 'DIVERGED']
    referenced = [r for r in cell_results if r.get('reference') is not None]
    if diverged:
        matrix_verdict = 'DRIFT'
    elif referenced and all(r['stability'] == 'STABLE' for r in referenced):
        matrix_verdict = 'STABLE_PASS'
    else:
        matrix_verdict = 'UNREFERENCED'  # ran, nothing comparable - recorded

    report = {
        'schema': REPORT_SCHEMA,
        'created_utc': _now_utc(),
        'tool': 'v6_matrix.py',
        'axes': {'quant': list(QUANTS), 'template': list(TEMPLATES),
                 'sampler': list(SAMPLERS), 'engine': list(ENGINES)},
        'cells_selected': {'rule': rule, 'ids': cells},
        'key_comparison': key_state,
        'tolerance': tol,
        'engine_policy': {'rust_status': rust_status,
                          'rust_reason': rust_reason},
        'cells': cell_results,
        'drift_names': drift_names,
        'matrix_verdict': matrix_verdict,
        'matrix_verdict_rule': ('STABLE_PASS iff every referenced cell is '
                                'STABLE; any DIVERGED cell => DRIFT with '
                                'DRIFT_<FIELD>_<cell> names; no comparable '
                                'reference rows => UNREFERENCED (recorded, '
                                'never claimed PASS)'),
        'kill_clause': KILL_CLAUSE,
        'generator': {'path': args.generator,
                      'python': gen_python,
                      'python_source': gen_python_source},
        'max_tokens': args.max_tokens,
    }
    report_path = os.path.join(out_dir, 'v6_report.json')
    try:
        with open(report_path, 'w', encoding='utf-8') as fh:
            json.dump(report, fh, indent=2)
            fh.write('\n')
    except OSError as exc:
        return fail('OUT_UNWRITABLE', '%s (%s)' % (report_path, exc))
    print(json.dumps({
        'tool': 'v6_matrix.py',
        'report': report_path,
        'matrix_verdict': matrix_verdict,
        'drift_names': drift_names,
        'cells_run': sum(1 for r in cell_results if r.get('status') == 'RUN'),
        'cells_parity_pending': sum(1 for r in cell_results
                                    if r.get('status') == 'PARITY_PENDING'),
    }, indent=2))
    return EXIT_OK


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--out', required=True, help='output dir (report + cells)')
    ap.add_argument('--dry-run', action='store_true',
                    help='print the plan; run nothing; write nothing')
    ap.add_argument('--key-before', default=None,
                    help='certification key json (with --key-after)')
    ap.add_argument('--key-after', default=None,
                    help='certification key json (with --key-before)')
    ap.add_argument('--reference-verdicts', default=None,
                    help='jsonl {cell, verdict PASS|FAIL, score} from the '
                         'ledgered certification')
    ap.add_argument('--tolerance', default=None,
                    help='pre-registered tolerance json {abs, rel}')
    ap.add_argument('--prompts-chat', default=None,
                    help='chat-template prompts file (one per line)')
    ap.add_argument('--prompts-raw', default=None,
                    help='raw prompts file (one per line)')
    ap.add_argument('--model-bf16', default=None, help='bf16 model dir')
    ap.add_argument('--model-4bit', default=None,
                    help='4bit-requant (of the edited mirror) model dir')
    ap.add_argument('--generator', default=GENERATOR_DEFAULT,
                    help='generation callback script (default: mlx_native '
                         'nursery wm_qwen35_generate.py)')
    ap.add_argument('--generator-python', default=None,
                    help='python that runs the generator (default: '
                         'wm_pyenv.sh resolution, fallback wm-mlx venv)')
    ap.add_argument('--rust-bin', default=None,
                    help='rust engine binary (placeholder until parity '
                         'lands; absent => PARITY_PENDING)')
    ap.add_argument('--parity-receipt', default=None,
                    help='json {python_digest, rust_digest, match} from '
                         'wm_qwen35_digest.py parity')
    ap.add_argument('--verdict-cmd', default=None,
                    help='zsh -lc command running the frozen battery per '
                         'cell (env WM_CELL_ID/WM_CELL_SPEC/WM_CELL_GEN/'
                         'WM_CELL_VERDICT_OUT)')
    ap.add_argument('--max-tokens', type=int, default=MAX_TOKENS_DEFAULT,
                    help='generation cap (frozen default %d, PREREG-D)'
                         % MAX_TOKENS_DEFAULT)
    ap.add_argument('--full-matrix', action='store_true',
                    help='run all 16 cells instead of the key-law subset')
    args = ap.parse_args(argv)

    if bool(args.key_before) != bool(args.key_after):
        return fail('KEY_PAIR_INCOMPLETE',
                    '--key-before and --key-after must be supplied together')
    if args.max_tokens < 1:
        return fail('USAGE_ERROR',
                    '--max-tokens must be >= 1, got %d' % args.max_tokens)

    key_state = {'provided': False, 'drifted_fields': None,
                 'note': 'no key pair supplied (sweep mode)'}
    if args.key_before:
        try:
            before, raw_b = load_key(args.key_before, 'before')
            after, raw_a = load_key(args.key_after, 'after')
        except RuntimeError as exc:
            print(str(exc), file=sys.stderr)
            return EXIT_INPUT
        drifted = key_drift(before, after)
        key_state = {
            'provided': True,
            'before': {'path': os.path.abspath(args.key_before),
                       'sha256': hashlib.sha256(raw_b).hexdigest()},
            'after': {'path': os.path.abspath(args.key_after),
                      'sha256': hashlib.sha256(raw_a).hexdigest()},
            'drifted_fields': drifted,
            'key_changed': bool(drifted),
            'note': ('KEY_UNCHANGED: the key law does not trigger; cell '
                     'selection falls through to sweep/full-matrix'
                     if not drifted else
                     'key law triggered: the frozen 3-cell subset re-runs'),
        }

    try:
        if args.dry_run:
            return run_dry(args, key_state)
        return run_real(args, key_state)
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001 - named, never silent
        return fail('INTERNAL_ERROR', '%s: %s' % (type(exc).__name__, exc))


if __name__ == '__main__':
    sys.exit(main())
