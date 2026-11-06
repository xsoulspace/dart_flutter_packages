#!/usr/bin/env python3
"""v5_audit.py - V-5 advisory calibration audit (PREREG-E, FROZEN).

PREREG-E V-5: screener = WS-4 predictor + WS-3 prior, run over >= 30 sampled
candidate edits drawn from the recorded denominator (A3+V-1+V-3 attempts,
plants and nulls). Report ROC + operating point + economics vs the full
battery. FLOOR (FROZEN): false-negative rate <= 10% at the operating point;
else the screener is DISABLED with NAMED SCREENER_UNCALIBRATED - the
disablement IS the verdict (kill clause: it disables the WS-4/V-5 tier
ONLY; ledgered certifications are untouched).

PROPOSE-ONLY LAW: even a calibrated screener NEVER certifies an edit; it
only reorders eval cost. Every output carries the banner.

Stdlib only (no venv, no numpy): ROC/AUC are exact rank computations. The
audit itself is hermetic - it reads recorded scores and labels, runs no
model. Real runs are therefore testable without any engine.

AUDIT SAMPLE SCHEMA (v5-audit-sample/v1) - defined and frozen HERE:
one JSON object per line; one line per sampled candidate edit (>= 30 lines
for a real audit). Required keys (strict; unknown keys refuse):

  attempt_id       str   unique; matches the denominator/VERDICTS row
  family           str   plant family of the candidate
  ws4_score        float WS-4 arm-(a) predictor score for this candidate
                         (produced by ws4_train.py's frozen model; the audit
                         never re-trains anything)
  ws3_prior_score  float WS-3 masked-attribution prior score for this
                         candidate (ws3_masked_attribution.py sidecar)
  battery_pass     bool  full-battery label from the FROZEN oracle

Optional: receipt_digest str.

FROZEN COMBINATION RULE: screener_score = (ws4_score + ws3_prior_score) / 2
- equal weights on the RAW columns. No fitted combination: tuning
combination weights against the labels would be editing the oracle
(frozen-oracle law), so the weights are frozen at 1/2 here and changing
them requires a new prereg row.

OPERATING POINT: pass --operating-threshold with the threshold from the
WS-4 report (source "ws4_receipt") - that is the true pre-registered audit:
the point was chosen on TRAIN by ws4_train.py and is validated here on the
sampled denominator. Without the flag the audit selects the highest
sample-score threshold with sample FNR <= 0.10 and records source
"audit_selected" plus a WEAK-CHECK caveat (an audit that picks its own
point cannot fail its own floor except by degenerate scores; the honest
audit carries the WS-4 threshold).

Floor check at the operating point: FNR > 0.10  =>  NAMED
SCREENER_UNCALIBRATED, screener_disabled = true in the output (exit 0: the
disablement is a measured verdict, not a tool failure - same exit-code law
as ws2_certify.py).

Usage:
  python3 -I tool/runs/v5_audit.py --sample <audit_sample.jsonl> \
      --out <v5_report.json> [--operating-threshold T] [--dry-run]

--dry-run validates the sample against the frozen schema and prints the
plan (rows, floor status, combination rule, operating-point source) as JSON
on stdout, exit 0. Nothing is written; the >=30 floor is REPORTED, not
enforced, in dry-run mode.

Exit codes (errors are NAMED on stderr as 'CODE: detail', never silent):
  0  ok (dry-run plan printed, or audit report written - INCLUDING a
     SCREENER_UNCALIBRATED verdict, which is a result, not a failure)
  1  named input/runtime error:
       AUDIT_INPUT_MISSING        sample file absent/unreadable/undecodable
       AUDIT_SAMPLE_EMPTY         no non-blank lines
       AUDIT_SCHEMA_ERROR         a line violates v5-audit-sample/v1
       AUDIT_SAMPLE_TOO_SMALL     real run with < 30 rows (PREREG-E floor;
                                  an underpowered audit is refused, never
                                  run with a lucky floor)
       OPERATING_THRESHOLD_INVALID --operating-threshold not a finite float
       OUT_UNWRITABLE             --out cannot be written (real run)
       INTERNAL_ERROR             unexpected exception (class + message)
"""

import argparse
import hashlib
import json
import math
import os
import sys
from datetime import datetime, timezone

EXIT_OK = 0
EXIT_INPUT = 1

SCHEMA = 'v5-audit-sample/v1'
REPORT_SCHEMA = 'v5-audit/v1'

