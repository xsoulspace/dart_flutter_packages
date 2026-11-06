#!/usr/bin/env python3
"""ws4_denominator.py - WS-4 denominator assembler (PREREG-E; builder owned here).

Assembles the ws4-denominator/v1 file (schema FROZEN in ws4_train.py; this
builder never edits that schema) from the receipts that exist NOW:

  A3   receipts/A3-run.jsonl + receipts/A3/ (16 arms: 8 plants + 8 nulls;
       label = certification verdict from receipts/A3/join-table.json,
       cross-checked against receipts/A3/blind-scored.json; features from
       receipts/A3/truth/specs/*/spec_L*.json, digest-verified against
       receipts/A3/truth/arms.json; baseline_loop_rate = the archived BASE
       (unedited-mirror) battery G2 loop rate 5/12 from the a3-base row)
  V-1  receipts/V1-nulls.jsonl (4 matched nulls on plant-1; label =
       certified flag; v1-null-3 CERTIFIED -> battery_pass=true with
       provenance note confounded-positive-control; features from
       receipts/V12/null*_spec.json, digest-verified against spec_sha256)
  WS-3 receipts/WS3-live.jsonl per-layer prior scores are NOT edit attempts
       -> exclusion rows, reason NOT_AN_EDIT_ATTEMPT
  V-3  (PREREG-E denominator component) never ran: the V-1 NULL_LEAK halt
       stopped the ladder before V-3 -> NAMED absence ledger entry
       V3_NOT_RUN, 0 rows

FEATURE HONESTY (capture_eigen_gap): PREREG-E WS-4 v1 required the capture
eigen-gap at the planted rank. The frozen capture instrument
(tool/eval/capture_activations.py, A4-frozen) records per-layer MEAN
activations only - no covariance, no spectrum - and no receipt in
receipts/A3, receipts/V1-nulls.jsonl or receipts/V12 records an eigen-gap
(this builder re-verifies that absence with a mechanical key sweep at run
time). The v1 run (2026-11-06, VERDICTS WS-4 train row) therefore excluded
all 20 edit-attempt candidates NAMED FEATURE_MISSING and the frozen trainer
refused DENOMINATOR_EMPTY. The PREREG-E Addendum 2026-11-06 (ledgered:
VERDICTS WS-4 feature-v2 row) DROPPED capture_eigen_gap from the trainable
feature set (feature-set v2 = {delta_norm, column_count, layer_ids,
baseline_loop_rate, layer_column_bands}; absent, never imputed; a FUTURE
candidate behind an instrument-change row) and authorized the ws4_train.py
schema edit making the field optional-absent. Under v2 the 20 candidates are
PROMOTED to trainable strict rows; the promotion is recorded as a ledger
entry in the exclusions sidecar (promoted count recomputed every run).

OUTPUTS (both under --out-dir, default receipts/):
  WS4-denominator.jsonl             strict ws4-denominator/v1 rows ONLY
                                    (the file ws4_train.py consumes; empty
                                    when every candidate is excluded)
  WS4-denominator-exclusions.jsonl  exclusion ledger rows
                                    (schema ws4-denominator-exclusions/v1,
                                    defined here: candidate rows with every
                                    computable feature + label + NAMED
                                    exclusion reason, plus source-level
                                    absence entries)
stdout: one assembly-report JSON (counts by source, exclusions by reason,
family set, the PROSPECTIVE frozen-rule split over the assembled family set
(labeled - the frozen tool executes the real split only on a non-empty
denominator), integrity-check results, eigen-gap sweep evidence, output
digests, propose-only banner).

PROPOSE-ONLY LAW (PROGRAM.md section 0 / PREREG-E): WS-4 is an ADVISORY
predictor; nothing assembled or trained here ever certifies an edit.

Usage:
  python3 -I tool/runs/ws4_denominator.py [--pkg-root DIR] [--out-dir DIR]

Exit codes (errors NAMED on stderr as 'CODE: detail', never silent):
  0  ok (outputs written; assembly report on stdout)
  1  named input error:
       RECEIPT_MISSING            a required receipt file is absent
       SPEC_DIGEST_MISMATCH       a spec file digest != its recorded digest
       LABEL_SOURCE_MISMATCH      join-table certified != blind-scored
       COLUMNS_MISMATCH           matched-control columns disagree
       DIRECTION_NOT_UNIT         a spec direction is not unit-norm (1e-6)
       BASELINE_MISSING           base G2 loop rate not recorded/parseable
       INTERNAL_ERROR             unexpected exception (class + message)
"""

