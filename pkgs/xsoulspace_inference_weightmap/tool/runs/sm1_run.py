#!/usr/bin/env python3
"""sm1_run.py - SM-1 sparse-mask proposer pilot (PREREG-SM1.md, FROZEN
2026-11-08). Question: does heatmap-guided column selection find
loop-reducing edits faster than random at matched budget? Descriptive pilot;
NO certification; improving samples = CANDIDATE repairs for a future prereg.

SUBCOMMANDS:
  probe  (device, AC-gated): captures (FROZEN capture_activations.py) ->
         directions (FROZEN a3_propose.py) -> column scores
         (G3_SM1_HEATMAP_COLUMN_PROJECTION) -> base fitness probe ->
         FITNESS-BLIND sample pre-draw -> sm1_state.json (digest-recorded
         freeze point).
  run    (device, AC-gated): consume frozen samples; per sample:
         apply_delta -> make_mirror -> greedy gens on fitness+guard cells ->
         journaled row; manifest resume; determinism re-measure of the best
         GUIDED sample.
  verdict (CPU): classes per PREREG-SM1 §4 -> receipts/SM1-run.jsonl
         (hash-chained, python chain writer per ledger law) + summary md.

House laws: device lock v3 (a3_lock.py); POWER GATE AC-only (poll 300s x12
then POWER_GATE_BATTERY_WAIT_EXHAUSTED stop row); PYTHONDONTWRITEBYTECODE=1;
scratch $TMPDIR; frozen tools reused via subprocess, never edited; named
errors; PARTIAL-with-denominator is a verdict; no commit; no VERDICTS.md.
"""

import argparse
import hashlib
import json
import os
import random
import signal
import struct
import subprocess
import sys
import time
from datetime import datetime, timezone

_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
_PKG_DIR = os.path.dirname(os.path.dirname(_SCRIPT_DIR))
_PKGS_DIR = os.path.dirname(_PKG_DIR)

# --- frozen constants (PREREG-SM1 §1-§3) -----------------------------------
SEED_DEFAULT = 20261108
K_COLS = 8
SCALE = 4.8
LAYERS = ('15', '19')
N_GUIDED, N_RANDOM, N_SHUFFLED = 12, 12, 6
FITNESS_N = 6            # first 6 G2 cells, cap 256 (base = 6/6 cap-hit)
GUARD_N = 4              # first 4 G1 label/string cells, cap 64
CAP_LOOP, CAP_GUARD = 256, 64
TENSOR_TEMPLATE = 'model.language_model.layers.%s.mlp.down_proj.weight'
SCORERS_OK = ('label_first_line', 'string_first_line')
MATH_INSTRUCTION = ('Please reason step by step, and put your final answer '
                    'within \\boxed{}.')
SHARD_REL = 'model.safetensors'
EXIT_OK, EXIT_INPUT, EXIT_DEP = 0, 1, 2

EVAL_TOOLS = os.path.join(_PKG_DIR, 'tool', 'eval')
CAPTURE_TOOL = os.path.join(EVAL_TOOLS, 'capture_activations.py')
APPLY_DELTA_TOOL = os.path.join(EVAL_TOOLS, 'apply_delta.py')
PROPOSE_TOOL = os.path.join(_SCRIPT_DIR, 'a3_propose.py')
MAKE_MIRROR_TOOL = os.path.join(_SCRIPT_DIR, 'make_mirror.py')
GENERATOR_DEFAULT = os.path.join(
    _PKGS_DIR, 'xsoulspace_inference_mlx_native', 'tool', 'nursery',
    'wm_qwen35_generate.py')
VENV_PYTHON_DEFAULT = os.path.expanduser('~/.local/share/wm-mlx/bin/python')

sys.path.insert(0, _SCRIPT_DIR)
import a3_lock  # noqa: E402

_LOCK_HELD = {'dir': None}


def fail(code, detail, rc=EXIT_INPUT):
    print('%s: %s' % (code, detail), file=sys.stderr)
    return rc


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
    print('SM1_INTERRUPTED: signal %d (lock released)' % signum,
          file=sys.stderr)
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


def sha256_text(s):
    return hashlib.sha256(s.encode('utf-8')).hexdigest()


def canonical(obj):
    return json.dumps(obj, sort_keys=True, separators=(',', ':'))


def atomic_write_json(path, obj):
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as fh:
        json.dump(obj, fh, indent=1)
        fh.write('\n')
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, path)


def append_jsonl(path, row):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'a', encoding='utf-8') as fh:
        fh.write(json.dumps(row, ensure_ascii=False, sort_keys=False) + '\n')
        fh.flush()
        os.fsync(fh.fileno())


def append_manifest(state_dir, row):
    append_jsonl(os.path.join(state_dir, 'manifest.jsonl'), row)


