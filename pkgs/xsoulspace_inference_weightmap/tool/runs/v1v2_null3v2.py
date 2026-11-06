#!/usr/bin/env python3
"""v1v2_null3v2.py - null3-v2 (format-style contrast) gated spec builder
(ARC-OWNED helper; PREREG-C addendum 2026-11-06b).

Builds the unrelated-v2 null direction for one edit E:
  direction = unit(mean(UPPER renders) - mean(lowercase renders)) of the
  same seeded neutral-prompt subset, computed by the FROZEN a3_propose.py
  diff-of-means rule (invoked as a subprocess, unmodified; --cap-loop =
  upper capture, --cap-neutral = lower capture), on captures taken on E's
  rebuilt mirror (device steps run earlier in the same batch).

CONSTRUCTION-TIME ORTHOGONALITY GATE (pre-registered, addendum 2026-11-06b):
  |cos(direction_L, d_hat_E,L)| <= 0.2 for EVERY layer L in {15, 19},
  computed and receipted BEFORE any certification. Draw d0 = subset seed
  SEED3; a draw failing the gate is RE-DRAWN ONCE with seed offset
  (d1 = SEED3 + offset, banks pre-captured); a second failure is recorded
  GATE_EXHAUSTED (the gate failure itself is a row) and this script exits
  NAMED so the batch blocks before any null3v2 battery.

Spec shape = the exact {tensors:[{name, columns, direction, scale}]}
consumed by the FROZEN a3_battery.py --repair: E's tensor names + E's 64
columns + E's removal scale, all read from E's archived A3 repair_spec.

Usage:
  python3 -I -B v1v2_null3v2.py \
      --cap-upper-d0 <json> --cap-lower-d0 <json> \
      --cap-upper-d1 <json> --cap-lower-d1 <json> \
      --d-hat <arm recovered.json> --repair-spec <arm repair_spec.json> \
      --bank-record <fmt_banks.json> --propose-tool <a3_propose.py> \
      --out-spec <null3v2_spec.json> --gate-receipt <null3v2_gate.json>

Exit codes: 0 gate passed + spec written; 1 NAMED error on stderr:
  FMT_INPUT_MISSING DHAT_MISSING PROPOSE_FAILED GATE_EXHAUSTED
  SPEC_UNWRITABLE REPAIR_SPEC_MALFORMED
"""

import argparse
import hashlib
import json
import math
import os
import subprocess
import sys
from datetime import datetime, timezone

LAYERS = ("15", "19")
GATE_THRESHOLD = 0.2


def fail(code, detail):
    print("%s: %s" % (code, detail), file=sys.stderr)
    return 1


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_json_list(vals):
    return hashlib.sha256(json.dumps(vals).encode()).hexdigest()


def l2norm(v):
    return math.sqrt(sum(x * x for x in v))


