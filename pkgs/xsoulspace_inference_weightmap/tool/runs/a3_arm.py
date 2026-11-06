#!/usr/bin/env python3
"""a3_arm.py - one blind A3 arm, end to end (driver; holds the device lock).

BLIND-STAGE LAW: reads only the arm's blind dir (specs + outputs). Never
reads truth/, the blinding key, or any kind/label information. Pipeline:

  1 apply_delta.py (frozen)  x2 tensors  -> arm/sidecars/L{15,19}/
  2 make_mirror.py           base+sidecars -> $TMPDIR mirror (base verified
                                             unchanged before/after)
  3 capture_activations.py (frozen) x2 banks -> arm/cap_{loop,neutral}.json
  4 a3_propose.py            -> arm/recovered.json (proposer output)
  5 a3_battery.py G0,G1,G2   -> arm/battery_M.jsonl (planted/null mirror)
  6 repair spec = -scale * recovered direction, same columns (from sidecar)
    a3_battery.py --repair   -> arm/battery_R.jsonl + repair_receipt.json
  7 arm_receipt.json (digests, wall rows tagged non-claim), mirror deleted

Usage:
  <venv-python> -I a3_arm.py --arm-dir <blind/arm-NNN> --snapshot <base> \
      --mirror-root <tmpdir>/mirrors --runs-dir <tool/runs> \
      --lock-dir <tmpdir>/wm-device.lock

Exit: 0 = arm complete; 1 = NAMED blocked step (arm_receipt.json records
`blocked`); 2 = device-lock timeout.
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

LAYERS = ["15", "19"]


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class ArmError(Exception):
    def __init__(self, step, code, detail):
        super().__init__("%s: %s (%s)" % (code, step, detail))
        self.step = step
        self.code = code
        self.detail = detail


def run_step(step, argv, receipt):
    t0 = time.time()
    proc = subprocess.run(argv, capture_output=True, text=True)
    wall_ms = int((time.time() - t0) * 1000)
    receipt["stages"].append({
        "step": step,
        "argv": argv,
        "exit": proc.returncode,
        "wall_ms": wall_ms,
        "wall_ms_claim": False,
    })
    if proc.returncode != 0:
        err = (proc.stderr or "").strip().splitlines()
        code = err[0].split(":")[0] if err else "UNNAMED_FAILURE"
        raise ArmError(step, code, (proc.stderr or "")[-800:])
    return proc.stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--arm-dir", required=True)
    ap.add_argument("--snapshot", required=True)
    ap.add_argument("--mirror-root", required=True)
    ap.add_argument("--runs-dir", required=True)
    ap.add_argument("--lock-dir", required=True)
    args = ap.parse_args()

    arm = os.path.abspath(args.arm_dir)
    label = os.path.basename(arm)
    runs = os.path.abspath(args.runs_dir)
    py = sys.executable
    mirror_dir = os.path.join(args.mirror_root, label)

    receipt = {
        "arm": label,
        "started_utc": now(),
        "stages": [],
        "artifacts": {},
        "blocked": None,
    }
    lock_wait_ms = None
    locked = False
    try:
        specs = {}
        for layer in LAYERS:
            sp = os.path.join(arm, "specs", "spec_L%s.json" % layer)
            if not os.path.isfile(sp):
                raise ArmError("specs", "SPEC_MISSING", sp)
            specs[layer] = sp

        lock_wait_ms, retry_interval = a3_lock.acquire(
            args.lock_dir, attempts=a3_lock.V3_ATTEMPTS,
            sleep_s=a3_lock.V3_SLEEP_S)
        locked = True
        receipt["lock_wait_ms"] = lock_wait_ms
        receipt["retry_interval_used"] = retry_interval

        # 1 - frozen sidecar writer (validates spec vs base header, base RO)
        for layer in LAYERS:
            out = os.path.join(arm, "sidecars", "L%s" % layer)
            run_step("apply_delta_L%s" % layer, [
                py, "-I", os.path.join(runs, "..", "eval", "apply_delta.py"),
                "--base", args.snapshot, "--spec", specs[layer], "--out", out,
            ], receipt)

        # 2 - mirror build (copy base to $TMPDIR, merge sidecars, verify)
        run_step("make_mirror", [
            py, "-I", os.path.join(runs, "make_mirror.py"),
            "--base", args.snapshot, "--out", mirror_dir,
            "--sidecar", os.path.join(arm, "sidecars", "L15"),
            "--sidecar", os.path.join(arm, "sidecars", "L19"),
            "--receipt", os.path.join(arm, "mirror_receipt.json"),
        ], receipt)

        # 3 - frozen capture tool on the mirror (both localization banks)
        for bank in ("loop", "neutral"):
            run_step("capture_%s" % bank, [
                py, "-I", os.path.join(runs, "..", "eval",
                                       "capture_activations.py"),
                "--model", mirror_dir,
                "--prompts", os.path.join(
                    runs, "prompts_localization_%s_A3.txt" % bank),
                "--layers", ",".join(LAYERS),
                "--out", os.path.join(arm, "cap_%s.json" % bank),
            ], receipt)

        # 4 - proposer (blind)
        run_step("propose", [
            py, "-I", os.path.join(runs, "a3_propose.py"),
            "--cap-loop", os.path.join(arm, "cap_loop.json"),
            "--cap-neutral", os.path.join(arm, "cap_neutral.json"),
            "--out", os.path.join(arm, "recovered.json"),
        ], receipt)

        # 5 - battery on the mirror (M)
        cells = os.path.join(runs, "cells_frozen_A3.json")
        run_step("battery_M", [
            py, "-I", os.path.join(runs, "a3_battery.py"),
            "--model", mirror_dir, "--cells", cells,
            "--groups", "G0,G1,G2",
            "--out", os.path.join(arm, "battery_M.jsonl"),
        ], receipt)

        # 6 - repair spec from PROPOSER output + sidecar columns/scale
        recovered = json.load(open(os.path.join(arm, "recovered.json")))
        import numpy as np
        tensors = []
        for layer in LAYERS:
            z = np.load(os.path.join(arm, "sidecars", "L%s" % layer,
                                     "delta.npz"), allow_pickle=False)
            tensors.append({
                "name": str(z["tensor_name"]),
                "columns": [int(c) for c in z["columns"]],
                "direction": recovered["layers"][layer]["direction"],
                "scale": -float(z["scale"]),  # removal = negated plant scale
            })
        repair_spec = os.path.join(arm, "repair_spec.json")
        with open(repair_spec, "w", encoding="utf-8") as fh:
            json.dump({"tensors": tensors}, fh)
        run_step("battery_R", [
            py, "-I", os.path.join(runs, "a3_battery.py"),
            "--model", mirror_dir, "--cells", cells,
            "--groups", "G0,G1,G2",
            "--repair", repair_spec,
            "--repair-out", os.path.join(arm, "battery_R.jsonl"),
            "--repair-receipt", os.path.join(arm, "repair_receipt.json"),
        ], receipt)

        # 7 - artifact digests
        for name in ("mirror_receipt.json", "recovered.json",
                     "battery_M.jsonl", "battery_R.jsonl",
                     "repair_receipt.json", "repair_spec.json",
                     "cap_loop.json", "cap_neutral.json"):
            p = os.path.join(arm, name)
            if os.path.isfile(p):
                receipt["artifacts"][name] = {
                    "path": p, "sha256": sha256_file(p),
                    "bytes": os.path.getsize(p),
                }
        receipt["verdict"] = "ARM_COMPLETE"
    except ArmError as exc:
        receipt["blocked"] = {"step": exc.step, "code": exc.code,
                              "detail": exc.detail}
        receipt["verdict"] = "ARM_BLOCKED"
    finally:
        receipt["finished_utc"] = now()
        if os.path.isdir(mirror_dir):
            shutil.rmtree(mirror_dir, ignore_errors=True)
            receipt["mirror_deleted"] = True
        try:
            with open(os.path.join(arm, "arm_receipt.json"), "w",
                      encoding="utf-8") as fh:
                json.dump(receipt, fh, indent=1)
        except OSError:
            pass
        if locked:
            a3_lock.release(args.lock_dir)

    if receipt["verdict"] == "ARM_COMPLETE":
        print("ARM_COMPLETE %s" % label)
        return 0
    print("ARM_BLOCKED %s %s" % (label, json.dumps(receipt["blocked"])),
          file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