def power_facts():
    try:
        ps = subprocess.run(['pmset', '-g', 'ps'], capture_output=True,
                            text=True, timeout=15)
        return ps.stdout.splitlines()[0].strip().strip("'") \
            if ps.stdout else 'unknown'
    except (OSError, subprocess.SubprocessError):
        return 'unknown'


def on_ac_power():
    return 'AC Power' in power_facts()


def ac_gate_wait(log):
    """POWER gate: AC-only device batches; poll 300s x12 then named stop."""
    for attempt in range(12):
        if on_ac_power():
            return True
        print('POWER_WAIT: attempt %d/12, sleeping 300s (battery: %s)'
              % (attempt + 1, power_facts()), file=log)
        time.sleep(300)
    return False


def add_device_time(state_dir, seconds, what):
    path = os.path.join(state_dir, 'device_time.json')
    data = {'total_device_wall_s': 0.0, 'segments': []}
    if os.path.isfile(path):
        try:
            data = json.load(open(path, encoding='utf-8'))
        except (OSError, ValueError):
            pass
    data['total_device_wall_s'] = round(
        data.get('total_device_wall_s', 0.0) + seconds, 3)
    data['segments'].append({'what': what, 's': round(seconds, 1),
                             'at': now()})
    atomic_write_json(path, data)


def run_locked(lock_dir, argv, state_dir, what):
    waited_ms, interval = a3_lock.acquire(
        lock_dir, attempts=a3_lock.V3_ATTEMPTS, sleep_s=a3_lock.V3_SLEEP_S)
    _LOCK_HELD['dir'] = lock_dir
    p0 = power_facts()
    t0 = time.time()
    try:
        proc = subprocess.run(argv, capture_output=True, text=True)
    finally:
        wall = time.time() - t0
        release_lock_if_held()
        time.sleep(3)
    add_device_time(state_dir, wall, what)
    append_manifest(state_dir, {
        'kind': 'device_batch', 'what': what, 'argv': argv,
        'exit': proc.returncode, 'wall_ms': int(wall * 1000),
        'wall_ms_claim': False, 'lock_wait_ms': waited_ms,
        'lock_retry_interval_s': interval,
        'power_start': p0, 'power_end': power_facts(), 'at': now()})
    return proc


def run_tool(argv, receipt, what):
    t0 = time.time()
    proc = subprocess.run(argv, capture_output=True, text=True)
    receipt.setdefault('tool_steps', []).append({
        'what': what, 'argv': argv, 'exit': proc.returncode,
        'wall_ms': int((time.time() - t0) * 1000)})
    return proc


# --------------------------------------------------------------------------
# FROZEN pure parts (unit-tested, no mlx)
# --------------------------------------------------------------------------

def draw_guided(scores, k, rng):
    """Columns sampled without replacement, prob ∝ score (zero-score
    excluded). Deterministic given (scores, rng seed)."""
    items = [(c, s) for c, s in enumerate(scores) if s > 0]
    if len(items) < k:
        raise RuntimeError('DRAW_FAILED: only %d nonzero scores < k=%d'
                           % (len(items), k))
    cols = []
    pool = dict(items)
    for _ in range(k):
        total = sum(pool.values())
        x = rng.random() * total
        acc = 0.0
        for c in sorted(pool):
            acc += pool[c]
            if acc >= x:
                cols.append(c)
                del pool[c]
                break
    return sorted(cols)


def draw_random(n_cols, k, rng):
    return sorted(rng.sample(range(n_cols), k))


def shuffled_scores(scores, seed):
    """Fixed seeded permutation of the column->score pairing (chance
    control): permute the SCORE multiset across columns."""
    rng = random.Random(seed)
    vals = list(scores)
    rng.shuffle(vals)
    return vals


def sample_columns(scores, n_cols, seed):
    """The 30 frozen draws: 12 guided / 12 random / 6 shuffled. Returns
    [{arm, idx, seed, columns}]. Fitness-blind by construction (called only
    from probe, before any fitness measurement)."""
    out = []
    for i in range(N_GUIDED):
        out.append({'arm': 'GUIDED', 'idx': i, 'seed': seed * 1000 + i,
                    'columns': draw_guided(scores, K_COLS,
                                           random.Random(seed * 1000 + i))})
    for i in range(N_RANDOM):
        out.append({'arm': 'RANDOM', 'idx': i,
                    'seed': seed * 1000 + 100000 + i,
                    'columns': draw_random(n_cols, K_COLS,
                                           random.Random(seed * 1000
                                                         + 100000 + i))})
    sh = shuffled_scores(scores, seed * 7 + 1)
    for i in range(N_SHUFFLED):
        out.append({'arm': 'SHUFFLED', 'idx': i,
                    'seed': seed * 1000 + 200000 + i,
                    'columns': draw_guided(sh, K_COLS,
                                           random.Random(seed * 1000
                                                         + 200000 + i))})
    return out


