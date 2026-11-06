#!/usr/bin/env python3
"""v3_base.py - V-3 base stage on the second cast (device-locked driver).

Wraps the FROZEN tools unchanged (subprocess), parameterized by layers:
  capture_activations.py (frozen) x2 banks on the BASE (dequantized) snapshot
    -> a3_propose.py -> base/directions_base.json (plant direction source)
    -> a3_battery.py (G0,G1,G2,pilot) -> base/battery_base.jsonl

The G2 loop rate from battery_base.jsonl IS the pre-check measurement
(threshold >= 0.25 = 3/12, PREREG-D addendum 2026-11-06b); the receipt
records it (cap-hit rule, same as a3_stage.py) plus the pilot base rate.

Usage:
  <venv-python> -I -B v3_base.py --snapshot <dequant-base> \
      --work $TMPDIR/wm-v3 --runs-dir <tool/runs> --layers 18,22 \
      --lock-dir ${TMPDIR}/wm-device.lock

Exit: 0 BASE_STAGE_OK; 1 named stage failure.
"""

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import a3_lock  # noqa: E402


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def sha256_file(path):
    import hashlib
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def power_state():
    try:
        out = subprocess.run(["pmset", "-g", "batt"], capture_output=True,
                             text=True, timeout=10).stdout.splitlines()
        return out[1] if len(out) > 1 else out
    except Exception:
        return "PMSET_UNAVAILABLE"


def run_step(step, argv, receipt):
    t0 = time.time()
    proc = subprocess.run(argv, capture_output=True, text=True,
                          env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
    wall_ms = int((time.time() - t0) * 1000)
    receipt.setdefault("stages", []).append({
        "step": step, "argv": argv, "exit": proc.returncode,
        "wall_ms": wall_ms, "wall_ms_claim": False,
        "stderr_tail": (proc.stderr or "")[-400:] if proc.returncode else "",
    })
    if proc.returncode != 0:
        err = (proc.stderr or "").strip().splitlines()
        code = err[0].split(":")[0] if err else "UNNAMED_FAILURE"
        raise RuntimeError("%s at step %s: %s" % (code, step,
                                                  (proc.stderr or "")[-600:]))
    return proc.stdout


def loop_rate(jsonl_path, group):
    hits = tot = 0
    with open(jsonl_path, encoding="utf-8") as fh:
        for line in fh:
            r = json.loads(line)
            if r["group"] == group:
                tot += 1
                hits += bool(r["cap_hit"])
    return (hits / tot if tot else None), hits, tot


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--snapshot", required=True)
    ap.add_argument("--work", required=True)
    ap.add_argument("--runs-dir", required=True)
    ap.add_argument("--layers", required=True, help="e.g. 18,22")
    ap.add_argument("--lock-dir", required=True)
    args = ap.parse_args()

    layers = [x.strip() for x in args.layers.split(",")]
    work = os.path.abspath(args.work)
    base_dir = os.path.join(work, "base")
    os.makedirs(base_dir, exist_ok=True)
    runs = os.path.abspath(args.runs_dir)
    py = sys.executable
    receipt = {"stage": "v3-base", "snapshot": args.snapshot,
               "layers": layers, "started_utc": now(),
               "power_start": power_state(),
               "loadavg_start": list(os.getloadavg()), "stages": []}

    try:
        wait, interval = a3_lock.acquire(args.lock_dir,
                                         attempts=a3_lock.V3_ATTEMPTS,
                                         sleep_s=a3_lock.V3_SLEEP_S)
    except SystemExit:
        # acquisition cap exhausted (360 x 10s bounded wait): receipt the
        # timeout honestly (separate file; stage_receipt.json is reserved
        # for the attempt that actually ran) and exit 2 for relaunch.
        receipt["verdict"] = "BASE_STAGE_LOCK_TIMEOUT"
        receipt["blocked"] = ("DEVICE_LOCK_TIMEOUT: %s (acquisition cap "
                              "360 x 10s exhausted; contention wait is a "
                              "non-claim)" % args.lock_dir)
        receipt["finished_utc"] = now()
        p = os.path.join(base_dir, "stage_receipt_locktimeout_%d.json"
                         % int(time.time()))
        with open(p, "w", encoding="utf-8") as fh:
            json.dump(receipt, fh, indent=1)
        print("DEVICE_LOCK_TIMEOUT: base stage never acquired; receipt %s"
              % p, file=sys.stderr)
        return 2
    receipt["lock_wait_ms"] = wait
    receipt["retry_interval_used"] = interval
    try:
        for bank in ("loop", "neutral"):
            run_step("capture_%s" % bank, [
                py, "-I", "-B",
                os.path.join(runs, "..", "eval", "capture_activations.py"),
                "--model", args.snapshot,
                "--prompts", os.path.join(
                    runs, "prompts_localization_%s_A3.txt" % bank),
                "--layers", ",".join(layers),
                "--out", os.path.join(base_dir, "cap_%s.json" % bank),
            ], receipt)
        run_step("propose", [
            py, "-I", "-B", os.path.join(runs, "a3_propose.py"),
            "--cap-loop", os.path.join(base_dir, "cap_loop.json"),
            "--cap-neutral", os.path.join(base_dir, "cap_neutral.json"),
            "--out", os.path.join(base_dir, "directions_base.json"),
        ], receipt)
        run_step("battery_base", [
            py, "-I", "-B", os.path.join(runs, "a3_battery.py"),
            "--model", args.snapshot,
            "--cells", os.path.join(runs, "cells_frozen_A3.json"),
            "--groups", "G0,G1,G2,pilot",
            "--out", os.path.join(base_dir, "battery_base.jsonl"),
        ], receipt)
        receipt["verdict"] = "BASE_STAGE_OK"
        for name in ("cap_loop.json", "cap_neutral.json",
                     "directions_base.json", "battery_base.jsonl"):
            p = os.path.join(base_dir, name)
            receipt.setdefault("artifacts", {})[name] = sha256_file(p)
        rate, hits, tot = loop_rate(
            os.path.join(base_dir, "battery_base.jsonl"), "G2")
        receipt["g2_base_loop_rate"] = rate
        receipt["g2_base_hits"] = hits
        receipt["g2_base_n"] = tot
        receipt["precheck_threshold"] = 0.25
        receipt["precheck_pass"] = (rate is not None and rate >= 0.25)
        prate, phits, ptot = loop_rate(
            os.path.join(base_dir, "battery_base.jsonl"), "pilot")
        receipt["pilot_base_loop_rate"] = prate
        receipt["pilot_base_hits"] = phits
        receipt["pilot_base_n"] = ptot
        print("BASE_STAGE_OK g2_base_loop=%d/%d precheck_pass=%s "
              "pilot_base_loop=%d/%d"
              % (hits, tot, receipt["precheck_pass"], phits, ptot))
    except RuntimeError as exc:
        receipt["verdict"] = "BASE_STAGE_BLOCKED"
        receipt["blocked"] = str(exc)
        print("BASE_STAGE_BLOCKED: %s" % exc, file=sys.stderr)
    finally:
        receipt["finished_utc"] = now()
        receipt["power_end"] = power_state()
        receipt["loadavg_end"] = list(os.getloadavg())
        a3_lock.release(args.lock_dir)
        time.sleep(3)  # protocol v3 courtesy
        with open(os.path.join(base_dir, "stage_receipt.json"), "w",
                  encoding="utf-8") as fh:
            json.dump(receipt, fh, indent=1)
    return 0 if receipt["verdict"] == "BASE_STAGE_OK" else 1


if __name__ == "__main__":
    sys.exit(main())
