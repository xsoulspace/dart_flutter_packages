#!/usr/bin/env python3
"""speed_proxy.py - L1 loop-proxy early-stop policy (PREREG-SPEED.md, FROZEN
2026-11-10). Pure functions, no mlx, no device: the policy decides WHEN to
stop generating a looping row and HOW the row is classified.

FROZEN CONSTANTS (a change = PREREG-SPEED addendum):
  T_PROXY   = 1024   proxy window bound (trigger positions must be <= this)
  F_EARLY   = 3      detector fires required inside the proxy bound
  MIN_TOKENS = 256   never classify before this many generated tokens

Classification taxonomy (frozen): LOOP_PROXY | LOOP_CAP | EOS | TRUNCATED.
LOOP_PROXY is a NAMED PROXY — never merged with cap_hit in
paper-comparability arithmetic (P-* arms are exempt from L1 entirely).
"""

T_PROXY = 1024
F_EARLY = 3
MIN_TOKENS = 256

LOOP_PROXY = 'LOOP_PROXY'
LOOP_CAP = 'LOOP_CAP'
EOS = 'EOS'
TRUNCATED = 'TRUNCATED'


def proxy_stop_decision(generated_len, trigger_count_within_proxy):
    """Decide at generation time (called after each step). Stop iff the row
    has enough tokens to trust (MIN_TOKENS) and the detector has fired
    F_EARLY times with all trigger positions inside the proxy bound."""
    if generated_len < MIN_TOKENS:
        return False
    return trigger_count_within_proxy >= F_EARLY


def count_within_proxy(triggers, generated_len):
    """Triggers at positions < min(T_PROXY, generated_len)."""
    bound = min(T_PROXY, generated_len)
    return sum(1 for t in triggers if t < bound)


def classify_row(triggers, finish_reason, generated_len, cap,
                 proxy_stop_at=None):
    """Offline classification (scorer twin of the runtime decision).

    finish_reason: 'proxy' (runtime fired L1) | 'eos' | 'length' |
    'truncated' (budget stop). generated_len = KEPT tokens. The proxy
    classification is accepted only when the runtime recorded a stop point
    consistent with the frozen policy (not before MIN_TOKENS, not past
    T_PROXY)."""
    if finish_reason == 'proxy':
        if proxy_stop_at is None:
            raise ValueError('PROXY_UNRECORDED: finish=proxy without a '
                             'stop point')
        if proxy_stop_at < MIN_TOKENS or proxy_stop_at > T_PROXY:
            raise ValueError('PROXY_OUT_OF_POLICY: stop at %d outside '
                             '[%d, %d]' % (proxy_stop_at, MIN_TOKENS,
                                           T_PROXY))
        return LOOP_PROXY
    if finish_reason == 'eos':
        return EOS
    if finish_reason == 'truncated':
        return TRUNCATED
    if finish_reason == 'length':
        if generated_len == cap:
            return LOOP_CAP
        raise ValueError('LENGTH_MISMATCH: finish=length but %d != cap %d'
                         % (generated_len, cap))
    raise ValueError('FINISH_UNKNOWN: %r' % finish_reason)


def effective_cap(cap, allow_proxy=True):
    """The cap a stage-3+ runner passes for one row under L1 (the true cap
    stays the prereg cap; the proxy merely stops early). P-* arms call with
    allow_proxy=False and owe the full generation."""
    return cap  # the cap does not shrink; the POLICY stops early


if __name__ == '__main__':
    print('speed_proxy: pure policy module (see test_speed_proxy.py)')
