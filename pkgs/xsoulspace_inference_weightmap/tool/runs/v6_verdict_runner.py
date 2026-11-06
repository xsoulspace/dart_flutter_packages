#!/usr/bin/env python3
"""v6_verdict_runner.py - V-6 drift re-certification runner (this run owns it).

Wires the FROZEN tool/runs/v6_matrix.py machinery to the frozen A3/WS-2
generation + scoring semantics. Three modes:

  generate   (DEFAULT; the frozen v6_matrix.py generator-callback surface)
      <venv-python> -I v6_verdict_runner.py --model DIR --prompts FILE \
          --max-tokens N --sampler "greedy"|<cfg-json> --out gens.jsonl
    Reuses the ws2_py_generate.py `generate` pattern verbatim where frozen:
      - greedy: next = argmax(logits - logsumexp(logits, keepdims)) — the
        wm_qwen35_digest.py parity contract (== mlx_lm generate_step's own
        greedy path)
      - EOS stop OFF: exactly cap steps; content_tokens = first generated
        EOS index else cap; cap_hit = content_tokens >= cap (A3 semantics)
      - prefill: chunks of <= 2048 over prompt[:-1]; last prompt token is
        the first decode step
      - per-cell caps come from the prompts file (cells_frozen_A3.json
        surface: G0=64, G2=256); --max-tokens is the PREREG-D ceiling,
        effective cap = min(cell cap, ceiling)  [CAP_SEMANTICS, pre-run]
      - t=0.6: mlx_lm.sample_utils.make_sampler(**cfg); sampler applied to
        logprobs = logits - logsumexp exactly as mlx_lm generate_step does;
        mx.random.seed(SEED=0) once per batch  [SEED_CHOICE +
        RNG_CELL_ORDER_DEPENDENCE, pre-run; PRESENCE_PENALTY_UNSUPPORTED is
        recorded by v6_matrix.py's own protocol notes]
    jsonl rows: the five WS-2 keys {mirror, prompt_id, token_ids, text,
    tokens} + evidence{...} + one __meta__ row (so the frozen Dart certify
    and ws2 tooling parse these files unchanged).

  verdict    (the frozen v6_matrix.py --verdict-cmd delegate; NEVER
    re-implements an oracle — the loop-rate rule is scorers.dart
    tokenLimitRate verbatim: hits = count >= cap, rate = hits/n over the
    12 G2 cells)
      env: WM_CELL_ID WM_CELL_SPEC WM_CELL_GEN WM_CELL_VERDICT_OUT
      python3 -I v6_verdict_runner.py verdict
    Writes {"cell", "verdict": PASS|FAIL, "score", +evidence}:
      score  = tokenLimitRate(G2 content_tokens, cap 256)   [the certified
               behavior_value: A3 arm-002 loop_rate_R = 0.3333333333333333]
      verdict = PASS iff score < LOOP_RATE_M_RECORDED (0.6666666666666666,
               A3 arm-002 join-table) — the loop-rate-DOWN leg of the A3
               certification rule against the FROZEN recorded M baseline
               [V6_VERDICT_RULE, pre-run]. The task-success leg is NOT
               re-evaluated under key changes: V6_TASK_LEG_NOT_RUN (named,
               never silently dropped).

  requant    4bit-requant of a mirror (quant axis)
      <venv-python> -I v6_verdict_runner.py requant --in DIR --out DIR \
          [--group-size 64 --bits 4] --receipt FILE
    Route REQUANT_SOURCE_BF16_NO_DEQUANT (pre-run): the R removal mirror is
    a PLAIN bf16 store, so the task's dequant->requant route has an identity
    dequant leg; the requant leg is mlx_lm.utils.quantize_model(group_size=
    64, bits=4, mode affine — mlx_lm defaults, matching the mlx-community
    4bit cast convention), saved via mlx_lm.utils.save_model + qconfig +
    byte-identical tokenizer-file copies (v3_dequant.py house pattern).

  render-raw  RAW battery rendering (template axis)
      python3 -I v6_verdict_runner.py render-raw --from CHAT_PROMPTS.json \
          --out RAW_PROMPTS.json
    RAW_SURFACE_DEFINITION (pre-run): templated := prompt VERBATIM — the
    chat wrapper AND the ' /no_think' directive are removed together as the
    one frozen chat surface (cells_frozen_A3.json surface.template); pure
    JSON transform of the digest-verified WS-2 chat rendering (no tokenizer
    needed; per-engine plain encode of the raw text happens at generate
    time, add_special_tokens unchanged).

Exit codes (errors NAMED on stderr as 'CODE: detail', never silent):
  0 ok; 1 named error:
    ARGS_INVALID MIRROR_DIR_MISSING PROMPTS_FILE_UNREADABLE PROMPTS_MALFORMED
    MLX_UNAVAILABLE MODEL_LOAD_ERROR OUT_UNWRITABLE SAMPLER_CONFIG_INVALID
    BATTERY_INCOMPLETE CELL_CAP_MISMATCH VERDICT_ENV_MISSING GEN_ROW_MALFORMED
    REQUANT_FAILED CONFIG_MISSING LOAD_SANITY_FAILED CHAT_PROMPTS_UNREADABLE
"""

