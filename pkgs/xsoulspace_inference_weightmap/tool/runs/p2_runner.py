#!/usr/bin/env python3
"""p2_runner.py - P-2 / P-2b head-to-head orchestration (PREREG-D, FROZEN).

PREREG-D P-2/P-2b: same base (Qwen3.5-0.8B), same suites (MATH-500, GSM8K
test, IFEval subset), same forward-pass budgets {10, 25, 50} as the paper's
exp8. OUR PIPELINE IS NOT AN LLM-PROPOSER PIPELINE, so P-2 compares the
measured pipeline against PUBLISHED LLM-proposer numbers: COMPARABILITY
DATA, NEVER A PASS BAR (banner embedded in every output row). P-2b is the
hygiene variant: practice pool strictly disjoint from the evals (built by
p2b_pool_builder.py); the P-2 vs P-2b delta MEASURES the paper's
contamination risk. Both are recorded. Parity is never a pass bar
(PROGRAM.md non-claims).

PRACTICE POOLS (paper exp8, fetched with sha256 receipts):
  default pool dir: $TMPDIR/p2-artifacts
  files + FROZEN sha256 (verified at every real-run start; constants below
  are the receipt of record 2026-11-05):
    README.txt          631d805dda363fdf6aaef95503e40a702ef9346d80a30f723dedf6ead791a039
    aime.jsonl          9f6f26b89e65c7123e6106a9dce51137783eb339547f974f2ab1413165122f56
    gsm8k_train.jsonl   06d0dd560a908c2c2883bfb7d27ab55a87b213ff0d625f5cd734836aeac9a3e5
    math_train.jsonl    abe7982b4d8c98394fe185fb152568a2c784a4157a75fe42b9c01857e71f0c6e
    stats.json          34a3be5db6095e0968bdc5555faa1c4149898e4ea8d6c4c6578975703a208dd6
  A missing file is RE-FETCHED from the recorded source
    https://raw.githubusercontent.com/RikiyaT/lm_understand-logs/main/exp8_math/practice/<file>
  and re-verified; POOL_UNAVAILABLE is raised ONLY when the file is missing
  AND the re-fetch fails (or --offline forbids it). A digest mismatch after
  a successful fetch is POOL_DIGEST_MISMATCH (corrupt data is a NAMED stop,
  never silently used). stats.json kept/dropped counts are cross-checked
  against the frozen constants AND against real line counts.

FROZEN PROTOCOL CONSTANTS (citations inline):
  budgets {10, 25, 50} forward passes            (PREREG-D; paper exp8)
  suites: math500.jsonl, gsm8k_test.jsonl, ifeval_subset.jsonl in --eval-dir
  samples per problem: MATH-500 4, GSM8K 2, IFEval 2
                                                  (exp8_math/README.md eval)
  token cap 32,768                                (PREREG-D / paper loop cap)
  OUR sampler: greedy                             (PREREG-A A2 primary, A4)
  THEIR sampler (recorded, never substituted): temperature 0.6, top_p 0.95,
      top_k 20, presence_penalty 1.5, thinking on, vLLM chat template
                                                  (exp8_math/README.md)
  presence_penalty has no mlx-lm make_sampler key => every row carries NAMED
  protocol difference PRESENCE_PENALTY_UNSUPPORTED; ours-vs-theirs sampler
  difference carries SAMPLER_PROTOCOL_DIFFERENCE. Never hidden.

PUBLISHED NUMBERS (accuracy %, mean over samples; embedded as constants):
  citation: RikiyaT/lm_understand-logs@main exp8_math/eval/RESULTS_excerpt.md
  - Experiment 6 (Qwen3.5-0.8B, thinking on), prompt-v3 rows p10c/p25c/p50c
  and the unedited row; retrieved 2026-11-05.
    unedited: MATH-500 7.9   GSM8K 13.8  IFEval 21.0
    10 passes (p10c): 12.3 / 25.7 / 49.0
    25 passes (p25c): 14.1 / 25.1 / 39.9
    50 passes (p50c): 48.1 / 67.1 / 62.3

DELEGATION CONTRACTS (this runner re-implements NO frozen oracle):
  * generation: wm_qwen35_generate.py surface (--model --prompts
    --max-tokens --sampler --out; output rows {prompt_id (line index),
    prompt, output_text, output_tokens, hit_token_limit, finish_reason,
    wall_ms}).
  * practice passes: --practice-cmd, a /bin/zsh -lc command executed ONCE
    PER PASS with env WM_VARIANT, WM_PASS_INDEX (1-based), WM_PASS_BUDGET,
    WM_POOL_DIR, WM_WORK_DIR. The pass accounting is enforced HERE (exactly
    budget invocations per (variant, budget); a non-zero exit is NAMED
    PRACTICE_PASS_FAILED).
  * after the passes of one (variant, budget), the pipeline must have
    written $WM_WORK_DIR/edit_manifest.json:
      {"edit_submitted": bool, "model_dir": str|null}
    ("no edit submitted" is a legal outcome - the paper's own table has
    such rows; eval then runs on the base model and the row records it).
  * scoring: --scorer-cli, a /bin/zsh -lc command with env WM_SCORED_INPUT
    (jsonl {suite, problem_id, sample_index, output_text, output_tokens,
    hit_token_limit}), WM_GOLD (the suite jsonl), WM_SUITE, WM_OUT_JSON
    (must write {"suite", "accuracy" (PERCENT 0-100, published units),
    "n_problems", "n_samples_correct_over"}). The FROZEN Dart scorers
    (lib/src/scorers.dart) live behind that CLI; a Python re-scoring here
    would be a second, unfrozen oracle and is structurally refused
    (SCORER_CLI_MISSING).

Usage:
  python3 -I tool/runs/p2_runner.py --model <base-hf-dir> \
      --eval-dir <dir> --practice-cmd <zsh-cmd> --scorer-cli <zsh-cmd> \
      --out <dir> [--variant p2|p2b|both] [--pool-dir <dir>] \
      [--p2b-pool <dir>] [--budgets 10,25,50] [--generate <path>] \
      [--generator-python <path>] [--max-tokens 32768] [--offline] \
      [--dry-run]

--dry-run prints the plan (pool status incl. per-file digest check WITHOUT
re-fetch, blockers a real run would NAMED-refuse, steps, frozen constants,
published numbers with citation, banner) as JSON on stdout, exit 0. Nothing
is written, nothing is fetched, no engine is run.

Exit codes (errors are NAMED on stderr as 'CODE: detail', never silent):
  0  ok (dry-run plan printed, or run completed and comparability written -
     comparability rows are DATA; there is no pass/fail exit for numbers)
  1  named input/runtime error:
       USAGE_ERROR              bad argv (bad --variant/--budgets syntax)
       BUDGET_NOT_FROZEN        --budgets outside {10,25,50} (FROZEN; dry-run
                                refuses too - the budget table is not
                                negotiable at runtime)
       POOL_DIGEST_MISMATCH     a pool file disagrees with its frozen sha256
       POOL_STATS_MISMATCH      stats.json disagrees with the frozen
                                kept/dropped constants
       POOL_COUNT_MISMATCH      a pool jsonl line count != its kept count
       P2B_POOL_MISSING         p2b variant without a built p2b pool
       P2B_RECEIPT_MISMATCH     p2b build_receipt.json digests != files
       MODEL_DIR_MISSING        --model absent (real run)
       GENERATOR_MISSING        generation callback absent (real run)
       GENERATOR_PYTHON_MISSING no generator python resolvable (real run)
       PRACTICE_CMD_MISSING     real run without --practice-cmd
       SCORER_CLI_MISSING       real run without --scorer-cli
       EVAL_DIR_MISSING         --eval-dir absent (real run)
       EVAL_SUITE_MISSING       a frozen suite file absent (names the suite)
       SUITE_JSONL_MALFORMED    a suite row violates p2-suite/v1
       PRACTICE_PASS_FAILED     practice command non-zero (variant, budget,
                                pass index, rc, stderr tail)
       EDIT_MANIFEST_MISSING    pipeline wrote no edit_manifest.json
       EDIT_MANIFEST_MALFORMED  manifest violates the frozen shape
       GENERATOR_FAILED         generator non-zero / row-count mismatch
       GENERATOR_OUTPUT_MISMATCH generations rows != prompts lines
       SCORER_FAILED            scorer cli non-zero
       SCORER_OUTPUT_MALFORMED  scorer out json missing/invalid
       OUT_UNWRITABLE           --out cannot be created/written
       INTERNAL_ERROR           unexpected exception (class + message)
  2  named dependency unavailable:
       POOL_UNAVAILABLE         pool files missing AND (re-fetch failed or
                                --offline); detail lists files + fetch errors
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
EXIT_DEP_UNAVAILABLE = 2

COMPARABILITY_SCHEMA = 'p2-comparability/v1'
SUITE_SCHEMA = 'p2-suite/v1'

# --- FROZEN protocol constants (PREREG-D / PREREG-A / exp8 README) ----------
BUDGETS_FROZEN = (10, 25, 50)
TOKEN_CAP = 32768
SUITES = (
    ('math500', 'math500.jsonl', 4, 'MATH-500'),
    ('gsm8k_test', 'gsm8k_test.jsonl', 2, 'GSM8K test'),
    ('ifeval_subset', 'ifeval_subset.jsonl', 2, 'IFEval subset'),
)
OUR_SAMPLER = 'greedy'  # PREREG-A A2 primary (A4-frozen)
THEIR_SAMPLER = {
    'temperature': 0.6, 'top_p': 0.95, 'top_k': 20,
    'presence_penalty': 1.5, 'thinking': 'on', 'engine': 'vLLM',
    'max_new_tokens': TOKEN_CAP,
}
PROTOCOL_DIFFERENCES = (
    'SAMPLER_PROTOCOL_DIFFERENCE(ours=greedy per PREREG-A A4 primary; '
    'theirs=t0.6/top_p0.95/top_k20/presence1.5 - recorded, never '
    'substituted)',
    'PRESENCE_PENALTY_UNSUPPORTED(their presence_penalty 1.5 has no mlx-lm '
    'make_sampler key)',
    'PROPOSER_DIFFERENCE(measured weightmap pipeline vs LLM-proposer Astra '
    'runs - PREREG-D: comparability data, never a pass bar)',
)
PASS_BAR = False
BANNER = ('COMPARABILITY DATA, NEVER A PASS BAR (PREREG-D P-2; PROGRAM.md '
          'benchmark policy + non-claims: parity is never a pass bar)')

# Published numbers (accuracy %, mean over samples). Citation of record.
PUBLISHED_CITATION = (
    'RikiyaT/lm_understand-logs@main exp8_math/eval/RESULTS_excerpt.md - '
    'Experiment 6 (Qwen3.5-0.8B, thinking on), prompt-v3 rows p10c/p25c/'
    'p50c + unedited row; retrieved 2026-11-05'
)
PUBLISHED = {
    None: {'run_id': 'unedited',
           'math500': 7.9, 'gsm8k_test': 13.8, 'ifeval_subset': 21.0},
    10: {'run_id': 'p10c',
         'math500': 12.3, 'gsm8k_test': 25.7, 'ifeval_subset': 49.0},
    25: {'run_id': 'p25c',
         'math500': 14.1, 'gsm8k_test': 25.1, 'ifeval_subset': 39.9},
    50: {'run_id': 'p50c',
         'math500': 48.1, 'gsm8k_test': 67.1, 'ifeval_subset': 62.3},
}

# Paper exp8 practice pool: frozen digests + source of record.
POOL_FILES = {
    'README.txt':
        '631d805dda363fdf6aaef95503e40a702ef9346d80a30f723dedf6ead791a039',
    'aime.jsonl':
        '9f6f26b89e65c7123e6106a9dce51137783eb339547f974f2ab1413165122f56',
    'gsm8k_train.jsonl':
        '06d0dd560a908c2c2883bfb7d27ab55a87b213ff0d625f5cd734836aeac9a3e5',
    'math_train.jsonl':
        'abe7982b4d8c98394fe185fb152568a2c784a4157a75fe42b9c01857e71f0c6e',
    'stats.json':
        '34a3be5db6095e0968bdc5555faa1c4149898e4ea8d6c4c6578975703a208dd6',
}
POOL_URL_BASE = ('https://raw.githubusercontent.com/RikiyaT/'
                 'lm_understand-logs/main/exp8_math/practice/')
THEIR_POOL_STATS = {  # stats.json of record (kept/dropped), exp8 practice/
    'gsm8k_train': {'kept': 7469, 'dropped': 4},
    'math_train': {'kept': 7275, 'dropped': 225},
    'aime': {'kept': 714, 'dropped': 0},
}
POOL_LINE_COUNTS = {'gsm8k_train.jsonl': 7469, 'math_train.jsonl': 7275,
                    'aime.jsonl': 714}

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


def _default_pool_dir():
    tmp = os.environ.get('TMPDIR') or '/tmp'
    return os.path.join(tmp, 'p2-artifacts')


def resolve_generator_python(explicit):
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


# --------------------------------------------------------------------------
# Pool verification (frozen digests; re-fetch only on real runs)
# --------------------------------------------------------------------------

def pool_status(pool_dir):
    """Read-only pool state for the dry-run plan and blocker list."""
    files = {}
    for name, digest in sorted(POOL_FILES.items()):
        path = os.path.join(pool_dir, name)
        state = {'exists': os.path.isfile(path), 'sha256_expected': digest,
                 'sha256_ok': None}
        if state['exists']:
            try:
                state['sha256_ok'] = _sha256_file(path) == digest
            except OSError:
                state['sha256_ok'] = False
        files[name] = state
    ok = all(f['exists'] and f['sha256_ok'] for f in files.values())
    missing = [n for n, f in files.items() if not f['exists']]
    mismatched = [n for n, f in files.items()
                  if f['exists'] and f['sha256_ok'] is not True]
    return {'dir': pool_dir, 'status': 'ok' if ok else (
        'missing' if missing and not mismatched else
        'digest_mismatch' if mismatched else 'missing'),
        'missing': missing, 'mismatched': mismatched, 'files': files}


def refetch_pool(pool_dir, fetch_receipt_path):
    """Fetch missing pool files from the recorded source; verify digests.

    Returns (status_dict, fetch_errors). Never silently trusts a fetch:
    every fetched file is re-verified against the frozen digest.
    """
    import urllib.error
    import urllib.request
    errors = []
    try:
        os.makedirs(pool_dir, exist_ok=True)
    except OSError as exc:
        return pool_status(pool_dir), ['makedirs %s: %s' % (pool_dir, exc)]
    for name, digest in sorted(POOL_FILES.items()):
        path = os.path.join(pool_dir, name)
        if os.path.isfile(path) and _sha256_file(path) == digest:
            continue
        url = POOL_URL_BASE + name
        try:
            req = urllib.request.Request(
                url, headers={'User-Agent': 'weightmap-p2-runner'})
            with urllib.request.urlopen(req, timeout=120) as resp:
                data = resp.read()
            got = hashlib.sha256(data).hexdigest()
            if got != digest:
                errors.append('%s fetched but sha256 %s != frozen %s'
                              % (name, got, digest))
                continue
            tmp = path + '.fetch-tmp'
            with open(tmp, 'wb') as fh:
                fh.write(data)
            os.replace(tmp, path)
            with open(fetch_receipt_path, 'a', encoding='utf-8') as fh:
                fh.write(json.dumps({
                    'fetched_utc': _now_utc(), 'file': name, 'url': url,
                    'sha256': got, 'sha256_expected': digest,
                    'match': True}) + '\n')
        except (urllib.error.URLError, OSError, ValueError) as exc:
            errors.append('%s: %s: %s' % (name, type(exc).__name__, exc))
    return pool_status(pool_dir), errors


def verify_pool_counts(pool_dir):
    """Cross-check stats.json + real line counts against frozen constants."""
    try:
        with open(os.path.join(pool_dir, 'stats.json'), 'rb') as fh:
            stats = json.loads(fh.read())
    except (OSError, ValueError) as exc:
        return 'POOL_STATS_MISMATCH: stats.json unreadable/invalid (%s)' % exc
    for key, expect in THEIR_POOL_STATS.items():
        got = stats.get(key)
        if got != expect:
            return ('POOL_STATS_MISMATCH: stats.json %s = %r, frozen '
                    'receipt-of-record %r' % (key, got, expect))
    for name, expect_lines in POOL_LINE_COUNTS.items():
        path = os.path.join(pool_dir, name)
        try:
            with open(path, 'rb') as fh:
                n = sum(1 for ln in fh if ln.strip())
        except OSError as exc:
            return 'POOL_COUNT_MISMATCH: %s unreadable (%s)' % (name, exc)
        if n != expect_lines:
            return ('POOL_COUNT_MISMATCH: %s has %d lines, expected %d '
                    '(kept count)' % (name, n, expect_lines))
    return None


# --------------------------------------------------------------------------
# P-2b pool (builder output) verification
# --------------------------------------------------------------------------

def verify_p2b_pool(p2b_dir):
    """The builder's receipt digests must match the built files."""
    receipt_path = os.path.join(p2b_dir, 'build_receipt.json')
    if not os.path.isfile(receipt_path):
        return ('P2B_POOL_MISSING: %s has no build_receipt.json (run '
                'p2b_pool_builder.py first)' % p2b_dir)
    try:
        with open(receipt_path, 'rb') as fh:
            receipt = json.loads(fh.read())
        outputs = receipt['outputs']
    except (OSError, ValueError, KeyError) as exc:
        return 'P2B_POOL_MISSING: build_receipt.json invalid (%s)' % exc
    for name, info in outputs.items():
        path = os.path.join(p2b_dir, name)
        if not os.path.isfile(path):
            return 'P2B_POOL_MISSING: receipt lists %s, file absent' % name
        if _sha256_file(path) != info.get('sha256'):
            return ('P2B_RECEIPT_MISMATCH: %s sha256 != build receipt'
                    % name)
    return None