# --- pre-registered constants (PREREG-E V-5; FROZEN) ------------------------
MIN_SAMPLE_N = 30               # PREREG-E: >= 30 sampled candidates
FNR_FLOOR = 0.10                # PREREG-E floor: false-negative rate <= 10%
COMBINATION_RULE = ('screener_score = (ws4_score + ws3_prior_score) / 2 '
                    '(equal weights on RAW columns, FROZEN; a fitted '
                    'combination would be an oracle edit)')
KILL_CLAUSE = ('SCREENER_UNCALIBRATED disables the WS-4/V-5 advisory tier '
               'ONLY; ledgered bf16/greedy/python certifications stay keyed '
               'to their receipts (PREREG-E kill clauses)')
PROPOSE_ONLY_BANNER = (
    'PROPOSE_ONLY: the screener is ADVISORY - it NEVER certifies an edit '
    '(PROGRAM.md propose-only law / pattern exp 0007). It changes eval '
    'COST, never verdicts.'
)

ROW_KEYS_REQUIRED = ('attempt_id', 'family', 'ws4_score', 'ws3_prior_score',
                     'battery_pass')
ROW_KEYS_OPTIONAL = ('receipt_digest',)


def fail(code, detail, exit_code=EXIT_INPUT):
    print('%s: %s' % (code, detail), file=sys.stderr)
    return exit_code


def _now_utc():
    return datetime.now(timezone.utc).isoformat(timespec='seconds')


def _sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def _is_finite_number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) \
        and math.isfinite(v)


def _validate_row(row, lineno, seen_ids):
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
        problems.append('line %d: MALFORMED_FIELD=attempt_id' % lineno)
    elif aid in seen_ids:
        problems.append('line %d: DUPLICATE_ATTEMPT_ID=%s' % (lineno, aid))
    else:
        seen_ids.add(aid)
    if not isinstance(row['family'], str) or not row['family']:
        problems.append('line %d: MALFORMED_FIELD=family' % lineno)
    for key in ('ws4_score', 'ws3_prior_score'):
        if not _is_finite_number(row[key]):
            problems.append('line %d: MALFORMED_FIELD=%s (finite float)'
                            % (lineno, key))
    if not isinstance(row['battery_pass'], bool):
        problems.append('line %d: MALFORMED_FIELD=battery_pass (bool)'
                        % lineno)
    if 'receipt_digest' in row and not isinstance(row['receipt_digest'], str):
        problems.append('line %d: MALFORMED_FIELD=receipt_digest (str)'
                        % lineno)
    return problems


def read_sample(path):
    """Read + schema-validate the audit sample. NAMED RuntimeError on fail."""
    try:
        with open(path, 'rb') as fh:
            raw = fh.read()
    except OSError as exc:
        raise RuntimeError('AUDIT_INPUT_MISSING: %s (%s)' % (path, exc))
    try:
        text = raw.decode('utf-8')
    except UnicodeDecodeError as exc:
        raise RuntimeError('AUDIT_INPUT_MISSING: %s not utf-8 (%s)'
                           % (path, exc))
    rows = []
    seen = set()
    problems = []
    for lineno, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except ValueError as exc:
            problems.append('line %d: not valid json (%s)' % (lineno, exc))
            continue
        problems.extend(_validate_row(row, lineno, seen))
        rows.append(row)
    if problems:
        raise RuntimeError('AUDIT_SCHEMA_ERROR: ' + '; '.join(problems[:20]))
    if not rows:
        raise RuntimeError('AUDIT_SAMPLE_EMPTY: %s has no non-blank lines'
                           % path)
    return rows, raw


def screener_scores(rows):
    """Frozen combination rule applied to the raw columns."""
    return [(r['ws4_score'] + r['ws3_prior_score']) / 2.0 for r in rows]


def mannwhitney_auc(scores, labels):
    """Tie-corrected Mann-Whitney AUC; None when single-class (degenerate)."""
    n = len(scores)
    n_pos = sum(1 for y in labels if y)
    n_neg = n - n_pos
    if n_pos == 0 or n_neg == 0:
        return None
    order = sorted(range(n), key=lambda i: scores[i])
    ranks = [0.0] * n
    i = 0
    while i < n:
        j = i
        while j + 1 < n and scores[order[j + 1]] == scores[order[i]]:
            j += 1
        mid = (i + j) / 2.0 + 1.0
        for k in range(i, j + 1):
            ranks[order[k]] = mid
        i = j + 1
    pos_rank_sum = sum(r for r, y in zip(ranks, labels) if y)
    u = pos_rank_sum - n_pos * (n_pos + 1) / 2.0
    return u / (n_pos * n_neg)