import argparse
import hashlib
import json
import math
import os
import random
import re
import sys
from datetime import datetime, timezone

EXIT_OK = 0
EXIT_INPUT = 1

SEED = 20261105                 # FROZEN (PREREG-A blinding seed / ws4_train)
HOLDOUT_FAMILY_FRACTION = 1.0 / 3.0
BAND_WIDTH = 256                # FROZEN (ws4_train.py)
FAMILIES_REQUIRED_MIN = 2

EXCL_SCHEMA = 'ws4-denominator-exclusions/v1'

PROPOSE_ONLY_BANNER = (
    'PROPOSE_ONLY: WS-4 is an ADVISORY predictor - it NEVER certifies an '
    'edit (PROGRAM.md propose-only law / PREREG-E). This assembler only '
    'builds the denominator; labels come from the frozen certification '
    'oracle receipts, never from a screener.'
)

A3_NULL_FAMILY = 'null-gaussian'   # A3 null construction = unit-norm
                                   # Gaussians per layer (plant_design.
                                   # null_directions); V-1 null1_gaussian
                                   # is the same construction type ->
                                   # families group BY CONSTRUCTION TYPE
V1_FAMILY_BY_KIND = {
    'null1_gaussian': 'null-gaussian',
    'null2_shuffle': 'null-shuffle',
    'null3_unrelated': 'null-unrelated',
    'null4_quantnoise': 'null-quantnoise',
}
V1_SPEC_BY_ID = {
    'v1-null-1': 'null1_gaussian_spec.json',
    'v1-null-2': 'null2_shuffle_spec.json',
    'v1-null-3': 'null3_unrelated_spec.json',
    'v1-null-4': 'null4_quantnoise_spec.json',
}


def fail(code, detail):
    print('%s: %s' % (code, detail), file=sys.stderr)
    return EXIT_INPUT


def _now_utc():
    return datetime.now(timezone.utc).isoformat(timespec='seconds')


def _sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(65536), b''):
            h.update(chunk)
    return h.hexdigest()


def _sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def _canonical_json(obj):
    return json.dumps(obj, sort_keys=True, separators=(',', ':'))


def _load_json(path, code='RECEIPT_MISSING'):
    try:
        with open(path, 'r', encoding='utf-8') as fh:
            return json.load(fh)
    except (OSError, ValueError) as exc:
        raise RuntimeError('%s: %s (%s)' % (code, path, exc))


def _load_jsonl(path):
    try:
        with open(path, 'r', encoding='utf-8') as fh:
            return [json.loads(line) for line in fh if line.strip()]
    except (OSError, ValueError) as exc:
        raise RuntimeError('RECEIPT_MISSING: %s (%s)' % (path, exc))


def _layer_of_tensor(name):
    m = re.match(r'^model\.layers\.(\d+)\.', name)
    if not m:
        raise RuntimeError('INTERNAL_ERROR: unparsable tensor name %r' % name)
    return int(m.group(1))


