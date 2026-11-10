#!/usr/bin/env python3
"""seq_stop.py - L5 sequential early-stop with ALWAYS-VALID CIs
(PREREG-SPEED.md, FROZEN 2026-11-10). Pure, no device.

Hoeffding mean-bound form: for a rate estimated from n bounded trials,
  halfwidth(n) = sqrt(ln(2/alpha) / (2n))
holds UNIFORMLY over n (always-valid: peeking after every cell is priced
by the form itself, per the statistical constitution's "optional stopping
priced, not hidden").

The stop rule + alpha are FROZEN in each arm's prereg before the first
cell; a post-hoc alpha is a new prereg row (never fitted to observed data).
"""

import math


def halfwidth(n, alpha):
    """Time-uniform Hoeffding half-width for a rate in [0,1]."""
    if n <= 0:
        raise ValueError('N_NONPOSITIVE: n must be >= 1')
    if not (0 < alpha < 1):
        raise ValueError('ALPHA_RANGE: alpha in (0,1), got %r' % alpha)
    return math.sqrt(math.log(2.0 / alpha) / (2.0 * n))


def ci(rate, n, alpha):
    lo = max(0.0, rate - halfwidth(n, alpha))
    hi = min(1.0, rate + halfwidth(n, alpha))
    return lo, hi


def stop_decision(passes, n, floor, alpha, side):
    """Decide whether the bank may stop early.

    side='below': the claim is 'true rate < floor' (e.g. loop rate below a
      repair floor) -> stop when the UPPER bound < floor.
    side='above': the claim is 'true rate > floor' -> stop when the LOWER
      bound > floor.
    Returns (stop: bool, reason: str) — never raises on undecided banks.
    """
    if n <= 0:
        return False, 'N_ZERO'
    if side not in ('below', 'above'):
        raise ValueError('SIDE_UNKNOWN: %r' % side)
    rate = passes / n
    lo, hi = ci(rate, n, alpha)
    if side == 'below' and hi < floor:
        return True, 'CI_BELOW_FLOOR(phat=%.3f,n=%d,hi=%.4f<floor=%.3f)' \
            % (rate, n, hi, floor)
    if side == 'above' and lo > floor:
        return True, 'CI_ABOVE_FLOOR(phat=%.3f,n=%d,lo=%.4f>floor=%.3f)' \
            % (rate, n, lo, floor)
    return False, 'UNDECIDED(n=%d,ci=[%.4f,%.4f])' % (n, lo, hi)


if __name__ == '__main__':
    print('seq_stop: pure always-valid stopping module')