def _counts_at(scores, labels, t):
    """Predicted-pass iff score >= t. FN = predicted fail but label pass."""
    tp = sum(1 for s, y in zip(scores, labels) if s >= t and y)
    fn = sum(1 for s, y in zip(scores, labels) if s < t and y)
    tn = sum(1 for s, y in zip(scores, labels) if s < t and not y)
    fp = sum(1 for s, y in zip(scores, labels) if s >= t and not y)
    return tp, fn, tn, fp


def fnr_at(scores, labels, t):
    tp, fn, _tn, _fp = _counts_at(scores, labels, t)
    return (fn / (tp + fn)) if (tp + fn) else 0.0


def select_operating_point(scores, labels):
    """Frozen fallback rule: highest sample threshold with FNR <= floor."""
    chosen = None
    for t in sorted(set(scores)):
        if fnr_at(scores, labels, t) <= FNR_FLOOR:
            chosen = t
    if chosen is None:
        chosen = min(scores) - 1.0 if scores else -1.0
    return chosen


def roc_points(scores, labels):
    """ROC/FNR points at every distinct threshold, descending."""
    pts = []
    for t in sorted(set(scores), reverse=True):
        tp, fn, tn, fp = _counts_at(scores, labels, t)
        pts.append({
            'threshold': t,
            'tpr': (tp / (tp + fn)) if (tp + fn) else None,
            'fpr': (fp / (fp + tn)) if (fp + tn) else None,
            'fnr': (fn / (tp + fn)) if (tp + fn) else 0.0,
            'evals_skipped': fn + tn,
            'false_negatives': fn,
        })
    return pts


def run_audit(args, rows, raw):
    if len(rows) < MIN_SAMPLE_N:
        return fail(
            'AUDIT_SAMPLE_TOO_SMALL',
            '%d rows < pre-registered minimum %d (PREREG-E V-5: >= 30 '
            'sampled candidates; an underpowered audit is refused, never '
            'run with a lucky floor)' % (len(rows), MIN_SAMPLE_N))

    labels = [bool(r['battery_pass']) for r in rows]
    scores = screener_scores(rows)
    ws4_only = [r['ws4_score'] for r in rows]
    ws3_only = [r['ws3_prior_score'] for r in rows]

    if args.operating_threshold is not None:
        threshold = args.operating_threshold
        source = 'ws4_receipt'
        weak_check = False
    else:
        threshold = select_operating_point(scores, labels)
        source = 'audit_selected'
        weak_check = True

    tp, fn, tn, fp = _counts_at(scores, labels, threshold)
    fnr = (fn / (tp + fn)) if (tp + fn) else 0.0
    floor_satisfied = fnr <= FNR_FLOOR
    skipped = fn + tn

    report = {
        'schema': REPORT_SCHEMA,
        'created_utc': _now_utc(),
        'tool': 'v5_audit.py',
        'propose_only': True,
        'banner': PROPOSE_ONLY_BANNER,
        'sample': {
            'path': os.path.abspath(args.sample),
            'sha256': _sha256_bytes(raw),
            'schema': SCHEMA,
            'n': len(rows),
            'positives': sum(1 for y in labels if y),
            'negatives': sum(1 for y in labels if not y),
            'families': sorted({r['family'] for r in rows}),
            'min_n_preregistered': MIN_SAMPLE_N,
        },
        'combination_rule': COMBINATION_RULE,
        'operating_point': {
            'threshold': threshold,
            'source': source,
            'weak_check': weak_check,
            'weak_check_note': (
                'an audit that selects its own operating point cannot fail '
                'its floor except on degenerate scores; the honest audit '
                'passes --operating-threshold from the WS-4 report '
                '(source ws4_receipt)' if weak_check else None),
        },
        'roc': roc_points(scores, labels),
        'auc': {
            'screener': mannwhitney_auc(scores, labels),
            'diagnostics': {
                'ws4_only': mannwhitney_auc(ws4_only, labels),
                'ws3_prior_only': mannwhitney_auc(ws3_only, labels),
                'note': ('diagnostic marginals only - the PREREG-E floor '
                         'applies to the COMBINED screener at the operating '
                         'point'),
            },
        },
        'economics': {
            'full_battery_evals': len(rows),
            'evals_skipped_at_operating_point': skipped,
            'skip_rate': skipped / len(rows),
            'false_negatives': fn,
            'evals_skipped_per_false_negative': (
                skipped / fn if fn > 0 else None),
            'counts': {'tp': tp, 'fn': fn, 'tn': tn, 'fp': fp},
            'note': 'economics reported raw (PREREG-E); null ratio iff fn==0',
        },
        'floor': {
            'fnr': fnr,
            'limit': FNR_FLOOR,
            'satisfied': floor_satisfied,
        },
        'screener_disabled': not floor_satisfied,
        'named': None if floor_satisfied else 'SCREENER_UNCALIBRATED',
        'kill_clause': None if floor_satisfied else KILL_CLAUSE,
    }

    try:
        out_dir = os.path.dirname(os.path.abspath(args.out))
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        tmp = args.out + '.tmp'
        with open(tmp, 'w', encoding='utf-8') as fh:
            json.dump(report, fh, indent=2)
            fh.write('\n')
        os.replace(tmp, args.out)
    except OSError as exc:
        return fail('OUT_UNWRITABLE', '%s (%s)' % (args.out, exc))

    if not floor_satisfied:
        # The disablement is the verdict - named loudly, but exit 0.
        print('SCREENER_UNCALIBRATED: fnr %.4f > floor %.2f at operating '
              'point %r (source %s) - screener DISABLED (WS-4/V-5 tier '
              'only)' % (fnr, FNR_FLOOR, threshold, source), file=sys.stderr)
    print(json.dumps({
        'tool': 'v5_audit.py',
        'report': os.path.abspath(args.out),
        'n': len(rows),
        'fnr': fnr,
        'floor_satisfied': floor_satisfied,
        'screener_disabled': report['screener_disabled'],
        'named': report['named'],
        'propose_only': True,
    }, indent=2))
    return EXIT_OK