# --------------------------------------------------------------------------
# Suites
# --------------------------------------------------------------------------

def read_suite(path, suite_name):
    """p2-suite/v1: one {id, problem|question, answer?} object per line."""
    try:
        with open(path, 'rb') as fh:
            text = fh.read().decode('utf-8')
    except (OSError, UnicodeDecodeError) as exc:
        raise RuntimeError('EVAL_SUITE_MISSING: %s (%s) unreadable (%s)'
                           % (suite_name, path, exc))
    problems = []
    for lineno, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except ValueError as exc:
            raise RuntimeError('SUITE_JSONL_MALFORMED: %s line %d not json '
                               '(%s)' % (suite_name, lineno, exc))
        if not isinstance(row, dict) or not isinstance(row.get('id'), str):
            raise RuntimeError('SUITE_JSONL_MALFORMED: %s line %d missing '
                               'str id' % (suite_name, lineno))
        text_key = 'problem' if 'problem' in row else (
            'question' if 'question' in row else None)
        if text_key is None or not isinstance(row[text_key], str):
            raise RuntimeError('SUITE_JSONL_MALFORMED: %s line %d missing '
                               'problem/question str' % (suite_name, lineno))
        problems.append({'id': row['id'], 'problem': row[text_key]})
    if not problems:
        raise RuntimeError('SUITE_JSONL_MALFORMED: %s empty' % suite_name)
    return problems


