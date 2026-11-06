#!/usr/bin/env python3
"""a3_ledger_arm.py - build the per-arm ledger payload (BLIND-SAFE).

Reads only blind/<label>/arm_receipt.json (+ battery jsonl line counts) and
emits a payload json for a3_ledger.dart. Contains no kind, no truth, no
cosines - those join post-freeze only.

Usage: python3 -I a3_ledger_arm.py --work $TMPDIR/wm-a3 --label arm-NNN \
           --out payload.json
"""

import argparse
import hashlib
import json
import os


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for c in iter(lambda: fh.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def count_lines(path):
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as fh:
        return sum(1 for l in fh if l.strip())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", required=True)
    ap.add_argument("--label", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    arm = os.path.join(args.work, "blind", args.label)
    receipt_path = os.path.join(arm, "arm_receipt.json")
    receipt = json.load(open(receipt_path, encoding="utf-8"))
    payload = {
        "arm": args.label,
        "verdict": receipt.get("verdict"),
        "started_utc": receipt.get("started_utc"),
        "finished_utc": receipt.get("finished_utc"),
        "blocked": receipt.get("blocked"),
        "lock_wait_ms": receipt.get("lock_wait_ms"),
        "stage_wall_ms": {
            s["step"]: s["wall_ms"] for s in receipt.get("stages", [])
        },
        "wall_ms_claim": False,
        "battery_M_rows": count_lines(os.path.join(arm, "battery_M.jsonl")),
        "battery_R_rows": count_lines(os.path.join(arm, "battery_R.jsonl")),
        "artifacts": receipt.get("artifacts", {}),
        "mirror_deleted": receipt.get("mirror_deleted", False),
    }
    payload["arm_receipt_sha256"] = sha256_file(receipt_path)
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=1)
    print("PAYLOAD_OK %s verdict=%s" % (args.out, payload["verdict"]))


if __name__ == "__main__":
    main()