import argparse
import hashlib
import json
import os
import shutil
import sys
import time
from datetime import datetime, timezone

EXIT_OK = 0
EXIT_FAIL = 1

PREFILL_STEP_SIZE = 2048          # frozen (wm_qwen35_digest.py contract)
SEED = 0                          # SEED_CHOICE (pre-run registration)
G2_GROUP = 'G2'
G2_CAP = 256                      # cells_frozen_A3.json surface.caps
LOOP_RATE_M_RECORDED = 0.6666666666666666   # A3 arm-002 join-table
LOOP_RATE_R_RECORDED = 0.3333333333333333   # A3 arm-002 join-table
REQUIRED_ROW_KEYS = ('mirror', 'prompt_id', 'token_ids', 'text', 'tokens')


def fail(code, detail):
    print('%s: %s' % (code, detail), file=sys.stderr)
    return EXIT_FAIL


def now():
    return datetime.now(timezone.utc).isoformat(timespec='seconds')


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(1 << 22), b''):
            h.update(chunk)
    return h.hexdigest()


# --------------------------------------------------------------------------
# generate mode (frozen v6_matrix.py generator-callback surface)
# --------------------------------------------------------------------------

def load_prompts(path):
    try:
        prompts = json.load(open(path, encoding='utf-8'))
        cells = prompts['cells']
        eos_ids = set(prompts['eos_token_ids'])
        assert isinstance(cells, list) and cells
    except (OSError, ValueError, KeyError, AssertionError) as exc:
        raise SystemExit(fail('PROMPTS_FILE_UNREADABLE',
                              '%s (%s)' % (path, exc)))
    return prompts, cells, eos_ids


def greedy_stream(mx, model, prompt_ids, max_tokens):
    """EXACT ws2_py_generate.py greedy_stream (wm_qwen35_digest.py contract
    minus logits-digest capture): chunked prefill over prompt[:-1], then
    max_tokens steps of next = argmax(logits - logsumexp(logits, keepdims));
    EOS stop OFF."""
    from mlx_lm.models.cache import make_prompt_cache

    cache = make_prompt_cache(model)
    prompt = mx.array(prompt_ids)
    total = len(prompt_ids)
    processed = 0
    cur = prompt
    while total - processed > 1:
        n = min(PREFILL_STEP_SIZE, (total - processed) - 1)
        model(cur[:n][None], cache=cache)
        mx.eval([c.state for c in cache])
        processed += n
        cur = cur[n:]
        mx.clear_cache()

    y = cur
    ids = []
    for _step in range(max_tokens):
        logits = model(y[None], cache=cache)[0, -1, :]
        mx.eval(logits)
        logprobs = logits - mx.logsumexp(logits, keepdims=True)
        next_token = int(mx.argmax(logprobs, axis=-1))
        ids.append(next_token)
        y = mx.array([next_token])
    return ids


