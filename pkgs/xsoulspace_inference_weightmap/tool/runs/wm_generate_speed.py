#!/usr/bin/env python3
"""wm_generate_speed.py - the L1/L2 speed generation surface (PREREG-SPEED.md
FROZEN 2026-11-10; python-first; the ONLY sanctioned long-cap generation
entry for stage-3+ arms).

Design (why a custom loop, not the frozen batch generator):
  - per-row outputs written IMMEDIATELY on row completion (L2: progress +
    row-level resume; the frozen generator is progress-blind mid-flight);
  - the frozen detector (g3_revision's golden-pinned twin, same constants)
    runs per step: at >= MIN_TOKENS with F_EARLY fires inside T_PROXY the
    row STOPS as LOOP_PROXY (L1) — up to ~30x on loop rows;
  - single process, model loaded once (no per-chunk reloads);
  - resume: rows with existing output files are skipped;
  - power gate AC default, --allow-battery = owner override 2026-11-08;
    device lock v3; PYTHONDONTWRITEBYTECODE; named exits; $TMPDIR scratch.

The qwen3_5 engine path mirrors g3_revision's worker loop (mlx_lm load;
Model.__call__ with per-layer make_cache; G3_ARGMAX_F32 greedy; eos set
from the tokenizer wrapper). Early-stop rows carry finish_reason 'proxy'
with proxy_stop_at recorded — speed_proxy.classify_row validates the policy
bounds offline (never silently conflated with cap_hit).

Usage:
  <venv-python> -I tool/runs/wm_generate_speed.py \
      --model DIR --prompts FILE --max-tokens N --out-dir DIR \
      [--proxy/--no-proxy] [--allow-battery] [--max-min M] [--dry-run]
Exit codes: 0 ok | 1 named error | 2 mlx unavailable.
"""

import argparse
import hashlib
import json
import os
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone

_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _SCRIPT_DIR)

import a3_lock  # noqa: E402
import speed_proxy as sp  # noqa: E402

VENV_PYTHON_DEFAULT = os.path.expanduser('~/.local/share/wm-mlx/bin/python')
EXIT_OK, EXIT_INPUT, EXIT_DEP = 0, 1, 2

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
    print('SPEEDGEN_INTERRUPTED: signal %d (lock released)' % signum,
          file=sys.stderr)
    sys.exit(128 + signum)


signal.signal(signal.SIGTERM, _sigterm)
signal.signal(signal.SIGINT, _sigterm)


def now():
    return datetime.now(timezone.utc).isoformat(timespec='seconds')


def sha256_text(s):
    import hashlib
    return hashlib.sha256(s.encode('utf-8')).hexdigest()


def power_facts():
    try:
        ps = subprocess.run(['pmset', '-g', 'ps'], capture_output=True,
                            text=True, timeout=15)
        return ps.stdout.splitlines()[0].strip().strip("'") \
            if ps.stdout else 'unknown'
    except (OSError, subprocess.SubprocessError):
        return 'unknown'


def detector_module():
    """The FROZEN detector twin lives in g3_revision (golden-pinned in both
    languages). Import lazily so --dry-run stays mlx-free."""
    import g3_revision
    return g3_revision.detector_fires_at, g3_revision.loop_triggers


def read_prompts(path):
    if not os.path.isfile(path):
        raise RuntimeError('PROMPTS_MISSING: %s' % path)
    rows = [ln.rstrip('\n').rstrip('\r') for ln in open(path,
                                                        encoding='utf-8')]
    prompts = [ln for ln in rows if ln.strip()]
    if not prompts:
        raise RuntimeError('PROMPTS_EMPTY: %s' % path)
    return prompts


def dry_run(args, prompts):
    det_fires, _ = detector_module()
    plan = {
        'mode': 'dry-run', 'tool': 'wm_generate_speed.py',
        'model': os.path.abspath(os.path.expanduser(args.model)),
        'rows': len(prompts),
        'prompts_sha256': sha256_text('\n'.join(prompts)),
        'cap': args.max_tokens,
        'proxy': {'enabled': args.proxy, 'constants':
                  [sp.T_PROXY, sp.F_EARLY, sp.MIN_TOKENS],
                  'classification': 'LOOP_PROXY is a NAMED PROXY, never '
                                    'cap_hit (PREREG-SPEED L1)'},
        'per_row_outputs': 'row_%04d.jsonl written immediately on row '
                           'completion (L2); resume skips existing rows',
        'power': {'gate': 'AC default; --allow-battery = owner override '
                          '2026-11-08', 'now': power_facts()},
        'lock': {'dir': args.lock_dir, 'protocol': 'v3'},
        'engine_rev': sha256_text(open(os.path.abspath(__file__),
                                       encoding='utf-8').read()),
        'note': 'plan only; no device, no mlx import, nothing written',
    }
    print(json.dumps(plan, indent=1))
    return EXIT_OK