def read_down_proj(base_dir, layer):
    """Minimal safetensors reader for one tensor (BF16/F16/F32 -> floats)."""
    shard = os.path.join(base_dir, SHARD_REL)
    if not os.path.isfile(shard):
        cands = [n for n in sorted(os.listdir(base_dir))
                 if n.endswith('.safetensors')]
        if not cands:
            raise RuntimeError('TENSOR_READ_FAILED: no safetensors in %s'
                               % base_dir)
        shard = os.path.join(base_dir, cands[0])
    with open(shard, 'rb') as fh:
        n = struct.unpack('<Q', fh.read(8))[0]
        header = json.loads(fh.read(n))
        meta = header.get(TENSOR_TEMPLATE % layer)
        if meta is None:
            raise RuntimeError('TENSOR_READ_FAILED: %s absent from %s'
                               % (TENSOR_TEMPLATE % layer, shard))
        dtype, shape, (a, b) = meta['dtype'], meta['shape'], meta['data_offsets']
        fh.seek(8 + a)
        raw = fh.read(b - a)
    rows, cols = shape
    if dtype == 'BF16':
        vals = [struct.unpack_from('<H', raw, i * 2)[0]
                for i in range(rows * cols)]
        # bf16 -> f32: place the 16 bits into the high half of an f32
        vals = [struct.unpack('<f', struct.pack('<I', v << 16))[0]
                for v in vals]
    elif dtype == 'F16':
        vals = [struct.unpack_from('<e', raw, i * 2)[0]
                for i in range(rows * cols)]
    elif dtype == 'F32':
        vals = [struct.unpack_from('<f', raw, i * 4)[0]
                for i in range(rows * cols)]
    else:
        raise RuntimeError('TENSOR_READ_FAILED: dtype %s unsupported' % dtype)
    return vals, rows, cols, shard


def column_scores(base_dir, layer, direction):
    """G3_SM1_HEATMAP_COLUMN_PROJECTION: score(c) = |sum_r W[r,c]*dir[r]|."""
    vals, rows, cols, shard = read_down_proj(base_dir, layer)
    if len(direction) != rows:
        raise RuntimeError('HEATMAP_FAILED: direction dim %d != rows %d'
                           % (len(direction), rows))
    scores = [0.0] * cols
    for r in range(rows):
        d = direction[r]
        if d == 0.0:
            continue
        base = r * cols
        for c in range(cols):
            scores[c] += d * vals[base + c]
    return [abs(s) for s in scores], shard


def score_first_line(cell, output):
    """A3-frozen first-line scorers (copied verbatim conventions from
    a3_score.dart; numeric_final excluded from the guard bank by PREREG-SM1
    SCORERS_OK)."""
    o = output
    if o.lstrip().startswith('<think>'):
        parts = o.split('</think>')
        if len(parts) > 1:
            o = ''.join(parts[1:])
    fl = None
    for ln in o.split('\n'):
        if ln.strip():
            fl = ln.strip()
            break
    if fl is None:
        return False
    gold = cell['gold']
    if cell['scorer'] == 'label_first_line':
        return fl.lower() == gold.lower()
    s = fl
    quotes = '"\'`'
    if len(s) >= 2 and s[0] == s[-1] and s[0] in quotes:
        s = s[1:-1]
    if not gold.endswith('.') and s.endswith('.'):
        s = s[:-1]
    return s == gold


def fitness_from_rows(loop_rows):
    """Sample fitness = cells improved = FITNESS_N - cap-hits (PREREG-SM1
    §3)."""
    hits = sum(1 for r in loop_rows if r['cap_hit'])
    return FITNESS_N - hits


def verdict_classes(manifest_rows, base_loop_hits, det_ok, det_present):
    """PREREG-SM1 §4 (pure)."""
    arms = {}
    for r in manifest_rows:
        if r['kind'] == 'sample_complete':
            arms.setdefault(r['arm'], []).append(r['fitness'])
    out = {'per_arm': {a: {'n': len(v), 'best': max(v) if v else None,
                           'mean': (sum(v) / len(v)) if v else None}
                       for a, v in arms.items()},
           'base_loop_hits': base_loop_hits}
    g, rnd, sh = arms.get('GUIDED', []), arms.get('RANDOM', []), \
        arms.get('SHUFFLED', [])
    if det_present and not det_ok:
        out['verdict'] = 'DETERMINISM_DRIFT'
    elif not g:
        out['verdict'] = 'PARTIAL_WITH_DENOMINATOR_NO_GUIDED_SAMPLES'
    elif not any(f > (FITNESS_N - base_loop_hits) for f in g) \
            and not any(f > (FITNESS_N - base_loop_hits) for f in rnd):
        out['verdict'] = 'NO_SAMPLE_IMPROVES'
    elif g and rnd and max(g) >= max(rnd) + 1 \
            and (sum(g) / len(g)) > (sum(rnd) / len(rnd)):
        out['verdict'] = 'GUIDED_BEATS_RANDOM'
        out['chance_control'] = (
            'CHANCE_CONTROL_LEAK' if sh and max(sh) >= max(g) + 0
            and max(sh) >= max(g) else 'CHANCE_CONTROL_OK')
    else:
        out['verdict'] = 'NO_SIGNAL'
        out['chance_control'] = ('CHANCE_CONTROL_LEAK'
                                 if sh and g and max(sh) >= max(g)
                                 else 'CHANCE_CONTROL_OK') if sh else None
    return out