def build_prompt_file(problems, samples_per_problem, path):
    """Problem-major repetition: p0 x k, p1 x k, ... (frozen order).

    Returns the (problem_id, sample_index) list aligned to line indices.
    No blank lines (the generator filters blanks and would shift ids).
    """
    mapping = []
    with open(path, 'w', encoding='utf-8') as fh:
        for p in problems:
            one_line = ' '.join(p['problem'].split())
            for s in range(samples_per_problem):
                fh.write(one_line + '\n')
                mapping.append((p['id'], s))
    return mapping


# --------------------------------------------------------------------------
# Real run
# --------------------------------------------------------------------------

def run_eval_suite(args, gen_python, model_dir, suite_name, suite_file,
                   samples_per_problem, work_dir, tag):
    """Generate (frozen sampler=greedy, cap) then delegate scoring."""
    problems = read_suite(suite_file, suite_name)
    prompts_path = os.path.join(work_dir, '%s_prompts.txt' % tag)
    mapping = build_prompt_file(problems, samples_per_problem, prompts_path)
    gens_path = os.path.join(work_dir, '%s_gens.jsonl' % tag)
    cmd = [gen_python, '-I', args.generate, '--model', model_dir,
           '--prompts', prompts_path, '--max-tokens', str(args.max_tokens),
           '--sampler', OUR_SAMPLER, '--out', gens_path]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0 or not os.path.isfile(gens_path):
        return None, ('GENERATOR_FAILED: %s suite %s rc=%d stderr-tail=%r'
                      % (tag, suite_name, proc.returncode,
                         proc.stderr[-400:]))
    scored_path = os.path.join(work_dir, '%s_scored_input.jsonl' % tag)
    hits = 0
    tokens = 0
    with open(gens_path, 'r', encoding='utf-8') as src, \
            open(scored_path, 'w', encoding='utf-8') as dst:
        for idx, line in enumerate(src):
            if not line.strip():
                continue
            row = json.loads(line)
            if row.get('prompt_id') != idx:
                return None, ('GENERATOR_OUTPUT_MISMATCH: %s suite %s line '
                              '%d prompt_id %r != index %d'
                              % (tag, suite_name, idx,
                                 row.get('prompt_id'), idx))
            problem_id, sample_index = mapping[idx]
            hits += 1 if row.get('hit_token_limit') else 0
            tokens += int(row.get('output_tokens') or 0)
            dst.write(json.dumps({
                'suite': suite_name, 'problem_id': problem_id,
                'sample_index': sample_index,
                'output_text': row.get('output_text', ''),
                'output_tokens': row.get('output_tokens'),
                'hit_token_limit': row.get('hit_token_limit'),
            }) + '\n')
    if idx + 1 != len(mapping):
        return None, ('GENERATOR_OUTPUT_MISMATCH: %s suite %s produced %d '
                      'rows, expected %d' % (tag, suite_name, idx + 1,
                                             len(mapping)))
    scores_path = os.path.join(work_dir, '%s_scores.json' % tag)
    env = dict(os.environ)
    env.update({'WM_SCORED_INPUT': scored_path, 'WM_GOLD': suite_file,
                'WM_SUITE': suite_name, 'WM_OUT_JSON': scores_path})
    sproc = subprocess.run(['/bin/zsh', '-lc', args.scorer_cli],
                           capture_output=True, text=True, env=env)
    if sproc.returncode != 0:
        return None, ('SCORER_FAILED: %s suite %s rc=%d stderr-tail=%r'
                      % (tag, suite_name, sproc.returncode,
                         sproc.stderr[-400:]))
    try:
        with open(scores_path, 'rb') as fh:
            sj = json.loads(fh.read())
        acc = sj['accuracy']
        if not isinstance(acc, (int, float)) or isinstance(acc, bool) \
                or not math.isfinite(acc) or not (0.0 <= acc <= 100.0):
            raise ValueError('accuracy %r not a finite percent in [0,100]'
                             % acc)
    except (OSError, ValueError, KeyError) as exc:
        return None, ('SCORER_OUTPUT_MALFORMED: %s suite %s (%s)'
                      % (tag, suite_name, exc))
    ours = {
        'accuracy': float(acc),
        'n_problems': len(problems),
        'samples_per_problem': samples_per_problem,
        'sampler': OUR_SAMPLER,
        'token_cap': args.max_tokens,
        'token_limit_hits': hits,
        'token_limit_rate': hits / len(mapping) if mapping else None,
        'mean_output_tokens': tokens / len(mapping) if mapping else None,
        'n_scored_rows': sj.get('n_samples_correct_over'),
        'scorer': {'cli': args.scorer_cli,
                   'note': 'frozen Dart scorers behind --scorer-cli'},
    }
    return ours, None