def sampled_stream(mx, model, prompt_ids, max_tokens, sampler):
    """Same frozen stream shape as greedy_stream; token choice = the
    make_sampler chain applied to logprobs exactly as mlx_lm generate_step
    does (sampler(logprobs[None])[0]); EOS stop OFF; mx.random.seed(SEED)
    was set once per batch (RNG_CELL_ORDER_DEPENDENCE, pre-run)."""
    from mlx_lm.models.cache import make_prompt_cache

    cache = make_prompt_cache(model)
    prompt = mx.array(prompt_ids)
    total = len(prompt_ids)
    processed = 0
    cur = prompt
    while total - processed > 1:
        n = min(PREFILL_STEP_SIZE, (total - processed) - 1)
        model(cur[:n][None], cache=cache)
        mx.eval([c.state for c in cache])
        processed += n
        cur = cur[n:]
        mx.clear_cache()

    y = cur
    ids = []
    for _step in range(max_tokens):
        logits = model(y[None], cache=cache)[0, -1, :]
        mx.eval(logits)
        logprobs = logits - mx.logsumexp(logits, keepdims=True)
        next_token = int(sampler(logprobs[None])[0])
        ids.append(next_token)
        y = mx.array([next_token])
    return ids


def mode_generate(args):
    if not os.path.isdir(args.model):
        return fail('MIRROR_DIR_MISSING', args.model)
    if args.max_tokens < 1:
        return fail('ARGS_INVALID',
                    '--max-tokens must be >= 1, got %d' % args.max_tokens)
    prompts, cells, eos_ids = load_prompts(args.prompts)

    # sampler resolution (frozen v6 contract: "greedy" | cfg-json)
    sampler_cfg = None
    if args.sampler != 'greedy':
        try:
            sampler_cfg = json.loads(args.sampler)
            assert isinstance(sampler_cfg, dict) and sampler_cfg
        except (ValueError, AssertionError) as exc:
            return fail('SAMPLER_CONFIG_INVALID',
                        '%r (%s)' % (args.sampler, exc))

    try:
        import importlib.metadata as md

        import mlx.core as mx
        from mlx_lm import load
    except ImportError as exc:
        return fail('MLX_UNAVAILABLE', str(exc))

    sampler = None
    sampler_desc = 'greedy: argmax(logits - logsumexp(logits))'
    if sampler_cfg is not None:
        try:
            from mlx_lm.sample_utils import make_sampler
            sampler = make_sampler(**sampler_cfg)
            mx.random.seed(SEED)
            sampler_desc = ('make_sampler(%s) on logprobs; mx.random.seed(%d) '
                            'once per batch'
                            % (json.dumps(sampler_cfg, sort_keys=True), SEED))
        except (TypeError, ValueError) as exc:
            return fail('SAMPLER_CONFIG_INVALID',
                        'make_sampler(%s): %s' % (sampler_cfg, exc))

    shard = os.path.join(args.model, 'model.safetensors')
    model_sha = sha256_file(shard) if os.path.isfile(shard) else None
    try:
        t_load = time.time()
        model, tok = load(args.model)
        load_s = round(time.time() - t_load, 2)
    except Exception as exc:
        return fail('MODEL_LOAD_ERROR', '%s (%s)' % (args.model, exc))
    add_special = tok.bos_token is None
    if add_special != prompts['add_special_tokens']:
        return fail('PROMPTS_MALFORMED',
                    'add_special_tokens drift: prompts file says %s, mirror '
                    'tokenizer says %s' % (prompts['add_special_tokens'],
                                           add_special))

    mirror_name = os.path.basename(os.path.normpath(args.model))
    rows = []
    t_batch = time.time()
    for i, cell in enumerate(cells):
        prompt_ids = [int(x) for x in tok.encode(
            cell['templated'], add_special_tokens=add_special)]
        cap = min(int(cell['cap']), int(args.max_tokens))  # CAP_SEMANTICS
        t0 = time.time()
        if sampler is None:
            ids = greedy_stream(mx, model, prompt_ids, cap)
        else:
            ids = sampled_stream(mx, model, prompt_ids, cap, sampler)
        wall_ms = int((time.time() - t0) * 1000)
        first_eos = next((k for k, t in enumerate(ids) if t in eos_ids), None)
        content_n = first_eos if first_eos is not None else cap
        cap_hit = content_n >= cap
        rows.append({
            'mirror': mirror_name,
            'prompt_id': cell['prompt_id'],
            'token_ids': ids,
            'text': tok.decode(ids),
            'tokens': len(ids),
            'evidence': {
                'engine': 'python_mlxlm',
                'group': cell['group'],
                'cap': cap,
                'prompt_token_ids': prompt_ids,
                'content_tokens': content_n,
                'first_eos_index': first_eos,
                'cap_hit': cap_hit,
                'eos_stop': False,
                'sampler': sampler_desc,
                'seed': (SEED if sampler is not None else None),
                'prefill_step_size': PREFILL_STEP_SIZE,
                'model_dir': os.path.abspath(args.model),
                'model_sha256': model_sha,
                'prompts_file_sha256': sha256_file(args.prompts),
                'load_s': load_s,
                'wall_ms': wall_ms,
                'wall_ms_claim': False,
                'at': now(),
            },
        })
        print('[%d/%d] %s %s tok=%d/%d content=%d hit=%s %.1fs'
              % (i + 1, len(cells), mirror_name, cell['prompt_id'],
                 len(ids), cap, content_n, cap_hit, wall_ms / 1000.0),
              flush=True)

    meta = {
        'mirror': mirror_name,
        'prompt_id': '__meta__',
        'token_ids': [],
        'text': '',
        'tokens': 0,
        'evidence': {
            'engine': 'python_mlxlm',
            'kind': 'batch_meta',
            'tool': 'v6_verdict_runner.py generate',
            'prompts_file': os.path.abspath(args.prompts),
            'prompts_file_sha256': sha256_file(args.prompts),
            'cells': len(rows),
            'batch_wall_s': round(time.time() - t_batch, 1),
            'batch_wall_s_claim': False,
            'max_tokens_ceiling': args.max_tokens,
            'cap_semantics': 'effective cap = min(cell cap, --max-tokens '
                             'ceiling); frozen per-cell caps authoritative',
            'sampler': sampler_desc,
            'mlx_version': md.version('mlx'),
            'mlx_lm_version': md.version('mlx-lm'),
            'transformers_version': md.version('transformers'),
            'python_version': sys.version.split()[0],
            'model_sha256': model_sha,
            'eos_token_ids': sorted(eos_ids),
            'created_utc': now(),
        },
    }
    try:
        out_dir = os.path.dirname(os.path.abspath(args.out))
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        with open(args.out, 'w', encoding='utf-8') as fh:
            for r in rows:
                fh.write(json.dumps(r, ensure_ascii=False) + '\n')
            fh.write(json.dumps(meta, ensure_ascii=False) + '\n')
    except OSError as exc:
        return fail('OUT_UNWRITABLE', str(exc))
    print('GENERATE_OK %s %d cells -> %s' % (mirror_name, len(rows), args.out))
    return EXIT_OK