def _features_from_spec_tensors(tensors):
    """Frozen-feature extraction from spec tensors (columns/direction/scale).

    tensors: list of dicts with name, columns, direction, scale (V12 shape)
             or per-layer spec dicts {tensor, columns, direction, scale}
             (A3 shape, one file per layer; caller passes layer explicitly).
    Returns (features_present, checks) where features_present holds every
    ws4-denominator/v1 feature computable from the archived receipts.
    delta_norm is the Frobenius norm of the fp32 merged delta per the frozen
    merge law W[:,cols] += scale*direction (pre-bf16-cast; the bf16 rounding
    residual is not reconstructible - mirrors deleted per scratch law - and
    the spec value is the recorded, reproducible quantity).
    """
    sq = 0.0
    cols_union = set()
    layer_ids = set()
    bands = set()
    for t in tensors:
        direction = t['direction']
        norm = math.sqrt(sum(x * x for x in direction))
        if abs(norm - 1.0) > 1e-6:
            raise RuntimeError(
                'DIRECTION_NOT_UNIT: %s layer %s dir norm %.12f'
                % (t.get('name', t.get('tensor', '?')), t.get('layer', '?'),
                   norm))
        cols = t['columns']
        layer = t['layer']
        scale = t['scale']
        sq += (abs(scale) * norm) ** 2 * len(cols)
        cols_union.update(cols)
        layer_ids.add(layer)
        for c in cols:
            bands.add((layer, c // BAND_WIDTH))
    return {
        'delta_norm': math.sqrt(sq),
        'column_count': len(cols_union),
        'layer_ids': sorted(layer_ids),
        'layer_column_bands': sorted([list(p) for p in bands]),
    }


def _eigen_gap_sweep(receipt_paths):
    """Mechanical evidence for FEATURE_MISSING: sweep receipts for any
    eigen/gap/spectrum/singular key or token. Returns the sweep record."""
    hits = []
    files_swept = 0
    pat = re.compile(r'eigen|spectrum|singular', re.IGNORECASE)
    for path in receipt_paths:
        if os.path.isdir(path):
            for root, _dirs, files in os.walk(path):
                for name in sorted(files):
                    if not name.endswith(('.json', '.jsonl')):
                        continue
                    files_swept += 1
                    try:
                        text = open(os.path.join(root, name),
                                    encoding='utf-8', errors='replace').read()
                    except OSError:
                        continue
                    for m in pat.finditer(text):
                        lo = max(0, m.start() - 60)
                        hits.append({'file': os.path.join(root, name),
                                     'context': text[lo:m.end() + 60]})
        elif os.path.isfile(path):
            files_swept += 1
            text = open(path, encoding='utf-8', errors='replace').read()
            for m in pat.finditer(text):
                lo = max(0, m.start() - 60)
                hits.append({'file': path, 'context': text[lo:m.end() + 60]})
    return {'files_swept': files_swept, 'pattern': 'eigen|spectrum|singular',
            'hits': hits}


def prospective_split(families):
    """The frozen ws4_train.py family-split rule applied to a FAMILY SET.

    Clearly labeled PROSPECTIVE by the caller: the frozen tool executes the
    authoritative split only on a non-empty denominator file; this records
    what the frozen rule assigns to the assembled family set (the split is a
    function of the family set only, per ws4_train.py).
    """
    order = sorted(families)
    random.Random(SEED).shuffle(order)
    n_holdout = max(1, math.ceil(len(order) * HOLDOUT_FAMILY_FRACTION))
    n_holdout = min(n_holdout, len(order) - 1)
    holdout = sorted(order[:n_holdout])
    train = sorted(f for f in order if f not in set(holdout))
    digest = _sha256_bytes(_canonical_json({
        'seed': SEED, 'train_families': train,
        'holdout_families': holdout}).encode('utf-8'))
    return {'seed': SEED, 'train_families': train,
            'holdout_families': holdout, 'split_digest': digest,
            'status': ('PROSPECTIVE_NOT_EXECUTED (frozen tool split runs '
                       'only on a non-empty denominator; computed here '
                       'from the assembled family set under the identical '
                       'frozen rule)')}


def assemble(pkg_root, out_dir):
    receipts = os.path.join(pkg_root, 'receipts')

    def rp(*parts):
        return os.path.join(receipts, *parts)

    # --- load receipts ----------------------------------------------------
    a3_rows = _load_jsonl(rp('A3-run.jsonl'))
    a3_base = next((r['payload'] for r in a3_rows
                    if r.get('kind') == 'a3-base'), None)
    if a3_base is None:
        raise RuntimeError('RECEIPT_MISSING: a3-base row in A3-run.jsonl')
    join = _load_json(rp('A3', 'join-table.json'))
    blind = _load_json(rp('A3', 'blind-scored.json'))
    arms_truth = _load_json(rp('A3', 'truth', 'arms.json'))['arms']
    v1_rows = _load_jsonl(rp('V1-nulls.jsonl'))
    ws3_rows = _load_jsonl(rp('WS3-live.jsonl'))

    # --- baseline_loop_rate: archived BASE (unedited-mirror) battery -------
    g2_raw = a3_base.get('battery_base', {}).get('g2_loop_rate')
    m = re.match(r'^(\d+)/(\d+)$', str(g2_raw)) if g2_raw else None
    if not m:
        raise RuntimeError('BASELINE_MISSING: battery_base.g2_loop_rate=%r'
                           % g2_raw)
    baseline_loop_rate = int(m.group(1)) / int(m.group(2))
    blind_g2 = blind.get('base', {}).get('loop_rate_G2')
    if blind_g2 is None or abs(blind_g2 - baseline_loop_rate) > 1e-12:
        raise RuntimeError(
            'BASELINE_MISSING: blind-scored base loop_rate_G2=%r disagrees '
            'with battery_base g2_loop_rate=%r' % (blind_g2, g2_raw))
    baseline_source = {
        'value': baseline_loop_rate,
        'raw': g2_raw,
        'source': ('A3 archived BASE (unedited-mirror) battery, '
                   'battery_base.g2_loop_rate on the G2-shaped cells '
                   '(PREREG-A A3); battery sha256 %s; cross-checked equal '
                   'to blind-scored base.loop_rate_G2'
                   % a3_base['battery_base'].get('sha256')),
    }

    # --- eigen-gap absence sweep (mechanical FEATURE_MISSING evidence) ----
    sweep = _eigen_gap_sweep([rp('A3'), rp('A3-run.jsonl'),
                              rp('V1-nulls.jsonl'), rp('V12'),
                              rp('WS3-live.jsonl')])
    sweep_hits_feature = [h for h in sweep['hits']
                          if 'eigen' in h['context'].lower()]
    eigen_gap_absent = not sweep_hits_feature

    candidates = []   # (row_dict, computable_features, provenance)
    integrity = []

    # --- A3: 16 arms ------------------------------------------------------
    join_by_real = {r['real_id']: r for r in join['rows']}
    blind_arms = blind['arms']
    for real_id in sorted(arms_truth):
        truth = arms_truth[real_id]
        jrow = join_by_real.get(real_id)
        if jrow is None:
            raise RuntimeError('RECEIPT_MISSING: join-table row for %s'
                               % real_id)
        brow = blind_arms.get(jrow['label'])
        if brow is None:
            raise RuntimeError('RECEIPT_MISSING: blind-scored arm %s'
                               % jrow['label'])
        if bool(brow['certified']) != bool(jrow['certified']):
            raise RuntimeError(
                'LABEL_SOURCE_MISMATCH: %s join-table certified=%r vs '
                'blind-scored certified=%r'
                % (real_id, jrow['certified'], brow['certified']))
        integrity.append({'check': 'certified_agreement', 'id': real_id,
                          'blind_label': jrow['label'], 'ok': True})
        tensors = []
        for layer_str, info in sorted(truth['layers'].items(),
                                      key=lambda kv: int(kv[0])):
            spec_rel = os.path.join('receipts', 'A3', 'truth', 'specs',
                                    real_id,
                                    'spec_L%s.json' % layer_str)
            spec_path = os.path.join(pkg_root, spec_rel)
            digest = _sha256_file(spec_path)
            if digest != info['truth_spec_sha256']:
                raise RuntimeError(
                    'SPEC_DIGEST_MISMATCH: %s %s != recorded %s'
                    % (spec_rel, digest, info['truth_spec_sha256']))
            spec = _load_json(spec_path)
            tensors.append({'name': spec['tensor'],
                            'layer': int(layer_str),
                            'columns': spec['columns'],
                            'direction': spec['direction'],
                            'scale': spec['scale']})
        integrity.append({'check': 'spec_digest', 'id': real_id, 'ok': True,
                          'files': len(truth['layers'])})
        kind = truth['kind']
        if kind == 'plant':
            family = 'plant-%d' % truth['pair']
        elif kind == 'null':
            family = A3_NULL_FAMILY
        else:
            raise RuntimeError('INTERNAL_ERROR: unknown A3 kind %r' % kind)
        # matched-control check: A3 null k shares columns with plant k
        feats = _features_from_spec_tensors(tensors)
        candidates.append({
            'attempt_id': real_id,
            'arm': 'A3',
            'family': family,
            'kind': kind,
            'label': {'battery_pass': bool(jrow['certified'])},
            'features_present': feats,
            'provenance': {
                'blind_label': jrow['label'],
                'cast': 'qwen3-0.6b-bf16 (mlx-community snapshot 42096995)',
                'proposer': ('a3_diff_of_means(loop,neutral) per layer, '
                             'L2-normalized, scale 4.8, rank 1'
                             if kind == 'plant' else
                             'a3_design.null_direction: two independent '
                             'unit-norm Gaussians per layer (norm-matched)'),
                'receipt_digest': jrow['digests']['arm_receipt'],
                'join_table_sha256': _sha256_file(rp('A3',
                                                     'join-table.json')),
                'loop_rate_M': jrow['loop_rate_M'],
                'loop_rate_R': jrow['loop_rate_R'],
            },
            'columns_by_layer': {str(t['layer']): t['columns']
                                 for t in tensors},
        })

    # matched-control column equality: A3 null-k columns == plant-k columns
    by_id = {c['attempt_id']: c for c in candidates}
    for k in range(1, 9):
        p = by_id.get('a3-plant-%d' % k)
        n = by_id.get('a3-null-%d' % k)
        if p and n and p['columns_by_layer'] != n['columns_by_layer']:
            raise RuntimeError(
                'COLUMNS_MISMATCH: a3-null-%d columns != a3-plant-%d '
                '(matched-control law)' % (k, k))
    integrity.append({'check': 'a3_matched_control_columns', 'pairs': 8,
                      'ok': True})

    # --- V-1: 4 matched nulls on plant-1 ----------------------------------
    v1_nulls = [r['payload'] for r in v1_rows if r.get('kind') == 'v1-null']
    if len(v1_nulls) != 4:
        raise RuntimeError('RECEIPT_MISSING: expected 4 v1-null rows, got %d'
                           % len(v1_nulls))
    plant1_cols = by_id['a3-plant-1']['columns_by_layer']
    for p in sorted(v1_nulls, key=lambda x: x['null_id']):
        nid = p['null_id']
        spec_rel = os.path.join('receipts', 'V12', V1_SPEC_BY_ID[nid])
        spec_path = os.path.join(pkg_root, spec_rel)
        digest = _sha256_file(spec_path)
        if digest != p['spec_sha256']:
            raise RuntimeError('SPEC_DIGEST_MISMATCH: %s %s != recorded %s'
                               % (spec_rel, digest, p['spec_sha256']))
        spec = _load_json(spec_path)
        tensors = []
        for t in spec['tensors']:
            tensors.append({'name': t['name'],
                            'layer': _layer_of_tensor(t['name']),
                            'columns': t['columns'],
                            'direction': t['direction'],
                            'scale': t['scale']})
        cols_by_layer = {str(t['layer']): t['columns'] for t in tensors}
        if cols_by_layer != plant1_cols:
            raise RuntimeError(
                'COLUMNS_MISMATCH: %s columns != A3 plant-1 (target edit; '
                'repair_plumbing_verification claims columns_equal_arm002)'
                % nid)
        feats = _features_from_spec_tensors(tensors)
        certified = bool(p['certified'])
        prov = {
            'cast': 'qwen3-0.6b-bf16 plant-1 mirror (arm-002 replay, shard '
                    '22e52d07 reproduced)',
            'proposer': 'V-1 matched null construction: %s (%s)'
                        % (p['null_kind'], p['construction']),
            'receipt_digest': p['spec_sha256'],
            'target_edit': p.get('target_edit'),
            'loop_rate_M': p['loop_rate_M'],
            'loop_rate_R': p['loop_rate_R'],
            'scale': p['scale'],
        }
        note = None
        if certified:
            note = ('confounded-positive-control: v1-null-3 CERTIFIED '
                    '(NULL_LEAK -> HALT, PREREG-C kill clause); '
                    'cos(null3,d_hat)=0.68/0.72 - a task-vs-neutral contrast '
                    'direction, not a true unrelated null; label recorded as '
                    'the frozen oracle verdict, provenance recorded here')
        candidates.append({
            'attempt_id': nid,
            'arm': 'V-1',
            'family': V1_FAMILY_BY_KIND[p['null_kind']],
            'kind': 'null',
            'label': {'battery_pass': certified},
            'features_present': feats,
            'provenance': prov,
            'provenance_note': note,
        })
    integrity.append({'check': 'v1_spec_digests_and_columns', 'rows': 4,
                      'ok': True})

    # --- exclusion decisions (feature-set v2, PREREG-E Addendum 2026-11-06)
    required_features = ('delta_norm', 'column_count', 'layer_ids',
                         'baseline_loop_rate', 'layer_column_bands')
    eigen_gap_present_anywhere = any(
        'capture_eigen_gap' in c['features_present'] for c in candidates)
    strict_rows = []
    exclusion_rows = []
    promoted_from_feature_missing_v1 = 0
    for c in candidates:
        feats = dict(c['features_present'])
        feats['baseline_loop_rate'] = baseline_loop_rate
        missing = [k for k in required_features if k not in feats]
        # v1 history: capture_eigen_gap was required and unrecordable; the
        # Addendum dropped it (absent, never imputed). A row that would have
        # been FEATURE_MISSING under v1 and is strict under v2 is PROMOTED.
        v1_would_miss = bool(missing) or not eigen_gap_present_anywhere
        row = {
            'schema': EXCL_SCHEMA,
            'attempt_id': c['attempt_id'],
            'arm': c['arm'],
            'family': c['family'],
            'cast_kind': c['kind'],
            'label': c['label'],
            'features_present': feats,
            'missing_features': missing,
            'provenance': c['provenance'],
        }
        if c.get('provenance_note'):
            row['provenance_note'] = c['provenance_note']
        if missing:
            row['exclusion_reason'] = 'FEATURE_MISSING'
            row['exclusion_detail'] = (
                'FEATURE_MISSING=%s: frozen-schema-required feature absent '
                'from every archived receipt and NOT COMPUTABLE offline '
                '(mechanical sweep: %d files, %d eigen hits); row excluded '
                'from training per the WS-4 denominator-honesty law '
                '(exclusions are rows too)'
                % (','.join(missing), sweep['files_swept'],
                   len(sweep_hits_feature)))
            exclusion_rows.append(row)
        else:
            if v1_would_miss:
                promoted_from_feature_missing_v1 += 1
            strict = {
                'attempt_id': c['attempt_id'],
                'arm': c['arm'],
                'family': c['family'],
                'features': feats,
                'label': c['label'],
            }
            for opt in ('cast', 'proposer', 'receipt_digest'):
                if opt in c['provenance']:
                    strict[opt] = c['provenance'][opt]
            strict_rows.append(strict)
    if promoted_from_feature_missing_v1:
        exclusion_rows.append({
            'schema': EXCL_SCHEMA,
            'attempt_id': 'promotion-feature-v2-2026-11-06',
            'arm': 'A3+V-1',
            'family': None,
            'cast_kind': 'promotion_ledger',
            'label': None,
            'features_present': {},
            'missing_features': [],
            'exclusion_reason': 'PROMOTED',
            'promoted_count': promoted_from_feature_missing_v1,
            'exclusion_detail': (
                '%d rows excluded FEATURE_MISSING=capture_eigen_gap in the '
                'v1 assembly (receipts history: WS4-denominator-exclusions '
                'v1, 20 such rows) are PROMOTED to trainable strict rows '
                'under feature-set v2 - PREREG-E Addendum 2026-11-06 '
                '(ledgered WS-4 feature-v2 row) dropped capture_eigen_gap '
                '(absent, never imputed; FUTURE candidate behind an '
                'instrument-change row) and authorized the ws4_train.py '
                'optional-absent schema edit; PASS bar UNCHANGED'
                % promoted_from_feature_missing_v1),
            'provenance': {'addendum': 'PREREG-E.md Addendum 2026-11-06'},
        })

    # --- WS-3: per-layer priors, NOT edit attempts -------------------------
    ws3_per_layer = [r for r in ws3_rows if r.get('kind') == 'ws3-per-layer']
    for r in sorted(ws3_per_layer, key=lambda x: (x.get('mirror', ''),
                                                  x.get('layer', -1),
                                                  x.get('seq', 0))):
        exclusion_rows.append({
            'schema': EXCL_SCHEMA,
            'attempt_id': 'ws3-%s-L%s' % (r.get('mirror'), r.get('layer')),
            'arm': 'WS-3',
            'family': None,
            'cast_kind': 'per_layer_prior_score',
            'label': None,
            'features_present': {'layer': r.get('layer'),
                                 'score': r.get('score'),
                                 'rank': r.get('rank'),
                                 'mirror': r.get('mirror'),
                                 'scored_mirror': r.get('scored_mirror')},
            'missing_features': [],
            'exclusion_reason': 'NOT_AN_EDIT_ATTEMPT',
            'exclusion_detail': (
                'WS-3 masked-attribution per-layer prior score (PREREG-D '
                'WS-3; RETIRED as index backbone per VERDICTS 2026-11-06) - '
                'a layer prior over one scored mirror, not a candidate edit '
                'attempt; not a ws4-denominator/v1 row'),
            'provenance': {'receipt_digest':
                           _sha256_file(rp('WS3-live.jsonl'))},
        })

    # --- V-3: named absence -------------------------------------------------
    exclusion_rows.append({
        'schema': EXCL_SCHEMA,
        'attempt_id': 'v3-absence',
        'arm': 'V-3',
        'family': None,
        'cast_kind': 'source_absence',
        'label': None,
        'features_present': {},
        'missing_features': [],
        'exclusion_reason': 'V3_NOT_RUN',
        'exclusion_detail': (
            'PREREG-E names the WS-4 denominator A3+V-1+V-3; V-3 '
            '(cross-cast x cross-proposer replication, PREREG-D) never ran - '
            'the V-1 NULL_LEAK halt (VERDICTS 2026-11-06) stopped the '
            'ladder before V-3 and no V-3 receipt exists; NAMED absence, 0 '
            'rows (an absence, not a zero)'),
        'provenance': {},
    })

    # --- outputs ------------------------------------------------------------
    os.makedirs(out_dir, exist_ok=True)
    strict_path = os.path.join(out_dir, 'WS4-denominator.jsonl')
    excl_path = os.path.join(out_dir, 'WS4-denominator-exclusions.jsonl')
    strict_bytes = (''.join(_canonical_json(r) + '\n'
                           for r in strict_rows)).encode('utf-8')
    excl_bytes = (''.join(json.dumps(r, sort_keys=True) + '\n'
                          for r in exclusion_rows)).encode('utf-8')
    with open(strict_path, 'wb') as fh:
        fh.write(strict_bytes)
    with open(excl_path, 'wb') as fh:
        fh.write(excl_bytes)

    families = sorted({c['family'] for c in candidates})
    by_reason = {}
    for r in exclusion_rows:
        by_reason[r['exclusion_reason']] = \
            by_reason.get(r['exclusion_reason'], 0) + 1
    report = {
        'tool': 'ws4_denominator.py',
        'schema_target': ('ws4-denominator/v1 as amended by the PREREG-E '
                          'Addendum 2026-11-06 (feature-set v2: '
                          'capture_eigen_gap optional-absent)'),
        'feature_set': ('v2 = {delta_norm, column_count, layer_ids, '
                        'baseline_loop_rate, layer_column_bands} (PREREG-E '
                        'Addendum 2026-11-06; PASS bar UNCHANGED)'),
        'exclusion_schema': EXCL_SCHEMA,
        'created_utc': _now_utc(),
        'banner': PROPOSE_ONLY_BANNER,
        'propose_only': True,
        'denominator_counts': {
            'by_source_candidates': {
                'A3': sum(1 for c in candidates if c['arm'] == 'A3'),
                'V-1': sum(1 for c in candidates if c['arm'] == 'V-1'),
                'V-3': 0,
                'WS-3': len(ws3_per_layer),
            },
            'edit_attempt_candidates': len(candidates),
            'strict_rows_written': len(strict_rows),
            'exclusion_rows_written': len(exclusion_rows),
            'exclusions_by_reason': by_reason,
            'promoted_from_feature_missing_v1':
                promoted_from_feature_missing_v1,
        },
        'labels': {
            'battery_pass_true': sorted(
                c['attempt_id'] for c in candidates
                if c['label']['battery_pass']),
            'battery_pass_false': sorted(
                c['attempt_id'] for c in candidates
                if not c['label']['battery_pass']),
            'label_rule': ('A3: certification verdict from '
                           'receipts/A3/join-table.json (frozen oracle, '
                           'verdict_frozen-before-unblind), cross-checked '
                           'against blind-scored.json; V-1: certified flag '
                           'per null (v1-null-3 certified -> true, '
                           'confounded-positive-control provenance note)'),
        },
        'baseline_loop_rate': baseline_source,
        'capture_eigen_gap': {
            'status': ('DROPPED_PER_ADDENDUM' if eigen_gap_absent
                       else 'PRESENT_UNEXPECTED_REVIEW'),
            'feature_set_v2': ('dropped from the trainable set by the '
                               'PREREG-E Addendum 2026-11-06 (absent, never '
                               'imputed); remains a FUTURE candidate behind '
                               'an instrument-change row '
                               '(capture_activations.py spectra + re-capture '
                               'on rebuilt mirrors)'),
            'absent_from_all_receipts': eigen_gap_absent,
            'sweep': {'files_swept': sweep['files_swept'],
                      'pattern': sweep['pattern'],
                      'eigen_hits': len(sweep_hits_feature),
                      'non_eigen_hits_contexts': [
                          h['context'][:100] for h in sweep['hits']
                          if 'eigen' not in h['context'].lower()][:5]},
            'instrument_note': (
                'tool/eval/capture_activations.py (A4-frozen, sha '
                '6327e048e6d884e1489d6feae6dca998ed0f11089894532334e344ddae'
                '78b22e per VERDICTS A4 freeze row) records per-layer '
                'mean_activation only (shape + tokens_averaged) - no '
                'covariance, no spectrum; directions_base.json records '
                'diff-of-means direction + diff_l2_norm only; the eigen-gap '
                'at the planted rank is NOT COMPUTABLE offline from any '
                'archived artifact'),
            'remedy_route': (
                'a capture-instrument change (record activation spectra) '
                'plus a new prereg row - owner decision, not runner decision'),
        },
        'families': families,
        'family_rule': ('plants: plant-1..plant-8 (one family per plant); '
                        'nulls: grouped BY CONSTRUCTION TYPE - A3 gaussian '
                        'nulls and V-1 null1_gaussian share null-gaussian; '
                        'null-shuffle / null-unrelated / null-quantnoise '
                        'from V-1'),
        'prospective_split': (prospective_split(families)
                              if len(families) >= FAMILIES_REQUIRED_MIN
                              else {'status': 'SPLIT_DEGENERATE_TOO_FEW_'
                                               'FAMILIES'}),
        'integrity_checks': integrity,
        'outputs': {
            'strict': {'path': os.path.abspath(strict_path),
                       'rows': len(strict_rows),
                       'sha256': _sha256_bytes(strict_bytes),
                       'note': ('strict ws4-denominator/v1 rows only - the '
                                'file ws4_train.py consumes; EMPTY: every '
                                'edit-attempt candidate lacks the frozen-'
                                'schema-required capture_eigen_gap'
                                if not strict_rows else '')},
            'exclusions': {'path': os.path.abspath(excl_path),
                           'rows': len(exclusion_rows),
                           'sha256': _sha256_bytes(excl_bytes)},
        },
        'small_n_note': (
            'the recorded denominator is 20 edit attempts over 12 families '
            '- per the PREREG-E Addendum 2026-11-06 this caps ANY outcome at '
            'MEASURED_SMALL_N (no generalization claim); economics numbers '
            'are reported raw'),
    }
    return report


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--pkg-root', default=None,
                    help='package root (default: the directory containing '
                         'tool/ above this script)')
    ap.add_argument('--out-dir', default=None,
                    help='output dir (default: <pkg-root>/receipts)')
    args = ap.parse_args(argv)

    pkg_root = args.pkg_root or os.path.dirname(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    out_dir = args.out_dir or os.path.join(pkg_root, 'receipts')
    try:
        report = assemble(pkg_root, out_dir)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return EXIT_INPUT
    except Exception as exc:  # noqa: BLE001 - named, never silent
        print('INTERNAL_ERROR: %s: %s' % (type(exc).__name__, exc),
              file=sys.stderr)
        return EXIT_INPUT
    print(json.dumps(report, indent=2))
    return EXIT_OK


if __name__ == '__main__':
    sys.exit(main())
