#!/usr/bin/env python3
"""screen_certify.py - L3 screen→certify orchestrator CORE (PREREG-SPEED.md,
FROZEN 2026-11-10). Pure functions only — no device, no model loading, no
downloads. The 4-bit checkpoint resolves at run time; a missing store is the
named refusal SCREEN_MODEL_MISSING (the CLI plan-mode prints the resolution
plan and exits without touching anything).

FROZEN SEMANTICS (propose-only law): screen verdicts NEVER certify. The
winner set = ALL arms passing the pre-registered screen floor (never top-k,
never select-best). Every winner is re-run + certified on bf16 under the
bf16 certification key. The screen's ROC is measured and receipted (V-5
audit shape), including evals_skipped_per_false_negative.
"""

SCREEN_QUANT = '4bit'
CERT_QUANT = 'bf16'


def resolve_model(candidates):
    """First EXISTING path among candidates; None if none exist (the CLI
    turns None into named SCREEN_MODEL_MISSING — never an auto-download)."""
    import os
    for c in candidates:
        if c and os.path.isdir(c):
            return c
    return None


def screen_pass(fitness, floor):
    """Screen floor (frozen per arm's prereg BEFORE the screen runs)."""
    return fitness >= floor


def winners(screen_rows, floor):
    """ALL passing arm ids in frozen input order — the never-select-best
    rule. screen_rows: [(arm_id, fitness), ...]."""
    return [arm_id for arm_id, fit in screen_rows if screen_pass(fit,
                                                                 floor)]


def confusion(screen_flags, truth_flags):
    """screen_flags/truth_flags aligned booleans: (tp, fp, tn, fn)."""
    if len(screen_flags) != len(truth_flags):
        raise ValueError('ALIGNMENT_MISMATCH: %d vs %d'
                         % (len(screen_flags), len(truth_flags)))
    tp = fp = tn = fn = 0
    for s, t in zip(screen_flags, truth_flags):
        if s and t:
            tp += 1
        elif s and not t:
            fp += 1
        elif not s and not t:
            tn += 1
        else:
            fn += 1
    return {'tp': tp, 'fp': fp, 'tn': tn, 'fn': fn}


def screen_roc(conf, certified_run_n):
    """V-5-shaped economics: measured ROC + evals skipped per false
    negative (the number that justifies the cheap tier, or kills it)."""
    total = conf['tp'] + conf['fp'] + conf['tn'] + conf['fn']
    screened_n = total
    truth_pos = conf['tp'] + conf['fn']
    truth_neg = conf['tn'] + conf['fp']
    if truth_pos and truth_neg:
        tpr = conf['tp'] / truth_pos
        fpr = conf['fp'] / truth_neg
    else:
        tpr = fpr = None    # degenerate truth set: named, not invented
    skipped = screened_n - certified_run_n
    return {'screened_n': screened_n,
            'certified_run_n': certified_run_n,
            'evals_skipped': skipped,
            'evals_skipped_per_fn': (skipped / conf['fn']) if conf['fn']
            else None,
            'tpr': tpr, 'fpr': fpr,
            'degenerate_truth': not (truth_pos and truth_neg)}


def certify_queue(winner_ids, frozen_cell_order):
    """Winners in FROZEN cell order (deterministic; never fitness-sorted)."""
    order = {cid: i for i, cid in enumerate(frozen_cell_order)}
    return sorted(winner_ids, key=lambda w: (order.get(w, len(order)), w))


def accounting(screen_rows, floor, certified_run_n, truth_flags):
    """One call for the receipt: winners, queue, ROC, denominators."""
    w = winners(screen_rows, floor)
    flags = [screen_pass(f, floor) for _, f in screen_rows]
    conf = confusion(flags, truth_flags)
    roc = screen_roc(conf, certified_run_n)
    return {'screened_n': len(screen_rows),
            'floor': floor,
            'winners': w,
            'certify_queue': certify_queue(w, [a for a, _ in screen_rows]),
            'confusion': conf,
            'roc': roc,
            'screen_quant': SCREEN_QUANT,
            'cert_quant': CERT_QUANT,
            'non_claim': 'screen verdicts never certify; winners re-run '
                         'and certified on bf16 under the bf16 key'}


if __name__ == '__main__':
    print('screen_certify: pure core (see test_screen_certify.py); the CLI '
          'plan mode prints model resolution + queue without touching '
          'anything')
