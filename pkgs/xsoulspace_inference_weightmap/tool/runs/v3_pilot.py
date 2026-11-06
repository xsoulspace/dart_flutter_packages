#!/usr/bin/env python3
"""v3_pilot.py - V-3 pilot scale ladder on the second cast (device-locked).

Wraps the FROZEN tools unchanged (apply_delta.py, make_mirror.py,
a3_battery.py), parameterized by layers + ladder. Same selection RULE as the
frozen A3 pilot (never changes): FIRST ladder scale with pilot loop-rate lift
>= +20pp vs the base pilot rate wins (smallest sufficient scale); EVERY ladder
row is recorded (denominator law); none => NAMED SCALE_UNCALIBRATABLE (a
verdict on this cast; run stops with rows).

Columns: v3_design.pair_columns_v3(1) (frozen procedure lineage, seed
20261105, range adapted to this cast's 6144 columns - recorded pre-run).
Direction: base/directions_base.json per mapped layer (frozen proposer).

One lock acquisition per ladder step (a3_stage.py pilot granularity); wait_ms
+ retry_interval_used receipted per step; mirror swept per step.

Usage:
  <venv-python> -I -B v3_pilot.py --snapshot <dequant-base> \
      --work $TMPDIR/wm-v3 --runs-dir <tool/runs> --layers 18,22 \
      --ladder 0.05,0.1,0.2,0.4,0.8,1.6,2.0,3.2,4.8 \
      --lock-dir ${TMPDIR}/wm-device.lock [--receipt-tag v1]

Exit: 0 PILOT_OK; 1 blocked; 3 SCALE_UNCALIBRATABLE.
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import a3_lock  # noqa: E402
from v3_design import pair_columns_v3, tensor_name  # noqa: E402

LIFT_TARGET = 0.20  # +20pp (frozen rule, task brief)


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


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
        "step": step, "exit": proc.returncode,
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
    ap.add_argument("--layers", required=True)
    ap.add_argument("--ladder", required=True,
                    help="comma-separated scales (frozen in run-plan row)")
    ap.add_argument("--lock-dir", required=True)
    ap.add_argument("--receipt-tag", default="v1")
    args = ap.parse_args()

    ladder = [float(x) for x in args.ladder.split(",")]
    layers = [x.strip() for x in args.layers.split(",")]
    work = os.path.abspath(args.work)
    runs = os.path.abspath(args.runs_dir)
    py = sys.executable
    pilot_dir = os.path.join(work, "pilot")
    os.makedirs(pilot_dir, exist_ok=True)

    base_batt = os.path.join(work, "base", "battery_base.jsonl")
    directions = json.load(
        open(os.path.join(work, "base", "directions_base.json"),
             encoding="utf-8"))
    base_rate, base_hits, base_n = loop_rate(base_batt, "pilot")
    if base_rate is None:
        print("PILOT_BLOCKED: no base pilot battery", file=sys.stderr)
        return 1
    cols1 = pair_columns_v3(1)  # pilot uses pair-1 columns (frozen procedure)

    receipt = {"stage": "v3-pilot", "started_utc": now(), "ladder": [],
               "ladder_scales": ladder,
               "layers": layers,
               "base_pilot_loop_rate": base_rate,
               "base_pilot_hits": base_hits,
               "base_pilot_n": base_n,
               "lift_target": LIFT_TARGET,
               "columns_procedure": "v3_design.pair_columns_v3(1)",
               "power_start": power_state()}
    receipt["columns_sha256"] = hashlib.sha256(
        json.dumps(cols1).encode()).hexdigest()
    chosen = None
    wait_total = 0
    try:
        for s in ladder:
            row = {"scale": s, "started_utc": now()}
            mirror = os.path.join(work, "mirrors", "v3-pilot-s%s" % s)
            sidecars = os.path.join(pilot_dir, "sidecars-s%s" % s)
            specs_dir = os.path.join(pilot_dir, "specs-s%s" % s)
            os.makedirs(specs_dir, exist_ok=True)
            spec_paths = []
            for layer in layers:
                sp = os.path.join(specs_dir, "spec_L%s.json" % layer)
                with open(sp, "w", encoding="utf-8") as fh:
                    json.dump({"tensor": tensor_name(layer),
                               "columns": cols1,
                               "direction": directions["layers"][layer]
                               ["direction"],
                               "scale": s}, fh)
                spec_paths.append(sp)
            try:
                wait, interval = a3_lock.acquire(
                    args.lock_dir, attempts=a3_lock.V3_ATTEMPTS,
                    sleep_s=a3_lock.V3_SLEEP_S)
            except SystemExit:
                row["blocked"] = ("DEVICE_LOCK_TIMEOUT (acquisition cap "
                                  "360 x 10s exhausted; non-claim)")
                row["finished_utc"] = now()
                receipt["ladder"].append(row)
                receipt["verdict"] = "PILOT_LOCK_TIMEOUT"
                receipt["finished_utc"] = now()
                out_path = os.path.join(
                    pilot_dir, "pilot_receipt_locktimeout_%d.json"
                    % int(time.time()))
                with open(out_path, "w", encoding="utf-8") as fh:
                    json.dump(receipt, fh, indent=1)
                print("DEVICE_LOCK_TIMEOUT at scale %s; receipt %s"
                      % (s, out_path), file=sys.stderr)
                return 2
            wait_total += wait
            row["lock_wait_ms"] = wait
            row["retry_interval_used"] = interval
            try:
                for layer, sp in zip(layers, spec_paths):
                    run_step("apply_delta_pilot_s%s_L%s" % (s, layer), [
                        py, "-I", "-B",
                        os.path.join(runs, "..", "eval", "apply_delta.py"),
                        "--base", args.snapshot, "--spec", sp,
                        "--out", os.path.join(sidecars, "L%s" % layer),
                    ], receipt)
                argv = [py, "-I", "-B", os.path.join(runs, "make_mirror.py"),
                        "--base", args.snapshot, "--out", mirror]
                for layer in layers:
                    argv += ["--sidecar", os.path.join(sidecars,
                                                       "L%s" % layer)]
                argv += ["--receipt",
                         os.path.join(pilot_dir,
                                      "mirror_receipt_s%s.json" % s)]
                run_step("make_mirror_pilot_s%s" % s, argv, receipt)
                out = os.path.join(pilot_dir, "battery_pilot_s%s.jsonl" % s)
                run_step("battery_pilot_s%s" % s, [
                    py, "-I", "-B", os.path.join(runs, "a3_battery.py"),
                    "--model", mirror,
                    "--cells", os.path.join(runs, "cells_frozen_A3.json"),
                    "--groups", "pilot",
                    "--out", out,
                ], receipt)
                rate, hits, tot = loop_rate(out, "pilot")
                row.update({"loop_rate": rate, "hits": hits, "n": tot,
                            "lift_pp": round((rate - base_rate) * 100, 2)})
            except RuntimeError as exc:
                row["blocked"] = str(exc)
            finally:
                if os.path.isdir(mirror):
                    shutil.rmtree(mirror, ignore_errors=True)
                a3_lock.release(args.lock_dir)
                time.sleep(3)  # protocol v3 courtesy
            row["finished_utc"] = now()
            receipt["ladder"].append(row)
            print("PILOT s=%s loop=%s lift=%spp %s"
                  % (s, row.get("loop_rate"), row.get("lift_pp"),
                     row.get("blocked", "")), flush=True)
            if row.get("lift_pp") is not None and \
                    row["lift_pp"] >= LIFT_TARGET * 100:
                chosen = s
                break
    finally:
        receipt["chosen_scale"] = chosen
        receipt["lock_wait_total_ms"] = wait_total
        receipt["finished_utc"] = now()
        receipt["power_end"] = power_state()
        if receipt.get("verdict") != "PILOT_LOCK_TIMEOUT":
            receipt["verdict"] = ("PILOT_OK scale=%s" % chosen if chosen
                                  is not None else "SCALE_UNCALIBRATABLE")
        out_path = os.path.join(pilot_dir,
                                "pilot_receipt_%s.json" % args.receipt_tag)
        with open(out_path, "w", encoding="utf-8") as fh:
            json.dump(receipt, fh, indent=1)
    if chosen is None:
        print("SCALE_UNCALIBRATABLE: no ladder scale reached +%.0fpp lift "
              "(rows recorded)" % (LIFT_TARGET * 100), file=sys.stderr)
        return 3
    print("PILOT_OK chosen_scale=%s" % chosen)
    return 0


if __name__ == "__main__":
    sys.exit(main())