# --------------------------------------------------------------------------
# verdict mode (frozen battery delegation; scorers.dart tokenLimitRate rule)
# --------------------------------------------------------------------------

def token_limit_rate(counts, cap):
    """scorers.dart tokenLimitRate verbatim: hits = count >= cap; hits/n.
    NONPOSITIVE_CAP / EMPTY_TOKEN_SAMPLE refusals mirrored."""
    if cap <= 0:
        raise ValueError('NONPOSITIVE_CAP: cap must be > 0, got %d' % cap)
    if not counts:
        raise ValueError('EMPTY_TOKEN_SAMPLE: undefined on an empty sample')
    if any(c < 0 for c in counts):
        raise ValueError('NEGATIVE_TOKEN_COUNT: counts must be >= 0')
    hits = sum(1 for c in counts if c >= cap)
    return hits / len(counts), hits


def mode_verdict(_args):
    missing = [k for k in ('WM_CELL_ID', 'WM_CELL_SPEC', 'WM_CELL_GEN',
                           'WM_CELL_VERDICT_OUT') if not os.environ.get(k)]
    if missing:
        return fail('VERDICT_ENV_MISSING', 'missing env: %s' % missing)
    cell_id = os.environ['WM_CELL_ID']
    spec_path = os.environ['WM_CELL_SPEC']
    gen_path = os.environ['WM_CELL_GEN']
    out_path = os.environ['WM_CELL_VERDICT_OUT']

    try:
        spec = json.load(open(spec_path, encoding='utf-8'))
    except (OSError, ValueError) as exc:
        return fail('PROMPTS_FILE_UNREADABLE', 'spec %s (%s)' % (spec_path, exc))
    try:
        expected = json.load(open(spec['prompts'], encoding='utf-8'))['cells']
    except (OSError, ValueError, KeyError) as exc:
        return fail('PROMPTS_FILE_UNREADABLE',
                    'prompts %s (%s)' % (spec.get('prompts'), exc))
    exp_by_id = {c['prompt_id']: c for c in expected}

    rows = {}
    try:
        for line in open(gen_path, encoding='utf-8'):
            if not line.strip():
                continue
            r = json.loads(line)
            for k in REQUIRED_ROW_KEYS:
                if k not in r:
                    return fail('GEN_ROW_MALFORMED',
                                '%s row missing key %s' % (gen_path, k))
            if r['prompt_id'] == '__meta__':
                continue
            ev = r.get('evidence') or {}
            if not isinstance(ev.get('content_tokens'), int) \
                    or 'group' not in ev or 'cap' not in ev:
                return fail('GEN_ROW_MALFORMED',
                            '%s row %s: evidence lacks content_tokens/group/'
                            'cap' % (gen_path, r['prompt_id']))
            rows[r['prompt_id']] = r
    except (OSError, ValueError) as exc:
        return fail('GEN_ROW_MALFORMED', '%s (%s)' % (gen_path, exc))

    absent = sorted(set(exp_by_id) - set(rows))
    if absent:
        return fail('BATTERY_INCOMPLETE',
                    'cell %s: %d expected prompt rows absent from gens: %s '
                    '(a partial battery is a refusal, not a score)'
                    % (cell_id, len(absent), absent))
    for pid, r in rows.items():
        if pid not in exp_by_id:
            return fail('BATTERY_INCOMPLETE',
                        'cell %s: unexpected prompt row %s' % (cell_id, pid))
        ev = r['evidence']
        exp_cap = min(int(exp_by_id[pid]['cap']), int(spec['max_tokens']))
        if int(ev['cap']) != exp_cap:
            return fail('CELL_CAP_MISMATCH',
                        'cell %s prompt %s: gens cap %s != expected %s'
                        % (cell_id, pid, ev['cap'], exp_cap))

    g2_counts = [rows[pid]['evidence']['content_tokens']
                 for pid in exp_by_id
                 if exp_by_id[pid]['group'] == G2_GROUP]
    g2_cap = min(G2_CAP, int(spec['max_tokens']))
    try:
        score, g2_hits = token_limit_rate(g2_counts, g2_cap)
        g0_counts = [rows[pid]['evidence']['content_tokens']
                     for pid in exp_by_id
                     if exp_by_id[pid]['group'] == 'G0']
        g0_rate, g0_hits = (token_limit_rate(g0_counts,
                                             min(64, int(spec['max_tokens'])))
                            if g0_counts else (None, None))
    except ValueError as exc:
        return fail('BATTERY_INCOMPLETE', 'cell %s: %s' % (cell_id, exc))

    verdict = 'PASS' if score < LOOP_RATE_M_RECORDED else 'FAIL'
    out = {
        'cell': cell_id,
        'verdict': verdict,
        'score': score,
        'evidence': {
            'score_rule': 'scorers.dart tokenLimitRate verbatim over the '
                          '12 G2 content-token counts, cap %d' % g2_cap,
            'g2_hits': g2_hits, 'g2_n': len(g2_counts),
            'loop_rate_G0': g0_rate, 'g0_hits': g0_hits,
            'verdict_rule': 'V6_VERDICT_RULE (pre-run): PASS iff score < '
                            'LOOP_RATE_M_RECORDED %r (A3 arm-002 join-table); '
                            'task-success leg V6_TASK_LEG_NOT_RUN'
                            % LOOP_RATE_M_RECORDED,
            'loop_rate_M_recorded': LOOP_RATE_M_RECORDED,
            'loop_rate_R_recorded': LOOP_RATE_R_RECORDED,
            'gens_sha256': sha256_file(gen_path),
            'n_rows': len(rows),
            'tool': 'v6_verdict_runner.py verdict',
            'at': now(),
        },
    }
    try:
        out_dir = os.path.dirname(os.path.abspath(out_path))
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        with open(out_path, 'w', encoding='utf-8') as fh:
            json.dump(out, fh, indent=1)
            fh.write('\n')
    except OSError as exc:
        return fail('OUT_UNWRITABLE', str(exc))
    print('VERDICT_OK %s %s score=%.16g (g2 %d/%d, g0 %s)'
          % (cell_id, verdict, score, g2_hits, len(g2_counts),
             ('%d/%d' % (g0_hits, len(g0_counts))) if g0_counts else 'n/a'))
    return EXIT_OK


