#!/usr/bin/env python3
"""ws4_train.py - WS-4 latent/budget predictor trainer (PREREG-E, FROZEN).

PREREG-E WS-4 (contract shape from pattern exp 0007): train five arms on the
A3+V-1+V-3 denominator and evaluate them on holdout PLANT FAMILIES:
  (a) logistic regression
  (b) matched-parameter MLP
  (c) null (train base rate)
  (d) exact memo (same plant family seen before)
  (e) n-gram table over (layer, column-band) co-occurrence
PASS bar (FROZEN): (a) beats best of (c)-(e) on holdout at <=10%
false-negative rate at its operating point; economics reported raw (full
evals skipped per false negative). FAIL = predictor retired, recorded.

PROPOSE-ONLY LAW (PROGRAM.md section 0 / pattern exp 0007 / ADR 0018): this
tool trains an ADVISORY predictor. It NEVER certifies an edit. Every output
carries the banner; a PASS bar met changes eval COST, never a verdict.

DENOMINATOR SCHEMA (ws4-denominator/v1) - defined and frozen HERE (this file
is its reference; a schema change needs a new prereg row, not an edit):
one JSON object per line; one line per candidate edit attempt in the recorded
A3+V-1+V-3 denominator. Required keys (strict; unknown keys refuse):

  attempt_id  str  unique across the file; matches the VERDICTS.md
                   denominator row for the attempt
  arm         str  provenance arm, one of "A3" | "V-1" | "V-3"
  family      str  plant family - THE SPLIT UNIT. Whole families go to
                   train or holdout; rows NEVER split across (leakage law:
                   a family seen in train cannot appear in holdout)
  features    obj  frozen feature block (PREREG-E WS-4), all required:
    delta_norm          float >= 0  Frobenius norm of the applied delta
    column_count        int  >= 1   distinct edited columns (all layers)
    layer_ids           [int]       sorted unique, non-empty: edited layers
    baseline_loop_rate  float in [0,1]  unedited-mirror loop rate on the
                                    G2-shaped cell (PREREG-A A3)
    capture_eigen_gap   float       capture eigen-gap at the planted rank
    layer_column_bands  [[int,int]] sorted (layer, band) co-occurrence
                                    pairs of the edited columns;
                                    band = column_id // 256 (BAND_WIDTH
                                    frozen below); may be empty only when
                                    column_count == 0 is impossible, so
                                    non-empty is required
  label       obj
    battery_pass  bool  full-battery verdict from the FROZEN oracle
                        (never from a screener, never from this tool)

Optional provenance keys (recorded in the receipt, never used as features):
  cast str, proposer str, receipt_digest str.

SPLIT (frozen): unique families sorted, shuffled with random.Random(SEED),
SEED = 20261105 (PREREG-A blinding seed); holdout = the first
ceil(n_families * 1/3) families of the shuffled order (>= 1, and train must
keep >= 1 family, so >= 2 families are required). The split is a function of
the family SET only - row order in the file cannot change it. split_digest =
sha256 of the canonical json {seed, train_families, holdout_families}.

FEATURE ENCODING for arms (a)/(b) (frozen): x = [delta_norm, column_count,
baseline_loop_rate, capture_eigen_gap] + multi-hot(layer_ids over the sorted
union of train-split layer_ids); z-scored with TRAIN means/stds (a dimension
with train std < 1e-12 is centered only, never scaled). The encoding is
recorded verbatim in the report.

ARM IMPLEMENTATIONS (frozen hyperparameters; deterministic; numpy):
  (a) logistic regression: sigmoid(w.x + b), full-batch gradient descent,
      lr 0.1, 2000 iterations, w=0 b=0 init, no regularization.
      params = d + 1.
  (b) matched-parameter MLP: one tanh hidden layer, h units; h* = argmin
      |params_mlp(h) - params_logistic| over h in {1,2,3,4} (ties -> smaller
      h; params_mlp(h) = h*(d+2)+1, so h*=1 with a documented +2-parameter
      residual is the normal outcome - BOTH counts are recorded, matching is
      never silently loosened). Init rng(SEED) normal std 0.01; full-batch
      GD lr 0.05, 4000 iterations, manual backprop.
  (c) null: constant train base rate P(battery_pass | train).
  (d) exact memo: key = family; prediction = mean train label within the
      family; a holdout family is BY CONSTRUCTION never in train, so every
      holdout row falls back to the train base rate and is counted as a
      memo_miss (this arm is the pre-registered memorization floor).
  (e) n-gram table: tokens = the row's sorted (layer, band) pairs; keys =
      unigrams (each token) + co-occurrence bigrams (each sorted 2-combination
      of tokens); table value = Laplace-smoothed train pass rate
      (passes + 1) / (rows + 2); prediction = mean over present bigram keys,
      else mean over present unigram keys, else train base rate.

OPERATING POINT (frozen, same rule in v5_audit.py): candidates = the sorted
unique train scores of the arm; predicted-pass iff score >= t; the operating
point is the HIGHEST t with train FNR <= 0.10 (FNR_FLOOR). A split with no
positive train rows defines FNR := 0.0 (no positive can be missed) and takes
the highest candidate. The threshold is chosen on TRAIN ONLY and then applied
untouched to holdout - the holdout never tunes anything.

HOLDOUT METRICS per arm (exact keys, frozen):
  auc                            Mann-Whitney AUC with midranks for ties;
                                 null + HOLDOUT_DEGENERATE when the holdout
                                 is single-class (recorded, never faked)
  fnr_at_operating_point         holdout false-negative rate at the frozen
                                 train-chosen threshold
  evals_skipped_per_false_negative  skipped / false_negatives, where
                                 skipped = holdout rows predicted fail (they
                                 skip the full battery) and false_negatives =
                                 skipped rows whose label was pass; null when
                                 false_negatives == 0 (raw counts always
                                 recorded alongside - economics raw per
                                 PREREG-E)

PASS-BAR EVALUATION (frozen PREREG-E rule, evaluated here, verdict recorded):
  constraint: arm (a) holdout fnr_at_operating_point <= 0.10, else FAIL with
              NAMED reason FNR_ABOVE_FLOOR;
  comparison: arm (a) holdout auc > max(auc of (c),(d),(e)), else FAIL with
              NAMED reason NOT_BETTER_THAN_CONTROLS; a null AUC on any
              compared arm fails with NAMED reason HOLDOUT_DEGENERATE;
  FAIL = predictor RETIRED, recorded (PREREG-E). This tool records the
  evaluation; it never edits VERDICTS.md (ledger writes belong to the
  operator/integration, append-only).

Real runs execute in the machine venv $HOME/.local/share/wm-mlx/bin/python
(override: env WM4_VENV_PYTHON). Invoked under another interpreter for a
REAL run, the script polls up to 10 min (env WM4_VENV_POLL_SECONDS) for the
venv python to appear and re-execs into it; on timeout it fails NAMED
VENV_MISSING. --dry-run never polls, never imports numpy, writes nothing,
and works with any python3 (same house pattern as ws3_masked_attribution.py).

Usage:
  python3 -I tool/runs/ws4_train.py --denominator <denominator.jsonl> \
      --out <report.json> [--dry-run]

--dry-run validates the denominator against the frozen schema, computes the
family split, and prints the plan (rows, families, split, arms a-e, metric
keys, floors, banner) as JSON on stdout, exit 0. Nothing is written.

Exit codes (errors are NAMED on stderr as 'CODE: detail', never silent):
  0  ok (dry-run plan printed, or real-run report written)
  1  named input/runtime error:
       DENOMINATOR_MISSING      file absent/unreadable/undecodable
       DENOMINATOR_EMPTY        no non-blank lines
       DENOMINATOR_SCHEMA_ERROR a line violates ws4-denominator/v1 (detail
                                names line number + MISSING_FIELD= /
                                MALFORMED_FIELD= / UNKNOWN_KEY= /
                                DUPLICATE_ATTEMPT_ID=)
       SPLIT_DEGENERATE         fewer than 2 families, or an empty split side
       OUT_UNWRITABLE           --out cannot be written (real run)
       USAGE_ERROR              bad argv (e.g. --out missing)
       INTERNAL_ERROR           unexpected exception (class + message named)
  2  named dependency unavailable (real run only):
       VENV_MISSING             venv python absent after the poll window
       NUMPY_UNAVAILABLE        numpy not importable in the venv
"""

