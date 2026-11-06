#!/usr/bin/env python3
"""p2_practice_pass.py - P-2/P-2b per-pass practice command (--practice-cmd
glue for p2_runner.py; closes the NAMED gap PRACTICE_CMD_MISSING).

CONTRACT (p2_runner.py delegation contract, FROZEN there): invoked as
`/bin/zsh -lc <cmd>` ONCE PER PASS with env
  WM_VARIANT      p2 | p2b
  WM_PASS_INDEX   1-based pass index
  WM_PASS_BUDGET  total passes for this (variant, budget)
  WM_POOL_DIR     practice pool dir (p2: paper exp8 pool; p2b: builder output)
  WM_WORK_DIR     runner work dir; MUST contain edit_manifest.json
                  {"edit_submitted": bool, "model_dir": str|null} after the
                  passes of one (variant, budget) complete.
Optional env (direct-cell flow under a device budget, never in a runner run):
  WM_BUILD_EDIT_NOW=1  build the edit at this pass even when
                       WM_PASS_INDEX < WM_PASS_BUDGET (the receipt records
                       passes_completed < budget: BUDGET_PARTIAL).

PASS SEMANTICS (task spec 2026-11-06, pre-run):
  pass k = capture activations (FROZEN tool/eval/capture_activations.py, venv)
  on practice batch k = the next 128 pool-file-order prompts of
  math_train.jsonl (p2) / p2b_math_train.jsonl (p2b); behavior-defined
  contrast WITHIN the batch: prompts whose greedy continuation (cap 1024,
  frozen wm_qwen35_generate.py surface) hits the cap = LOOP set, the rest =
  NEUTRAL. Per-pass set sizes are recorded; a pass whose loop set (or, named
  symmetrically, neutral set) is EMPTY contributes NO update and is recorded
  as such. Unit diff-of-means direction per pass comes from the FROZEN
  proposer tool/runs/a3_propose.py (PREREG-D primary proposer; never
  re-implemented here). Cumulative mean direction over passes 1..k is the
  arithmetic mean of the CONTRIBUTING passes' unit directions (per layer).
  direction_estimate_<k>.json + pass_receipt.json are emitted per pass and
  copied into WM_WORK_DIR.

EDIT SPEC AT EVAL = apply_delta spec (FROZEN tool/eval/apply_delta.py):
  tensor   model.language_model.layers.{15,19}.mlp.down_proj.weight
           (the paper's edited tensors; A1 audit rows in VERDICTS.md,
           shape [1024, 3584] each)
  columns  64 per tensor, PRE-RUN deterministic draw recorded before any
           measurement: sorted(Random(20261105*1000+1).sample(range(3584),
           64)) - the a3_design.pair_columns procedure generalized to this
           cast's column count with the program blinding seed; the same draw
           for both layers (A3 pair convention); digest-recorded in
           columns_draw.json on first use.
  direction  -cumulative_mean_unit (REMOVAL sign convention: A3/V-3 repair
           spec = -scale x recovered unit direction; the cumulative mean is
           RENORMALIZED to unit before the spec so the scale ladder means
           the same thing it meant on the A3 cast - NAMED
           CUMULATIVE_MEAN_RENORMALIZED_UNIT).
  scale    s in {2.4, 4.8, 9.6} sensitivity triple; ALL THREE are built and
           recorded as DATA, never select-best. s=4.8 is the manifest's
           model_dir (primary) under the NAMED assumption
           CROSS_CAST_TRANSFER_ASSUMPTION_S4.8: 4.8 was the certified repair
           scale on the A3 primary cast (qwen3-0.6b-bf16); its transfer to
           Qwen3.5-0.8B is an assumption, and the V-3 SCALE_UNCALIBRATABLE
           verdict on qwen3-1.7b-4bit is the recorded counterexample that
           makes the triple necessary.
Mirrors are built with FROZEN-behavior tool/runs/make_mirror.py (base store
verified unchanged; edit confined to the spec columns; UNCHANGED reuse per
WS-1 receipt convention). The base store is opened read-only by the frozen
tools; mirrors live under --mirror-root ($TMPDIR, probe-scratch law).

DEVICE LOCK protocol v3 (house law): mkdir <lock-dir> per device batch
(<= ~20 min), 10 s acquisition retries bounded 360x (=1 h), rmdir + 3 s
courtesy between batches, every wait receipted, contention-chunk wall_ms
are NON-CLAIMS.

Usage (the zsh command the runner executes embeds the static flags):
  <venv-python> -I tool/runs/p2_practice_pass.py \
      --model <base-store-dir> [--state-dir DIR] [--mirror-root DIR] \
      [--lock-dir DIR] [--batch-size 128] [--cont-cap 1024] \
      [--gen-chunk 24] [--scales 2.4,4.8,9.6] [--layers 15,19] \
      [--cols 64] [--seed 20261105] [--max-min M] [--dry-run]

--dry-run prints the pass plan (pool file + digest, batch slice, render/gen/
capture/propose/build steps, tool paths + digests, columns draw) as JSON on
stdout, exit 0. No device, no mlx import, no state writes.

Exit codes (errors NAMED on stderr as 'CODE: detail', never silent):
  0  pass complete (direction_estimate_k.json + receipt written; on the
     budget's last pass or WM_BUILD_EDIT_NOW=1 also edit_manifest.json)
  1  named error:
       ENV_MISSING / ENV_INVALID        WM_* contract violation
       POOL_FILE_MISSING                variant's pool jsonl absent
       POOL_BATCH_SHORT                 pool has < k*batch_size rows
       ROW_TEXT_MISSING                 a batch row has no problem/question
       RENDER_FAILED                    chat-template render error (named)
       BASE_MODEL_MISSING               --model dir absent
       TOOL_MISSING                     a frozen tool path is absent
       COLUMNS_DRAW_FAILED              base safetensors header unreadable /
                                        tensor absent / shape unexpected
       GENERATOR_FAILED                 continuation chunk non-zero (tail)
       CHUNK_ROW_COUNT                  generator wrote != expected rows
       CAPTURE_FAILED / PROPOSE_FAILED / APPLY_DELTA_FAILED / MIRROR_FAILED
                                        frozen-tool step non-zero (tail)
       PASS_INCOMPLETE_BUDGET_STOP      --max-min exhausted mid-pass (state
                                        is resume-safe; rerun to continue)
       DEVICE_LOCK_TIMEOUT              bounded lock wait exhausted
       STATE_UNWRITABLE                 state/work dir cannot be written
  2  MLX_UNAVAILABLE surfaced from a frozen tool (rc 2 passthrough)
"""