# --------------------------------------------------------------------------
# requant mode (quant axis: 4bit-requant of the R mirror)
# --------------------------------------------------------------------------

def mode_requant(args):
    src, dst = args.src, args.out
    if not os.path.isdir(src):
        return fail('MIRROR_DIR_MISSING', src)
    cfg_path = os.path.join(src, 'config.json')
    if not os.path.isfile(cfg_path):
        return fail('CONFIG_MISSING', cfg_path)
    if os.path.exists(dst):
        return fail('OUT_UNWRITABLE', 'refusing to overwrite %s' % dst)
    try:
        import mlx.core as mx  # noqa: F401
        from mlx_lm import load
        from mlx_lm.utils import quantize_model, save_model
    except ImportError as exc:
        return fail('MLX_UNAVAILABLE', str(exc))

    t0 = time.time()
    receipt = {
        'tool': 'v6_verdict_runner.py requant',
        'created_utc': now(),
        'route': 'REQUANT_SOURCE_BF16_NO_DEQUANT (pre-run NAMED): the R '
                 'removal mirror is a plain bf16 store, so the dequant leg '
                 'of the task route is the identity; requant leg = '
                 'mlx_lm.utils.quantize_model',
        'in_dir': os.path.abspath(src),
        'in_shard_sha256': sha256_file(os.path.join(src, 'model.safetensors'))
        if os.path.isfile(os.path.join(src, 'model.safetensors')) else None,
        'group_size': args.group_size, 'bits': args.bits, 'mode': 'affine',
    }
    try:
        config = json.load(open(cfg_path, encoding='utf-8'))
        model, _tok = load(src)
        qmodel, qconfig = quantize_model(model, config, args.group_size,
                                         args.bits)
        os.makedirs(dst)
        save_model(dst, qmodel, donate_model=True)
        with open(os.path.join(dst, 'config.json'), 'w',
                  encoding='utf-8') as fh:
            json.dump(qconfig, fh, indent=2)
        copied = {}
        for name in sorted(os.listdir(src)):
            if name in ('config.json', 'model.safetensors',
                        'model.safetensors.index.json'):
                continue
            p = os.path.join(src, name)
            if os.path.isfile(p):
                shutil.copy2(p, os.path.join(dst, name))
                copied[name] = sha256_file(os.path.join(dst, name))
        receipt['files_copied'] = copied
        receipt['out_dir'] = os.path.abspath(dst)
        receipt['out_shard_sha256'] = sha256_file(
            os.path.join(dst, 'model.safetensors'))
        receipt['quantization_config'] = qconfig.get('quantization')
        # load sanity (no generation): the requant store must load
        try:
            load(dst)
            receipt['load_sanity'] = 'LOAD_SANITY_OK'
        except Exception as exc:
            receipt['load_sanity'] = 'LOAD_SANITY_FAILED'
            receipt['wall_s'] = round(time.time() - t0, 1)
            receipt['wall_s_claim'] = False
            _write_receipt(args.receipt, receipt)
            return fail('LOAD_SANITY_FAILED',
                        '%s did not reload (%s)' % (dst, exc))
    except Exception as exc:
        receipt['error'] = 'REQUANT_FAILED: %s: %s' % (type(exc).__name__, exc)
        receipt['wall_s'] = round(time.time() - t0, 1)
        receipt['wall_s_claim'] = False
        _write_receipt(args.receipt, receipt)
        return fail('REQUANT_FAILED', '%s: %s' % (type(exc).__name__, exc))
    receipt['wall_s'] = round(time.time() - t0, 1)
    receipt['wall_s_claim'] = False
    _write_receipt(args.receipt, receipt)
    print('REQUANT_OK %s -> %s sha256=%s (%.1fs)'
          % (src, dst, receipt['out_shard_sha256'], receipt['wall_s']))
    return EXIT_OK