import argparse
import hashlib
import json
import math
import os
import random
import sys
import time
from datetime import datetime, timezone

EXIT_OK = 0
EXIT_INPUT = 1
EXIT_DEP_UNAVAILABLE = 2

SCHEMA = 'ws4-denominator/v1'
REPORT_SCHEMA = 'ws4-report/v1'

# --- pre-registered constants (PREREG-E WS-4 / PREREG-A; FROZEN) ------------
SEED = 20261105                 # PREREG-A blinding seed (frozen)
HOLDOUT_FAMILY_FRACTION = 1.0 / 3.0
FNR_FLOOR = 0.10                # PREREG-E: <=10% false-negative rate
BAND_WIDTH = 256                # column band = column_id // BAND_WIDTH
ARMS = (
    ('a', 'a_logistic', 'logistic regression'),
    ('b', 'b_mlp_matched', 'matched-parameter MLP'),
    ('c', 'c_null', 'null'),
    ('d', 'd_exact_memo', 'exact memo'),
    ('e', 'e_ngram_table', 'n-gram table'),
)
METRIC_KEYS = ('auc', 'fnr_at_operating_point',
               'evals_skipped_per_false_negative')
# Frozen arm hyperparameters (documented in the module docstring).
LOGISTIC_LR = 0.1
LOGISTIC_ITERS = 2000
MLP_LR = 0.05
MLP_ITERS = 4000
MLP_HIDDEN_CHOICES = (1, 2, 3, 4)
NGRAM_ALPHA = 1.0               # Laplace alpha; smoothing (p+1)/(n+2)

PROPOSE_ONLY_BANNER = (
    'PROPOSE_ONLY: WS-4 is an ADVISORY predictor - it NEVER certifies an '
    'edit (PROGRAM.md propose-only law / pattern exp 0007). Metrics here '
    'change eval COST, never verdicts.'
)

VENV_PYTHON_DEFAULT = os.path.expanduser('~/.local/share/wm-mlx/bin/python')
VENV_POLL_SECONDS_DEFAULT = 600  # house law: poll 10 min, then NAMED
VENV_POLL_INTERVAL = 5.0