import argparse
import hashlib
import json
import os
import random
import shutil
import signal
import struct
import subprocess
import sys
import time
from datetime import datetime, timezone

_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
_PKG_DIR = os.path.dirname(os.path.dirname(_SCRIPT_DIR))
_PKGS_DIR = os.path.dirname(_PKG_DIR)

EVAL_TOOLS = os.path.join(_PKG_DIR, 'tool', 'eval')
CAPTURE_TOOL = os.path.join(EVAL_TOOLS, 'capture_activations.py')
APPLY_DELTA_TOOL = os.path.join(EVAL_TOOLS, 'apply_delta.py')
PROPOSE_TOOL = os.path.join(_SCRIPT_DIR, 'a3_propose.py')
MAKE_MIRROR_TOOL = os.path.join(_SCRIPT_DIR, 'make_mirror.py')
GENERATOR_DEFAULT = os.path.join(
    _PKGS_DIR, 'xsoulspace_inference_mlx_native', 'tool', 'nursery',
    'wm_qwen35_generate.py')
VENV_PYTHON_DEFAULT = os.path.expanduser('~/.local/share/wm-mlx/bin/python')

MATH_INSTRUCTION = ('Please reason step by step, and put your final answer '
                    'within \\boxed{}.')
TENSOR_TEMPLATE = 'model.language_model.layers.%s.mlp.down_proj.weight'
POOL_FILE_FOR_VARIANT = {'p2': 'math_train.jsonl',
                         'p2b': 'p2b_math_train.jsonl'}
PRIMARY_SCALE = 4.8   # manifest model_dir; CROSS_CAST_TRANSFER_ASSUMPTION_S4_8
SHARD_REL = 'model.safetensors'   # staged base store layout (make_mirror)

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
    print('PASS_INTERRUPTED: signal %d (lock released)' % signum,
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


def sha256_floats(vals):
    return hashlib.sha256(
        json.dumps([round(v, 10) for v in vals]).encode()).hexdigest()


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


def power_facts():
    """POWER.md facts beside every number (state recorded; ms non-claims)."""
    out = {}
    try:
        ps = subprocess.run(['pmset', '-g', 'ps'], capture_output=True,
                            text=True, timeout=15)
        out['source'] = ps.stdout.splitlines()[0].strip().strip("'") \
            if ps.stdout else 'unknown'
    except (OSError, subprocess.SubprocessError):
        out['source'] = 'unknown'
    try:
        ioreg = subprocess.run(['ioreg', '-rn', 'AppleSmartBattery'],
                               capture_output=True, text=True, timeout=15)
        for ln in ioreg.stdout.splitlines():
            if '"Amperage"' in ln:
                out['amperage_mA'] = ln.split('=')[-1].strip()
                break
    except (OSError, subprocess.SubprocessError):
        out['amperage_mA'] = 'NA'
    return out


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


def run_locked(lock_dir, argv, state_dir, receipt, what, cwd=None):
    """One device batch under the v3 lock: acquire (10 s retries, bounded),
    run, release + 3 s courtesy; waits and power receipted."""
    waited_ms, interval = a3_lock.acquire(
        lock_dir, attempts=a3_lock.V3_ATTEMPTS, sleep_s=a3_lock.V3_SLEEP_S)
    _LOCK_HELD['dir'] = lock_dir
    p_start = power_facts()
    t0 = time.time()
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, cwd=cwd)
    finally:
        wall = time.time() - t0
        release_lock_if_held()
        time.sleep(3)   # courtesy yield (protocol v3)
    p_end = power_facts()
    add_device_time(state_dir, wall, what)
    receipt['device_batches'].append({
        'what': what, 'argv': argv, 'exit': proc.returncode,
        'wall_ms': int(wall * 1000), 'wall_ms_claim': False,
        'lock_wait_ms': waited_ms, 'lock_retry_interval_s': interval,
        'power_start': p_start, 'power_end': p_end,
        'started_utc': now()})
    return proc


def run_tool(argv, receipt, what):
    """CPU-only frozen tool step (no lock)."""
    t0 = time.time()
    proc = subprocess.run(argv, capture_output=True, text=True)
    receipt['tool_steps'].append({
        'what': what, 'argv': argv, 'exit': proc.returncode,
        'wall_ms': int((time.time() - t0) * 1000)})
    return proc


