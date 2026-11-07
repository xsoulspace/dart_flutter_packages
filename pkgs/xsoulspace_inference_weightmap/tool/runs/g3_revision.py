#!/usr/bin/env python3
"""g3_revision.py - G-3 revision-dynamics ladder runner (PREREG-G.md, FROZEN
2026-11-07). Sampler-side loop interventions on the qwen3.5-0.8b BASE cast:
R0 greedy / R1 repetition-penalty (boring control) / R2 soft-mixture decode
(input_embeddings) / R3 detect-and-resample (RECOMPUTE_REWIND) / NULL-A
random-rewind control. Python-boundary reference per house law (a Rust
separate-file port is post-verdict work, PREREG-G §7 stage 3).

TWO MODES (single file, house scope law: runners stay standalone):
  orchestrator (default, --stage pilot): NO mlx import. Verifies the frozen
    cells digest + base FETCH receipt + AC power gate, then launches one
    WORKER SUBPROCESS PER ARM under the device lock (protocol v3; model
    loaded inside the acquired section = LOAD-AFTER-LOCK by construction).
    Resume-safe: an arm with an arm_complete manifest row is never
    re-launched; budget stops land BETWEEN arms.
  worker (--arm R0|R1|R2|R3|NULLA): imports mlx/mlx_lm, loads model once,
    runs every incomplete (arm, cell) pair, appends per-cell rows to
    gens/arm_<X>.jsonl + manifest cell_complete rows (append+fsync after
    every cell; completed cells never re-run).

FROZEN CONSTANTS (PREREG-G §1-§3; a change = addendum + new denominator):
  detector: n-gram 4, window 64 generated ids, threshold 3 (fires when the
    just-completed 4-gram has >=3 distinct window starts).
  R1: penalty 1.2, context = last 64 sequence tokens (prompt+generated).
  R2: top-k 32, renormalized softmax mixture, f32 accumulate, HARD READOUT
    recorded token = f32 log-softmax argmax (G3_ARGMAX_F32 everywhere).
  R3/NULL-A: resample window W=16 at temp 0.9; max interventions I=3/cell;
    R3 rewind_to = first-occurrence-end of the trigger 4-gram (p0+4),
    RECOMPUTE_REWIND (fresh caches + full re-prefill; correct for GDN
    recurrent state by construction); NULL-A intervenes when kept length
    first exceeds {48, 96, 144}, rewind uniform in [L-32, L-8] (python
    Random, seeds recorded).
  cap applies to KEPT generated tokens (G3_CAP_ON_KEPT); discarded tokens
    and recompute prefills are receipted as total_forward_tokens.
  EOS: mlx-lm tokenizer wrapper's reported eos set (expected {248046});
    recorded as a NAMED FACT, never a tunable.
  surface: apply_chat_template([{role:user, content:prompt+' /no_think'}],
    add_generation_prompt=True, tokenize=False) - frozen A3 render, ported
    to this cast's tokenizer (G3_SURFACE_PORT_FROM_A3).

Usage:
  <venv-python> -I tool/runs/g3_revision.py \
      --model <snapshot-dir> [--stage pilot] [--arms R0,R1,R2,R3,NULLA] \
      [--cells tool/runs/cells_frozen_A3.json] [--out DIR] [--lock-dir DIR] \
      [--venv-python P] [--seed 20261107] [--max-min M] [--dry-run]
  worker (internal): ... --arm R1

Exit codes (errors NAMED on stderr as 'CODE: detail', never silent):
  0  stage/arm complete (or dry-run plan printed)
  1  named error: CELLS_FILE_MISSING / CELLS_DIGEST_DRIFT /
     BASE_RECEIPT_DRIFT / BASE_MODEL_MISSING / TOOL_MISSING /
     POWER_GATE_BATTERY / G3_BUDGET_STOP (resume-safe) /
     DEVICE_LOCK_TIMEOUT / STATE_UNWRITABLE / RENDER_FAILED /
     EMBED_PATH_UNRESOLVED / SURFACE_UNEXPECTED / INTERNAL
  2  MLX_UNAVAILABLE (rc passthrough)
"""

import argparse
import hashlib
import json
import math
import os
import random
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone

_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
_PKG_DIR = os.path.dirname(os.path.dirname(_SCRIPT_DIR))

# --- frozen constants (PREREG-G; never retuned within a stage) ------------
CELLS_SHA256_FROZEN = (
    '8406130623b6e85922eac6cbd92b73dd2282e6fc19538bb3c199f647f518d760')
BASE_RECEIPT_SHA256_FROZEN = (
    '17f7fd5d45b7b8707606e3488cff31ba282abceb55541458315936fbd7915834')
BASE_RECEIPT_REL = os.path.join('..', '..', 'FETCH-RECEIPT.sha256')
ARMS_FROZEN = ['R0', 'R1', 'R2', 'R3', 'NULLA']
SEED_DEFAULT = 20261107
DET_N = 4
DET_WINDOW = 64
DET_THRESHOLD = 3
R1_PENALTY = 1.2
R1_CONTEXT = 64
R2_TOPK = 32
RESAMPLE_W = 16
RESAMPLE_TEMP = 0.9
MAX_INTERVENTIONS = 3
NULLA_AT = (48, 96, 144)
NULLA_BACK = 32
NULLA_MIN_KEEP_BACK = 8
GUARD_GROUP = 'G0'
GUARD_N = 8          # first 8 G0 cells in frozen file order
PRIMARY_GROUP = 'G2'
VENV_PYTHON_DEFAULT = os.path.expanduser('~/.local/share/wm-mlx/bin/python')
EXIT_OK = 0
EXIT_INPUT = 1
EXIT_DEP = 2

sys.path.insert(0, _SCRIPT_DIR)
import a3_lock  # noqa: E402  (house lock helper; protocol v3 constants)

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
    print('G3_INTERRUPTED: signal %d (lock released)' % signum,
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


def atomic_write_json(path, obj):
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as fh:
        json.dump(obj, fh, indent=1)
        fh.write('\n')
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, path)


def append_manifest(state_dir, row):
    """Resilience rule: append + fsync after every completed unit."""
    path = os.path.join(state_dir, 'manifest.jsonl')
    os.makedirs(state_dir, exist_ok=True)
    with open(path, 'a', encoding='utf-8') as fh:
        fh.write(json.dumps(row, sort_keys=False) + '\n')
        fh.flush()
        os.fsync(fh.fileno())


def append_jsonl(path, row):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'a', encoding='utf-8') as fh:
        fh.write(json.dumps(row, ensure_ascii=False, sort_keys=False) + '\n')
        fh.flush()
        os.fsync(fh.fileno())


def power_facts():
    out = {}
    try:
        ps = subprocess.run(['pmset', '-g', 'ps'], capture_output=True,
                            text=True, timeout=15)
        out['source'] = ps.stdout.splitlines()[0].strip().strip("'") \
            if ps.stdout else 'unknown'
    except (OSError, subprocess.SubprocessError):
        out['source'] = 'unknown'
    return out


def on_ac_power():
    return 'AC Power' in power_facts().get('source', '')


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


# --------------------------------------------------------------------------
# FROZEN loop-signature detector (PREREG-G §3; golden-pinned in both langs)
# --------------------------------------------------------------------------

def detector_fires_at(ids):
    """True when the just-completed 4-gram (ids[-4:]) has >= DET_THRESHOLD
    distinct occurrence starts within the last DET_WINDOW ids. Pure, no
    state; the runtime incremental check = this function on the prefix."""
    t1 = len(ids)                      # exclusive end (= t+1)
    if t1 < DET_N:
        return False
    g = tuple(ids[t1 - DET_N:t1])
    lo = max(0, t1 - DET_WINDOW)
    cnt = 0
    for i in range(lo, t1 - DET_N + 1):
        if tuple(ids[i:i + DET_N]) == g:
            cnt += 1
            if cnt >= DET_THRESHOLD:
                return True
    return False


def loop_triggers(ids):
    """Offline scorer form: every position t (0-based) where the detector
    fires on the prefix ids[:t+1]."""
    return [t for t in range(len(ids)) if detector_fires_at(ids[:t + 1])]


