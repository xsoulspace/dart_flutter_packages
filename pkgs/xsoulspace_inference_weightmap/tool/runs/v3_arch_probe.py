#!/usr/bin/env python3
"""v3_arch_probe.py - V-3 pre-check step 1: RUNTIME arch verification of a
candidate cast against the FROZEN A3 instrument set (device-locked).

The V-3 task brief: "lfm arch supported by mlx-lm? verify at runtime;
unsupported => NAMED ARCH_UNSUPPORTED for that candidate, try next."

This probe records, honestly and mechanically:
  A. does mlx_lm.load() succeed on the candidate (arch supported by mlx-lm)?
  B. does a 1-token greedy generation succeed (runtime generation support)?
  C. does the model tree satisfy the FROZEN capture_activations.py shape law
     (.model.layers[i].mlp present for the mapped layers)?
  D. does the store carry the A3 spec tensors model.layers.{L}.mlp.down_proj
     .weight as PLAIN 2-D float tensors (apply_delta.py/make_mirror.py law)?
  E. subprocess: run the FROZEN capture_activations.py on the candidate with a
     2-prompt scratch file and record its NAMED exit (expected for lfm2:
     ARCH_SHAPE_UNEXPECTED - lfm2 exposes feed_forward.w1/w2/w3, not .mlp).

Frozen scripts are NEVER edited; this probe only RUNS them and records.

Usage:
  <venv-python> -I -B v3_arch_probe.py --snapshot <hub-snapshot-dir> \
      --layers 10,13 --work $TMPDIR/wm-v3 --lock-dir ${TMPDIR}/wm-device.lock \
      --out <receipt.json>

Exit: 0 probe complete (verdict inside the receipt: SUPPORTED or
NAMED refusal); 1 probe infrastructure failure.
"""