# ---- chain writer (python twin of lib/src/ledger.dart law) ---------------

def chain_append(path, kind, payload):
    rows = []
    if os.path.isfile(path):
        with open(path, 'r', encoding='utf-8') as fh:
            rows = [json.loads(ln) for ln in fh if ln.strip()]
    seq = len(rows)
    prev = rows[-1]['digest'] if rows else '0' * 64
    ts = now()
    digest = hashlib.sha256(
        (prev + canonical({'seq': seq, 'ts': ts, 'kind': kind,
                           'payload': payload})).encode('utf-8')).hexdigest()
    append_jsonl(path, {'seq': seq, 'ts': ts, 'kind': kind,
                        'payload': payload, 'prevDigest': prev,
                        'digest': digest})
    return digest


def chain_verify(path):
    rows = []
    if os.path.isfile(path):
        with open(path, 'r', encoding='utf-8') as fh:
            rows = [json.loads(ln) for ln in fh if ln.strip()]
    prev = '0' * 64
    for i, r in enumerate(rows):
        want = hashlib.sha256(
            (prev + canonical({'seq': i, 'ts': r['ts'], 'kind': r['kind'],
                               'payload': r['payload']})).encode('utf-8')
        ).hexdigest()
        if r['prevDigest'] != prev or r['digest'] != want:
            return 'CHAIN_BROKEN_AT=%d' % i
        prev = r['digest']
    return 'CHAIN_INTACT(%d rows)' % len(rows)


# --------------------------------------------------------------------------
# Cells
# --------------------------------------------------------------------------

def load_banks():
    path = os.path.join(_SCRIPT_DIR, 'cells_frozen_A3.json')
    data = json.load(open(path, encoding='utf-8'))
    cells = data['cells']
    loop = [c for c in cells['G2']][:FITNESS_N]
    guard_pool = [c for c in cells['G1']
                  if c.get('scorer') in SCORERS_OK][:GUARD_N]
    if len(loop) < FITNESS_N:
        raise RuntimeError('BANK_SHORT: G2 loop bank %d < %d'
                           % (len(loop), FITNESS_N))
    if len(guard_pool) < GUARD_N:
        raise RuntimeError('BANK_SHORT: G1 guard pool %d < %d'
                           % (len(guard_pool), GUARD_N))
    return loop, guard_pool, data['surface']['template']


def render_prompt(hf_tok, template_note, prompt):
    del template_note
    return hf_tok.apply_chat_template(
        [{'role': 'user', 'content': prompt + ' /no_think'}],
        add_generation_prompt=True, tokenize=False)


# --------------------------------------------------------------------------
# probe (device, AC-gated)
# --------------------------------------------------------------------------

