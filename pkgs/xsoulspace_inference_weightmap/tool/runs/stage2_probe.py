#!/usr/bin/env python3
"""stage2_probe.py - G-3 STAGE-2 cell freeze (PREREG-G-STAGE2.md, FROZEN
2026-11-08). Base-behavior-conditioned selection, THEN freeze, THEN arms:
  1. render pathology candidates = first 48 rows of the paper exp8
     math_train.jsonl (digest-matched to the P-2b record abe7982b) with the
     PRACTICE_RENDER_SAME_AS_A2 convention (problem + '\\n' + MATH
     instruction, thinking chat template enable_thinking=True,
     NEWLINES_TO_SPACES single pass); render guards = the 12 G1 perm cells
     (chat + ' /no_think', same one-line pass);
  2. base greedy probe on the Qwen3.5-0.8B base snapshot (cap 1024
     pathology / 64 guards) under the device lock;
  3. select: pathology = FIRST 12 in order with cap_hit=true (SHORT_SELECTION
     named if fewer); guards = FIRST 8 in order where base PASSES
     (SHORT_GUARDS named if fewer);
  4. write tool/runs/cells_frozen_G3_stage2.json (group names REUSED:
     'G2' = pathology cap 1024, 'G0' = guard cap 64; lineage records
     pool digest + probe receipt path + selection rule) and print its
     sha256 — the sha that PREREG-G-STAGE2.md freezes and the arms verify.
No arm runs here. Power gate: AC-only unless --allow-battery (owner
override 2026-11-08)."""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone

_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
_PKG_DIR = os.path.dirname(os.path.dirname(_SCRIPT_DIR))
_PKGS_DIR = os.path.dirname(_PKG_DIR)
GENERATOR_DEFAULT = os.path.join(
    _PKGS_DIR, 'xsoulspace_inference_mlx_native', 'tool', 'nursery',
    'wm_qwen35_generate.py')
VENV_PYTHON_DEFAULT = os.path.expanduser('~/.local/share/wm-mlx/bin/python')
MATH_INSTRUCTION = ('Please reason step by step, and put your final answer '
                    'within \\boxed{}.')
POOL_SHA_EXPECT = ('abe7982b4d8c98394fe185fb152568a2'
                   'c784a4157a75fe42b9c01857e71f0c6e')
N_CAND = 48
SEL_PATHOLOGY = 12
SEL_GUARD = 8
CAP_PATHOLOGY = 1024
CAP_GUARD = 64
EXIT_OK, EXIT_INPUT = 0, 1

sys.path.insert(0, _SCRIPT_DIR)
import a3_lock  # noqa: E402

_LOCK_HELD = {'dir': None}


def release_lock_if_held():
    d = _LOCK_HELD['dir']
    if d:
        _LOCK_HELD['dir'] = None
        try:
            os.rmdir(d)
        except OSError:
            pass


def _sigterm(signum, frame):
    release_lock_if_held()
    print('S2_INTERRUPTED: signal %d' % signum, file=sys.stderr)
    sys.exit(128 + signum)


signal.signal(signal.SIGTERM, _sigterm)
signal.signal(signal.SIGINT, _sigterm)