# --------------------------------------------------------------------------
# Pool batch + prompt rendering
# --------------------------------------------------------------------------

def pool_file(pool_dir, variant):
    name = POOL_FILE_FOR_VARIANT.get(variant)
    if name is None:
        raise RuntimeError('ENV_INVALID: WM_VARIANT %r not in %s'
                           % (variant, sorted(POOL_FILE_FOR_VARIANT)))
    path = os.path.join(pool_dir, name)
    if not os.path.isfile(path):
        raise RuntimeError('POOL_FILE_MISSING: %s (variant %s; dir has %s)'
                           % (path, variant, sorted(os.listdir(pool_dir))
                              if os.path.isdir(pool_dir) else 'NO DIR'))
    return path


def batch_rows(path, k, batch_size):
    rows = []
    with open(path, 'r', encoding='utf-8') as fh:
        for i, ln in enumerate(fh):
            if i < (k - 1) * batch_size:
                continue
            if i >= k * batch_size:
                break
            if not ln.strip():
                continue
            try:
                rows.append((i, json.loads(ln)))
            except ValueError as exc:
                raise RuntimeError('POOL_ROW_MALFORMED: %s line %d (%s)'
                                   % (path, i + 1, exc))
    if len(rows) < batch_size:
        # a short FINAL slice is still a short batch: the spec is 128 in pool
        # file order; running off the end of the pool is a named refusal.
        raise RuntimeError('POOL_BATCH_SHORT: batch %d needs rows [%d,%d); '
                           'pool yielded %d (file exhausted)'
                           % (k, (k - 1) * batch_size, k * batch_size,
                              len(rows)))
    return rows


def render_prompts(model_dir, problems, out_path):
    """Same render as the A2-local frozen convention (build_a2_prompts.py,
    receipted there): problem + newline + Qwen MATH instruction as the user
    turn of the THINKING chat template (enable_thinking=True,
    add_generation_prompt=True), one-lined (\\n, \\r -> ' '; runs not
    collapsed) for the frozen line-based prompts-file protocol.
    NAMED decision PRACTICE_RENDER_SAME_AS_A2 (recorded in the receipt)."""
    from transformers import AutoTokenizer  # runtime import (venv)
    tok = AutoTokenizer.from_pretrained(model_dir)

    def one_line(s):
        return s.replace('\r', ' ').replace('\n', ' ')

    lines = []
    for idx, problem in problems:
        content = problem + '\n' + MATH_INSTRUCTION
        try:
            r = tok.apply_chat_template(
                [{'role': 'user', 'content': content}],
                tokenize=False, add_generation_prompt=True,
                enable_thinking=True)
        except Exception as exc:  # noqa: BLE001 - named, never silent
            raise RuntimeError('RENDER_FAILED: row %d: %s: %s'
                               % (idx, type(exc).__name__, exc))
        r = one_line(r)
        if not r.strip():
            raise RuntimeError('RENDER_FAILED: row %d rendered empty' % idx)
        lines.append(r)
    tmp = out_path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(lines) + '\n')
    os.replace(tmp, out_path)


# --------------------------------------------------------------------------
# Columns draw (PRE-RUN, digest-recorded before any measurement)
# --------------------------------------------------------------------------

def read_tensor_shape(base_dir, tensor):
    shard = os.path.join(base_dir, SHARD_REL)
    if not os.path.isfile(shard):
        # tolerate the raw hub layout too (header read only)
        cands = [n for n in sorted(os.listdir(base_dir))
                 if n.endswith('.safetensors')]
        if not cands:
            raise RuntimeError('COLUMNS_DRAW_FAILED: no safetensors in %s'
                               % base_dir)
        shard = os.path.join(base_dir, cands[0])
    with open(shard, 'rb') as fh:
        n = struct.unpack('<Q', fh.read(8))[0]
        header = json.loads(fh.read(n))
    if tensor not in header:
        raise RuntimeError('COLUMNS_DRAW_FAILED: tensor %s absent from %s '
                           'header' % (tensor, shard))
    return header[tensor]['shape'], shard


def columns_draw(state_dir, base_dir, layers, cols, seed, receipt):
    path = os.path.join(state_dir, 'columns_draw.json')
    if os.path.isfile(path):
        draw = json.load(open(path, encoding='utf-8'))
        receipt['columns_draw'] = dict(draw, reused=True)
        return draw
    probe_tensor = TENSOR_TEMPLATE % layers[0]
    shape, shard = read_tensor_shape(base_dir, probe_tensor)
    if len(shape) != 2:
        raise RuntimeError('COLUMNS_DRAW_FAILED: %s shape %r not 2-D'
                           % (probe_tensor, shape))
    rows, n_cols = shape
    if cols > n_cols:
        raise RuntimeError('COLUMNS_DRAW_FAILED: cols %d > tensor columns %d'
                           % (cols, n_cols))
    columns = sorted(random.Random(seed * 1000 + 1).sample(range(n_cols),
                                                           cols))
    draw = {
        'schema': 'p2-columns-draw/v1',
        'rule': ('sorted(Random(seed*1000+1).sample(range(n_cols), cols)); '
                 'a3_design.pair_columns procedure generalized to this '
                 'cast; same draw for every edited layer (A3 pair '
                 'convention); PRE-RUN, recorded before any measurement'),
        'seed': seed, 'cols': cols, 'n_cols': n_cols, 'rows': rows,
        'probe_tensor': probe_tensor, 'probe_shard': shard,
        'columns': columns, 'columns_sha256': sha256_floats(columns),
        'created_utc': now(),
    }
    atomic_write_json(path, draw)
    receipt['columns_draw'] = draw
    return draw