def first_occurrence_end(ids, t):
    """R3 rewind target: first start p0 of the trigger 4-gram in the
    generated span; rewind_to = p0 + DET_N (PREREG-G §1)."""
    g = tuple(ids[t - DET_N + 1:t + 1])
    for p0 in range(0, len(ids) - DET_N + 1):
        if tuple(ids[p0:p0 + DET_N]) == g:
            return p0 + DET_N
    return max(0, t - DET_N + 1)       # unreachable when the detector fired


def rep_penalty_indices(seq_ids, context):
    """R1 context set: unique ids in the last `context` sequence tokens."""
    return sorted(set(seq_ids[-context:]))


def nulla_rewind_to(gen_len, cell_idx, int_idx, seed):
    """NULL-A frozen rule: uniform in [max(0, L-NULLA_BACK),
    L-NULLA_MIN_KEEP_BACK]; deterministic python RNG, seed recorded."""
    lo = max(0, gen_len - NULLA_BACK)
    hi = gen_len - NULLA_MIN_KEEP_BACK
    if hi <= lo:
        return lo
    rng = random.Random(seed * 1000 + cell_idx * 7 + int_idx)
    return rng.randrange(lo, hi)


def resample_seed(seed, cell_idx, int_idx):
    """Frozen per-intervention RNG seed (PREREG-G §1, R3 and NULL-A share
    the formula; RNG_ENGINE_MX_RANDOM)."""
    return seed * 1000003 + cell_idx * 1009 + int_idx


# --------------------------------------------------------------------------
# Cells
# --------------------------------------------------------------------------

def load_cells(path, expect_sha=None):
    if not os.path.isfile(path):
        raise RuntimeError('CELLS_FILE_MISSING: %s' % path)
    digest = sha256_file(path)
    frozen = expect_sha or CELLS_SHA256_FROZEN
    if digest != frozen:
        raise RuntimeError(
            'CELLS_DIGEST_DRIFT: %s is %s, expected %s (frozen-oracle law: a '
            'change = new prereg row)' % (path, digest, frozen))
    data = json.load(open(path, encoding='utf-8'))
    groups = data['cells']
    sel = []
    for c in groups[PRIMARY_GROUP]:
        sel.append({'id': c['id'], 'group': PRIMARY_GROUP,
                    'prompt': c['prompt'], 'cap': int(c['cap'])})
    for c in groups[GUARD_GROUP][:GUARD_N]:
        sel.append({'id': c['id'], 'group': GUARD_GROUP,
                    'prompt': c['prompt'], 'cap': int(c['cap'])})
    return sel, digest


# --------------------------------------------------------------------------
# Worker (one arm; mlx imported HERE only)
# --------------------------------------------------------------------------