FEATURE_KEYS_REQUIRED = (
    'delta_norm', 'column_count', 'layer_ids', 'baseline_loop_rate',
    'capture_eigen_gap', 'layer_column_bands',
)
ROW_KEYS_REQUIRED = ('attempt_id', 'arm', 'family', 'features', 'label')
ROW_KEYS_OPTIONAL = ('cast', 'proposer', 'receipt_digest')
ARM_VALUES = ('A3', 'V-1', 'V-3')


def _venv_python():
    return os.environ.get('WM4_VENV_PYTHON', VENV_PYTHON_DEFAULT)


def _venv_poll_seconds():
    raw = os.environ.get('WM4_VENV_POLL_SECONDS')
    if raw is None:
        return VENV_POLL_SECONDS_DEFAULT
    try:
        return max(0.0, float(raw))
    except ValueError:
        return VENV_POLL_SECONDS_DEFAULT


def fail(code, detail, exit_code=EXIT_INPUT):
    """Print a NAMED error to stderr; return the exit code for main."""
    print('%s: %s' % (code, detail), file=sys.stderr)
    return exit_code


def _now_utc():
    return datetime.now(timezone.utc).isoformat(timespec='seconds')


def _sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def _canonical_json(obj):
    """Canonical json text: sorted keys, tight separators (receipt digests)."""
    return json.dumps(obj, sort_keys=True, separators=(',', ':'))


# --------------------------------------------------------------------------
# Denominator reading + frozen schema validation (stdlib only)
# --------------------------------------------------------------------------

def _is_finite_number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) \
        and math.isfinite(v)


def _validate_row(row, lineno, seen_ids):
    """Return a list of schema problems for one parsed row (empty = ok)."""
    problems = []
    if not isinstance(row, dict):
        return ['line %d: row is not a JSON object' % lineno]
    for key in ROW_KEYS_REQUIRED:
        if key not in row:
            problems.append('line %d: MISSING_FIELD=%s' % (lineno, key))
    allowed = set(ROW_KEYS_REQUIRED) | set(ROW_KEYS_OPTIONAL)
    for key in sorted(row):
        if key not in allowed:
            problems.append('line %d: UNKNOWN_KEY=%s' % (lineno, key))
    if problems:
        return problems

    aid = row['attempt_id']
    if not isinstance(aid, str) or not aid:
        problems.append('line %d: MALFORMED_FIELD=attempt_id (non-empty str)'
                        % lineno)
    elif aid in seen_ids:
        problems.append('line %d: DUPLICATE_ATTEMPT_ID=%s' % (lineno, aid))
    else:
        seen_ids.add(aid)
    if not isinstance(row['arm'], str) or row['arm'] not in ARM_VALUES:
        problems.append('line %d: MALFORMED_FIELD=arm (one of %s)'
                        % (lineno, list(ARM_VALUES)))
    if not isinstance(row['family'], str) or not row['family']:
        problems.append('line %d: MALFORMED_FIELD=family (non-empty str)'
                        % lineno)

    feats = row['features']
    if not isinstance(feats, dict):
        problems.append('line %d: MALFORMED_FIELD=features (object)' % lineno)
        return problems
    for key in FEATURE_KEYS_REQUIRED:
        if key not in feats:
            problems.append('line %d: MISSING_FIELD=features.%s'
                            % (lineno, key))
    for key in sorted(feats):
        if key not in FEATURE_KEYS_REQUIRED:
            problems.append('line %d: UNKNOWN_KEY=features.%s'
                            % (lineno, key))
    if problems:
        return problems

    if not _is_finite_number(feats['delta_norm']) or feats['delta_norm'] < 0:
        problems.append('line %d: MALFORMED_FIELD=features.delta_norm '
                        '(finite float >= 0)' % lineno)
    cc = feats['column_count']
    if not isinstance(cc, int) or isinstance(cc, bool) or cc < 1:
        problems.append('line %d: MALFORMED_FIELD=features.column_count '
                        '(int >= 1)' % lineno)
    lids = feats['layer_ids']
    if (not isinstance(lids, list) or not lids
            or not all(isinstance(i, int) and not isinstance(i, bool)
                       and i >= 0 for i in lids)
            or lids != sorted(set(lids))):
        problems.append('line %d: MALFORMED_FIELD=features.layer_ids '
                        '(sorted unique non-empty [int >= 0])' % lineno)
    blr = feats['baseline_loop_rate']
    if not _is_finite_number(blr) or not (0.0 <= blr <= 1.0):
        problems.append('line %d: MALFORMED_FIELD=features.'
                        'baseline_loop_rate (float in [0,1])' % lineno)
    if not _is_finite_number(feats['capture_eigen_gap']):
        problems.append('line %d: MALFORMED_FIELD=features.capture_eigen_gap '
                        '(finite float)' % lineno)
    bands = feats['layer_column_bands']
    bands_ok = (
        isinstance(bands, list) and bands
        and all(isinstance(p, list) and len(p) == 2
                and all(isinstance(x, int) and not isinstance(x, bool)
                        and x >= 0 for x in p) for p in bands)
        and [tuple(p) for p in bands] == sorted({tuple(p) for p in bands})
    )
    if not bands_ok:
        problems.append('line %d: MALFORMED_FIELD=features.'
                        'layer_column_bands (sorted unique [[layer, band]] '
                        'int pairs, non-empty)' % lineno)

    label = row['label']
    if not isinstance(label, dict):
        problems.append('line %d: MALFORMED_FIELD=label (object)' % lineno)
    else:
        for key in sorted(label):
            if key != 'battery_pass':
                problems.append('line %d: UNKNOWN_KEY=label.%s'
                                % (lineno, key))
        if 'battery_pass' not in label:
            problems.append('line %d: MISSING_FIELD=label.battery_pass'
                            % lineno)
        elif not isinstance(label['battery_pass'], bool):
            problems.append('line %d: MALFORMED_FIELD=label.battery_pass '
                            '(bool)' % lineno)

    for key in ROW_KEYS_OPTIONAL:
        if key in row and not isinstance(row[key], str):
            problems.append('line %d: MALFORMED_FIELD=%s (str)'
                            % (lineno, key))
    return problems


