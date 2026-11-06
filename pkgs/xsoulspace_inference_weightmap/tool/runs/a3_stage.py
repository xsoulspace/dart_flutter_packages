#!/usr/bin/env python3
"""a3_stage.py - base stage + pilot scale ladder (device-locked driver).

STAGE base:
  capture_activations.py (frozen) x2 banks on the BASE snapshot ->
  a3_propose.py -> base/directions_base.json (THE plant direction source) ->
  a3_battery.py (all 4 groups incl. pilot) -> base/battery_base.jsonl.

STAGE pilot (scale calibration, pre-registered ladder):
  for s in LADDER: build a pilot mirror (plant direction, columns C_1, scale
  s) via apply_delta.py + make_mirror.py, run the 16 pilot cells, compute
  lift = pilot_loop_rate(M_s) - pilot_loop_rate(base). FIRST s with
  lift >= +0.20 wins (smallest sufficient scale). Every ladder row is
  recorded (denominator law). If none: NAMED BLOCKED SCALE_UNCALIBRATABLE.

Usage:
  <venv-python> -I a3_stage.py base --snapshot SNAP --work $TMPDIR/wm-a3 \
      --runs-dir tool/runs --lock-dir LOCK
  <venv-python> -I a3_stage.py pilot --snapshot SNAP --work $TMPDIR/wm-a3 \
      --runs-dir tool/runs --lock-dir LOCK

Exit: 0 ok; 1 named stage failure; 3 SCALE_UNCALIBRATABLE.
"""

import argparse
import json
import os
import random
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import a3_lock  # noqa: E402
from a3_design import pair_columns  # noqa: E402

LAYERS = ["15", "19"]
LADDER = [0.05, 0.1, 0.2, 0.4, 0.8, 1.6]  # v1 (frozen in run-plan row; verdict
# SCALE_UNCALIBRATABLE). Ladder v2 frozen in the amendment row BEFORE its run;
# pass it explicitly via --ladder. The selection RULE never changes: first
# ladder scale with pilot lift >= +20pp wins; none => SCALE_UNCALIBRATABLE.
LIFT_TARGET = 0.20                          # +20pp (frozen, task brief)


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def sha256_file(path):
    import hashlib
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def run_step(step, argv, receipt):
    t0 = time.time()
    proc = subprocess.run(argv, capture_output=True, text=True)
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
    return hits / tot if tot else None, hits, tot


