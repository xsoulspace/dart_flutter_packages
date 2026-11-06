#!/usr/bin/env python3
"""v12_verdict.py - V12 score-work assembler + pre-registered rule applier
(V12-OWNED). NEVER scores cells: per-cell pass/fail and loop rates come only
from the FROZEN certifier (a3_score.dart over cells_frozen_A3.json +
scorers.dart). This script applies the decision rules pre-registered in
receipts/V1-nulls.jsonl kind=v12-run-plan and writes ledger payload JSONs.

Modes:
  --mode assemble : build an a3_score.dart work-dir:
      <work>/base/battery_base.jsonl (copy)
      <work>/blind/arm-table.json {"arms":[{"label":...},...]}
      <work>/blind/<label>/battery_M.jsonl (copy of the session M battery)
      <work>/blind/<label>/battery_R.jsonl (copy per --r-map label=path,...)
  --mode v1 : apply the V-1 floor (0 of 4 nulls certified; any certified =
      NAMED NULL_LEAK halt). Inputs: the frozen certifier output (--scored),
      nulls_manifest.json (--manifest), A3 join-table.json (--arm-join),
      archived arm-002 battery_M.jsonl (--archived-m) for M continuity.
      Writes payload_null{1..4}.json + payload_v1_verdict.json to --out-dir.
  --mode v2 : apply the pre-registered V-2 rules (tolerance = half the A3
      removal effect; EFFECT on held-out G1 perm cells; MECHANISM on the
      three interventions; classes PASS / EFFECT_TRUE_MECHANISM_FALSE /
      EFFECT_FALSE). Inputs: --scored, --arm-join, --archived-m (arm-002
      battery_M.jsonl), --archived-r (arm-002 battery_R.jsonl), --session-m
      (this run's M battery), --batteries ablate=path,restore=path,
      relocate=path. Writes payload_v2_interventions.json +
      payload_v2_verdict.json to --out-dir.

Named errors (exit 1): INPUT_MISSING SCORED_LABEL_MISSING JOIN_ROW_MISSING
BATTERY_SHAPE_MISMATCH. Continuity FLAGS (recorded, never silent):
M_DRIFT (session M battery differs from archived arm-002 M per-cell),
ABULATE_NOT_IDENTITY, RESTORE_DRIFT.
"""

import argparse
import json
import math
import os
import shutil
import sys
from datetime import datetime, timezone

V1_LABELS = [("v1-null-1", "null1_gaussian"), ("v1-null-2", "null2_shuffle"),
             ("v1-null-3", "null3_unrelated"),
             ("v1-null-4", "null4_quantnoise")]
V2_LABELS = ["v2-ablate", "v2-restore", "v2-relocate"]
Z95 = 1.959964


def fail(code, detail):
    print("%s: %s" % (code, detail), file=sys.stderr)
    return 1


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def read_jsonl(path):
    with open(path, encoding="utf-8") as fh:
        return [json.loads(l) for l in fh if l.strip()]


def cell_sig(rows):
    return [(r["cell_id"], r["output_sha256"]) for r in rows]


def sig_diff(a, b):
    if len(a) != len(b):
        return {"cells_total_a": len(a), "cells_total_b": len(b),
                "cells_matching": None}
    match = sum(1 for x, y in zip(a, b) if x == y)
    return {"cells_total": len(a), "cells_matching": match,
            "cells_differing": len(a) - match,
            "differing_cell_ids": [x[0] for x, y in zip(a, b) if x != y]}


def wilson_ci95(hits, n):
    if n == 0:
        return None
    p = hits / n
    denom = 1 + Z95 * Z95 / n
    center = p + Z95 * Z95 / (2 * n)
    half = Z95 * math.sqrt(p * (1 - p) / n + Z95 * Z95 / (4 * n * n))
    return [max(0.0, (center - half) / denom),
            min(1.0, (center + half) / denom)]


def net_g1_flips(flips):
    up = sum(1 for f in flips if f["cell_id"].startswith("g1-perm")
             and not f["M"] and f["R"])
    down = sum(1 for f in flips if f["cell_id"].startswith("g1-perm")
               and f["M"] and not f["R"])
    return up - down