def read_denominator(path):
    """Read + schema-validate the denominator jsonl.

    Returns (rows, raw_bytes). Raises RuntimeError with a NAMED code:
    DENOMINATOR_MISSING / DENOMINATOR_EMPTY / DENOMINATOR_SCHEMA_ERROR.
    """
    try:
        with open(path, 'rb') as fh:
            raw = fh.read()
    except (OSError, UnicodeDecodeError) as exc:
        raise RuntimeError('DENOMINATOR_MISSING: %s (%s)' % (path, exc))
    try:
        text = raw.decode('utf-8')
    except UnicodeDecodeError as exc:
        raise RuntimeError('DENOMINATOR_MISSING: %s not utf-8 (%s)'
                           % (path, exc))
    rows = []
    seen_ids = set()
    problems = []
    for lineno, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except ValueError as exc:
            problems.append('line %d: not valid json (%s)' % (lineno, exc))
            continue
        problems.extend(_validate_row(row, lineno, seen_ids))
        rows.append(row)
    if problems:
        raise RuntimeError('DENOMINATOR_SCHEMA_ERROR: ' + '; '.join(
            problems[:20]) + ('' if len(problems) <= 20
                              else '; ... +%d more' % (len(problems) - 20)))
    if not rows:
        raise RuntimeError('DENOMINATOR_EMPTY: %s has no non-blank lines'
                           % path)
    return rows, raw


# --------------------------------------------------------------------------
# Frozen family split (never by row)
# --------------------------------------------------------------------------

def family_split(rows):
    """Deterministic train/holdout split by plant FAMILY.

    Returns (train_rows, holdout_rows, split_info). Raises RuntimeError
    SPLIT_DEGENERATE when a family-level split is impossible.
    """
    families = sorted({r['family'] for r in rows})
    if len(families) < 2:
        raise RuntimeError(
            'SPLIT_DEGENERATE: %d family/families - a family-level '
            'train/holdout split needs >= 2 families (rows never split)'
            % len(families))
    order = list(families)
    random.Random(SEED).shuffle(order)
    n_holdout = max(1, math.ceil(len(order) * HOLDOUT_FAMILY_FRACTION))
    n_holdout = min(n_holdout, len(order) - 1)  # train keeps >= 1 family
    holdout = set(order[:n_holdout])
    train_rows = [r for r in rows if r['family'] not in holdout]
    holdout_rows = [r for r in rows if r['family'] in holdout]
    if not train_rows or not holdout_rows:
        raise RuntimeError('SPLIT_DEGENERATE: an empty split side '
                           '(train=%d holdout=%d rows)'
                           % (len(train_rows), len(holdout_rows)))
    train_families = sorted({r['family'] for r in train_rows})
    holdout_families = sorted(holdout)
    split_info = {
        'seed': SEED,
        'rule': ('families sorted, shuffled with random.Random(%d), holdout '
                 '= first ceil(n*1/3) (>=1, train keeps >=1); rows follow '
                 'their family, never split' % SEED),
        'train_families': train_families,
        'holdout_families': holdout_families,
        'train_rows': len(train_rows),
        'holdout_rows': len(holdout_rows),
        'split_digest': _sha256_bytes(_canonical_json({
            'seed': SEED,
            'train_families': train_families,
            'holdout_families': holdout_families,
        }).encode('utf-8')),
    }
    return train_rows, holdout_rows, split_info


# --------------------------------------------------------------------------
# Frozen operating-point rule + metrics (pure python; numpy used by the arms)
# --------------------------------------------------------------------------

def _fnr_at(scores, labels, threshold):
    """FNR at threshold: predicted-pass iff score >= threshold."""
    positives = [s for s, y in zip(scores, labels) if y]
    if not positives:
        return 0.0  # frozen convention: no positives -> nothing to miss
    missed = sum(1 for s in positives if s < threshold)
    return missed / len(positives)


def operating_point(train_scores, train_labels):
    """Frozen rule: HIGHEST train-score threshold with train FNR <= 0.10."""
    candidates = sorted(set(train_scores))
    chosen = None
    for t in candidates:
        if _fnr_at(train_scores, train_labels, t) <= FNR_FLOOR:
            chosen = t  # candidates ascending -> last feasible is highest
    if chosen is None:  # unreachable given the FNR convention, kept explicit
        chosen = candidates[0] - 1.0 if candidates else -1.0
    return chosen