# --------------------------------------------------------------------------
# Pass
# --------------------------------------------------------------------------

def gen_continuations(args, pass_dir, prompts_path, n_prompts, receipt,
                      budget_deadline):
    """Greedy continuations at --cont-cap in lock-batched chunks; resume-safe
    (an existing chunk with the expected row count is skipped, recorded)."""
    gens_path = os.path.join(pass_dir, 'continuations.jsonl')
    manifest_path = os.path.join(pass_dir, 'cont_manifest.jsonl')
    chunk_dir = os.path.join(pass_dir, 'chunks')
    os.makedirs(chunk_dir, exist_ok=True)
    all_rows = []
    start = 0
    nn = 0
    while start < n_prompts:
        if budget_deadline and time.time() > budget_deadline:
            raise BudgetStop(start)
        end = min(start + args.gen_chunk, n_prompts)
        cfile = os.path.join(pass_dir, 'cont_chunk%02d.jsonl' % nn)
        expected = end - start
        if os.path.isfile(cfile):
            with open(cfile, 'r', encoding='utf-8') as fh:
                rows = [json.loads(ln) for ln in fh if ln.strip()]
            if len(rows) == expected:
                receipt['resumed_chunks'].append(nn)
                all_rows.extend(rows)
                start = end
                nn += 1
                continue
        pfile = os.path.join(chunk_dir, 'cont_chunk%02d.txt' % nn)
        with open(prompts_path, 'r', encoding='utf-8') as src, \
                open(pfile, 'w', encoding='utf-8') as dst:
            for i, ln in enumerate(src):
                if start <= i < end:
                    dst.write(ln)
        cmd = [args.venv_python, '-I', args.generate,
               '--model', args.model, '--prompts', pfile,
               '--max-tokens', str(args.cont_cap), '--sampler', 'greedy',
               '--out', cfile]
        proc = run_locked(args.lock_dir, cmd, args.state_dir, receipt,
                          'continuations_chunk%02d[%d,%d)' % (nn, start, end))
        if proc.returncode == EXIT_DEP:
            raise DepUnavailable(proc.stderr[-400:])
        if proc.returncode != 0 or not os.path.isfile(cfile):
            raise StepError('GENERATOR_FAILED',
                            'chunk %d rc=%d stderr-tail=%r'
                            % (nn, proc.returncode, proc.stderr[-400:]))
        with open(cfile, 'r', encoding='utf-8') as fh:
            rows = [json.loads(ln) for ln in fh if ln.strip()]
        if len(rows) != expected:
            raise StepError('CHUNK_ROW_COUNT',
                            'chunk %d wrote %d rows, expected %d'
                            % (nn, len(rows), expected))
        for j, r in enumerate(rows):
            if r.get('prompt_id') != j:
                raise StepError('CHUNK_ROW_COUNT',
                                'chunk %d row %d prompt_id %r != %d'
                                % (nn, j, r.get('prompt_id'), j))
        with open(manifest_path, 'a', encoding='utf-8') as fh:
            fh.write(json.dumps(receipt['device_batches'][-1]) + '\n')
        all_rows.extend(rows)
        start = end
        nn += 1
    with open(gens_path, 'w', encoding='utf-8') as fh:
        for r in all_rows:
            fh.write(json.dumps(r) + '\n')
    return all_rows


class StepError(Exception):
    def __init__(self, code, detail):
        super().__init__('%s: %s' % (code, detail))
        self.code = code


class BudgetStop(Exception):
    def __init__(self, rows_done):
        super().__init__('PASS_INCOMPLETE_BUDGET_STOP at row %d' % rows_done)
        self.rows_done = rows_done


class DepUnavailable(Exception):
    pass


def capture_bank(args, pass_dir, name, prompt_indices, prompts_path,
                 receipt):
    bank_prompts = os.path.join(pass_dir, '%s_prompts.txt' % name)
    with open(prompts_path, 'r', encoding='utf-8') as src:
        lines = src.read().splitlines()
    with open(bank_prompts, 'w', encoding='utf-8') as fh:
        for i in prompt_indices:
            fh.write(lines[i] + '\n')
    out = os.path.join(pass_dir, 'cap_%s.json' % name)
    if os.path.isfile(out):
        receipt['reused_captures'].append(name)
        return out
    cmd = [args.venv_python, '-I', CAPTURE_TOOL, '--model', args.model,
           '--prompts', bank_prompts, '--layers', args.layers, '--out', out]
    proc = run_locked(args.lock_dir, cmd, args.state_dir, receipt,
                      'capture_%s(n=%d)' % (name, len(prompt_indices)))
    if proc.returncode == EXIT_DEP:
        raise DepUnavailable(proc.stderr[-400:])
    if proc.returncode != 0:
        raise StepError('CAPTURE_FAILED', '%s bank rc=%d stderr-tail=%r'
                        % (name, proc.returncode, proc.stderr[-400:]))
    return out