def load(p):
    if not os.path.isfile(p):
        raise FileNotFoundError(p)
    return json.load(open(p, encoding="utf-8"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", required=True,
                    choices=["assemble", "v1", "v2"])
    ap.add_argument("--work", default=None)
    ap.add_argument("--labels", default=None)
    ap.add_argument("--m-battery", default=None)
    ap.add_argument("--base-battery", default=None)
    ap.add_argument("--r-map", default=None, help="label=path,label=path")
    ap.add_argument("--scored", default=None)
    ap.add_argument("--manifest", default=None)
    ap.add_argument("--arm-join", default=None)
    ap.add_argument("--archived-m", default=None)
    ap.add_argument("--archived-r", default=None)
    ap.add_argument("--session-m", default=None)
    ap.add_argument("--batteries", default=None, help="k=path,k=path")
    ap.add_argument("--out-dir", default=None)
    args = ap.parse_args()

    if args.mode == "assemble":
        labels = [l.strip() for l in args.labels.split(",")]
        rmap = dict(kv.split("=", 1) for kv in args.r_map.split(","))
        os.makedirs(os.path.join(args.work, "base"), exist_ok=True)
        shutil.copyfile(args.base_battery,
                        os.path.join(args.work, "base",
                                     "battery_base.jsonl"))
        blind = os.path.join(args.work, "blind")
        os.makedirs(blind, exist_ok=True)
        with open(os.path.join(blind, "arm-table.json"), "w",
                  encoding="utf-8") as fh:
            json.dump({"arms": [{"label": l} for l in labels]}, fh)
        for label in labels:
            d = os.path.join(blind, label)
            os.makedirs(d, exist_ok=True)
            shutil.copyfile(args.m_battery,
                            os.path.join(d, "battery_M.jsonl"))
            shutil.copyfile(rmap[label], os.path.join(d, "battery_R.jsonl"))
        print("ASSEMBLE_OK %s labels=%s" % (args.work, labels))
        return 0

    # ---------- shared inputs for v1/v2 ----------
    try:
        scored = load(args.scored)
        join = load(args.arm_join)
    except FileNotFoundError as exc:
        return fail("INPUT_MISSING", str(exc))
    arm = None
    for row in join["rows"]:
        if row["real_id"] == "a3-plant-1":
            arm = row
    if arm is None or not arm.get("certified"):
        return fail("JOIN_ROW_MISSING",
                    "a3-plant-1 row missing or not certified")
    arms = scored["arms"]
    os.makedirs(args.out_dir, exist_ok=True)

    def dump(name, payload):
        p = os.path.join(args.out_dir, name)
        with open(p, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, indent=1)
        return p

    if args.mode == "v1":
        try:
            manifest = load(args.manifest)
            arch_m = cell_sig(read_jsonl(args.archived_m))
        except FileNotFoundError as exc:
            return fail("INPUT_MISSING", str(exc))
        # M continuity: session M battery vs archived arm-002 battery_M.
        if args.session_m is None:
            return fail("INPUT_MISSING", "--session-m required for v1 mode")
        session_m_rows = read_jsonl(args.session_m)
        m_cont = sig_diff(cell_sig(session_m_rows), arch_m)
        m_drift = m_cont.get("cells_matching") != m_cont.get("cells_total")
        payloads = []
        certified_count = 0
        for label, kind in V1_LABELS:
            if label not in arms or arms[label].get("status") != "SCORED":
                return fail("SCORED_LABEL_MISSING", label)
            a = arms[label]
            man = manifest["nulls"].get(kind, {})
            payload = {
                "artifact": "V-1 matched null (PREREG-C)",
                "at": now(),
                "target_edit": "A3 plant-1 (arm-002) certified removal edit",
                "null_id": label,
                "null_kind": kind,
                "construction": man.get("construction"),
                "spec_sha256": man.get("spec_sha256"),
                "scale": man.get("scale"),
                "per_layer": man.get("per_layer"),
                "certification_rule": scored["certification_rule"],
                "loop_rate_M": a["loop_rate_M"],
                "loop_rate_R": a["loop_rate_R"],
                "loop_delta_R_minus_M": a["loop_delta_R_minus_M"],
                "task_success_M": a["task_success_M"],
                "task_success_R": a["task_success_R"],
                "task_success_delta_R_minus_M":
                    a["task_success_delta_R_minus_M"],
                "task_pass_M": a["task_pass_M"],
                "task_pass_R": a["task_pass_R"],
                "certified": a["certified"],
                "flips": a["flips"],
                "digests": a["digests"],
            }
            certified_count += 1 if a["certified"] else 0
            payloads.append(("payload_%s.json" % label, {
                "kind": "v1-null", "payload": payload}))
        ci = wilson_ci95(certified_count, len(V1_LABELS))
        verdict = {
            "artifact": "V-1 verdict (floor FROZEN in PREREG-C: 0 of 4 "
                        "nulls certified per edit)",
            "at": now(),
            "target_edit": "A3 plant-1 (arm-002); denominator note: this "
                           "run covers 1 of the 6 A3-certified edits "
                           "(plants 1,3,4,5,6,7); family-wise completion "
                           "for the remaining 5 is deferred and recorded",
            "nulls_run": len(V1_LABELS),
            "nulls_certified": certified_count,
            "certified_ids": [l for l, _ in V1_LABELS
                              if arms[l]["certified"]],
            "floor": "0 of 4",
            "floor_met": certified_count == 0,
            "verdict": ("CLEAN_0_OF_4" if certified_count == 0
                        else "NULL_LEAK"),
            "halt": None if certified_count == 0 else {
                "code": "NULL_LEAK",
                "rule": "PREREG-C kill clause: any certified null = NAMED "
                        "NULL_LEAK -> pipeline HALT; the halt and its "
                        "denominator are the verdict; V-2 not run",
                "certified_nulls": [l for l, _ in V1_LABELS
                                    if arms[l]["certified"]]},
            "family_wise": {
                "rate": "%d/%d" % (certified_count, len(V1_LABELS)),
                "wilson95": ci,
                "note": "this edit only; program-wide rate accumulates as "
                        "remaining certified edits run V-1"},
            "m_continuity_vs_archived_arm002": m_cont,
            "m_drift_flag": ("M_DRIFT" if m_drift else None),
            "cells_sha256": scored["cells_sha256"],
        }
        payloads.append(("payload_v1_verdict.json", {
            "kind": "v1-verdict", "payload": verdict}))
        for name, obj in payloads:
            dump(name, obj)
        print("V1_VERDICT %s certified=%d/4 floor_met=%s%s" % (
            verdict["verdict"], certified_count, verdict["floor_met"],
            "" if not m_drift else " M_DRIFT=%s" % json.dumps(m_cont)))
        return 0

    # ---------- v2 ----------
    try:
        arch_m = cell_sig(read_jsonl(args.archived_m))
        arch_r = cell_sig(read_jsonl(args.archived_r))
        session_m = cell_sig(read_jsonl(args.session_m))
        bat = dict(kv.split("=", 1) for kv in args.batteries.split(","))
        for k in V2_LABELS:
            assert k in arms and arms[k].get("status") == "SCORED", k
    except (FileNotFoundError, AssertionError) as exc:
        return fail("INPUT_MISSING", str(exc))
    for label in V2_LABELS:
        if label not in arms:
            return fail("SCORED_LABEL_MISSING", label)

    e_ref = arm["loop_delta_R_minus_M"]          # A3 removal effect (-1/3)
    tol = abs(e_ref) / 2.0                       # pre-registered tolerance
    loop_m = {l: arms[l]["loop_rate_M"] for l in V2_LABELS}
    if len(set(loop_m.values())) != 1:
        return fail("BATTERY_SHAPE_MISMATCH",
                    "loop_rate_M differs across intervention dirs: %s"
                    % loop_m)
    loop_m = loop_m[V2_LABELS[0]]
    ref_g1 = net_g1_flips(arm["flips"]) / 12.0   # +0.5 for arm-002

    m_cont = sig_diff(session_m, arch_m)
    interventions = {}
    for label in V2_LABELS:
        a = arms[label]
        rows = read_jsonl(bat[label])
        iv = {
            "intervention": label,
            "loop_rate_M": a["loop_rate_M"],
            "loop_rate_I": a["loop_rate_R"],
            "loop_delta_I_minus_M": a["loop_delta_R_minus_M"],
            "task_success_M": a["task_success_M"],
            "task_success_I": a["task_success_R"],
            "task_success_delta_I_minus_M": a["task_success_delta_R_minus_M"],
            "net_g1_flips": net_g1_flips(a["flips"]),
            "delta_g1_task_success": net_g1_flips(a["flips"]) / 12.0,
            "flips": a["flips"],
            "digests": a["digests"],
        }
        if label == "v2-ablate":
            ident = sig_diff(cell_sig(rows), session_m)
            iv["identity_vs_session_M"] = ident
            iv["flag"] = (None if ident.get("cells_matching")
                          == ident.get("cells_total")
                          else "ABULATE_NOT_IDENTITY")
            iv["dies"] = abs(iv["loop_delta_I_minus_M"]) <= tol
        elif label == "v2-restore":
            cont = sig_diff(cell_sig(rows), arch_r)
            iv["continuity_vs_archived_R"] = cont
            iv["flag"] = (None if cont.get("cells_matching")
                          == cont.get("cells_total") else "RESTORE_DRIFT")
            iv["returns"] = (iv["loop_delta_I_minus_M"] < 0
                             and abs(iv["loop_delta_I_minus_M"] - e_ref)
                             <= tol)
        else:  # relocate
            iv["dies"] = abs(iv["loop_delta_I_minus_M"]) <= tol
        interventions[label] = iv

    mechanism_pass = (interventions["v2-ablate"]["dies"]
                      and interventions["v2-restore"]["returns"]
                      and interventions["v2-relocate"]["dies"])
    delta_g1 = interventions["v2-restore"]["delta_g1_task_success"]
    effect_true = delta_g1 >= abs(ref_g1) / 2.0
    if effect_true and mechanism_pass:
        klass = "PASS"
    elif effect_true:
        klass = "EFFECT_TRUE_MECHANISM_FALSE"
    else:
        klass = "EFFECT_FALSE"
    verdict = {
        "artifact": "V-2 effect/mechanism split verdict (PREREG-C)",
        "at": now(),
        "target_edit": "A3 plant-1 (arm-002) certified removal edit",
        "pre_registered_rules": {
            "E_ref": e_ref,
            "tol": tol,
            "dies(x)": "|loop(x) - loop(M)| <= tol",
            "returns": "loop(restore) < loop(M) AND |loop(restore)-loop(M)"
                       " - E_ref| <= tol",
            "EFFECT": "delta_G1 := net g1-perm flips(restore)/12; "
                      "EFFECT_TRUE := delta_G1 >= |ref_G1|/2",
            "ref_G1": ref_g1,
            "classes": ["PASS", "EFFECT_TRUE_MECHANISM_FALSE",
                        "EFFECT_FALSE"],
        },
        "loop_rate_M": loop_m,
        "ablate_dies": interventions["v2-ablate"]["dies"],
        "restore_returns": interventions["v2-restore"]["returns"],
        "relocate_dies": interventions["v2-relocate"]["dies"],
        "MECHANISM": "PASS" if mechanism_pass else "FAIL",
        "delta_G1_held_out": delta_g1,
        "EFFECT": "EFFECT_TRUE" if effect_true else "EFFECT_FALSE",
        "class": klass,
        "secondary_columns": {
            "restore_loop_delta": interventions[
                "v2-restore"]["loop_delta_I_minus_M"],
            "restore_task_success_delta_G0G1": interventions[
                "v2-restore"]["task_success_delta_I_minus_M"],
            "relocate_loop_delta": interventions[
                "v2-relocate"]["loop_delta_I_minus_M"],
            "ablate_loop_delta": interventions[
                "v2-ablate"]["loop_delta_I_minus_M"],
        },
        "continuity": {
            "session_M_vs_archived_M": m_cont,
            "m_drift_flag": (None if m_cont.get("cells_matching")
                             == m_cont.get("cells_total") else "M_DRIFT"),
            "ablate_identity_flag": interventions["v2-ablate"]["flag"],
            "restore_drift_flag": interventions["v2-restore"]["flag"],
        },
        "held_out_note": "EFFECT is judged on the 12 G1 perm cells (disjoint "
                         "from the 128+128 loop/neutral localization banks "
                         "and from the G2 cells carrying the MECHANISM "
                         "loop-rate criterion). Caveat recorded, not hidden: "
                         "in A3 the G1 cells also contributed to the "
                         "task_success half of certification; their "
                         "held-out status here is vs localization and vs "
                         "the V-2 mechanism metric.",
        "cells_sha256": scored["cells_sha256"],
    }
    dump("payload_v2_interventions.json", {
        "kind": "v2-interventions",
        "payload": {"artifact": "V-2 intervention measurements",
                    "at": now(), "interventions": interventions}})
    dump("payload_v2_verdict.json", {
        "kind": "v2-verdict", "payload": verdict})
    print("V2_VERDICT class=%s MECHANISM=%s EFFECT=%s (delta_G1=%+.3f) "
          "ablate_dies=%s restore_returns=%s relocate_dies=%s" % (
              klass, verdict["MECHANISM"], verdict["EFFECT"], delta_g1,
              verdict["ablate_dies"], verdict["restore_returns"],
              verdict["relocate_dies"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