def run_arm(args):
    arm = args.arm
    if arm not in ARMS_FROZEN:
        return fail('SURFACE_UNEXPECTED', '--arm %r not in %s'
                    % (arm, ARMS_FROZEN))
    try:
        cells, cells_digest = load_cells(args.cells, args.expect_cells_sha)
    except (RuntimeError, ValueError, KeyError) as exc:
        code, _, detail = str(exc).partition(': ')
        return fail(code if code.isupper() else 'CELLS_FILE_MISSING',
                    detail or str(exc))
    # base FETCH receipt re-verification (PREREG-G §5)
    snap = os.path.abspath(args.model)
    receipt_path = os.path.normpath(os.path.join(snap, BASE_RECEIPT_REL))
    base_receipt = {'path': receipt_path, 'status': 'ABSENT'}
    if os.path.isfile(receipt_path):
        rsha = sha256_file(receipt_path)
        if rsha != BASE_RECEIPT_SHA256_FROZEN:
            return fail('BASE_RECEIPT_DRIFT',
                        '%s is %s, frozen %s' % (receipt_path, rsha,
                                                 BASE_RECEIPT_SHA256_FROZEN))
        base_receipt = {'path': receipt_path, 'status': 'MATCH',
                        'sha256': rsha}
    if not os.path.isdir(snap):
        return fail('BASE_MODEL_MISSING', snap)

    try:
        import mlx.core as mx
        from mlx_lm import load as mlx_load
    except ImportError as exc:
        return fail('MLX_UNAVAILABLE', str(exc), EXIT_DEP)

    gens_path = os.path.join(args.out, 'gens', 'arm_%s.jsonl' % arm)
    done = set()
    if os.path.isfile(gens_path):
        with open(gens_path, 'r', encoding='utf-8') as fh:
            for ln in fh:
                if ln.strip():
                    try:
                        done.add(json.loads(ln)['cell_id'])
                    except (ValueError, KeyError):
                        pass
    manifest_path = os.path.join(args.out, 'manifest.jsonl')
    if os.path.isfile(manifest_path):
        with open(manifest_path, 'r', encoding='utf-8') as fh:
            for ln in fh:
                if ln.strip():
                    try:
                        r = json.loads(ln)
                        if r.get('kind') == 'cell_complete' \
                                and r.get('arm') == arm:
                            done.add(r['cell_id'])
                    except (ValueError, KeyError):
                        pass
    todo = [c for c in cells if c['id'] not in done]

    t_load0 = time.time()
    model, tokenizer = mlx_load(snap)
    hf_tok = getattr(tokenizer, 'tokenizer', tokenizer)
    eos_ids = set()
    for attr in ('eos_token_ids',):
        v = getattr(tokenizer, attr, None)
        if v:
            eos_ids |= set(v)
    single = getattr(tokenizer, 'eos_token_id', None) \
        or getattr(hf_tok, 'eos_token_id', None)
    if single is not None:
        eos_ids.add(int(single))
    if not eos_ids:
        return fail('SURFACE_UNEXPECTED', 'no eos id resolvable')

    embed_path = None
    if arm == 'R2':
        for path, obj in (('model.model.embed_tokens',
                           getattr(getattr(model, 'model', None),
                                   'embed_tokens', None)),
                          ('model.embed_tokens',
                           getattr(model, 'embed_tokens', None)),
                          ('model.language_model.model.embed_tokens',
                           getattr(getattr(getattr(model, 'language_model',
                                                   None), 'model', None),
                                   'embed_tokens', None))):
            if obj is not None and hasattr(obj, 'weight'):
                embed_path = path
                E = obj.weight
                break
        if embed_path is None:
            return fail('EMBED_PATH_UNRESOLVED',
                        'no embed_tokens.weight candidate resolved; arm R2 '
                        'BLOCKED per PREREG-G §6.5 (other arms unaffected)')

    def render(prompt):
        try:
            return hf_tok.apply_chat_template(
                [{'role': 'user', 'content': prompt + ' /no_think'}],
                add_generation_prompt=True, tokenize=False)
        except Exception as exc:  # noqa: BLE001 - named, never silent
            raise RuntimeError('RENDER_FAILED: %s: %s'
                               % (type(exc).__name__, exc))

    def encode(text):
        enc = getattr(tokenizer, 'encode', None)
        ids = enc(text) if callable(enc) else hf_tok.encode(text)
        return [int(i) for i in ids]

    render0 = render(cells[0]['prompt'])
    receipt = {
        'schema': 'g3-arm-receipt/v1', 'arm': arm, 'model_dir': snap,
        'base_receipt': base_receipt, 'cells_sha256': cells_digest,
        'engine_rev': sha256_file(os.path.abspath(__file__)),
        'tokenizer': {'eos_ids': sorted(eos_ids),
                      'render_cell0_sha256': sha256_text(render0),
                      'render_cell0_prefix': render0[:96]},
        'constants': {'detector': [DET_N, DET_WINDOW, DET_THRESHOLD],
                      'r1': [R1_PENALTY, R1_CONTEXT], 'r2_topk': R2_TOPK,
                      'resample': [RESAMPLE_W, RESAMPLE_TEMP],
                      'max_interventions': MAX_INTERVENTIONS,
                      'nulla_at': list(NULLA_AT), 'seed': args.seed,
                      'argmax': 'G3_ARGMAX_F32',
                      'cap_rule': 'G3_CAP_ON_KEPT'},
        'embed_path': embed_path,
        'load_wall_s': round(time.time() - t_load0, 1),
        'started_utc': now(), 'cells_total': len(cells),
        'cells_resumed': sorted(done), 'cells_todo': [c['id'] for c in todo],
    }

    def logsoftmax_f32(logits):
        f32 = logits.astype(mx.float32)
        return f32 - mx.logsumexp(f32, keepdims=True, axis=-1)

    def mixture_embedding(ls):
        k = min(R2_TOPK, ls.shape[-1])
        top = mx.argpartition(ls, kth=k - 1, axis=-1)[..., -k:]
        top_logits = mx.take_along_axis(ls, top, axis=-1)
        p = mx.softmax(top_logits, axis=-1).reshape(-1)
        rows = mx.take_along_axis(
            E.astype(mx.float32), top.reshape(-1)[:, None], axis=0)
        emb = (p[:, None] * rows).sum(axis=0)
        return emb.astype(E.dtype).reshape(1, 1, -1)

    def generate(cell, cell_idx):
        cap = cell['cap']
        prompt_ids = encode(render(cell['prompt']))
        gen = []
        interventions = []
        forwards = len(prompt_ids)          # total_forward_tokens accounting
        resample_left = 0
        finish = 'length'
        cache = model.make_cache()
        y = model(mx.array([prompt_ids]), cache=cache)
        logits = y[0, -1, :]
        nulla_next = 0
        t0 = time.perf_counter()
        while len(gen) < cap:
            ls = None
            if arm == 'R1':
                ctx = rep_penalty_indices(prompt_ids + gen, R1_CONTEXT)
                idx = mx.array(ctx)
                lv = mx.take(logits, idx, axis=0)
                adj = mx.where(lv > 0, lv / R1_PENALTY, lv * R1_PENALTY)
                logits = mx.put_along_axis(logits, idx, adj, axis=-1)
            f32 = logits.astype(mx.float32)
            ls = f32 - mx.logsumexp(f32, keepdims=True, axis=-1)
            if resample_left > 0:
                # RNG was seeded ONCE at the intervention (frozen
                # per-intervention seed); draws advance it through the
                # window. Reseeding per step would repeat one token.
                nxt = int(mx.random.categorical(ls / RESAMPLE_TEMP).item())
                resample_left -= 1
            else:
                nxt = int(mx.argmax(ls, axis=-1).item())
            if nxt in eos_ids:
                finish = 'eos'
                break
            gen.append(nxt)
            emb_in = None
            if arm == 'R2':
                emb_in = mixture_embedding(ls)
            # intervention checks operate on the KEPT generated span
            trig = None
            if arm == 'R3' and len(interventions) < MAX_INTERVENTIONS \
                    and detector_fires_at(gen):
                t = len(gen) - 1
                trig = ('detector', t, first_occurrence_end(gen, t))
            elif arm == 'NULLA' and len(interventions) < MAX_INTERVENTIONS \
                    and nulla_next < len(NULLA_AT) \
                    and len(gen) > NULLA_AT[nulla_next]:
                L = len(gen)
                trig = ('length>%d' % NULLA_AT[nulla_next], L - 1,
                        nulla_rewind_to(L, cell_idx, len(interventions),
                                        args.seed))
                nulla_next += 1
            if trig is not None:
                _why, tpos, rewind_to = trig
                rewind_to = min(rewind_to, len(gen))
                seed_i = resample_seed(args.seed, cell_idx,
                                       len(interventions))
                interventions.append({
                    'why': _why, 'trigger_pos': tpos,
                    'kept_before': len(gen), 'rewind_to': rewind_to,
                    'seed': seed_i})
                gen = gen[:rewind_to]
                cache = model.make_cache()
                full = prompt_ids + gen
                mx.random.seed(seed_i)   # frozen per-intervention seed
                y = model(mx.array([full]), cache=cache)
                forwards += len(full)
                logits = y[0, -1, :]
                resample_left = RESAMPLE_W
                continue
            kw = {}
            if emb_in is not None:
                kw['input_embeddings'] = emb_in
            y = model(mx.array([[nxt]]), cache=cache, **kw) \
                if kw else model(mx.array([[nxt]]), cache=cache)
            forwards += 1
            logits = y[0, -1, :]
        text = tokenizer.decode(gen) if gen else ''
        return {
            'schema': 'g3-cell/v1', 'arm': arm, 'cell_id': cell['id'],
            'group': cell['group'], 'cap': cap,
            'prompt_sha256': sha256_text(cell['prompt']),
            'generated_ids': gen, 'output': text,
            'output_tokens': len(gen), 'cap_hit': finish == 'length',
            'finish_reason': finish, 'interventions': interventions,
            'total_forward_tokens': forwards,
            'wall_ms': round((time.perf_counter() - t0) * 1000, 1),
            'wall_ms_claim': False,
        }

    for cell_idx, cell in enumerate(cells):
        if cell['id'] in done:
            continue
        row = generate(cell, cell_idx)
        append_jsonl(gens_path, row)
        append_manifest(args.out, {
            'kind': 'cell_complete', 'arm': arm, 'cell_id': cell['id'],
            'group': cell['group'], 'at': now(),
            'output_tokens': row['output_tokens'],
            'cap_hit': row['cap_hit'],
            'interventions': len(row['interventions'])})

    # PREREG-G §4 determinism cross-check (R0 only): re-run the first 4 G2
    # cells in fresh state and require exact reproduction (A2 determinism
    # precedent). A mismatch is a NAMED row; the scorer caps the stage
    # verdict at INSTRUMENT_UNVALIDATED.
    if arm == 'R0':
        prior = {}
        with open(gens_path, 'r', encoding='utf-8') as fh:
            for ln in fh:
                if ln.strip():
                    r = json.loads(ln)
                    prior[r['cell_id']] = r   # last-wins
        g2_first4 = [c for c in cells if c['group'] == PRIMARY_GROUP][:4]
        mismatches = []
        checked = []
        for ci, cell in enumerate(g2_first4):
            if cell['id'] not in prior:
                mismatches.append({'cell_id': cell['id'],
                                   'reason': 'PRIOR_ROW_MISSING'})
                continue
            rerun = generate(cell, 1000 + ci)   # R0: no sampling, no seeds
            checked.append(cell['id'])
            a, b = prior[cell['id']], rerun
            if (a['cap_hit'] != b['cap_hit']
                    or a['output_tokens'] != b['output_tokens']
                    or sha256_text(json.dumps(a['generated_ids']))
                    != sha256_text(json.dumps(b['generated_ids']))):
                mismatches.append({
                    'cell_id': cell['id'],
                    'prior': [a['cap_hit'], a['output_tokens']],
                    'rerun': [b['cap_hit'], b['output_tokens']]})
        receipt['determinism'] = {
            'rule': 'R0 re-run of the first 4 G2 cells must reproduce '
                    'cap_hit, output_tokens and generated-ids digest '
                    'exactly (PREREG-G §4)',
            'checked': checked, 'reproduced': not mismatches,
            'mismatches': mismatches}

    receipt['finished_utc'] = now()
    n_rows = 0
    if os.path.isfile(gens_path):
        with open(gens_path, 'r', encoding='utf-8') as fh:
            n_rows = sum(1 for ln in fh if ln.strip())
    receipt['gens_rows'] = n_rows
    atomic_write_json(os.path.join(args.out, 'arm_receipt_%s.json' % arm),
                      receipt)
    append_manifest(args.out, {'kind': 'arm_complete', 'arm': arm,
                               'at': receipt['finished_utc'],
                               'receipt': os.path.join(
                                   args.out, 'arm_receipt_%s.json' % arm)})
    print(json.dumps({'tool': 'g3_revision.py', 'mode': 'worker',
                      'arm': arm, 'cells': len(cells),
                      'resumed': len(done), 'gens': gens_path}))
    return EXIT_OK