def cmd_probe(args, log):
    if not ac_gate_wait(log):
        append_manifest(args.out, {'kind': 'stop', 'reason':
                                   'POWER_GATE_BATTERY_WAIT_EXHAUSTED',
                                   'at': now()})
        return fail('POWER_GATE_BATTERY_WAIT_EXHAUSTED',
                    'no AC within the polling budget; state is resume-safe')
    snap = os.path.abspath(os.path.expanduser(args.model))
    if not os.path.isdir(snap):
        return fail('BASE_MODEL_MISSING', snap)
    loop, guard_pool, _tpl = load_banks()
    os.makedirs(args.out, exist_ok=True)

    try:
        from transformers import AutoTokenizer
    except ImportError:
        return fail('MLX_UNAVAILABLE', 'transformers unavailable in venv',
                    EXIT_DEP)
    hf_tok = AutoTokenizer.from_pretrained(snap)

    def prompts_file(cells, name):
        p = os.path.join(args.out, 'prompts_%s.txt' % name)
        with open(p, 'w', encoding='utf-8') as fh:
            for c in cells:
                r = hf_tok.apply_chat_template(
                    [{'role': 'user',
                      'content': c['prompt'] + ' /no_think'}],
                    add_generation_prompt=True, tokenize=False)
                fh.write(r.replace('\r', ' ').replace('\n', ' ') + '\n')
        return p

    receipt = {'schema': 'sm1-probe/v1', 'model': snap,
               'created_utc': now(), 'tool_steps': [],
               'device_batches': []}
    # captures (loop + neutral banks)
    banks = {}
    for name, cells in (('loop', loop), ('neutral', guard_pool)):
        pf = prompts_file(cells, name)
        out = os.path.join(args.out, 'cap_%s.json' % name)
        if not os.path.isfile(out):
            proc = run_locked(args.lock_dir,
                              [args.venv_python, '-I', CAPTURE_TOOL,
                               '--model', snap, '--prompts', pf,
                               '--layers', ','.join(LAYERS), '--out', out],
                              args.out, 'capture_%s' % name)
            if proc.returncode != 0:
                return fail('CAPTURE_FAILED',
                            '%s rc=%d %r' % (name, proc.returncode,
                                             proc.stderr[-300:]))
        banks[name] = out
    # directions via FROZEN proposer
    rec_path = os.path.join(args.out, 'recovered.json')
    proc = run_tool([sys.executable, '-I', PROPOSE_TOOL,
                     '--cap-loop', banks['loop'], '--cap-neutral',
                     banks['neutral'], '--out', rec_path], receipt,
                    'a3_propose')
    if proc.returncode != 0:
        return fail('PROPOSE_FAILED', proc.stderr[-300:])
    recovered = json.load(open(rec_path, encoding='utf-8'))
    # column scores + sample pre-draw
    scores, samples = {}, None
    for layer in LAYERS:
        d = recovered['layers'][layer]['direction']
        sc, shard = column_scores(snap, layer, d)
        scores[layer] = {'scores': sc, 'shard': shard,
                         'sha256': sha256_text(canonical(sc))}
    # fitness base probe: 6 loop cells (expect cap-hits) + 4 guard cells
    base_dir = os.path.join(args.out, 'base_probe')
    os.makedirs(base_dir, exist_ok=True)
    loop_pf = prompts_file(loop, 'fitness')
    guard_pf = prompts_file(guard_pool, 'guard')
    gens = {}
    for name, cells, pf, cap in (('loop', loop, loop_pf, CAP_LOOP),
                                 ('guard', guard_pool, guard_pf, CAP_GUARD)):
        out = os.path.join(base_dir, 'base_%s.jsonl' % name)
        if not os.path.isfile(out):
            proc = run_locked(args.lock_dir,
                              [args.venv_python, '-I', GENERATOR_DEFAULT,
                               '--model', snap, '--prompts', pf,
                               '--max-tokens', str(cap),
                               '--sampler', 'greedy', '--out', out],
                              args.out, 'base_probe_%s' % name)
            if proc.returncode != 0:
                return fail('BASE_PROBE_FAILED',
                            '%s rc=%d %r' % (name, proc.returncode,
                                             proc.stderr[-300:]))
        rows = [json.loads(ln) for ln in open(out, encoding='utf-8')
                if ln.strip()]
        gens[name] = rows
    base_hits = sum(1 for r in gens['loop'] if r['hit_token_limit'])
    if base_hits != FITNESS_N:
        return fail('BASELINE_DRIFT',
                    'base cap-hits %d/%d on the frozen fitness bank '
                    '(stage-1 receipt says 12/12 on the full bank; probe '
                    'frozen to first 6)'
                    % (base_hits, FITNESS_N))
    guard_pass = [score_first_line(c, r['output_text'])
                  for c, r in zip(guard_pool, gens['guard'])]
    if sum(guard_pass) < 3:
        receipt['guard_note'] = 'GUARD_FLOOR_LIMITED (base pass %d/4)' \
            % sum(guard_pass)
    # fitness-blind sample pre-draw (frozen point)
    primary = scores[LAYERS[0]]['scores']
    samples = sample_columns(primary, 3584, args.seed)
    samples_path = os.path.join(args.out, 'sm1_samples.json')
    atomic_write_json(samples_path, {
        'schema': 'sm1-samples/v1', 'seed': args.seed, 'k': K_COLS,
        'scale': SCALE, 'layers': list(LAYERS),
        'scores_sha256': {l: scores[l]['sha256'] for l in LAYERS},
        'samples': samples})
    state = {
        'schema': 'sm1-state/v1', 'model': snap,
        'directions_sha256': {l: recovered['layers'][l]['direction_sha256']
                              for l in LAYERS},
        'scores': {l: scores[l]['sha256'] for l in LAYERS},
        'samples_sha256': sha256_file(samples_path),
        'base_loop_hits': base_hits,
        'guard_base_pass': sum(guard_pass),
        'guard_cells': [c['id'] for c in guard_pool],
        'fitness_cells': [c['id'] for c in loop],
        'created_utc': now(),
        'engine_rev': sha256_file(os.path.abspath(__file__)),
        'receipt': receipt,
    }
    atomic_write_json(os.path.join(args.out, 'sm1_state.json'), state)
    append_manifest(args.out, {'kind': 'probe_complete', 'at': now(),
                               'state': os.path.join(args.out,
                                                     'sm1_state.json')})
    print(json.dumps({'tool': 'sm1_run.py', 'cmd': 'probe',
                      'base_loop_hits': base_hits,
                      'guard_base_pass': sum(guard_pass),
                      'samples': len(samples),
                      'state': os.path.join(args.out, 'sm1_state.json')}))
    return EXIT_OK