def run(args):
    if not args.allow_battery and 'AC Power' not in power_facts():
        return fail('POWER_GATE_BATTERY',
                    'AC-only default stands; --allow-battery = owner '
                    'override 2026-11-08 (source: %r)' % power_facts())
    snap = os.path.abspath(os.path.expanduser(args.model))
    if not os.path.isdir(snap):
        return fail('MODEL_DIR_MISSING', snap)
    prompts = read_prompts(args.prompts)
    os.makedirs(args.out_dir, exist_ok=True)
    waited_ms, _ = a3_lock.acquire(args.lock_dir,
                                   attempts=a3_lock.V3_ATTEMPTS,
                                   sleep_s=a3_lock.V3_SLEEP_S)
    _LOCK_HELD['dir'] = args.lock_dir
    deadline = (time.time() + args.max_min * 60) if args.max_min else None
    try:
        import mlx.core as mx
        from mlx_lm import load as mlx_load
        model, tokenizer = mlx_load(snap)
        hf_tok = getattr(tokenizer, 'tokenizer', tokenizer)
        eos_ids = set()
        v = getattr(tokenizer, 'eos_token_ids', None)
        if v:
            eos_ids |= set(v)
        single = getattr(tokenizer, 'eos_token_id', None) or \
            getattr(hf_tok, 'eos_token_id', None)
        if single is not None:
            eos_ids.add(int(single))
        det_fires, _ = detector_module()

        def logsoftmax_f32(logits):
            f32 = logits.astype(mx.float32)
            return f32 - mx.logsumexp(f32, keepdims=True, axis=-1)

        summary = []
        for row_idx, prompt in enumerate(prompts):
            out_path = os.path.join(args.out_dir, 'row_%04d.jsonl' % row_idx)
            if os.path.isfile(out_path):
                summary.append({'row': row_idx, 'status': 'RESUMED_SKIP'})
                continue
            if deadline and time.time() > deadline:
                append_manifest(args.out_dir, {'kind': 'budget_stop',
                                               'row': row_idx, 'at': now()})
                return fail('SPEEDGEN_BUDGET_STOP',
                            'budget exhausted before row %d (resume-safe; '
                            'rerun the same command)' % row_idx)
            rendered = hf_tok.apply_chat_template(
                [{'role': 'user', 'content': prompt + ' /no_think'}],
                add_generation_prompt=True, tokenize=False)
            enc = getattr(tokenizer, 'encode', None)
            ids = enc(rendered) if callable(enc) else \
                hf_tok.encode(rendered)
            prompt_ids = [int(i) for i in ids]
            gen = []
            triggers = []
            finish = 'length'
            proxy_stop_at = None
            cache = model.make_cache()
            y = model(mx.array([prompt_ids]), cache=cache)
            logits = y[0, -1, :]
            t0 = time.perf_counter()
            while len(gen) < args.max_tokens:
                f32 = logits.astype(mx.float32)
                ls = f32 - mx.logsumexp(f32, keepdims=True, axis=-1)
                nxt = int(mx.argmax(ls, axis=-1).item())
                if nxt in eos_ids:
                    finish = 'eos'
                    break
                gen.append(nxt)
                if det_fires(gen):
                    triggers.append(len(gen) - 1)
                    if args.proxy and sp.proxy_stop_decision(
                            len(gen),
                            sp.count_within_proxy(triggers, len(gen))):
                        finish = 'proxy'
                        proxy_stop_at = len(gen)
                        break
                y = model(mx.array([[nxt]]), cache=cache)
                logits = y[0, -1, :]
            row = {
                'schema': 'speedgen-row/v1', 'row': row_idx,
                'prompt_sha256': sha256_text(prompt),
                'generated_ids': gen, 'output':
                    tokenizer.decode(gen) if gen else '',
                'output_tokens': len(gen), 'cap': args.max_tokens,
                'finish_reason': finish, 'proxy_stop_at': proxy_stop_at,
                'trigger_positions': triggers,
                'classification': sp.classify_row(
                    triggers, finish, len(gen), args.max_tokens,
                    proxy_stop_at=proxy_stop_at),
                'wall_ms': round((time.perf_counter() - t0) * 1000, 1),
                'wall_ms_claim': False,
            }
            with open(out_path + '.tmp', 'w', encoding='utf-8') as fh:
                json.dump(row, fh, ensure_ascii=False)
                fh.write('\n')
            os.replace(out_path + '.tmp', out_path)
            summary.append({'row': row_idx, 'status': row['classification'],
                            'tokens': len(gen)})
        append_manifest(args.out_dir, {'kind': 'run_complete',
                                       'rows': len(prompts), 'at': now(),
                                       'summary': summary})
        print(json.dumps({'tool': 'wm_generate_speed.py', 'rows':
                          len(prompts), 'summary': summary}))
        return EXIT_OK
    except RuntimeError as exc:
        code, _, detail = str(exc).partition(': ')
        return fail(code if code.isupper() else 'INTERNAL', detail)
    finally:
        release_lock_if_held()


def append_manifest(out_dir, row):
    path = os.path.join(out_dir, 'manifest.jsonl')
    with open(path, 'a', encoding='utf-8') as fh:
        fh.write(json.dumps(row, sort_keys=False) + '\n')
        fh.flush()
        os.fsync(fh.fileno())


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--model', required=True)
    ap.add_argument('--prompts', required=True)
    ap.add_argument('--max-tokens', type=int, required=True)
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--proxy', dest='proxy', action='store_true',
                    default=True)
    ap.add_argument('--no-proxy', dest='proxy', action='store_false',
                    help='exempt arm (P-* comparability): owe the full cap')
    ap.add_argument('--lock-dir', default=None)
    ap.add_argument('--venv-python', default=VENV_PYTHON_DEFAULT)
    ap.add_argument('--max-min', type=float, default=None)
    ap.add_argument('--allow-battery', action='store_true')
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args(argv)
    if args.max_tokens < 1:
        return fail('MAX_TOKENS_INVALID', str(args.max_tokens))
    if args.lock_dir is None:
        args.lock_dir = os.path.join(os.environ.get('TMPDIR', '/tmp'),
                                     'wm-device.lock')
    if args.dry_run:
        return dry_run(args, read_prompts(args.prompts))
    return run(args)


if __name__ == '__main__':
    sys.exit(main())