def holdout_metrics(scores, labels, threshold):
    """Frozen holdout metric block (exact keys per PREREG-E task shape)."""
    n = len(labels)
    positives = sum(1 for y in labels if y)
    negatives = n - positives
    predicted_fail = [i for i in range(n) if scores[i] < threshold]
    skipped = len(predicted_fail)
    false_negatives = sum(1 for i in predicted_fail if labels[i])
    auc = None
    degenerate = positives == 0 or negatives == 0
    if not degenerate:
        auc = mannwhitney_auc(scores, labels)
    return {
        'auc': auc,
        'fnr_at_operating_point': (false_negatives / positives
                                   if positives else 0.0),
        'evals_skipped_per_false_negative': (
            skipped / false_negatives if false_negatives > 0 else None),
        'raw': {
            'rows': n,
            'positives': positives,
            'negatives': negatives,
            'evals_skipped': skipped,
            'false_negatives': false_negatives,
            'ratio_note': ('evals_skipped_per_false_negative is null iff '
                           'false_negatives == 0; raw counts are the '
                           'evidence (PREREG-E: economics reported raw)'),
        },
        'degenerate': 'HOLDOUT_DEGENERATE' if degenerate else None,
    }


def mannwhitney_auc(scores, labels):
    """AUC via midranks (tie-corrected Mann-Whitney U). Pure python."""
    n = len(scores)
    order = sorted(range(n), key=lambda i: scores[i])
    ranks = [0.0] * n
    i = 0
    while i < n:
        j = i
        while j + 1 < n and scores[order[j + 1]] == scores[order[i]]:
            j += 1
        midrank = (i + j) / 2.0 + 1.0  # 1-based midrank for ties
        for k in range(i, j + 1):
            ranks[order[k]] = midrank
        i = j + 1
    n_pos = sum(1 for y in labels if y)
    n_neg = n - n_pos
    if n_pos == 0 or n_neg == 0:
        return None
    pos_rank_sum = sum(r for r, y in zip(ranks, labels) if y)
    u = pos_rank_sum - n_pos * (n_pos + 1) / 2.0
    return u / (n_pos * n_neg)


# --------------------------------------------------------------------------
# Real-run machinery (numpy). Everything below runs only after the venv gate.
# --------------------------------------------------------------------------

def ensure_venv_python(argv):
    """Real-run venv gate: poll for the venv python, re-exec into it.

    Returns None when already running under the venv python; otherwise
    re-execs (never returns) or returns exit code 2 with NAMED VENV_MISSING
    when the venv python does not appear within the poll window.
    """
    venv_py = _venv_python()
    if os.path.realpath(sys.executable) == os.path.realpath(venv_py):
        return None
    deadline = time.monotonic() + _venv_poll_seconds()
    announced = False
    while True:
        if os.path.isfile(venv_py) and os.access(venv_py, os.X_OK):
            os.execv(venv_py, [venv_py, '-I', os.path.abspath(__file__)]
                     + list(argv))
        if time.monotonic() >= deadline:
            return fail(
                'VENV_MISSING',
                'venv python %s not found/executable after %.0fs poll '
                '(real runs require the wm-mlx venv with numpy; --dry-run '
                'does not)' % (venv_py, _venv_poll_seconds()),
                EXIT_DEP_UNAVAILABLE)
        if not announced:
            print('waiting for venv python %s (poll window %.0fs)...'
                  % (venv_py, _venv_poll_seconds()), file=sys.stderr)
            announced = True
        time.sleep(VENV_POLL_INTERVAL)


def _encode_features(rows, layer_vocab):
    """Frozen encoding: 4 scalars + layer multi-hot (numpy float64 matrix)."""
    import numpy as np
    x = np.zeros((len(rows), 4 + len(layer_vocab)), dtype=np.float64)
    for i, r in enumerate(rows):
        f = r['features']
        x[i, 0] = f['delta_norm']
        x[i, 1] = float(f['column_count'])
        x[i, 2] = f['baseline_loop_rate']
        x[i, 3] = f['capture_eigen_gap']
        for lid in f['layer_ids']:
            if lid in layer_vocab:
                x[i, 4 + layer_vocab[lid]] = 1.0
    return x


def _standardize(x_train, x_holdout):
    """Train-mean/std z-score; std < 1e-12 dims are centered only (frozen)."""
    import numpy as np
    mean = x_train.mean(axis=0)
    std = x_train.std(axis=0)
    scale = np.where(std < 1e-12, 1.0, std)
    return (x_train - mean) / scale, (x_holdout - mean) / scale, mean, std


def _sigmoid(z):
    import numpy as np
    return 1.0 / (1.0 + np.exp(-np.clip(z, -35.0, 35.0)))


def _train_logistic(x, y):
    """Arm (a): full-batch GD logistic regression, frozen hyperparameters."""
    import numpy as np
    n, d = x.shape
    w = np.zeros(d)
    b = 0.0
    for _ in range(LOGISTIC_ITERS):
        p = _sigmoid(x @ w + b)
        err = p - y
        w -= LOGISTIC_LR * (x.T @ err) / n
        b -= LOGISTIC_LR * err.mean()
    return w, b