def base_stage(args):
    work = args.work
    base_dir = os.path.join(work, "base")
    os.makedirs(base_dir, exist_ok=True)
    runs = os.path.abspath(args.runs_dir)
    py = sys.executable
    receipt = {"stage": "base", "started_utc": now(), "stages": []}
    wait, interval = a3_lock.acquire(args.lock_dir,
                                     attempts=a3_lock.V3_ATTEMPTS,
                                     sleep_s=a3_lock.V3_SLEEP_S)
    receipt["lock_wait_ms"] = wait
    receipt["retry_interval_used"] = interval
    try:
        for bank in ("loop", "neutral"):
            run_step("capture_%s" % bank, [
                py, "-I", os.path.join(runs, "..", "eval",
                                       "capture_activations.py"),
                "--model", args.snapshot,
                "--prompts", os.path.join(
                    runs, "prompts_localization_%s_A3.txt" % bank),
                "--layers", ",".join(LAYERS),
                "--out", os.path.join(base_dir, "cap_%s.json" % bank),
            ], receipt)
        run_step("propose", [
            py, "-I", os.path.join(runs, "a3_propose.py"),
            "--cap-loop", os.path.join(base_dir, "cap_loop.json"),
            "--cap-neutral", os.path.join(base_dir, "cap_neutral.json"),
            "--out", os.path.join(base_dir, "directions_base.json"),
        ], receipt)
        run_step("battery_base", [
            py, "-I", os.path.join(runs, "a3_battery.py"),
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
            os.path.join(base_dir, "battery_base.jsonl"), "pilot")
        receipt["pilot_base_loop_rate"] = rate
        rate2, h2, t2 = loop_rate(
            os.path.join(base_dir, "battery_base.jsonl"), "G2")
        receipt["g2_base_loop_rate"] = rate2
        print("BASE_STAGE_OK pilot_base_loop=%d/%d g2_base_loop=%d/%d"
              % (hits, tot, h2, t2))
    except RuntimeError as exc:
        receipt["verdict"] = "BASE_STAGE_BLOCKED"
        receipt["blocked"] = str(exc)
        print("BASE_STAGE_BLOCKED: %s" % exc, file=sys.stderr)
    finally:
        receipt["finished_utc"] = now()
        a3_lock.release(args.lock_dir)
        with open(os.path.join(base_dir, "stage_receipt.json"), "w") as fh:
            json.dump(receipt, fh, indent=1)
    return 0 if receipt["verdict"] == "BASE_STAGE_OK" else 1


def build_spec(direction, columns, scale, layer):
    return {
        "tensor": "model.layers.%s.mlp.down_proj.weight" % layer,
        "columns": columns,
        "direction": direction,
        "scale": scale,
    }


def pilot_stage(args):
    ladder = ([float(x) for x in args.ladder.split(",")]
              if args.ladder else LADDER)
    work = args.work
    runs = os.path.abspath(args.runs_dir)
    py = sys.executable
    pilot_dir = os.path.join(work, "pilot")
    os.makedirs(pilot_dir, exist_ok=True)
    base_batt = os.path.join(work, "base", "battery_base.jsonl")
    directions = json.load(
        open(os.path.join(work, "base", "directions_base.json")))
    base_rate, _, _ = loop_rate(base_batt, "pilot")
    if base_rate is None:
        print("PILOT_BLOCKED: no base pilot battery", file=sys.stderr)
        return 1
    cols1 = pair_columns(1)  # pilot uses pair-1 columns (frozen procedure)

    receipt = {"stage": "pilot", "started_utc": now(), "ladder": [],
               "ladder_scales": ladder,
               "base_pilot_loop_rate": base_rate,
               "lift_target": LIFT_TARGET,
               "columns_procedure": "a3_design.pair_columns(1)"}
    import hashlib
    receipt["columns_sha256"] = hashlib.sha256(
        json.dumps(cols1).encode()).hexdigest()
    chosen = None
    wait_total = 0
    try:
        for s in ladder:
            row = {"scale": s, "started_utc": now()}
            mirror = os.path.join(work, "mirrors", "pilot-s%s" % s)
            sidecars = os.path.join(pilot_dir, "sidecars-s%s" % s)
            specs_dir = os.path.join(pilot_dir, "specs-s%s" % s)
            os.makedirs(specs_dir, exist_ok=True)
            spec_paths = []
            for layer in LAYERS:
                sp = os.path.join(specs_dir, "spec_L%s.json" % layer)
                with open(sp, "w", encoding="utf-8") as fh:
                    json.dump(build_spec(directions["layers"][layer]
                                         ["direction"], cols1, s, layer), fh)
                spec_paths.append(sp)
            wait, interval = a3_lock.acquire(args.lock_dir,
                                             attempts=a3_lock.V3_ATTEMPTS,
                                             sleep_s=a3_lock.V3_SLEEP_S)
            wait_total += wait
            row["lock_wait_ms"] = wait
            row["retry_interval_used"] = interval
            try:
                for layer, sp in zip(LAYERS, spec_paths):
                    run_step("apply_delta_pilot_s%s_L%s" % (s, layer), [
                        py, "-I",
                        os.path.join(runs, "..", "eval", "apply_delta.py"),
                        "--base", args.snapshot, "--spec", sp,
                        "--out", os.path.join(sidecars, "L%s" % layer),
                    ], receipt)
                run_step("make_mirror_pilot_s%s" % s, [
                    py, "-I", os.path.join(runs, "make_mirror.py"),
                    "--base", args.snapshot, "--out", mirror,
                    "--sidecar", os.path.join(sidecars, "L15"),
                    "--sidecar", os.path.join(sidecars, "L19"),
                    "--receipt", os.path.join(pilot_dir,
                                              "mirror_receipt_s%s.json" % s),
                ], receipt)
                out = os.path.join(pilot_dir, "battery_pilot_s%s.jsonl" % s)
                run_step("battery_pilot_s%s" % s, [
                    py, "-I", os.path.join(runs, "a3_battery.py"),
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
            row["finished_utc"] = now()
            receipt["ladder"].append(row)
            print("PILOT s=%s loop=%s lift=%spp %s"
                  % (s, row.get("loop_rate"), row.get("lift_pp"),
                     row.get("blocked", "")))
            if row.get("lift_pp") is not None and \
                    row["lift_pp"] >= LIFT_TARGET * 100:
                chosen = s
                break
    finally:
        receipt["chosen_scale"] = chosen
        receipt["lock_wait_total_ms"] = wait_total
        receipt["finished_utc"] = now()
        receipt["verdict"] = ("PILOT_OK scale=%s" % chosen if chosen
                              is not None else "SCALE_UNCALIBRATABLE")
        with open(os.path.join(pilot_dir, "pilot_receipt.json"), "w") as fh:
            json.dump(receipt, fh, indent=1)
    if chosen is None:
        print("SCALE_UNCALIBRATABLE: no ladder scale reached +%.0fpp lift "
              "(rows recorded)" % (LIFT_TARGET * 100), file=sys.stderr)
        return 3
    print("PILOT_OK chosen_scale=%s" % chosen)
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="stage", required=True)
    for name in ("base", "pilot"):
        p = sub.add_parser(name)
        p.add_argument("--snapshot", required=True)
        p.add_argument("--work", required=True)
        p.add_argument("--runs-dir", required=True)
        p.add_argument("--lock-dir", required=True)
        if name == "pilot":
            p.add_argument("--ladder", default=None,
                           help="comma-separated scale ladder (default: v1)")
    args = ap.parse_args()
    if args.stage == "base":
        sys.exit(base_stage(args))
    else:
        sys.exit(pilot_stage(args))


if __name__ == "__main__":
    main()