# --------------------------------------------------------------------------
# run (device, AC-gated)
# --------------------------------------------------------------------------

def cmd_run(args, log):
    if not ac_gate_wait(log):
        append_manifest(args.out, {'kind': 'stop', 'reason':
                                   'POWER_GATE_BATTERY_WAIT_EXHAUSTED',
                                   'at': now()})
        return fail('POWER_GATE_BATTERY_WAIT_EXHAUSTED',
                    'no AC within the polling budget; state is resume-safe')
    state_path = os.path.join(args.out, 'sm1_state.json')
    samples_path = os.path.join(args.out, 'sm1_samples.json')
    if not (os.path.isfile(state_path) and os.path.isfile(samples_path)):
        return fail('PROBE_MISSING', 'run `probe` first (freeze point)')
    state = json.load(open(state_path, encoding='utf-8'))
    samples_doc = json.load(open(samples_path, encoding='utf-8'))
    snap = state['model']
    loop, guard_pool, _tpl = load_banks()
    manifest_path = os.path.join(args.out, 'manifest.jsonl')
    done = set()
    if os.path.isfile(manifest_path):
        for ln in open(manifest_path, encoding='utf-8'):
            if ln.strip():
                r = json.loads(ln)
                if r.get('kind') == 'sample_complete':
                    done.add((r['arm'], r['idx']))

    try:
        from transformers import AutoTokenizer
    except ImportError:
        return fail('MLX_UNAVAILABLE', 'transformers unavailable', EXIT_DEP)
    hf_tok = AutoTokenizer.from_pretrained(snap)
    loop_pf = os.path.join(args.out, 'prompts_fitness.txt')
    guard_pf = os.path.join(args.out, 'prompts_guard.txt')
    for pf, cells in ((loop_pf, loop), (guard_pf, guard_pool)):
        if not os.path.isfile(pf):
            with open(pf, 'w', encoding='utf-8') as fh:
                for c in cells:
                    r = hf_tok.apply_chat_template(
                        [{'role': 'user', 'content': c['prompt']
                          + ' /no_think'}],
                        add_generation_prompt=True, tokenize=False)
                    fh.write(r.replace('\r', ' ').replace('\n', ' ') + '\n')

    budget_deadline = (time.time() + args.max_min * 60) \
        if args.max_min else None
    ran = 0
    for s in samples_doc['samples']:
        arm, idx = s['arm'], s['idx']
        if (arm, idx) in done:
            continue
        if budget_deadline and time.time() > budget_deadline:
            append_manifest(args.out, {'kind': 'budget_stop', 'arm': arm,
                                       'idx': idx, 'at': now()})
            return fail('SM1_BUDGET_STOP',
                        'budget exhausted before sample %s/%d '
                        '(resume-safe: rerun `run`)' % (arm, idx))
        tag = '%s_%02d' % (arm, idx)
        mirror = os.path.join(args.mirror_root, tag)
        os.makedirs(args.mirror_root, exist_ok=True)
        sidecars = []
        for layer in LAYERS:
            spec_dir = os.path.join(args.out, 'sidecars', tag,
                                    'L%s' % layer)
            os.makedirs(spec_dir, exist_ok=True)
            spec_path = os.path.join(spec_dir, 'spec.json')
            # direction comes from the frozen state? directions live in the
            # recovered.json captured at probe; re-read it.
            rec = json.load(open(os.path.join(args.out, 'recovered.json'),
                                 encoding='utf-8'))
            d = rec['layers'][layer]['direction']
            atomic_write_json(spec_path, {
                'tensor': TENSOR_TEMPLATE % layer,
                'columns': s['columns'], 'direction': [-x for x in d],
                'scale': SCALE})
            proc = run_tool([args.venv_python, '-I', APPLY_DELTA_TOOL,
                             '--base', snap, '--spec', spec_path,
                             '--out', spec_dir], {}, 'apply_delta_%s_L%s'
                            % (tag, layer))
            if proc.returncode != 0:
                return fail('APPLY_DELTA_FAILED',
                            '%s L%s rc=%d %r' % (tag, layer,
                                                 proc.returncode,
                                                 proc.stderr[-300:]))
            sidecars.append(spec_dir)
        mrecv = mirror + '_receipt.json'
        if not (os.path.isdir(mirror)
                and os.path.isfile(os.path.join(mirror, SHARD_REL))
                and os.path.isfile(mrecv)):
            if os.path.isdir(mirror):
                import shutil
                shutil.rmtree(mirror, ignore_errors=True)
            argv = [args.venv_python, '-I', MAKE_MIRROR_TOOL, '--base',
                    snap, '--out', mirror, '--receipt', mrecv]
            for sc in sidecars:
                argv += ['--sidecar', sc]
            proc = run_locked(args.lock_dir, argv, args.out,
                              'make_mirror_%s' % tag)
            if proc.returncode != 0:
                return fail('MIRROR_FAILED',
                            '%s rc=%d %r' % (tag, proc.returncode,
                                             proc.stderr[-300:]))
        # gens
        loop_out = os.path.join(args.out, 'gens', '%s_loop.jsonl' % tag)
        guard_out = os.path.join(args.out, 'gens', '%s_guard.jsonl' % tag)
        for pf, out, cap in ((loop_pf, loop_out, CAP_LOOP),
                             (guard_pf, guard_out, CAP_GUARD)):
            if not os.path.isfile(out):
                proc = run_locked(args.lock_dir,
                                  [args.venv_python, '-I',
                                   GENERATOR_DEFAULT, '--model', mirror,
                                   '--prompts', pf, '--max-tokens',
                                   str(cap), '--sampler', 'greedy',
                                   '--out', out],
                                  args.out, 'gen_%s_%s'
                                  % (tag, 'loop' if cap == CAP_LOOP
                                     else 'guard'))
                if proc.returncode != 0:
                    return fail('GENERATOR_FAILED',
                                '%s rc=%d %r' % (tag, proc.returncode,
                                                 proc.stderr[-300:]))
        loop_rows = [json.loads(ln) for ln in open(loop_out,
                                                   encoding='utf-8')
                     if ln.strip()]
        guard_rows = [json.loads(ln) for ln in open(guard_out,
                                                    encoding='utf-8')
                      if ln.strip()]
        fitness = fitness_from_rows(loop_rows)
        guard_pass = sum(1 for c, r in zip(guard_pool, guard_rows)
                         if score_first_line(c, r['output_text']))
        append_manifest(args.out, {
            'kind': 'sample_complete', 'arm': arm, 'idx': idx,
            'seed': s['seed'], 'columns': s['columns'],
            'fitness': fitness, 'loop_cap_hits': FITNESS_N - fitness,
            'guard_pass': guard_pass, 'mirror': mirror, 'at': now()})
        ran += 1

    # determinism re-measure of the best GUIDED sample
    rows = [json.loads(ln) for ln in open(manifest_path,
                                          encoding='utf-8') if ln.strip()]
    guided = [r for r in rows if r.get('kind') == 'sample_complete'
              and r['arm'] == 'GUIDED']
    det = {'present': False, 'ok': None}
    if guided:
        best = max(guided, key=lambda r: r['fitness'])
        tag = 'GUIDED_%02d' % best['idx']
        loop_out = os.path.join(args.out, 'gens', '%s_loop.jsonl' % tag)
        first = [json.loads(ln) for ln in open(loop_out,
                                               encoding='utf-8')
                 if ln.strip()]
        sdoc = json.load(open(samples_path, encoding='utf-8'))
        s = [x for x in sdoc['samples']
             if x['arm'] == 'GUIDED' and x['idx'] == best['idx']][0]
        mirror = os.path.join(args.mirror_root, 'DET_' + tag)
        sidecars = []
        for layer in LAYERS:
            spec_dir = os.path.join(args.out, 'sidecars', 'DET_' + tag,
                                    'L%s' % layer)
            os.makedirs(spec_dir, exist_ok=True)
            spec_path = os.path.join(spec_dir, 'spec.json')
            rec = json.load(open(os.path.join(args.out, 'recovered.json'),
                                 encoding='utf-8'))
            d = rec['layers'][layer]['direction']
            atomic_write_json(spec_path, {
                'tensor': TENSOR_TEMPLATE % layer,
                'columns': s['columns'], 'direction': [-x for x in d],
                'scale': SCALE})
            sidecars.append(spec_dir)
        argv = [args.venv_python, '-I', MAKE_MIRROR_TOOL, '--base', snap,
                '--out', mirror, '--receipt', mirror + '_receipt.json']
        for sc in sidecars:
            argv += ['--sidecar', sc]
        run_locked(args.lock_dir, argv, args.out,
                   'make_mirror_DET_%s' % tag)
        det_out = os.path.join(args.out, 'gens', 'DET_%s_loop.jsonl' % tag)
        proc = run_locked(args.lock_dir,
                          [args.venv_python, '-I', GENERATOR_DEFAULT,
                           '--model', mirror, '--prompts', loop_pf,
                           '--max-tokens', str(CAP_LOOP),
                           '--sampler', 'greedy', '--out', det_out],
                          args.out, 'gen_DET_%s' % tag)
        if proc.returncode == 0:
            second = [json.loads(ln) for ln in open(det_out,
                                                    encoding='utf-8')
                      if ln.strip()]
            det = {'present': True,
                   'ok': ([r['hit_token_limit'] for r in first]
                          == [r['hit_token_limit'] for r in second]
                          and [r['output_tokens'] for r in first]
                          == [r['output_tokens'] for r in second])}
    state['determinism'] = det
    atomic_write_json(state_path, state)
    append_manifest(args.out, {'kind': 'run_complete', 'samples_ran': ran,
                               'determinism': det, 'at': now()})
    print(json.dumps({'tool': 'sm1_run.py', 'cmd': 'run',
                      'samples_ran': ran, 'determinism': det}))
    return EXIT_OK