def _train_mlp(x, y, hidden):
    """Arm (b): one tanh hidden layer, manual backprop, frozen GD."""
    import numpy as np
    n, d = x.shape
    rng = np.random.default_rng(SEED)
    w1 = rng.normal(0.0, 0.01, size=(d, hidden))
    b1 = rng.normal(0.0, 0.01, size=(hidden,))
    w2 = rng.normal(0.0, 0.01, size=(hidden,))
    b2 = float(rng.normal(0.0, 0.01))
    for _ in range(MLP_ITERS):
        z = x @ w1 + b1
        h = np.tanh(z)
        p = _sigmoid(h @ w2 + b2)
        err = (p - y) / n
        dw2 = h.T @ err
        db2 = err.sum()
        dh = np.outer(err, w2) * (1.0 - h * h)
        dw1 = x.T @ dh
        db1 = dh.sum(axis=0)
        w1 -= MLP_LR * dw1
        b1 -= MLP_LR * db1
        w2 -= MLP_LR * dw2
        b2 -= MLP_LR * db2
    return w1, b1, w2, b2


def _mlp_forward(x, params):
    import numpy as np
    w1, b1, w2, b2 = params
    return _sigmoid(np.tanh(x @ w1 + b1) @ w2 + b2)


def _band_tokens(row):
    """Arm (e) tokens: the row's sorted (layer, band) pairs as strings."""
    return ['%d:%d' % (p[0], p[1]) for p in row['features']
            ['layer_column_bands']]


def _train_ngram(train_rows):
    """Arm (e) table: Laplace-smoothed pass rates over uni/bigram keys."""
    uni = {}
    bi = {}
    for r in train_rows:
        y = 1.0 if r['label']['battery_pass'] else 0.0
        toks = _band_tokens(r)
        for t in toks:
            n, s = uni.get(t, (0, 0.0))
            uni[t] = (n + 1, s + y)
        for i in range(len(toks)):
            for j in range(i + 1, len(toks)):
                key = tuple(sorted((toks[i], toks[j])))
                n, s = bi.get(key, (0, 0.0))
                bi[key] = (n + 1, s + y)
    alpha = NGRAM_ALPHA
    uni_p = {t: (s + alpha) / (n + 2 * alpha) for t, (n, s) in uni.items()}
    bi_p = {k: (s + alpha) / (n + 2 * alpha) for k, (n, s) in bi.items()}
    return uni_p, bi_p


def _ngram_score(row, uni_p, bi_p, base_rate):
    toks = _band_tokens(row)
    bis = [tuple(sorted((toks[i], toks[j])))
           for i in range(len(toks)) for j in range(i + 1, len(toks))]
    bi_vals = [bi_p[k] for k in bis if k in bi_p]
    if bi_vals:
        return sum(bi_vals) / len(bi_vals)
    uni_vals = [uni_p[t] for t in toks if t in uni_p]
    if uni_vals:
        return sum(uni_vals) / len(uni_vals)
    return base_rate