import argparse
import hashlib
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--snapshot", required=True)
    ap.add_argument("--layers", required=True, help="mapped layers, e.g. 10,13")
    ap.add_argument("--work", required=True)
    ap.add_argument("--lock-dir", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    runs = os.path.dirname(os.path.abspath(__file__))
    py = sys.executable
    layers = [int(x) for x in args.layers.split(",")]
    receipt = {
        "tool": "v3_arch_probe.py",
        "candidate_snapshot": os.path.abspath(args.snapshot),
        "mapped_layers": layers,
        "started_utc": now(),
        "power_start": power_state(),
        "loadavg_start": list(os.getloadavg()),
        "checks": {},
    }

    wait, interval = a3_lock.acquire(args.lock_dir,
                                     attempts=a3_lock.V3_ATTEMPTS,
                                     sleep_s=a3_lock.V3_SLEEP_S)
    receipt["lock_wait_ms"] = wait
    receipt["retry_interval_used"] = interval
    try:
        # --- D. CPU-side store header scan (no device) ---
        try:
            import glob
            shards = sorted(glob.glob(os.path.join(args.snapshot,
                                                   "*.safetensors")))
            names = set()
            for sh in shards:
                with open(sh, "rb") as fh:
                    hlen = int.from_bytes(fh.read(8), "little")
                    header = json.loads(fh.read(hlen))
                names.update(k for k in header if k != "__metadata__")
            down_plain = sorted(n for n in names
                                if n.endswith(".mlp.down_proj.weight"))
            ff_w2 = sorted(n for n in names if "feed_forward.w2" in n)
            receipt["checks"]["store_tensors"] = {
                "shards": [os.path.basename(s) for s in shards],
                "tensor_count": len(names),
                "mlp_down_proj_weight_count": len(down_plain),
                "mlp_down_proj_weight_sample": down_plain[:4],
                "feed_forward_w2_count": len(ff_w2),
                "feed_forward_w2_sample": ff_w2[:4],
                "mapped_layer_tensors": sorted(
                    n for n in names
                    if any((".layers.%d." % L) in n for L in layers))[:24],
            }
        except Exception as exc:  # record, do not crash
            receipt["checks"]["store_tensors"] = {"error": str(exc)}

        # --- A/B/C. runtime load + 1-token generate + shape law ---
        try:
            t0 = time.time()
            import mlx.core as mx
            from mlx_lm import generate, load
            model, tok = load(args.snapshot)
            mx.eval(model.parameters())
            receipt["checks"]["mlx_lm_load"] = {
                "ok": True, "wall_ms": int((time.time() - t0) * 1000)}
            tower = getattr(getattr(model, "model", None), "layers", None)
            n_layers = len(tower) if tower else None
            shape = {"has_model_layers": bool(tower),
                     "layers_total": n_layers}
            if tower:
                per = {}
                for i in layers:
                    if i < len(tower):
                        layer = tower[i]
                        per[str(i)] = {
                            "has_mlp": getattr(layer, "mlp", None) is not None,
                            "has_feed_forward":
                                getattr(layer, "feed_forward", None) is not None,
                            "attrs": sorted(
                                a for a in ("mlp", "feed_forward", "self_attn",
                                            "conv", "ffn_norm",
                                            "post_attention_layernorm")
                                if getattr(layer, a, None) is not None),
                        }
                shape["mapped_layers"] = per
            receipt["checks"]["arch_shape"] = shape
            t0 = time.time()
            out = generate(model, tok, prompt="Hello", max_tokens=1,
                           verbose=False)
            receipt["checks"]["generate_1tok"] = {
                "ok": True, "wall_ms": int((time.time() - t0) * 1000),
                "text_len": len(out or "")}
        except Exception as exc:
            receipt["checks"]["runtime"] = {
                "ok": False, "error": "%s: %s" % (type(exc).__name__, exc)}

        # --- E. run the FROZEN capture script and record its NAMED refusal ---
        scratch = os.path.join(args.work, "arch-probe")
        os.makedirs(scratch, exist_ok=True)
        pf = os.path.join(scratch, "probe_prompts.txt")
        with open(pf, "w", encoding="utf-8") as fh:
            fh.write("Hello there.\nCount with me.\n")
        t0 = time.time()
        proc = subprocess.run(
            [py, "-I", "-B",
             os.path.join(runs, "..", "eval", "capture_activations.py"),
             "--model", args.snapshot, "--prompts", pf,
             "--layers", args.layers,
             "--out", os.path.join(scratch, "cap_probe.json")],
            capture_output=True, text=True,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
        receipt["checks"]["frozen_capture_attempt"] = {
            "exit": proc.returncode,
            "wall_ms": int((time.time() - t0) * 1000),
            "wall_ms_claim": False,
            "stderr": (proc.stderr or "").strip()[-600:],
            "stdout_tail": (proc.stdout or "").strip()[-200:],
        }
    finally:
        receipt["finished_utc"] = now()
        receipt["power_end"] = power_state()
        receipt["loadavg_end"] = list(os.getloadavg())
        a3_lock.release(args.lock_dir)
        time.sleep(3)  # protocol v3 courtesy

    # --- mechanical verdict ---
    cap = receipt["checks"].get("frozen_capture_attempt", {})
    load_ok = receipt["checks"].get("mlx_lm_load", {}).get("ok", False)
    if cap.get("exit") == 0 and load_ok:
        receipt["verdict"] = "SUPPORTED"
    else:
        code = (cap.get("stderr", "").split(":")[0]
                if cap.get("stderr") else "RUNTIME_LOAD_FAILURE")
        receipt["verdict"] = "ARCH_UNSUPPORTED"
        receipt["named_code"] = code
        receipt["detail"] = (
            "mlx_lm runtime load=%s; frozen capture_activations.py exit=%s "
            "(%s). Frozen instruments are read-only (A4 freeze law): a cast "
            "whose tree/store does not satisfy the frozen shape law "
            "(.model.layers[i].mlp + plain mlp.down_proj.weight tensors) "
            "cannot host the replicated pipeline."
            % (load_ok, cap.get("exit"), code))
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(receipt, fh, indent=1)
    print("ARCH_PROBE %s verdict=%s" % (args.snapshot, receipt["verdict"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