def _write_receipt(path, receipt):
    if not path:
        return
    try:
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        with open(path, 'w', encoding='utf-8') as fh:
            json.dump(receipt, fh, indent=1)
            fh.write('\n')
    except OSError as exc:
        print('OUT_UNWRITABLE: receipt %s (%s)' % (path, exc), file=sys.stderr)


# --------------------------------------------------------------------------
# render-raw mode (template axis)
# --------------------------------------------------------------------------

def mode_render_raw(args):
    try:
        chat = json.load(open(args.source, encoding='utf-8'))
        cells = chat['cells']
        assert isinstance(cells, list) and cells
    except (OSError, ValueError, AssertionError, KeyError) as exc:
        return fail('CHAT_PROMPTS_UNREADABLE', '%s (%s)' % (args.source, exc))
    raw_cells = []
    for c in cells:
        raw_cells.append({
            'prompt_id': c['prompt_id'], 'group': c['group'], 'cap': c['cap'],
            'prompt': c['prompt'],
            'templated': c['prompt'],   # RAW_SURFACE_DEFINITION (pre-run)
        })
    out = {
        'artifact': 'v6_prompts_raw',
        'created_utc': now(),
        'tool': 'v6_verdict_runner.py render-raw',
        'source_prompts_file': os.path.abspath(args.source),
        'source_prompts_sha256': sha256_file(args.source),
        'cells_file_sha256': chat.get('cells_file_sha256'),
        'surface_template': 'RAW_SURFACE_DEFINITION (pre-run): templated := '
                            'prompt verbatim - the chat wrapper AND the '
                            "' /no_think' directive removed together as the "
                            'one frozen chat surface (cells_frozen_A3.json '
                            'surface.template)',
        'add_special_tokens': chat['add_special_tokens'],
        'eos_token_ids': chat['eos_token_ids'],
        'cells': raw_cells,
    }
    try:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, 'w', encoding='utf-8') as fh:
            json.dump(out, fh, ensure_ascii=False, indent=1)
    except OSError as exc:
        return fail('OUT_UNWRITABLE', str(exc))
    print('RENDER_RAW_OK %d cells -> %s sha256=%s'
          % (len(raw_cells), args.out, sha256_file(args.out)))
    return EXIT_OK


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('mode', nargs='?', default='generate',
                    choices=['generate', 'verdict', 'requant', 'render-raw'],
                    help='default generate (the frozen v6_matrix.py '
                         'generator-callback surface takes no mode word)')
    ap.add_argument('--model', help='generate: mirror dir')
    ap.add_argument('--prompts', help='generate: prompts json (WS-2 shape)')
    ap.add_argument('--max-tokens', type=int, default=32768,
                    help='generate: PREREG-D ceiling; effective cap = '
                         'min(cell cap, ceiling)')
    ap.add_argument('--sampler', default='greedy',
                    help='generate: "greedy" | make_sampler cfg-json')
    ap.add_argument('--out', help='generate/requant/render-raw: output')
    ap.add_argument('--in', dest='src', help='requant: source mirror dir')
    ap.add_argument('--group-size', type=int, default=64)
    ap.add_argument('--bits', type=int, default=4)
    ap.add_argument('--receipt', help='requant: receipt json path')
    ap.add_argument('--from', dest='source',
                    help='render-raw: chat prompts json')
    args = ap.parse_args()

    if args.mode == 'generate':
        if not (args.model and args.prompts and args.out):
            return fail('ARGS_INVALID',
                        'generate needs --model, --prompts and --out')
        return mode_generate(args)
    if args.mode == 'verdict':
        return mode_verdict(args)
    if args.mode == 'requant':
        if not (args.src and args.out):
            return fail('ARGS_INVALID', 'requant needs --in and --out')
        return mode_requant(args)
    if args.mode == 'render-raw':
        if not (args.source and args.out):
            return fail('ARGS_INVALID', 'render-raw needs --from and --out')
        return mode_render_raw(args)
    return fail('ARGS_INVALID', 'unreachable mode %r' % args.mode)


if __name__ == '__main__':
    sys.exit(main())