def comparability_row(variant, budget, suite_name, suite_label, ours):
    pub = PUBLISHED[budget]
    differences = list(PROTOCOL_DIFFERENCES)
    if variant == 'p2b':
        differences.append(
            'PRACTICE_POOL_DIFFERENCE(P-2b pool strictly disjoint from the '
            'evals by construction via p2b_pool_builder.py; the paper pool '
            'claims disjointness - P-2b verifies it mechanically)')
    return {
        'schema': COMPARABILITY_SCHEMA,
        'created_utc': _now_utc(),
        'variant': variant,
        'budget': budget,
        'suite': suite_name,
        'suite_label': suite_label,
        'pass_bar': PASS_BAR,
        'banner': BANNER,
        'ours': ours,
        'published': {'accuracy': pub[suite_name],
                      'run_id': pub['run_id']},
        'published_citation': PUBLISHED_CITATION,
        'delta_points': (None if ours is None
                         else round(ours['accuracy'] - pub[suite_name], 4)),
        'protocol_differences': differences,
    }


def run_real(args, variants, budgets):
    # --- blocker refusals, frozen order ------------------------------------
    pool_dir = args.pool_dir
    if 'p2' in variants:
        status = pool_status(pool_dir)
        if status['status'] != 'ok':
            if args.offline:
                if status['mismatched']:
                    return fail('POOL_DIGEST_MISMATCH',
                                'pool %s files %s disagree with their frozen '
                                'sha256 and --offline forbids the re-fetch '
                                '(corrupt data is a NAMED stop, never '
                                'silently used)'
                                % (pool_dir, status['mismatched']))
                return fail('POOL_UNAVAILABLE',
                            'pool %s missing files %s and --offline forbids '
                            'the re-fetch from %s'
                            % (pool_dir, status['missing'], POOL_URL_BASE),
                            EXIT_DEP_UNAVAILABLE)
            os.makedirs(os.path.abspath(args.out), exist_ok=True)
            receipt = os.path.join(os.path.abspath(args.out),
                                   'pool_fetch_receipt.jsonl')
            # Missing AND mismatched files are (re-)fetched + re-verified.
            status, errors = refetch_pool(pool_dir, receipt)
            if status['mismatched']:
                return fail('POOL_DIGEST_MISMATCH',
                            'pool %s files %s still disagree with their '
                            'frozen sha256 after re-fetch from %s (%s)'
                            % (pool_dir, status['mismatched'], POOL_URL_BASE,
                               '; '.join(errors) or 'source digest drift'))
            if status['missing']:
                return fail('POOL_UNAVAILABLE',
                            'pool %s still missing files %s after re-fetch '
                            'from %s (fetch errors: %s)'
                            % (pool_dir, status['missing'], POOL_URL_BASE,
                               '; '.join(errors) or 'none recorded'),
                            EXIT_DEP_UNAVAILABLE)
        count_problem = verify_pool_counts(pool_dir)
        if count_problem:
            code, _, detail = count_problem.partition(':')
            return fail(code.strip(), detail.strip())
    if 'p2b' in variants:
        if not args.p2b_pool:
            return fail('P2B_POOL_MISSING',
                        'variant p2b needs --p2b-pool (built by '
                        'p2b_pool_builder.py)')
        problem = verify_p2b_pool(args.p2b_pool)
        if problem:
            code, _, detail = problem.partition(':')
            return fail(code.strip(), detail.strip())
    if not os.path.isdir(args.model):
        return fail('MODEL_DIR_MISSING', args.model)
    if not os.path.isfile(args.generate):
        return fail('GENERATOR_MISSING', args.generate)
    gen_python, gen_python_source = resolve_generator_python(
        args.generator_python)
    if not os.path.isfile(gen_python):
        return fail('GENERATOR_PYTHON_MISSING',
                    'no generator python at %s (source %s)'
                    % (gen_python, gen_python_source))
    if not args.practice_cmd:
        return fail('PRACTICE_CMD_MISSING',
                    'real runs need --practice-cmd (the measured pipeline\'s '
                    'per-pass command; this runner never re-implements the '
                    'proposer)')
    if not args.scorer_cli:
        return fail('SCORER_CLI_MISSING',
                    'real runs need --scorer-cli (the frozen Dart scorers; '
                    'Python re-scoring here would be a second, unfrozen '
                    'oracle)')
    if not os.path.isdir(args.eval_dir):
        return fail('EVAL_DIR_MISSING', args.eval_dir)
    for suite_name, suite_file, _k, _label in SUITES:
        if not os.path.isfile(os.path.join(args.eval_dir, suite_file)):
            return fail('EVAL_SUITE_MISSING',
                        '%s (%s) absent from %s'
                        % (suite_name, suite_file, args.eval_dir))

    out_dir = os.path.abspath(args.out)
    try:
        os.makedirs(os.path.join(out_dir, 'work'), exist_ok=True)
    except OSError as exc:
        return fail('OUT_UNWRITABLE', '%s (%s)' % (out_dir, exc))
    comp_path = os.path.join(out_dir, 'comparability.jsonl')

    def append_row(row):
        with open(comp_path, 'a', encoding='utf-8') as fh:
            fh.write(json.dumps(row, sort_keys=False) + '\n')

    def eval_all_suites(model_dir, work_dir, tag_prefix):
        results = {}
        for suite_name, suite_file, k, _label in SUITES:
            ours, err = run_eval_suite(
                args, gen_python, model_dir, suite_name,
                os.path.join(args.eval_dir, suite_file), k, work_dir,
                '%s_%s' % (tag_prefix, suite_name))
            if err:
                code, _, detail = err.partition(':')
                return None, fail(code.strip(), detail.strip())
            results[suite_name] = ours
        return results, None

    # --- baseline (budget 0, unedited) -------------------------------------
    base_work = os.path.join(out_dir, 'work', 'baseline')
    os.makedirs(base_work, exist_ok=True)
    baseline, rc = eval_all_suites(args.model, base_work, 'baseline')
    if rc is not None:
        return rc
    for variant in variants:
        for suite_name, _f, _k, label in SUITES:
            row = comparability_row(variant, None, suite_name, label,
                                    dict(baseline[suite_name],
                                         model='unedited base',
                                         edit_submitted=None))
            append_row(row)

    # --- per (variant, budget): practice passes -> manifest -> eval ---------
    for variant in variants:
        pool_for_variant = pool_dir if variant == 'p2' else args.p2b_pool
        for budget in budgets:
            work = os.path.join(out_dir, 'work', variant, 'b%d' % budget)
            os.makedirs(work, exist_ok=True)
            for pass_index in range(1, budget + 1):
                env = dict(os.environ)
                env.update({'WM_VARIANT': variant,
                            'WM_PASS_INDEX': str(pass_index),
                            'WM_PASS_BUDGET': str(budget),
                            'WM_POOL_DIR': pool_for_variant,
                            'WM_WORK_DIR': work})
                proc = subprocess.run(['/bin/zsh', '-lc', args.practice_cmd],
                                      capture_output=True, text=True,
                                      env=env)
                if proc.returncode != 0:
                    return fail('PRACTICE_PASS_FAILED',
                                'variant %s budget %d pass %d/%d rc=%d '
                                'stderr-tail=%r'
                                % (variant, budget, pass_index, budget,
                                   proc.returncode, proc.stderr[-400:]))
            manifest_path = os.path.join(work, 'edit_manifest.json')
            if not os.path.isfile(manifest_path):
                return fail('EDIT_MANIFEST_MISSING',
                            'variant %s budget %d: the practice pipeline '
                            'wrote no %s' % (variant, budget, manifest_path))
            try:
                with open(manifest_path, 'rb') as fh:
                    manifest = json.loads(fh.read())
                submitted = manifest['edit_submitted']
                model_dir = manifest.get('model_dir')
                if not isinstance(submitted, bool) \
                        or (submitted and
                            (not isinstance(model_dir, str)
                             or not os.path.isdir(model_dir))) \
                        or (not submitted and model_dir is not None):
                    raise ValueError('bad shape %r' % (manifest,))
            except (OSError, ValueError, KeyError) as exc:
                return fail('EDIT_MANIFEST_MALFORMED',
                            'variant %s budget %d (%s); contract: '
                            '{"edit_submitted": bool, "model_dir": str '
                            'iff submitted else null}'
                            % (variant, budget, exc))
            eval_model = model_dir if submitted else args.model
            results, rc = eval_all_suites(eval_model, work,
                                          '%s_b%d' % (variant, budget))
            if rc is not None:
                return rc
            for suite_name, _f, _k, label in SUITES:
                row = comparability_row(
                    variant, budget, suite_name, label,
                    dict(results[suite_name],
                         edit_submitted=submitted,
                         practice_passes=budget,
                         practice_pool={'dir': pool_for_variant,
                                        'kind': ('paper exp8 pool (digest-'
                                                 'verified)' if variant == 'p2'
                                                 else 'p2b strictly-disjoint '
                                                      'pool (builder '
                                                      'receipt)')}))
                append_row(row)

    # --- P-2 vs P-2b contamination delta (both recorded; data, not a bar) ---
    summary = {
        'schema': 'p2-summary/v1',
        'created_utc': _now_utc(),
        'variants': list(variants),
        'budgets': list(budgets),
        'pass_bar': PASS_BAR,
        'banner': BANNER,
        'contamination_note': ('the P-2 vs P-2b delta MEASURES the paper\'s '
                               'contamination risk (PREREG-D); both are '
                               'recorded; neither is a pass bar'),
        'their_pool_stats': {'values': THEIR_POOL_STATS,
                             'citation': ('exp8_math/practice/stats.json '
                                          '(digest-verified); kept/dropped '
                                          'counts of the paper pool')},
        'comparability_file': comp_path,
    }
    if 'p2' in variants and 'p2b' in variants:
        rows_by_key = {}
        with open(comp_path, 'r', encoding='utf-8') as fh:
            for line in fh:
                r = json.loads(line)
                if r['budget'] is not None and r['ours'] is not None:
                    rows_by_key[(r['variant'], r['budget'],
                                 r['suite'])] = r['ours']['accuracy']
        deltas = {}
        for budget in budgets:
            for suite_name, _f, _k, _label in SUITES:
                a = rows_by_key.get(('p2', budget, suite_name))
                b = rows_by_key.get(('p2b', budget, suite_name))
                if a is not None and b is not None:
                    deltas['%s@b%d' % (suite_name, budget)] = round(a - b, 4)
        summary['contamination_delta_p2_minus_p2b_points'] = deltas
    summary_path = os.path.join(out_dir, 'comparability_summary.json')
    try:
        with open(summary_path, 'w', encoding='utf-8') as fh:
            json.dump(summary, fh, indent=2)
            fh.write('\n')
    except OSError as exc:
        return fail('OUT_UNWRITABLE', '%s (%s)' % (summary_path, exc))
    print(json.dumps({
        'tool': 'p2_runner.py',
        'comparability': comp_path,
        'summary': summary_path,
        'pass_bar': PASS_BAR,
        'banner': BANNER,
    }, indent=2))
    return EXIT_OK