# --------------------------------------------------------------------------
# verdict (CPU)
# --------------------------------------------------------------------------

def cmd_verdict(args):
    manifest_path = os.path.join(args.out, 'manifest.jsonl')
    if not os.path.isfile(manifest_path):
        return fail('MANIFEST_MISSING', manifest_path)
    rows = [json.loads(ln) for ln in open(manifest_path,
                                          encoding='utf-8') if ln.strip()]
    state = json.load(open(os.path.join(args.out, 'sm1_state.json'),
                           encoding='utf-8'))
    det = state.get('determinism', {'present': False, 'ok': None})
    v = verdict_classes(rows, state['base_loop_hits'],
                        det.get('ok'), det.get('present'))
    chain = os.path.join(_PKG_DIR, 'receipts', 'SM1-run.jsonl')
    chain_append(chain, 'sm1_verdict', {
        'prereg': 'PREREG-SM1.md FROZEN 2026-11-08',
        'out': args.out,
        'samples_sha256': state['samples_sha256'],
        'base_loop_hits': state['base_loop_hits'],
        'guard_base_pass': state['guard_base_pass'],
        'determinism': det,
        'classes': v,
        'denominator': {r['kind']: 1 for r in rows if
                        r['kind'] == 'run_complete'} or
                       {'run_complete': 0},
    })
    chain_append(chain, 'sm1_chain_check', {'verify': chain_verify(chain)})
    summary = ['# SM-1 pilot summary (PREREG-SM1, frozen 2026-11-08)', '',
               'Verdict: **%s**' % v['verdict'], '']
    for arm, st in sorted(v['per_arm'].items()):
        summary.append('- %s: n=%d best=%s mean=%s'
                       % (arm, st['n'], st['best'], st['mean']))
    summary += ['', 'chance control: %s' % v.get('chance_control'),
                'determinism: %s' % det,
                'chain: %s' % chain_verify(chain),
                '', 'Non-claims: descriptive pilot, NO certification; '
                    'improving samples are candidate repairs for a future '
                    'prereg only; absolute ms non-claims.']
    with open(args.summary, 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(summary) + '\n')
    print(json.dumps({'tool': 'sm1_run.py', 'cmd': 'verdict',
                      'verdict': v['verdict'], 'chain': chain}))
    return EXIT_OK


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('cmd', choices=['probe', 'run', 'verdict'])
    ap.add_argument('--model',
                    default=os.path.expanduser('~/.cache/huggingface/hub/'
                                               'models--Qwen--Qwen3.5-0.8B/'
                                               'snapshots/main'))
    ap.add_argument('--out', default=None)
    ap.add_argument('--mirror-root', default=None)
    ap.add_argument('--lock-dir', default=None)
    ap.add_argument('--venv-python', default=VENV_PYTHON_DEFAULT)
    ap.add_argument('--seed', type=int, default=SEED_DEFAULT)
    ap.add_argument('--max-min', type=float, default=None)
    ap.add_argument('--summary', default=None)
    args = ap.parse_args(argv)
    tmp = os.environ.get('TMPDIR') or '/tmp'
    if args.out is None:
        args.out = os.path.join(tmp, 'sm1-artifacts', 'run')
    if args.mirror_root is None:
        args.mirror_root = os.path.join(tmp, 'sm1-artifacts', 'mirrors')
    if args.lock_dir is None:
        args.lock_dir = os.path.join(tmp, 'wm-device.lock')
    log = sys.stderr
    try:
        if args.cmd == 'probe':
            return cmd_probe(args, log)
        if args.cmd == 'run':
            return cmd_run(args, log)
        return cmd_verdict(args)
    except RuntimeError as exc:
        code, _, detail = str(exc).partition(': ')
        return fail(code if code.isupper() else 'INTERNAL', detail)
    finally:
        release_lock_if_held()


if __name__ == '__main__':
    sys.exit(main())