def cosine(a, b):
    return sum(x * y for x, y in zip(a, b)) / (l2norm(a) * l2norm(b))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cap-upper-d0", required=True)
    ap.add_argument("--cap-lower-d0", required=True)
    ap.add_argument("--cap-upper-d1", required=True)
    ap.add_argument("--cap-lower-d1", required=True)
    ap.add_argument("--d-hat", required=True)
    ap.add_argument("--repair-spec", required=True)
    ap.add_argument("--bank-record", required=True)
    ap.add_argument("--propose-tool", required=True)
    ap.add_argument("--out-spec", required=True)
    ap.add_argument("--gate-receipt", required=True)
    args = ap.parse_args()

    caps = {"d0": (args.cap_upper_d0, args.cap_lower_d0),
            "d1": (args.cap_upper_d1, args.cap_lower_d1)}
    for draw, (u, l) in caps.items():
        for p in (u, l):
            if not os.path.isfile(p):
                return fail("FMT_INPUT_MISSING", "%s (%s)" % (draw, p))
    for p in (args.d_hat, args.repair_spec, args.bank_record,
              args.propose_tool):
        if not os.path.isfile(p):
            return fail("DHAT_MISSING" if p == args.d_hat
                        else "FMT_INPUT_MISSING", p)

    d_hat = json.load(open(args.d_hat, encoding="utf-8"))
    try:
        d_hat_dirs = {L: list(d_hat["layers"][L]["direction"])
                      for L in LAYERS}
    except (KeyError, TypeError) as exc:
        return fail("DHAT_MISSING", "layers/direction: %s" % exc)

    repair = json.load(open(args.repair_spec, encoding="utf-8"))
    try:
        tensors = repair["tensors"]
        names_cols = {}
        scale = None
        for t in tensors:
            layer = t["name"].split(".")[2]
            if layer not in LAYERS:
                raise KeyError("unexpected tensor %s" % t["name"])
            names_cols[layer] = (t["name"], [int(c) for c in t["columns"]])
            if scale is None:
                scale = float(t["scale"])
            elif abs(float(t["scale"]) - scale) > 1e-12:
                raise ValueError("mixed scales in repair_spec")
        for L in LAYERS:
            if L not in names_cols:
                raise KeyError("layer %s missing" % L)
    except (KeyError, ValueError, TypeError) as exc:
        return fail("REPAIR_SPEC_MALFORMED", str(exc))

    out_dir = os.path.dirname(os.path.abspath(args.gate_receipt))
    os.makedirs(out_dir, exist_ok=True)
    draws_receipt = []
    gate_receipt = {
        "tool": "v1v2_null3v2.py",
        "at": now(),
        "gate_rule": "|cos(null3v2_direction, d_hat_E)| <= %.1f per layer "
                     "{15,19}; construction-time; receipted BEFORE any "
                     "certification; ONE re-draw with seed offset, then "
                     "GATE_EXHAUSTED (PREREG-C addendum 2026-11-06b)"
                     % GATE_THRESHOLD,
        "threshold": GATE_THRESHOLD,
        "convention": "direction = unit(mean(UPPER) - mean(lowercase)) via "
                      "FROZEN a3_propose.py (--cap-loop=upper capture, "
                      "--cap-neutral=lower capture); captures on E's "
                      "rebuilt mirror; spec = E's tensor names, E's 64 "
                      "columns, E's removal scale (%s)" % scale,
        "d_hat_source": {"path": os.path.abspath(args.d_hat),
                         "sha256": sha256_file(args.d_hat)},
        "repair_spec_source": {"path": os.path.abspath(args.repair_spec),
                               "sha256": sha256_file(args.repair_spec)},
        "bank_record": {"path": os.path.abspath(args.bank_record),
                        "sha256": sha256_file(args.bank_record)},
        "propose_tool_sha256": sha256_file(args.propose_tool),
        "draws": draws_receipt,
    }

    passed = None
    for draw in ("d0", "d1"):
        upper, lower = caps[draw]
        rec_p = os.path.join(out_dir, "recovered_fmt_%s.json" % draw)
        proc = subprocess.run(
            [sys.executable, "-I", "-B", args.propose_tool,
             "--cap-loop", upper, "--cap-neutral", lower,
             "--out", rec_p],
            capture_output=True, text=True,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
        if proc.returncode != 0:
            gate_receipt["status"] = "PROPOSE_FAILED"
            try:
                json.dump(gate_receipt,
                          open(args.gate_receipt, "w", encoding="utf-8"),
                          indent=1)
            except OSError:
                pass
            return fail("PROPOSE_FAILED",
                        "%s: %s" % (draw, (proc.stderr or "")[-400:]))
        rec = json.load(open(rec_p, encoding="utf-8"))
        dirs = {L: list(rec["layers"][L]["direction"]) for L in LAYERS}
        cos = {L: cosine(dirs[L], d_hat_dirs[L]) for L in LAYERS}
        ok = all(abs(cos[L]) <= GATE_THRESHOLD for L in LAYERS)
        draws_receipt.append({
            "draw": draw,
            "captures": {"upper": {"path": upper, "sha256":
                                   sha256_file(upper)},
                         "lower": {"path": lower, "sha256":
                                   sha256_file(lower)}},
            "recovered_fmt": {"path": rec_p, "sha256": sha256_file(rec_p)},
            "per_layer": {L: {"cos_with_d_hat": cos[L],
                              "abs_cos": abs(cos[L]),
                              "direction_sha256":
                                  rec["layers"][L]["direction_sha256"],
                              "recomputed_direction_sha256":
                                  sha256_json_list(dirs[L]),
                              "diff_l2_norm":
                                  rec["layers"][L]["diff_l2_norm"],
                              "norm": l2norm(dirs[L])} for L in LAYERS},
            "gate_pass": ok,
        })
        if ok:
            passed = (draw, dirs)
            break

    if passed is None:
        gate_receipt["status"] = "GATE_EXHAUSTED"
        gate_receipt["at"] = now()
        try:
            with open(args.gate_receipt, "w", encoding="utf-8") as fh:
                json.dump(gate_receipt, fh, indent=1)
        except OSError as exc:
            return fail("SPEC_UNWRITABLE", str(exc))
        return fail("GATE_EXHAUSTED",
                    "both draws failed |cos| <= %.1f (cos d0=%s d1=%s); "
                    "gate failure receipted at %s"
                    % (GATE_THRESHOLD,
                       {L: round(draws_receipt[0]["per_layer"][L]
                                 ["cos_with_d_hat"], 6) for L in LAYERS},
                       {L: round(draws_receipt[1]["per_layer"][L]
                                 ["cos_with_d_hat"], 6) for L in LAYERS},
                       args.gate_receipt))

    draw, dirs = passed
    spec = {"tensors": [
        {"name": names_cols[L][0], "columns": names_cols[L][1],
         "direction": dirs[L], "scale": scale} for L in LAYERS]}
    try:
        with open(args.out_spec, "w", encoding="utf-8") as fh:
            json.dump(spec, fh)
        with open(args.gate_receipt, "w", encoding="utf-8") as fh:
            gate_receipt["status"] = "GATE_PASS"
            gate_receipt["draw_used"] = draw
            gate_receipt["spec"] = {
                "path": os.path.abspath(args.out_spec),
                "sha256": sha256_file(args.out_spec),
                "scale": scale,
                "columns_per_layer": {L: names_cols[L][1] for L in LAYERS},
                "per_layer_direction_sha256": {
                    L: sha256_json_list(dirs[L]) for L in LAYERS},
            }
            gate_receipt["at"] = now()
            json.dump(gate_receipt, fh, indent=1)
    except OSError as exc:
        return fail("SPEC_UNWRITABLE", str(exc))
    print("NULL3V2_GATE_PASS draw=%s cos=%s spec=%s" % (
        draw,
        {L: round(draws_receipt[-1]["per_layer"][L]["cos_with_d_hat"], 6)
         for L in LAYERS},
        gate_receipt["spec"]["sha256"][:16]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