def train_all_arms(train_rows, holdout_rows):
    """Train arms (a)-(e); return per-arm train/holdout score lists + info."""
    import numpy as np
    y_train = np.array([1.0 if r['label']['battery_pass'] else 0.0
                        for r in train_rows])
    y_hold = np.array([1.0 if r['label']['battery_pass'] else 0.0
                       for r in holdout_rows])
    base_rate = float(y_train.mean()) if len(y_train) else 0.0

    layer_vocab = {lid: i for i, lid in enumerate(sorted(
        {lid for r in train_rows for lid in r['features']['layer_ids']}))}
    x_tr = _encode_features(train_rows, layer_vocab)
    x_ho = _encode_features(holdout_rows, layer_vocab)
    x_tr_s, x_ho_s, mean, std = _standardize(x_tr, x_ho)
    d = x_tr_s.shape[1]

    arms = {}

    # (a) logistic regression
    w, b = _train_logistic(x_tr_s, y_train)
    arms['a_logistic'] = {
        'train_scores': _sigmoid(x_tr_s @ w + b).tolist(),
        'holdout_scores': _sigmoid(x_ho_s @ w + b).tolist(),
        'info': {'params': int(d + 1), 'lr': LOGISTIC_LR,
                 'iterations': LOGISTIC_ITERS, 'init': 'zeros',
                 'regularization': 'none'},
    }

    # (b) matched-parameter MLP
    p_lin = d + 1
    diffs = {h: abs((h * (d + 2) + 1) - p_lin) for h in MLP_HIDDEN_CHOICES}
    hidden = min(sorted(diffs), key=lambda h: (diffs[h], h))
    params_mlp = hidden * (d + 2) + 1
    mlp = _train_mlp(x_tr_s, y_train, hidden)
    arms['b_mlp_matched'] = {
        'train_scores': _mlp_forward(x_tr_s, mlp).tolist(),
        'holdout_scores': _mlp_forward(x_ho_s, mlp).tolist(),
        'info': {'hidden_units': int(hidden), 'activation': 'tanh',
                 'params': int(params_mlp), 'logistic_params': int(p_lin),
                 'param_match_residual': int(abs(params_mlp - p_lin)),
                 'match_rule': ('h* = argmin |params_mlp(h) - (d+1)| over '
                                'h in %s, ties -> smaller h; residual '
                                'recorded, never silently loosened'
                                % (list(MLP_HIDDEN_CHOICES),)),
                 'lr': MLP_LR, 'iterations': MLP_ITERS,
                 'init': 'rng(%d) normal std 0.01' % SEED},
    }

    # (c) null
    arms['c_null'] = {
        'train_scores': [base_rate] * len(train_rows),
        'holdout_scores': [base_rate] * len(holdout_rows),
        'info': {'base_rate': base_rate},
    }

    # (d) exact memo (key = family; holdout families are unseen BY
    #     CONSTRUCTION of the family split -> base-rate fallback + miss count)
    fam_rate = {}
    for r in train_rows:
        fam_rate.setdefault(r['family'], []).append(
            1.0 if r['label']['battery_pass'] else 0.0)
    fam_rate = {f: sum(v) / len(v) for f, v in fam_rate.items()}
    memo_hits = sum(1 for r in holdout_rows if r['family'] in fam_rate)
    arms['d_exact_memo'] = {
        'train_scores': [fam_rate[r['family']] for r in train_rows],
        'holdout_scores': [fam_rate.get(r['family'], base_rate)
                           for r in holdout_rows],
        'info': {'key': 'family', 'families_memorized': len(fam_rate),
                 'holdout_memo_hits': memo_hits,
                 'holdout_memo_misses': len(holdout_rows) - memo_hits,
                 'fallback': 'train base rate',
                 'note': ('the family split makes holdout families unseen by '
                          'construction; this arm is the pre-registered '
                          'memorization floor')},
    }

    # (e) n-gram table over (layer, column-band) co-occurrence
    uni_p, bi_p = _train_ngram(train_rows)
    arms['e_ngram_table'] = {
        'train_scores': [_ngram_score(r, uni_p, bi_p, base_rate)
                         for r in train_rows],
        'holdout_scores': [_ngram_score(r, uni_p, bi_p, base_rate)
                           for r in holdout_rows],
        'info': {'unigram_keys': len(uni_p), 'bigram_keys': len(bi_p),
                 'laplace_alpha': NGRAM_ALPHA,
                 'fallback_order': ['bigram mean', 'unigram mean',
                                    'train base rate'],
                 'band_width': BAND_WIDTH},
    }

    encoding = {
        'scalars': ['delta_norm', 'column_count', 'baseline_loop_rate',
                    'capture_eigen_gap'],
        'layer_vocab': layer_vocab,
        'standardization': {
            'rule': 'train mean/std z-score; std < 1e-12 dims centered only',
            'mean': mean.tolist(), 'std': std.tolist(),
        },
        'dim': int(d),
    }
    return arms, encoding, y_train.tolist(), y_hold.tolist()


def evaluate_pass_bar(arms_metrics):
    """Frozen PREREG-E PASS-bar evaluation over the per-arm metric blocks."""
    a = arms_metrics['a_logistic']
    controls = ('c_null', 'd_exact_memo', 'e_ngram_table')
    fnr = a['metrics']['fnr_at_operating_point']
    constraint_ok = fnr <= FNR_FLOOR
    aucs = {name: arms_metrics[name]['metrics']['auc'] for name in controls}
    a_auc = a['metrics']['auc']
    fail_reason = None
    beats = None
    best_control = None
    if not constraint_ok:
        fail_reason = 'FNR_ABOVE_FLOOR'
    elif a_auc is None or any(v is None for v in aucs.values()):
        fail_reason = 'HOLDOUT_DEGENERATE'
    else:
        best_control = max(aucs, key=lambda k: aucs[k])
        beats = a_auc > aucs[best_control]
        if not beats:
            fail_reason = 'NOT_BETTER_THAN_CONTROLS'
    return {
        'rule': ('FROZEN (PREREG-E): arm (a) holdout FNR at its operating '
                 'point <= %.2f AND arm (a) holdout AUC > max AUC of (c),(d),'
                 '(e); FAIL = predictor retired, recorded' % FNR_FLOOR),
        'constraint': {'fnr_floor': FNR_FLOOR,
                       'arm_a_holdout_fnr': fnr,
                       'satisfied': constraint_ok},
        'comparison': {'arm_a_holdout_auc': a_auc,
                       'control_aucs': aucs,
                       'best_control_arm': best_control,
                       'arm_a_beats_best_control': beats},
        'verdict': 'PASS_BAR_MET' if fail_reason is None else 'FAIL',
        'fail_reason': fail_reason,
        'on_fail': 'predictor RETIRED, recorded (PREREG-E); no appeal here',
        'propose_only': True,
    }