# --------------------------------------------------------------------------
# Dry run
# --------------------------------------------------------------------------

def real_run_blockers(args, variants):
    """The NAMED refusals a real run would hit right now (checklist)."""
    blockers = []
    if 'p2' in variants:
        status = pool_status(args.pool_dir)
        if status['status'] != 'ok':
            if args.offline:
                blockers.append('POOL_DIGEST_MISMATCH'
                                if status['mismatched']
                                else 'POOL_UNAVAILABLE')
            else:
                blockers.append('refetch-then-verify from %s '
                                '(POOL_DIGEST_MISMATCH if the source drifts, '
                                'POOL_UNAVAILABLE only if the re-fetch also '
                                'fails)' % POOL_URL_BASE)
        elif verify_pool_counts(args.pool_dir):
            blockers.append('POOL_STATS_MISMATCH / POOL_COUNT_MISMATCH')
    if 'p2b' in variants:
        if not args.p2b_pool:
            blockers.append('P2B_POOL_MISSING')
        else:
            problem = verify_p2b_pool(args.p2b_pool)
            if problem:
                blockers.append(problem.partition(':')[0].strip())
    if not os.path.isdir(args.model):
        blockers.append('MODEL_DIR_MISSING')
    if not os.path.isfile(args.generate):
        blockers.append('GENERATOR_MISSING')
    gen_python, _src = resolve_generator_python(args.generator_python)
    if not os.path.isfile(gen_python):
        blockers.append('GENERATOR_PYTHON_MISSING')
    if not args.practice_cmd:
        blockers.append('PRACTICE_CMD_MISSING')
    if not args.scorer_cli:
        blockers.append('SCORER_CLI_MISSING')
    if not os.path.isdir(args.eval_dir):
        blockers.append('EVAL_DIR_MISSING')
    else:
        for suite_name, suite_file, _k, _label in SUITES:
            if not os.path.isfile(os.path.join(args.eval_dir, suite_file)):
                blockers.append('EVAL_SUITE_MISSING(%s)' % suite_name)
    return blockers