def now():
    return datetime.now(timezone.utc).isoformat(timespec='seconds')


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def fail(code, detail):
    print('%s: %s' % (code, detail), file=sys.stderr)
    return EXIT_INPUT


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--model', required=True)
    ap.add_argument('--pool', required=True,
                    help='math_train.jsonl (digest-verified stage)')
    ap.add_argument('--out', required=True,
                    help='probe state dir ($TMPDIR/g3s2-artifacts/probe)')
    ap.add_argument('--lock-dir', default=os.path.join(
        os.environ.get('TMPDIR', '/tmp'), 'wm-device.lock'))
    ap.add_argument('--venv-python', default=VENV_PYTHON_DEFAULT)
    ap.add_argument('--allow-battery', action='store_true')
    args = ap.parse_args()

    snap = os.path.abspath(os.path.expanduser(args.model))
    if not os.path.isdir(snap):
        return fail('BASE_MODEL_MISSING', snap)
    pool_sha = sha256_file(args.pool)
    if pool_sha != POOL_SHA_EXPECT:
        return fail('POOL_DIGEST_DRIFT',
                    '%s is %s, P-2b record %s' % (args.pool, pool_sha,
                                                 POOL_SHA_EXPECT))
    pool = [json.loads(ln) for ln in open(args.pool, encoding='utf-8')
            if ln.strip()]
    cands = pool[:N_CAND]
    if len(cands) < N_CAND:
        return fail('POOL_SHORT', 'only %d rows' % len(cands))
    if not args.allow_battery and 'AC Power' not in subprocess.run(
            ['pmset', '-g', 'ps'], capture_output=True,
            text=True).stdout:
        return fail('POWER_GATE_BATTERY',
                    'AC-only gate stands; --allow-battery = owner override '
                    '2026-11-08')

    os.makedirs(args.out, exist_ok=True)
    try:
        from transformers import AutoTokenizer
    except ImportError:
        return fail('MLX_UNAVAILABLE', 'transformers unavailable')

    hf_tok = AutoTokenizer.from_pretrained(snap)
    cells_a3 = json.load(open(os.path.join(
        _SCRIPT_DIR, 'cells_frozen_A3.json'), encoding='utf-8'))
    guards_src = [c for c in cells_a3['cells']['G1']][:12]

    def write_prompts(name, items, render):
        p = os.path.join(args.out, 'prompts_%s.txt' % name)
        with open(p, 'w', encoding='utf-8') as fh:
            for it in items:
                fh.write(render(it).replace('\r', ' ')
                         .replace('\n', ' ') + '\n')
        return p

    def pathology_render(row):
        content = row['problem'] + '\n' + MATH_INSTRUCTION
        return hf_tok.apply_chat_template(
            [{'role': 'user', 'content': content}], tokenize=False,
            add_generation_prompt=True, enable_thinking=True)

    def guard_render(cell):
        return hf_tok.apply_chat_template(
            [{'role': 'user', 'content': cell['prompt'] + ' /no_think'}],
            tokenize=False, add_generation_prompt=True)

    p_path = write_prompts('pathology', cands, pathology_render)
    p_guard = write_prompts('guard', guards_src, guard_render)

    def gen(name, pf, cap):
        out = os.path.join(args.out, 'base_%s.jsonl' % name)
        if os.path.isfile(out) and sum(1 for ln in open(out,
                                       encoding='utf-8') if ln.strip()):
            return out
        waited, _ = a3_lock.acquire(args.lock_dir, attempts=a3_lock.V3_ATTEMPTS,
                                    sleep_s=a3_lock.V3_SLEEP_S)
        _LOCK_HELD['dir'] = args.lock_dir
        t0 = time.time()
        try:
            proc = subprocess.run([args.venv_python, '-I',
                                   GENERATOR_DEFAULT, '--model', snap,
                                   '--prompts', pf, '--max-tokens', str(cap),
                                   '--sampler', 'greedy', '--out', out],
                                  capture_output=True, text=True)
        finally:
            release_lock_if_held()
            time.sleep(3)
        if proc.returncode != 0:
            raise RuntimeError('GENERATOR_FAILED: %s rc=%d %r'
                               % (name, proc.returncode, proc.stderr[-300:]))
        with open(os.path.join(args.out, 'probe_log.jsonl'), 'a') as fh:
            fh.write(json.dumps({'kind': 'device_batch', 'what': name,
                                 'wall_ms': int((time.time() - t0) * 1000),
                                 'wall_ms_claim': False,
                                 'lock_wait_ms': waited, 'at': now()}) + '\n')
        return out

    try:
        out_path = gen('pathology', p_path, CAP_PATHOLOGY)
        out_guard = gen('guard', p_guard, CAP_GUARD)
    except RuntimeError as exc:
        code, _, detail = str(exc).partition(': ')
        return fail(code, detail)
    gen_rows = [json.loads(ln) for ln in open(out_path, encoding='utf-8')
                if ln.strip()]
    guard_rows = [json.loads(ln) for ln in open(out_guard, encoding='utf-8')
                  if ln.strip()]

    # selection: FIRST 12 pathology cap-hit in order; FIRST 8 guards passing
    # (guard pass = output_tokens < cap AND non-empty first line)
    sel_p = [cands[r['prompt_id']] for r in gen_rows if r['hit_token_limit']]
    sel_p = sel_p[:SEL_PATHOLOGY]
    sel_g = [guards_src[r['prompt_id']] for r in guard_rows
             if not r['hit_token_limit'] and r['output_text'].strip()]
    sel_g = sel_g[:SEL_GUARD]
    notes = {}
    if len(sel_p) < SEL_PATHOLOGY:
        notes['SHORT_SELECTION'] = len(sel_p)
    if len(sel_g) < SEL_GUARD:
        notes['SHORT_GUARDS'] = len(sel_g)

    cells_doc = {
        'artifact': 'cells_frozen_G3_stage2/v1',
        'status': 'FROZEN at probe time (PREREG-G-STAGE2.md §1)',
        'frozen_utc': now(),
        'lineage': {
            'pool': {'path': args.pool, 'sha256': pool_sha,
                     'note': 'paper exp8 math_train.jsonl; P-2b digest '
                             'matched'},
            'probe_receipt': args.out,
            'selection': 'pathology = first %d in file order with '
                         'base cap_hit=true @1024; guards = first %d G1 '
                         'cells with base pass @64 (headroom-checked)'
                         % (SEL_PATHOLOGY, SEL_GUARD),
            'notes': notes,
        },
        'cells': {
            'G2': [{'id': 's2-%s' % r['id'], 'group': 'G2',
                    'cap': CAP_PATHOLOGY, 'scorer': 'token_limit_cap',
                    'gold': None,
                    'prompt': r['problem'],
                    'lineage': {'source': 'exp8 math_train row',
                                'pool_sha256': pool_sha}}
                   for r in sel_p],
            'G0': [{'id': c['id'], 'group': 'G0', 'cap': CAP_GUARD,
                    'scorer': c['scorer'], 'gold': c['gold'],
                    'prompt': c['prompt'],
                    'lineage': {'source': 'cells_frozen_A3 G1 (headroom '
                                             'probe pass)'}}
                   for c in sel_g],
        },
    }
    out_cells = os.path.join(_SCRIPT_DIR, 'cells_frozen_G3_stage2.json')
    tmp = out_cells + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as fh:
        json.dump(cells_doc, fh, indent=1)
        fh.write('\n')
    os.replace(tmp, out_cells)
    print(json.dumps({'tool': 'stage2_probe.py', 'pathology': len(sel_p),
                      'guards': len(sel_g), 'notes': notes,
                      'cells_file': out_cells,
                      'cells_sha256': sha256_file(out_cells),
                      'base_pathology_hits':
                          sum(1 for r in gen_rows if r['hit_token_limit']),
                      'guard_pass':
                          sum(1 for r in guard_rows
                              if not r['hit_token_limit']
                              and r['output_text'].strip())}))
    return EXIT_OK


if __name__ == '__main__':
    sys.exit(main())