# --------------------------------------------------------------------------
# Orchestrator (no mlx import)
# --------------------------------------------------------------------------

def run_locked(lock_dir, argv, state_dir, what):
    waited_ms, interval = a3_lock.acquire(
        lock_dir, attempts=a3_lock.V3_ATTEMPTS, sleep_s=a3_lock.V3_SLEEP_S)
    _LOCK_HELD['dir'] = lock_dir
    p_start = power_facts()
    t0 = time.time()
    try:
        proc = subprocess.run(argv, capture_output=True, text=True)
    finally:
        wall = time.time() - t0
        release_lock_if_held()
        time.sleep(3)   # courtesy yield (protocol v3)
    p_end = power_facts()
    add_device_time(state_dir, wall, what)
    append_manifest(state_dir, {
        'kind': 'device_batch', 'what': what, 'argv': argv,
        'exit': proc.returncode, 'wall_ms': int(wall * 1000),
        'wall_ms_claim': False, 'lock_wait_ms': waited_ms,
        'lock_retry_interval_s': interval,
        'power_start': p_start, 'power_end': p_end, 'at': now()})
    return proc


def orchestrate(args):
    try:
        cells, cells_digest = load_cells(args.cells, args.expect_cells_sha)
    except (RuntimeError, ValueError, KeyError) as exc:
        code, _, detail = str(exc).partition(': ')
        return fail(code if code.isupper() else 'CELLS_FILE_MISSING',
                    detail or str(exc))
    snap = os.path.abspath(os.path.expanduser(args.model))
    if not os.path.isdir(snap):
        return fail('BASE_MODEL_MISSING', snap)
    receipt_path = os.path.normpath(os.path.join(snap, BASE_RECEIPT_REL))
    if os.path.isfile(receipt_path):
        rsha = sha256_file(receipt_path)
        if rsha != BASE_RECEIPT_SHA256_FROZEN:
            return fail('BASE_RECEIPT_DRIFT',
                        '%s is %s, frozen %s' % (receipt_path, rsha,
                                                 BASE_RECEIPT_SHA256_FROZEN))
    for tool in (args.venv_python, os.path.abspath(__file__)):
        if not os.path.isfile(tool):
            return fail('TOOL_MISSING', tool)
    if not args.dry_run and not on_ac_power():
        return fail('POWER_GATE_BATTERY',
                    'live launch requires AC power (PREREG-G §7 POWER GATE; '
                    'current source: %r)' % power_facts().get('source'))

    arms = [a.strip() for a in args.arms.split(',') if a.strip()]
    unknown = [a for a in arms if a not in ARMS_FROZEN]
    if unknown:
        return fail('SURFACE_UNEXPECTED', 'arms %s not in %s'
                    % (unknown, ARMS_FROZEN))

    if args.dry_run:
        plan = {
            'mode': 'dry-run', 'tool': 'g3_revision.py',
            'stage': args.stage, 'model': snap,
            'base_receipt': receipt_path, 'cells': args.cells,
            'cells_sha256': cells_digest,
            'cells_selected': [(c['id'], c['group'], c['cap'])
                               for c in cells],
            'arms': arms, 'seed': args.seed,
            'constants': {'detector': [DET_N, DET_WINDOW, DET_THRESHOLD],
                          'r1': [R1_PENALTY, R1_CONTEXT],
                          'r2_topk': R2_TOPK,
                          'resample': [RESAMPLE_W, RESAMPLE_TEMP],
                          'max_interventions': MAX_INTERVENTIONS,
                          'nulla_at': list(NULLA_AT)},
            'prereg': os.path.join(_PKG_DIR, 'PREREG-G.md'),
            'engine_rev': sha256_file(os.path.abspath(__file__)),
            'lock': {'dir': args.lock_dir,
                     'protocol': 'v3 per-arm batches (10s acquisition '
                                 'retries, rmdir+3s courtesy, '
                                 'LOAD-AFTER-LOCK)'},
            'power': power_facts(),
            'note': 'plan only; no device, no mlx import, nothing written',
        }
        print(json.dumps(plan, indent=1))
        return EXIT_OK

    try:
        os.makedirs(os.path.join(args.out, 'gens'), exist_ok=True)
    except OSError as exc:
        return fail('STATE_UNWRITABLE', str(exc))
    manifest_path = os.path.join(args.out, 'manifest.jsonl')
    complete = set()
    if os.path.isfile(manifest_path):
        with open(manifest_path, 'r', encoding='utf-8') as fh:
            for ln in fh:
                if ln.strip():
                    try:
                        r = json.loads(ln)
                        if r.get('kind') in ('arm_complete', 'arm_blocked') \
                                and r.get('arm'):
                            complete.add(r['arm'])
                    except (ValueError, KeyError):
                        pass
    deadline = (time.time() + args.max_min * 60) if args.max_min else None
    launched = []
    for arm in arms:
        if arm in complete:
            launched.append({'arm': arm, 'status': 'RESUMED_SKIP'})
            continue
        if deadline and time.time() > deadline:
            append_manifest(args.out, {'kind': 'budget_stop', 'arm': arm,
                                       'at': now()})
            return fail('G3_BUDGET_STOP',
                        'budget exhausted before arm %s (resume-safe: '
                        'rerun the same command)' % arm)
        append_manifest(args.out, {'kind': 'arm_started', 'arm': arm,
                                   'at': now()})
        argv = [args.venv_python, '-I', os.path.abspath(__file__),
                '--arm', arm, '--model', snap, '--cells', args.cells,
                '--out', args.out, '--seed', str(args.seed)]
        if args.expect_cells_sha:
            argv += ['--expect-cells-sha', args.expect_cells_sha]
        proc = run_locked(args.lock_dir, argv, args.out, 'arm_%s' % arm)
        if proc.returncode == EXIT_DEP:
            return fail('MLX_UNAVAILABLE', proc.stderr[-400:], EXIT_DEP)
        if proc.returncode != 0:
            if 'EMBED_PATH_UNRESOLVED' in proc.stderr:
                append_manifest(args.out, {
                    'kind': 'arm_blocked', 'arm': arm, 'at': now(),
                    'reason': 'EMBEDS_RUNTIME_FAIL',
                    'stderr_tail': proc.stderr[-400:]})
                launched.append({'arm': arm, 'status': 'BLOCKED'})
                continue
            append_manifest(args.out, {
                'kind': 'arm_failed', 'arm': arm, 'at': now(),
                'exit': proc.returncode, 'stderr_tail': proc.stderr[-400:]})
            return fail('INTERNAL', 'arm %s worker rc=%d stderr-tail=%r'
                        % (arm, proc.returncode, proc.stderr[-400:]))
        launched.append({'arm': arm, 'status': 'COMPLETE'})
    print(json.dumps({'tool': 'g3_revision.py', 'mode': 'orchestrator',
                      'stage': args.stage, 'arms': launched,
                      'next': 'dart run tool/runs/g3_score.dart --state %s '
                              '--cells %s --out receipts/G3-run.jsonl '
                              '--summary receipts/G3-summary.md'
                              % (args.out, args.cells)}))
    return EXIT_OK


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--model', required=True,
                    help='qwen3.5-0.8b base snapshot dir (hub cache)')
    ap.add_argument('--stage', default='pilot', choices=['pilot'])
    ap.add_argument('--arm', default=None,
                    help='worker mode: single arm (internal)')
    ap.add_argument('--arms', default=','.join(ARMS_FROZEN))
    ap.add_argument('--cells',
                    default=os.path.join(_SCRIPT_DIR, 'cells_frozen_A3.json'))
    ap.add_argument('--expect-cells-sha', dest='expect_cells_sha',
                    default=None,
                    help='expected cells sha256 (default: stage-1 frozen '
                         'constant; PREREG-G-STAGE2 passes its own)')
    ap.add_argument('--out', default=None,
                    help='state dir (default $TMPDIR/g3-artifacts/run)')
    ap.add_argument('--lock-dir', default=None,
                    help='device lock dir (default $TMPDIR/wm-device.lock)')
    ap.add_argument('--venv-python', default=VENV_PYTHON_DEFAULT)
    ap.add_argument('--seed', type=int, default=SEED_DEFAULT)
    ap.add_argument('--max-min', type=float, default=None,
                    help='orchestrator wall budget; clean stop BETWEEN arms')
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args(argv)
    tmp = os.environ.get('TMPDIR') or '/tmp'
    if args.out is None:
        args.out = os.path.join(tmp, 'g3-artifacts', 'run')
    if args.lock_dir is None:
        args.lock_dir = os.path.join(tmp, 'wm-device.lock')
    try:
        if args.arm:
            return run_arm(args)
        return orchestrate(args)
    except RuntimeError as exc:
        code, _, detail = str(exc).partition(': ')
        return fail(code if code.isupper() else 'INTERNAL', detail)
    except OSError as exc:
        return fail('STATE_UNWRITABLE', str(exc))
    finally:
        release_lock_if_held()


if __name__ == '__main__':
    sys.exit(main())
