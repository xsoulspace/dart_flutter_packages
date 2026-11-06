#!/usr/bin/env python3
"""v3_dequant.py - V-3 NAMED adaptation DEQUANT_BASE (device-locked).

WHY (recorded pre-run in the V3 run-plan row): the frozen A3 builders
(apply_delta.py header/shape law, make_mirror.py merge law W[:,cols] +=
scale*direction cast back to the STORED dtype, a3_battery.py --repair) require
a PLAIN 2-D float tensor store. The candidate cast qwen3-1.7b-4bit ships a
4-bit PACKED store (down_proj.weight uint32 [2048,768] + .scales/.biases):
columns 0..6143 are out of range for the packed axis, so the frozen scripts
refuse it with NAMED errors (SPEC_SHAPE_MISMATCH / TENSOR_MISSING_IN_MODEL).
Frozen oracles are read-only; they are NEVER edited. The adaptation is the
standard, deterministic mlx_lm route: dequantize_model() (lossless
reconstruction of the quantized values) -> fp16 store in $TMPDIR (probe
scratch law: derived model binaries never land in the repo tree).

ALL V-3 measurements (pre-check, base, pilot, arms) run on this dequantized
snapshot; the hub 4bit store stays read-only and its G2 rate is recorded for
reference only. The dequantized config.json is the hub config minus the
"quantization" key; tokenizer files are copied byte-identical (digests
recorded).

Usage:
  <venv-python> -I -B v3_dequant.py --snapshot <hub-4bit-snapshot> \
      --out $TMPDIR/wm-v3/base-dequant --lock-dir ${TMPDIR}/wm-device.lock \
      --receipt <receipt.json>

Exit: 0 ok; 1 NAMED failure (receipt still written).
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
from v3_design import LAYERS, tensor_name  # noqa: E402


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 22), b""):
            h.update(chunk)
    return h.hexdigest()


def power_state():
    try:
        out = subprocess.run(["pmset", "-g", "batt"], capture_output=True,
                             text=True, timeout=10).stdout.splitlines()
        return out[1] if len(out) > 1 else out
    except Exception:
        return "PMSET_UNAVAILABLE"


def fail(receipt, code, detail, out_path):
    receipt["verdict"] = "DEQUANT_BLOCKED"
    receipt["blocked"] = {"code": code, "detail": detail}
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(receipt, fh, indent=1)
    print("%s: %s" % (code, detail), file=sys.stderr)
    return 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--snapshot", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--lock-dir", required=True)
    ap.add_argument("--receipt", required=True)
    args = ap.parse_args()

    receipt = {
        "tool": "v3_dequant.py",
        "named_adaptation": "DEQUANT_BASE (frozen builders require a plain "
                            "float store; 4bit packed store refused by frozen "
                            "apply_delta/make_mirror with NAMED errors; "
                            "frozen scripts NEVER edited)",
        "hub_snapshot": os.path.abspath(args.snapshot),
        "started_utc": now(),
        "power_start": power_state(),
        "loadavg_start": list(os.getloadavg()),
    }
    os.makedirs(os.path.dirname(os.path.abspath(args.receipt)), exist_ok=True)

    hub_shard = os.path.join(args.snapshot, "model.safetensors")
    if not os.path.isfile(hub_shard):
        return fail(receipt, "HUB_SHARD_MISSING", hub_shard, args.receipt)
    receipt["hub_model_safetensors_sha256"] = sha256_file(hub_shard)

    if os.path.exists(args.out):
        return fail(receipt, "OUT_EXISTS", args.out, args.receipt)

    wait, interval = a3_lock.acquire(args.lock_dir,
                                     attempts=a3_lock.V3_ATTEMPTS,
                                     sleep_s=a3_lock.V3_SLEEP_S)
    receipt["lock_wait_ms"] = wait
    receipt["retry_interval_used"] = interval
    try:
        import mlx.core as mx
        from mlx_lm import load
        from mlx_lm.utils import dequantize_model, save_model

        t0 = time.time()
        model, _tok = load(args.snapshot)
        receipt["load_wall_ms"] = int((time.time() - t0) * 1000)
        t0 = time.time()
        model = dequantize_model(model)
        mx.eval(model.parameters())
        receipt["dequant_wall_ms"] = int((time.time() - t0) * 1000)
        t0 = time.time()
        save_model(args.out, model)
        receipt["save_wall_ms"] = int((time.time() - t0) * 1000)
    except Exception as exc:
        a3_lock.release(args.lock_dir)
        return fail(receipt, "DEQUANT_FAILED",
                    "%s: %s" % (type(exc).__name__, exc), args.receipt)
    finally:
        pass
    a3_lock.release(args.lock_dir)
    time.sleep(3)  # protocol v3 courtesy

    # --- config + tokenizer files (CPU; hub read-only) ---
    copied = {}
    try:
        hub_cfg = json.load(open(os.path.join(args.snapshot, "config.json"),
                                 encoding="utf-8"))
        quant = hub_cfg.pop("quantization", None)
        quant_legacy = hub_cfg.pop("quantization_config", None)
        receipt["hub_quantization_config"] = quant
        receipt["hub_quantization_config_legacy_popped"] = quant_legacy
        with open(os.path.join(args.out, "config.json"), "w",
                  encoding="utf-8") as fh:
            json.dump(hub_cfg, fh, indent=2, sort_keys=True)
        for name in sorted(os.listdir(args.snapshot)):
            if name in ("config.json",) or name.endswith(".safetensors") \
                    or name.endswith(".safetensors.index.json"):
                continue
            src = os.path.join(args.snapshot, name)
            if os.path.isfile(src):
                shutil.copy2(src, os.path.join(args.out, name))
                copied[name] = sha256_file(src)
    except (OSError, ValueError) as exc:
        return fail(receipt, "CONFIG_COPY_FAILED", str(exc), args.receipt)
    receipt["copied_files_sha256"] = copied

    # --- verification (read-only) ---
    try:
        out_shard = os.path.join(args.out, "model.safetensors")
        if not os.path.isfile(out_shard):
            return fail(receipt, "SINGLE_SHARD_MISSING",
                        "save_model produced multiple shards; make_mirror.py "
                        "requires model.safetensors", args.receipt)
        arrays = mx.load(out_shard)
        names = set(arrays.keys())
        packed = sorted(n for n in names
                        if n.endswith((".scales", ".biases")))
        checks = {"tensor_count": len(names),
                  "packed_leftover_count": len(packed),
                  "mapped_layers": {}}
        ok = True
        for layer in LAYERS:
            tn = tensor_name(layer)
            if tn not in names:
                checks["mapped_layers"][layer] = {"present": False}
                ok = False
                continue
            w = arrays[tn]
            checks["mapped_layers"][layer] = {
                "present": True, "shape": list(w.shape),
                "dtype": str(w.dtype)}
            if list(w.shape) != [2048, 6144]:
                ok = False
        checks["dtypes_observed"] = sorted({str(a.dtype) for a in
                                            arrays.values()})
        receipt["verify"] = checks
        receipt["out_model_safetensors_sha256"] = sha256_file(out_shard)
        receipt["out_config_sha256"] = sha256_file(
            os.path.join(args.out, "config.json"))
        if packed or not ok:
            return fail(receipt, "DEQUANT_VERIFY_FAILED",
                        json.dumps(checks), args.receipt)
    except Exception as exc:
        return fail(receipt, "DEQUANT_VERIFY_FAILED",
                    "%s: %s" % (type(exc).__name__, exc), args.receipt)

    receipt["verdict"] = "DEQUANT_OK"
    receipt["finished_utc"] = now()
    receipt["power_end"] = power_state()
    receipt["loadavg_end"] = list(os.getloadavg())
    receipt["wall_ms_claim"] = False
    with open(args.receipt, "w", encoding="utf-8") as fh:
        json.dump(receipt, fh, indent=1)
    print("DEQUANT_OK %s tensors=%d sha=%s"
          % (args.out, checks["tensor_count"],
             receipt["out_model_safetensors_sha256"][:16]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