def run_dry(args, rows, raw):
    meets_floor = len(rows) >= MIN_SAMPLE_N
    if args.operating_threshold is not None:
        op = {'source': 'ws4_receipt', 'threshold': args.operating_threshold,
              'weak_check': False}
    else:
        op = {'source': 'audit_selected',
              'rule': 'highest sample threshold with sample FNR <= %.2f'
                      % FNR_FLOOR,
              'weak_check': True}
    plan = {
        'mode': 'dry-run',
        'tool': 'v5_audit.py',
        'schema': SCHEMA,
        'sample': {'path': os.path.abspath(args.sample),
                   'sha256': _sha256_bytes(raw),
                   'rows': len(rows),
                   'positives': sum(1 for r in rows if r['battery_pass']),
                   'families': len({r['family'] for r in rows})},
        'floor': {'min_n': MIN_SAMPLE_N, 'fnr_limit': FNR_FLOOR,
                  'sample_meets_min_n': meets_floor,
                  'note': ('dry-run REPORTS the floor; a real audit with '
                           'n < %d refuses AUDIT_SAMPLE_TOO_SMALL'
                           % MIN_SAMPLE_N)},
        'combination_rule': COMBINATION_RULE,
        'operating_point': op,
        'outputs': {'report_keys': ['roc', 'auc', 'operating_point',
                                    'economics', 'floor',
                                    'screener_disabled', 'named'],
                    'named_on_floor_miss': 'SCREENER_UNCALIBRATED',
                    'kill_clause': KILL_CLAUSE},
        'out': os.path.abspath(args.out),
        'propose_only': True,
        'banner': PROPOSE_ONLY_BANNER,
        'note': 'plan only; nothing written; stdlib only (no venv, no model)',
    }
    print(json.dumps(plan, indent=2))
    return EXIT_OK


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--sample', required=True,
                    help='audit sample jsonl (schema %s)' % SCHEMA)
    ap.add_argument('--out', required=True, help='audit report JSON path')
    ap.add_argument('--operating-threshold', type=float, default=None,
                    help='operating point from the WS-4 report (the true '
                         'pre-registered audit); omit only for the weak '
                         'audit-selected check')
    ap.add_argument('--dry-run', action='store_true',
                    help='validate + print the plan; write nothing')
    args = ap.parse_args(argv)

    if args.operating_threshold is not None \
            and not math.isfinite(args.operating_threshold):
        return fail('OPERATING_THRESHOLD_INVALID',
                    '%r is not a finite float' % args.operating_threshold)

    try:
        rows, raw = read_sample(args.sample)
        if args.dry_run:
            return run_dry(args, rows, raw)
        return run_audit(args, rows, raw)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return EXIT_INPUT
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001 - named, never silent
        return fail('INTERNAL_ERROR', '%s: %s' % (type(exc).__name__, exc))


if __name__ == '__main__':
    sys.exit(main())