def build_edit(args, variant, k, budget, cum_unit, receipt, pass_dir):
    """apply_delta specs (x layers x scales) -> sidecars -> make_mirror
    mirrors; returns (manifest_obj, build_receipt)."""
    draw = receipt['columns_draw']
    columns = draw['columns']
    build = {'schema': 'p2-edit-build/v1', 'created_utc': now(),
             'variant': variant, 'pass_k': k, 'pass_budget': budget,
             'passes_completed': k,
             'budget_partial': k < budget,
             'tensor_template': TENSOR_TEMPLATE,
             'columns_sha256': draw['columns_sha256'], 'columns_n': len(columns),
             'sign_convention': ('direction = -cumulative_mean_unit (REMOVAL; '
                                 'A3/V-3 repair-spec convention)'),
             'renorm_note': ('CUMULATIVE_MEAN_RENORMALIZED_UNIT: the '
                             'cumulative mean of per-pass unit directions is '
                             'renormalized to unit before the spec so the '
                             'scale ladder keeps its A3 meaning'),
             'scale_assumption': ('CROSS_CAST_TRANSFER_ASSUMPTION_S4.8: '
                                  's=4.8 was the certified repair scale on '
                                  'the A3 primary cast (qwen3-0.6b-bf16); '
                                  'transfer to Qwen3.5-0.8B is an ASSUMPTION '
                                  '- all three scales are recorded as data, '
                                  'never select-best (V-3 '
                                  'SCALE_UNCALIBRATABLE on qwen3-1.7b-4bit '
                                  'is the recorded counterexample)'),
             'scales': {}}
    mirrors = {}
    sidecar_root = os.path.join(args.state_dir, variant, 'sidecars')
    for s in args.scales:
        sname = ('%g' % s)
        sidecars = []
        spec_digests = {}
        for layer in args.layers.split(','):
            direction = [-x for x in cum_unit[layer]]
            spec = {'tensor': TENSOR_TEMPLATE % layer,
                    'columns': list(columns),
                    'direction': direction,
                    'scale': float(s)}
            spec_dir = os.path.join(sidecar_root, 's%s' % sname,
                                    'L%s' % layer)
            os.makedirs(spec_dir, exist_ok=True)
            spec_path = os.path.join(spec_dir, 'spec.json')
            atomic_write_json(spec_path, spec)
            spec_digests[layer] = sha256_file(spec_path)
            proc = run_tool([args.venv_python, '-I', APPLY_DELTA_TOOL,
                             '--base', args.model, '--spec', spec_path,
                             '--out', spec_dir], receipt,
                            'apply_delta_s%s_L%s' % (sname, layer))
            if proc.returncode != 0:
                raise StepError('APPLY_DELTA_FAILED',
                                's=%s L%s rc=%d stderr-tail=%r'
                                % (s, layer, proc.returncode,
                                   proc.stderr[-400:]))
            sidecars.append(spec_dir)
        mirror = os.path.join(args.mirror_root,
                              '%s_b%d_s%s' % (variant, budget, sname))
        mrecv = mirror + '_receipt.json'
        mirror_complete = (os.path.isdir(mirror)
                           and os.path.isfile(mrecv)
                           and os.path.isfile(os.path.join(mirror,
                                                           SHARD_REL)))
        if mirror_complete:
            receipt['reused_mirrors'].append(mirror)
        else:
            if os.path.isdir(mirror):
                # a half-built mirror (killed mid-copytree) is never reused
                shutil.rmtree(mirror, ignore_errors=True)
            argv = [args.venv_python, '-I', MAKE_MIRROR_TOOL,
                    '--base', args.model, '--out', mirror,
                    '--receipt', mrecv]
            for sc in sidecars:
                argv += ['--sidecar', sc]
            # make_mirror loads/merges via mx (brief Metal touch): run it
            # under the device lock like every model-touching step.
            proc = run_locked(args.lock_dir, argv, args.state_dir, receipt,
                              'make_mirror_s%s' % sname)
            if proc.returncode != 0:
                if os.path.isdir(mirror):
                    shutil.rmtree(mirror, ignore_errors=True)
                raise StepError('MIRROR_FAILED',
                                's=%s rc=%d stderr-tail=%r'
                                % (s, proc.returncode, proc.stderr[-400:]))
        mirrors[sname] = mirror
        build['scales'][sname] = {
            'scale': s, 'mirror': mirror,
            'spec_sha256': spec_digests,
            'direction_sha256': {l: sha256_floats(cum_unit[l])
                                 for l in cum_unit},
        }
    build['mirrors'] = mirrors
    build['primary_scale'] = PRIMARY_SCALE
    manifest = {'edit_submitted': True,
                'model_dir': mirrors['%g' % PRIMARY_SCALE]}
    return manifest, build


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--model', required=True,
                    help='base checkpoint dir (staged store; tokenizer + '
                         'weights) used for continuations and capture')
    ap.add_argument('--state-dir', default=None,
                    help='persistent per-variant pass state (default '
                         '$TMPDIR/p2-artifacts/run)')
    ap.add_argument('--mirror-root', default=None,
                    help='mirror output root (default $TMPDIR/p2-artifacts/'
                         'mirrors; probe-scratch law)')
    ap.add_argument('--lock-dir', default=None,
                    help='device lock dir (default $TMPDIR/wm-device.lock)')
    ap.add_argument('--generate', default=GENERATOR_DEFAULT)
    ap.add_argument('--venv-python', default=VENV_PYTHON_DEFAULT)
    ap.add_argument('--batch-size', type=int, default=128)
    ap.add_argument('--cont-cap', type=int, default=1024)
    ap.add_argument('--gen-chunk', type=int, default=24)
    ap.add_argument('--scales', default='2.4,4.8,9.6')
    ap.add_argument('--layers', default='15,19')
    ap.add_argument('--cols', type=int, default=64)
    ap.add_argument('--seed', type=int, default=20261105)
    ap.add_argument('--max-min', type=float, default=None,
                    help='wall budget; clean stop BETWEEN chunks; an '
                         'unfinished pass exits non-zero (resume-safe)')
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args(argv)

    tmp = os.environ.get('TMPDIR') or '/tmp'
    if args.state_dir is None:
        args.state_dir = os.path.join(tmp, 'p2-artifacts', 'run')
    if args.mirror_root is None:
        args.mirror_root = os.path.join(tmp, 'p2-artifacts', 'mirrors')
    if args.lock_dir is None:
        args.lock_dir = os.path.join(tmp, 'wm-device.lock')
    try:
        args.scales = [float(x) for x in args.scales.split(',') if x.strip()]
    except ValueError:
        return fail('ENV_INVALID', '--scales %r' % args.scales)
    if PRIMARY_SCALE not in args.scales:
        return fail('ENV_INVALID', 'primary scale %g not in --scales %s'
                    % (PRIMARY_SCALE, args.scales))

    env = os.environ
    variant = env.get('WM_VARIANT')
    k = env.get('WM_PASS_INDEX')
    budget = env.get('WM_PASS_BUDGET')
    pool_dir = env.get('WM_POOL_DIR')
    work_dir = env.get('WM_WORK_DIR')
    for name, val in (('WM_VARIANT', variant), ('WM_PASS_INDEX', k),
                      ('WM_PASS_BUDGET', budget), ('WM_POOL_DIR', pool_dir),
                      ('WM_WORK_DIR', work_dir)):
        if not val:
            return fail('ENV_MISSING', name)
    try:
        k = int(k)
        budget = int(budget)
    except ValueError:
        return fail('ENV_INVALID', 'WM_PASS_INDEX/WM_PASS_BUDGET not int')
    if not (1 <= k <= budget):
        return fail('ENV_INVALID', 'pass %d outside [1,%d]' % (k, budget))
    if variant not in POOL_FILE_FOR_VARIANT:
        return fail('ENV_INVALID', 'WM_VARIANT %r' % variant)
    build_now = env.get('WM_BUILD_EDIT_NOW') == '1' or k == budget

    for tool in (CAPTURE_TOOL, PROPOSE_TOOL, APPLY_DELTA_TOOL,
                 MAKE_MIRROR_TOOL, args.generate, args.venv_python):
        if not os.path.isfile(tool):
            return fail('TOOL_MISSING', tool)
    if not os.path.isdir(args.model):
        return fail('BASE_MODEL_MISSING', args.model)

    try:
        pfile = pool_file(pool_dir, variant)
    except RuntimeError as exc:
        return fail(*str(exc).split(': ', 1))
    pool_sha = sha256_file(pfile)

    try:
        rows = batch_rows(pfile, k, args.batch_size)
    except (RuntimeError, ValueError) as exc:
        code, _, detail = str(exc).partition(': ')
        return fail(code if code.isupper() else 'POOL_BATCH_SHORT', detail)
    problems = []
    for idx, row in rows:
        text = row.get('problem') or row.get('question')
        if not isinstance(text, str) or not text.strip():
            return fail('ROW_TEXT_MISSING', 'pool row %d' % idx)
        problems.append((idx, text))

    if args.dry_run:
        draw_path = os.path.join(args.state_dir, 'columns_draw.json')
        plan = {
            'mode': 'dry-run', 'tool': 'p2_practice_pass.py',
            'variant': variant, 'pass': k, 'budget': budget,
            'pool_file': pfile, 'pool_sha256': pool_sha,
            'batch_rows': [(i, None) for i, _ in problems],
            'batch_size': len(problems),
            'contrast': {'cont_cap': args.cont_cap, 'sampler': 'greedy',
                         'rule': ('hit_token_limit => LOOP; else NEUTRAL; '
                                  'empty either set => NO UPDATE recorded')},
            'render': 'thinking chat template + MATH instruction, one-lined '
                      '(PRACTICE_RENDER_SAME_AS_A2)',
            'tools': {p: sha256_file(p) for p in
                      (CAPTURE_TOOL, PROPOSE_TOOL, APPLY_DELTA_TOOL,
                       MAKE_MIRROR_TOOL, args.generate)},
            'layers': args.layers, 'cols': args.cols, 'seed': args.seed,
            'scales': args.scales, 'primary_scale': PRIMARY_SCALE,
            'build_edit_at_this_pass': build_now,
            'columns_draw': (json.load(open(draw_path, encoding='utf-8'))
                             if os.path.isfile(draw_path) else
                             'PRE-RUN draw at first real use'),
            'gen_chunk': args.gen_chunk,
            'lock': {'dir': args.lock_dir, 'protocol': 'v3 (10s retries, '
                     '<=20min batches, rmdir+3s courtesy, waits receipted)'},
            'note': 'plan only; no device; nothing written',
        }
        print(json.dumps(plan, indent=1))
        return EXIT_OK

    var_dir = os.path.join(args.state_dir, variant)
    pass_dir = os.path.join(var_dir, 'pass_%03d' % k)
    try:
        os.makedirs(pass_dir, exist_ok=True)
        os.makedirs(work_dir, exist_ok=True)
        os.makedirs(args.mirror_root, exist_ok=True)
    except OSError as exc:
        return fail('STATE_UNWRITABLE', str(exc))

    receipt = {'schema': 'p2-pass-receipt/v1', 'variant': variant,
               'pass': k, 'budget': budget, 'created_utc': now(),
               'pool_file': pfile, 'pool_sha256': pool_sha,
               'model': os.path.abspath(args.model),
               'device_batches': [], 'tool_steps': [],
               'resumed_chunks': [], 'reused_captures': [],
               'reused_mirrors': [],
               'constants': {'batch_size': args.batch_size,
                             'cont_cap': args.cont_cap,
                             'gen_chunk': args.gen_chunk,
                             'sampler': 'greedy', 'layers': args.layers,
                             'cols': args.cols, 'seed': args.seed,
                             'scales': args.scales}}
    deadline = (time.time() + args.max_min * 60) if args.max_min else None

    try:
        draw = columns_draw(args.state_dir, args.model,
                            args.layers.split(','), args.cols, args.seed,
                            receipt)
        prompts_path = os.path.join(pass_dir, 'batch_prompts.txt')
        if os.path.isfile(prompts_path):
            with open(prompts_path, 'r', encoding='utf-8') as fh:
                n_lines = sum(1 for ln in fh if ln.strip())
            if n_lines != len(problems):
                raise StepError('STATE_UNWRITABLE',
                                'cached batch_prompts.txt has %d lines, '
                                'expected %d' % (n_lines, len(problems)))
            receipt['render_reused'] = True
        else:
            render_prompts(args.model, problems, prompts_path)
            receipt['render_reused'] = False
        receipt['batch_prompts_sha256'] = sha256_file(prompts_path)

        gen_rows = gen_continuations(args, pass_dir, prompts_path,
                                     len(problems), receipt, deadline)
        loop_idx = [i for i, r in enumerate(gen_rows)
                    if r.get('hit_token_limit')]
        neutral_idx = [i for i, r in enumerate(gen_rows)
                       if not r.get('hit_token_limit')]
        receipt['set_sizes'] = {'loop': len(loop_idx),
                                'neutral': len(neutral_idx)}
        receipt['loop_indices'] = loop_idx

        est_path = os.path.join(pass_dir, 'direction_estimate_%d.json' % k)
        cum_state_path = os.path.join(var_dir, 'cumulative_state.json')
        cum_state = {'schema': 'p2-cumulative-state/v1', 'variant': variant,
                     'passes': [], 'sum': {}, 'contributing': []}
        if os.path.isfile(cum_state_path):
            cum_state = json.load(open(cum_state_path, encoding='utf-8'))

        no_update = None
        pass_direction = None
        if not loop_idx:
            no_update = 'EMPTY_LOOP_SET_NO_UPDATE'
        elif not neutral_idx:
            no_update = 'EMPTY_NEUTRAL_SET_NO_UPDATE'
        if no_update is None:
            cap_loop = capture_bank(args, pass_dir, 'loop', loop_idx,
                                    prompts_path, receipt)
            cap_neutral = capture_bank(args, pass_dir, 'neutral',
                                       neutral_idx, prompts_path, receipt)
            recovered_path = os.path.join(pass_dir, 'recovered.json')
            proc = run_tool([sys.executable, '-I', PROPOSE_TOOL,
                             '--cap-loop', cap_loop, '--cap-neutral',
                             cap_neutral, '--out', recovered_path],
                            receipt, 'a3_propose_pass%d' % k)
            if proc.returncode != 0:
                raise StepError('PROPOSE_FAILED',
                                'rc=%d stderr-tail=%r'
                                % (proc.returncode, proc.stderr[-400:]))
            recovered = json.load(open(recovered_path, encoding='utf-8'))
            pass_direction = recovered['layers']
            receipt['recovered_sha256'] = sha256_file(recovered_path)
            receipt['capture_sha256'] = {'loop': sha256_file(cap_loop),
                                         'neutral': sha256_file(cap_neutral)}
            # cumulative update
            for lname, ldata in pass_direction.items():
                cur = cum_state['sum'].get(lname)
                if cur is None:
                    cur = [0.0] * len(ldata['direction'])
                    cum_state['sum'][lname] = cur
                for j, v in enumerate(ldata['direction']):
                    cur[j] += v
            already = any(p.get('k') == k for p in cum_state['passes'])
            if not already:
                cum_state['passes'].append(
                    {'k': k, 'set_sizes': receipt['set_sizes'],
                     'direction_sha256': {
                         l: d['direction_sha256']
                         for l, d in pass_direction.items()}})
                cum_state['contributing'].append(k)
        else:
            already = any(p.get('k') == k and p.get('no_update')
                          for p in cum_state['passes'])
            if not already:
                cum_state['passes'].append(
                    {'k': k, 'set_sizes': receipt['set_sizes'],
                     'no_update': no_update})

        contributing = cum_state['contributing']
        cum_mean = {}
        cum_unit = {}
        for lname, vec in cum_state['sum'].items():
            n = len(contributing)
            mean = [v / n for v in vec] if n else list(vec)
            norm = sum(x * x for x in mean) ** 0.5
            cum_mean[lname] = {'vector': mean, 'norm': norm}
            if norm > 0:
                cum_unit[lname] = [x / norm for x in mean]
        atomic_write_json(cum_state_path, cum_state)

        estimate = {
            'schema': 'p2-direction-estimate/v1',
            'variant': variant, 'k': k, 'budget': budget,
            'pool_file': pfile, 'pool_sha256': pool_sha,
            'batch': {'k': k, 'size': len(problems),
                      'pool_rows': [(i, None) for i, _ in problems]},
            'contrast': {'cont_cap': args.cont_cap, 'sampler': 'greedy',
                         'loop_set_size': len(loop_idx),
                         'neutral_set_size': len(neutral_idx),
                         'no_update': no_update},
            'pass_direction': pass_direction,
            'cumulative': {
                'contributing_passes': contributing,
                'no_update_passes': [p['k'] for p in cum_state['passes']
                                     if p.get('no_update')],
                'mean': cum_mean,
                'unit': {l: {'direction': cum_unit[l],
                             'sha256': sha256_floats(cum_unit[l])}
                         for l in cum_unit},
                'renorm_note': 'CUMULATIVE_MEAN_RENORMALIZED_UNIT (spec '
                               'direction = -unit(cumulative mean))',
            },
            'created_utc': now(),
        }
        atomic_write_json(est_path, estimate)
        try:
            shutil.copyfile(est_path, os.path.join(
                work_dir, 'direction_estimate_%d.json' % k))
        except OSError as exc:
            return fail('STATE_UNWRITABLE', 'work_dir copy: %s' % exc)

        manifest_obj = None
        if build_now:
            if not cum_unit or set(cum_unit) != set(
                    str(x) for x in
                    sorted(int(l) for l in args.layers.split(','))):
                manifest_obj = {'edit_submitted': False, 'model_dir': None}
                receipt['no_edit_reason'] = ('NO_DIRECTION_NO_EDIT: no '
                                             'contributing pass produced a '
                                             'cumulative direction over the '
                                             'edit layers %s' % args.layers)
            else:
                manifest_obj, build = build_edit(
                    args, variant, k, budget, cum_unit, receipt, pass_dir)
                atomic_write_json(
                    os.path.join(work_dir, 'edit_build_receipt.json'), build)
        if manifest_obj is not None:
            atomic_write_json(os.path.join(work_dir, 'edit_manifest.json'),
                              manifest_obj)
            receipt['edit_manifest'] = manifest_obj

        receipt['finished_utc'] = now()
        receipt['power_end'] = power_facts()
        atomic_write_json(os.path.join(pass_dir, 'pass_receipt.json'),
                          receipt)
        append_manifest(args.state_dir, {
            'kind': 'pass_complete', 'variant': variant, 'k': k,
            'budget': budget, 'at': receipt['finished_utc'],
            'loop_n': len(loop_idx), 'neutral_n': len(neutral_idx),
            'no_update': no_update,
            'contributing_passes': contributing,
            'cumulative_mean_norm': {l: cum_mean[l]['norm']
                                     for l in cum_mean},
            'edit_built': bool(manifest_obj and
                               manifest_obj.get('edit_submitted')),
            'device_wall_s_this_pass': round(sum(
                b['wall_ms'] for b in receipt['device_batches']) / 1000, 1),
            'lock_wait_ms_total': sum(
                b['lock_wait_ms'] for b in receipt['device_batches']),
            'pass_receipt': os.path.join(pass_dir, 'pass_receipt.json'),
            'estimate': est_path})
        print(json.dumps({
            'tool': 'p2_practice_pass.py', 'variant': variant, 'pass': k,
            'budget': budget, 'loop_n': len(loop_idx),
            'neutral_n': len(neutral_idx), 'no_update': no_update,
            'contributing_passes': contributing,
            'estimate': est_path,
            'edit_manifest': (manifest_obj if manifest_obj else
                              'not built at this pass')}))
        return EXIT_OK
    except BudgetStop as exc:
        receipt['budget_stop'] = str(exc)
        try:
            atomic_write_json(os.path.join(pass_dir, 'pass_receipt.json'),
                              receipt)
        except OSError:
            pass
        append_manifest(args.state_dir, {
            'kind': 'pass_incomplete_budget_stop', 'variant': variant,
            'k': k, 'budget': budget, 'at': now(),
            'rows_done': exc.rows_done,
            'device_batches': len(receipt['device_batches'])})
        return fail('PASS_INCOMPLETE_BUDGET_STOP',
                    'pass %d stopped at row %d (resume-safe; rerun the same '
                    'pass to continue)' % (k, exc.rows_done))
    except DepUnavailable as exc:
        return fail('MLX_UNAVAILABLE', str(exc), EXIT_DEP)
    except StepError as exc:
        receipt['error'] = str(exc)
        try:
            atomic_write_json(os.path.join(pass_dir, 'pass_receipt.json'),
                              receipt)
        except OSError:
            pass
        append_manifest(args.state_dir, {
            'kind': 'pass_failed', 'variant': variant, 'k': k,
            'budget': budget, 'at': now(), 'error': str(exc)})
        code, _, detail = str(exc).partition(': ')
        return fail(code, detail)
    except RuntimeError as exc:
        return fail(*str(exc).split(': ', 1))
    finally:
        release_lock_if_held()


if __name__ == '__main__':
    sys.exit(main())
