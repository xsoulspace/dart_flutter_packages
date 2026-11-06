#!/usr/bin/env python3
"""a3_lock.py - device-lock helper (house battery law: serial -j 1).

Coordinator protocol (2026-11-05): acquire `mkdir <lock-dir>` (atomic) before
ANY model-loading/capture/battery run; on EEXIST sleep 60s and retry with a
bounded cap; release with rmdir after the stage's battery completes; failure
paths release via try/finally. Wait time is recorded in receipts; wall_ms rows
are non-claims (wall_ms_claim=false) because the machine carries heavy
external load regardless of lock state.
"""

import os
import sys
import time

DEFAULT_ATTEMPTS = 60   # bounded: 60 x 60s = 1h max wait
DEFAULT_SLEEP_S = 60
# Protocol v3 (coordinator authorization 2026-11-06): ACQUISITION-ONLY fast
# retry at 10s, bounded by the same 1h per-acquire cap (360 attempts).
# Release granularity is unchanged (per arm / per ladder step). Every
# acquisition records retry_interval_used in its receipt.
V3_SLEEP_S = 10
V3_ATTEMPTS = 360


def acquire(lock_dir, attempts=DEFAULT_ATTEMPTS, sleep_s=DEFAULT_SLEEP_S):
    """Returns (waited_ms, retry_interval_used). Exits(1) with
    DEVICE_LOCK_TIMEOUT when the bounded wait is exhausted."""
    waited = 0.0
    for _ in range(attempts):
        try:
            os.mkdir(lock_dir)
            return int(waited * 1000), sleep_s
        except FileExistsError:
            time.sleep(sleep_s)
            waited += sleep_s
        except OSError as exc:
            print("DEVICE_LOCK_ERROR: %s (%s)" % (lock_dir, exc),
                  file=sys.stderr)
            sys.exit(1)
    print("DEVICE_LOCK_TIMEOUT: %s after %.0fs" % (lock_dir, waited),
          file=sys.stderr)
    sys.exit(1)


def release(lock_dir):
    try:
        os.rmdir(lock_dir)
    except FileNotFoundError:
        pass
    except OSError as exc:
        print("DEVICE_LOCK_RELEASE_ERROR: %s (%s)" % (lock_dir, exc),
              file=sys.stderr)