def run_dry(args, variants, budgets):
    gen_python, gen_python_source = resolve_generator_python(
        args.generator_python)
    steps = ['verify pool digests (re-fetch from the recorded source unless '
             '--offline; POOL_UNAVAILABLE only if that also fails)',
             'cross-check stats.json + line counts vs frozen constants',
             'baseline eval (unedited base, all suites) -> comparability '
             'rows budget=null']
    for variant in variants:
        pool = args.pool_dir if variant == 'p2' else args.p2b_pool
        for budget in budgets:
            steps.append('%s budget %d: %d practice passes via '
                         '--practice-cmd (pool %s; pass accounting enforced '
                         'here)' % (variant, budget, budget, pool))
            steps.append('%s budget %d: read edit_manifest.json -> eval all '
                         'suites (generator + scorer-cli) -> comparability '
                         'rows' % (variant, budget))
    steps.append('write comparability.jsonl (append per row) + '
                 'comparability_summary.json (P-2 vs P-2b contamination '
                 'delta when both variants ran)')
    plan = {
        'mode': 'dry-run',
        'tool': 'p2_runner.py',
        'schema': COMPARABILITY_SCHEMA,
        'variants': list(variants),
        'budgets': list(budgets),
        'budgets_frozen': list(BUDGETS_FROZEN),
        'pass_bar': PASS_BAR,
        'banner': BANNER,
        'pool': dict(pool_status(args.pool_dir),
                     refetch={'allowed': not args.offline,
                              'url_base': POOL_URL_BASE,
                              'rule': ('missing files are re-fetched and '
                                       're-verified against the frozen '
                                       'digests; POOL_UNAVAILABLE only if '
                                       'the re-fetch also fails')},
                     their_stats={'values': THEIR_POOL_STATS,
                                  'line_counts': POOL_LINE_COUNTS}),
        'p2b_pool': {'dir': args.p2b_pool,
                     'status': ('not supplied' if not args.p2b_pool else
                                ('ok' if verify_p2b_pool(args.p2b_pool)
                                 is None else
                                 verify_p2b_pool(args.p2b_pool)
                                 .partition(':')[0].strip()))},
        'model': {'path': args.model, 'exists': os.path.isdir(args.model)},
        'generate': {'path': args.generate,
                     'exists': os.path.isfile(args.generate)},
        'generator_python': {'path': gen_python,
                             'source': gen_python_source,
                             'exists': os.path.isfile(gen_python)},
        'practice_cmd': {'provided': args.practice_cmd is not None,
                         'contract': ('zsh -lc, once per pass, env '
                                      'WM_VARIANT/WM_PASS_INDEX/'
                                      'WM_PASS_BUDGET/WM_POOL_DIR/'
                                      'WM_WORK_DIR; manifest at '
                                      '$WM_WORK_DIR/edit_manifest.json '
                                      '{"edit_submitted": bool, '
                                      '"model_dir": str|null}')},
        'scorer_cli': {'provided': args.scorer_cli is not None,
                       'contract': ('zsh -lc, env WM_SCORED_INPUT/WM_GOLD/'
                                    'WM_SUITE/WM_OUT_JSON; accuracy in '
                                    'PERCENT 0-100 (published units); the '
                                    'frozen Dart scorers live behind it')},
        'eval_dir': {'path': args.eval_dir,
                     'exists': os.path.isdir(args.eval_dir),
                     'suites': {s[0]: {'file': s[1],
                                       'samples_per_problem': s[2],
                                       'exists': os.path.isfile(
                                           os.path.join(args.eval_dir, s[1]))}
                                for s in SUITES}},
        'protocol': {
            'our_sampler': OUR_SAMPLER,
            'their_sampler': THEIR_SAMPLER,
            'token_cap': args.max_tokens,
            'samples_per_problem': {s[0]: s[2] for s in SUITES},
            'differences': list(PROTOCOL_DIFFERENCES),
        },
        'published': {'citation': PUBLISHED_CITATION,
                      'accuracy_percent': {
                          (str(k) if k is not None else 'unedited'): {
                              s[0]: PUBLISHED[k][s[0]] for s in SUITES}
                          for k in PUBLISHED}},
        'steps': steps,
        'real_run_blockers': real_run_blockers(args, variants),
        'out': os.path.abspath(args.out),
        'note': ('plan only; nothing written, nothing fetched, no engine '
                 'run; comparability rows are DATA - never a pass bar'),
    }
    print(json.dumps(plan, indent=2))
    return EXIT_OK


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--model', required=True,
                    help='base model dir (Qwen3.5-0.8B HF snapshot)')
    ap.add_argument('--eval-dir', required=True,
                    help='dir with the frozen suite files')
    ap.add_argument('--out', required=True,
                    help='output dir (comparability.jsonl + work/)')
    ap.add_argument('--variant', default='both',
                    choices=('p2', 'p2b', 'both'))
    ap.add_argument('--pool-dir', default=None,
                    help='paper exp8 practice pool dir (default '
                         '$TMPDIR/p2-artifacts)')
    ap.add_argument('--p2b-pool', default=None,
                    help='p2b_pool_builder.py output dir (p2b variant)')
    ap.add_argument('--budgets', default='10,25,50',
                    help='comma list; FROZEN to a subset of {10,25,50}')
    ap.add_argument('--generate', default=GENERATOR_DEFAULT,
                    help='generation callback (default: mlx_native nursery '
                         'wm_qwen35_generate.py)')
    ap.add_argument('--generator-python', default=None,
                    help='python running the generator (default: '
                         'wm_pyenv.sh resolution)')
    ap.add_argument('--practice-cmd', default=None,
                    help='zsh -lc per-pass practice command (real run)')
    ap.add_argument('--scorer-cli', default=None,
                    help='zsh -lc frozen-scorer command (real run)')
    ap.add_argument('--max-tokens', type=int, default=TOKEN_CAP,
                    help='generation cap (frozen default %d)' % TOKEN_CAP)
    ap.add_argument('--offline', action='store_true',
                    help='never re-fetch pool files (hermetic runs/tests)')
    ap.add_argument('--dry-run', action='store_true',
                    help='print the plan; fetch nothing; write nothing')
    args = ap.parse_args(argv)

    if args.pool_dir is None:
        args.pool_dir = _default_pool_dir()

    try:
        budgets = [int(b.strip()) for b in args.budgets.split(',')
                   if b.strip()]
    except ValueError:
        return fail('USAGE_ERROR', '--budgets %r is not a comma int list'
                    % args.budgets)
    if not budgets or len(set(budgets)) != len(budgets) \
            or any(b not in BUDGETS_FROZEN for b in budgets):
        return fail('BUDGET_NOT_FROZEN',
                    '--budgets %r outside the frozen table %s (PREREG-D; '
                    'not negotiable at runtime)'
                    % (budgets, list(BUDGETS_FROZEN)))
    if args.max_tokens < 1:
        return fail('USAGE_ERROR',
                    '--max-tokens must be >= 1, got %d' % args.max_tokens)
    variants = (('p2', 'p2b') if args.variant == 'both'
                else (args.variant,))

    try:
        if args.dry_run:
            return run_dry(args, variants, budgets)
        return run_real(args, variants, budgets)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return EXIT_INPUT
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001 - named, never silent
        return fail('INTERNAL_ERROR', '%s: %s' % (type(exc).__name__, exc))


if __name__ == '__main__':
    sys.exit(main())
