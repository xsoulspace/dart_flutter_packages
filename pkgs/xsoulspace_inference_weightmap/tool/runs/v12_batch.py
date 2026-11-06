#!/usr/bin/env python3
"""v12_batch.py - V12 device-batch runner (V12-OWNED; orchestrates FROZEN
tools unchanged; house battery law: serial -j 1).

Reads a pre-registered batch step file and runs one device batch:

  {"batch": "<name>",
   "mirror_dir": "<dir to rmtree at batch end (sweep)>",
   "gates": [{"after": "<step>", "file": "<json path>", "key": "<dotted.key>",
              "expect": "<value>", "code": "<NAMED error>"}],
   "steps": [{"step": "<name>", "argv": [...]}, ...]}

Protocol (device lock v3, coordinator-authorized 2026-11-06):
  1. acquire mkdir lock (a3_lock V3: 10s acquisition retries, 360 cap =>
     DEVICE_LOCK_TIMEOUT); wait_ms + retry_interval_used receipted.
  2. tag power state (pmset -g batt) + loadavg at start and end of batch.
  3. run steps SERIALLY, each row {step, argv, exit, wall_ms,
     wall_ms_claim:false}; after each step run its gates (dotted-key lookup
     in a JSON receipt; mismatch => NAMED gate code, batch blocked).
  4. finally: sweep mirror_dir (probe scratch law), write receipt, release
     lock (rmdir), sleep 3s courtesy.

Subprocesses get PYTHONDONTWRITEBYTECODE=1 (house law; __pycache__ in the
repo tree violates the probe scratch law).

Usage:
  <venv-python> -I -B v12_batch.py --lock-dir ${TMPDIR}/wm-device.lock \
      --batch-file <B.json> --receipt <B-receipt.json>

Exit: 0 batch complete; 1 NAMED blocked step/gate; 2 DEVICE_LOCK_TIMEOUT.
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

COURTESY_SLEEP_S = 3


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def power_state():
    try:
        out = subprocess.run(["pmset", "-g", "batt"], capture_output=True,
                             text=True, timeout=10).stdout.splitlines()
        return {"source": "pmset -g batt", "lines": out[:2]}
    except (OSError, subprocess.TimeoutExpired):
        return {"source": "pmset -g batt", "error": "PMSET_UNAVAILABLE"}


def lookup(obj, dotted):
    node = obj
    for part in dotted.split("."):
        if isinstance(node, dict):
            node = node[part]
        elif isinstance(node, list) and part.isdigit():
            node = node[int(part)]
        else:
            raise KeyError(dotted)
    return node


def run_steps(batch, receipt, env):
    receipt["power_start"] = power_state()
    receipt["loadavg_start"] = list(os.getloadavg())
    for step in batch["steps"]:
        t0 = time.time()
        proc = subprocess.run(step["argv"], capture_output=True,
                              text=True, env=env)
        wall_ms = int((time.time() - t0) * 1000)
        receipt["stages"].append({
            "step": step["step"], "argv": step["argv"],
            "exit": proc.returncode, "wall_ms": wall_ms,
            "wall_ms_claim": False})
        if proc.returncode != 0:
            err = (proc.stderr or "").strip().splitlines()
            code = err[0].split(":")[0] if err else "UNNAMED_FAILURE"
            receipt["blocked"] = {"step": step["step"], "code": code,
                                  "detail": (proc.stderr or "")[-800:]}
            return
        blocked = False
        for gate in batch.get("gates", []):
            if gate["after"] != step["step"]:
                continue
            try:
                got = lookup(
                    json.load(open(gate["file"], encoding="utf-8")),
                    gate["key"])
            except (OSError, ValueError, KeyError) as exc:
                receipt["gates"].append({**gate, "ok": False, "got": None,
                                         "error": str(exc)})
                receipt["blocked"] = {
                    "step": step["step"], "code": gate["code"],
                    "detail": "gate file/key unreadable: %s" % exc}
                blocked = True
                break
            ok = got == gate["expect"]
            receipt["gates"].append({**gate, "ok": ok, "got": got})
            if not ok:
                receipt["blocked"] = {
                    "step": step["step"], "code": gate["code"],
                    "detail": "gate %s: %s = %r != expected %r" % (
                        gate["file"], gate["key"], got, gate["expect"])}
                blocked = True
                break
        if blocked:
            return


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lock-dir", required=True)
    ap.add_argument("--batch-file", required=True)
    ap.add_argument("--receipt", required=True)
    args = ap.parse_args()

    batch = json.load(open(args.batch_file, encoding="utf-8"))
    receipt = {
        "batch": batch["batch"],
        "batch_file_sha256": sha256_file(args.batch_file),
        "started_utc": now(),
        "stages": [],
        "gates": [],
        "blocked": None,
        "lock_wait_ms": None,
        "verdict": "BATCH_INCOMPLETE",
    }
    env = dict(os.environ)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    locked = False
    lock_timeout = False
    try:
        try:
            wait_ms, retry_interval = a3_lock.acquire(
                args.lock_dir, attempts=a3_lock.V3_ATTEMPTS,
                sleep_s=a3_lock.V3_SLEEP_S)
            locked = True
            receipt["lock_wait_ms"] = wait_ms
            receipt["retry_interval_used"] = retry_interval
        except SystemExit:
            # a3_lock names DEVICE_LOCK_TIMEOUT on stderr and exits(1);
            # re-surface it as exit 2 with a receipted block.
            lock_timeout = True
            receipt["blocked"] = {"step": "device_lock",
                                  "code": "DEVICE_LOCK_TIMEOUT",
                                  "detail": args.lock_dir}
            receipt["verdict"] = "BATCH_BLOCKED"
        if locked:
            run_steps(batch, receipt, env)
            if receipt["verdict"] == "BATCH_INCOMPLETE":
                receipt["verdict"] = ("BATCH_COMPLETE"
                                      if not receipt["blocked"]
                                      else "BATCH_BLOCKED")
    finally:
        receipt["finished_utc"] = now()
        receipt["power_end"] = power_state()
        receipt["loadavg_end"] = list(os.getloadavg())
        mirror_dir = batch.get("mirror_dir")
        if mirror_dir and os.path.isdir(mirror_dir):
            shutil.rmtree(mirror_dir, ignore_errors=True)
            receipt["mirror_swept"] = mirror_dir
        try:
            os.makedirs(os.path.dirname(os.path.abspath(args.receipt)),
                        exist_ok=True)
            with open(args.receipt, "w", encoding="utf-8") as fh:
                json.dump(receipt, fh, indent=1)
        except OSError:
            pass
        if locked:
            a3_lock.release(args.lock_dir)
            time.sleep(COURTESY_SLEEP_S)  # protocol v3 courtesy after release

    if lock_timeout:
        return 2
    if receipt["verdict"] == "BATCH_COMPLETE":
        print("BATCH_COMPLETE %s lock_wait_ms=%s"
              % (batch["batch"], receipt["lock_wait_ms"]))
        return 0
    print("BATCH_BLOCKED %s %s"
          % (batch["batch"], json.dumps(receipt["blocked"])), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