def run_real(args, rows, raw):
    """Real run: venv gate -> numpy -> train arms -> write the report."""
    venv_rc = ensure_venv_python(sys.argv[1:])
    if venv_rc is not None:
        return venv_rc
    try:
        import numpy as np
    except ImportError as exc:
        return fail('NUMPY_UNAVAILABLE', str(exc), EXIT_DEP_UNAVAILABLE)

    try:
        train_rows, holdout_rows, split_info = family_split(rows)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return EXIT_INPUT

    try:
        arms, encoding, y_train, y_hold = train_all_arms(
            train_rows, holdout_rows)
    except Exception as exc:  # noqa: BLE001 - named, never silent
        return fail('INTERNAL_ERROR', '%s: %s'
                    % (type(exc).__name__, exc))

    arms_metrics = {}
    for _letter, arm_id, arm_name in ARMS:
        arm = arms[arm_id]
        labels_train = [bool(r['label']['battery_pass']) for r in train_rows]
        threshold = operating_point(arm['train_scores'], labels_train)
        metrics = holdout_metrics(arm['holdout_scores'], y_hold_bool(y_hold),
                                  threshold)
        arms_metrics[arm_id] = {
            'arm': arm_id,
            'name': arm_name,
            'params_or_capacity': arm['info'],
            'operating_point': {
                'threshold': threshold,
                'rule': ('highest train-score threshold with train FNR <= '
                         '%.2f (chosen on TRAIN only, applied untouched to '
                         'holdout)' % FNR_FLOOR),
                'train_fnr_at_threshold': _fnr_at(arm['train_scores'],
                                                  labels_train, threshold),
            },
            'metrics': metrics,
        }

    report = {
        'schema': REPORT_SCHEMA,
        'created_utc': _now_utc(),
        'tool': 'ws4_train.py',
        'propose_only': True,
        'banner': PROPOSE_ONLY_BANNER,
        'provenance': {
            'denominator': {
                'path': os.path.abspath(args.denominator),
                'sha256': _sha256_bytes(raw),
                'schema': SCHEMA,
                'rows': len(rows),
                'families': len({r['family'] for r in rows}),
            },
            'split': split_info,
            'venv': {'python': os.path.realpath(sys.executable),
                     'numpy_version': np.__version__,
                     'python_version': sys.version.split()[0]},
            'feature_encoding': encoding,
            'seed': SEED,
            'fnr_floor': FNR_FLOOR,
            'band_width': BAND_WIDTH,
        },
        'arms': arms_metrics,
        'pass_bar': evaluate_pass_bar(arms_metrics),
        'holdout_note': ('holdout families were never trained on (split by '
                         'plant FAMILY, never by row)'),
    }

    out_dir = os.path.dirname(os.path.abspath(args.out))
    try:
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        tmp = args.out + '.tmp'
        with open(tmp, 'w', encoding='utf-8') as fh:
            json.dump(report, fh, indent=2, sort_keys=False)
            fh.write('\n')
        os.replace(tmp, args.out)
    except OSError as exc:
        return fail('OUT_UNWRITABLE', '%s (%s)' % (args.out, exc))
    print(json.dumps({
        'tool': 'ws4_train.py',
        'report': os.path.abspath(args.out),
        'pass_bar_verdict': report['pass_bar']['verdict'],
        'fail_reason': report['pass_bar']['fail_reason'],
        'propose_only': True,
    }, indent=2))
    return EXIT_OK


def y_hold_bool(y_hold):
    return [bool(v) for v in y_hold]


# --------------------------------------------------------------------------
# Dry run
# --------------------------------------------------------------------------

def run_dry(args, rows, raw):
    """Print the plan (split computed; nothing trained, nothing written)."""
    try:
        train_rows, holdout_rows, split_info = family_split(rows)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return EXIT_INPUT
    plan = {
        'mode': 'dry-run',
        'tool': 'ws4_train.py',
        'schema': SCHEMA,
        'denominator': {
            'path': os.path.abspath(args.denominator),
            'sha256': _sha256_bytes(raw),
            'rows': len(rows),
            'families': sorted({r['family'] for r in rows}),
        },
        'split': split_info,
        'arms': [{'arm': letter, 'id': arm_id, 'name': name}
                 for letter, arm_id, name in ARMS],
        'arm_letters': [letter for letter, _id, _n in ARMS],
        'metrics_per_arm': list(METRIC_KEYS),
        'fnr_floor': FNR_FLOOR,
        'seed': SEED,
        'band_width': BAND_WIDTH,
        'operating_point_rule': ('highest train-score threshold with train '
                                 'FNR <= %.2f; chosen on TRAIN only'
                                 % FNR_FLOOR),
        'pass_bar_rule': ('arm (a) beats best of (c)-(e) on holdout AUC at '
                          'holdout FNR <= %.2f; FAIL = predictor retired, '
                          'recorded (PREREG-E, FROZEN)' % FNR_FLOOR),
        'venv': {
            'python': _venv_python(),
            'poll_seconds': _venv_poll_seconds(),
            'checked': False,
            'note': 'dry-run never polls the venv and never imports numpy',
        },
        'out': os.path.abspath(args.out),
        'propose_only': True,
        'banner': PROPOSE_ONLY_BANNER,
        'note': 'plan only; venv NOT polled; numpy NOT imported; nothing '
                'written',
    }
    print(json.dumps(plan, indent=2))
    return EXIT_OK


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--denominator', required=True,
                    help='denominator jsonl (schema %s)' % SCHEMA)
    ap.add_argument('--out', required=True, help='report JSON path')
    ap.add_argument('--dry-run', action='store_true',
                    help='validate + print the plan; poll nothing; write '
                         'nothing')
    args = ap.parse_args(argv)

    try:
        rows, raw = read_denominator(args.denominator)
        if args.dry_run:
            return run_dry(args, rows, raw)
        return run_real(args, rows, raw)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return EXIT_INPUT
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001 - named, never silent
        return fail('INTERNAL_ERROR', '%s: %s' % (type(exc).__name__, exc))


if __name__ == '__main__':
    sys.exit(main())
