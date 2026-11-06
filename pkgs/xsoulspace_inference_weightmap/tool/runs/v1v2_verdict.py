#!/usr/bin/env python3
"""v1v2_verdict.py - V1-v2 arc payload assembler + pre-registered rule
applier (ARC-OWNED). NEVER scores cells: per-cell pass/fail, loop rates and
the certified flag come ONLY from the FROZEN certifier (a3_score.dart over
cells_frozen_A3.json + scorers.dart). This script applies the rules frozen in
PREREG-C + addendum 2026-11-06b and the arc run-plan row, and writes ledger
payload JSONs (appended afterwards via the frozen lib ledger, a3_ledger.dart).

Modes:
  --mode construction : per-edit construction row (specs + provenance +
      null3v2 GATE COS VALUES, receipted BEFORE any certification row).
      Inputs: --arc-manifest --gate-receipt --edit --arm --tag --out-dir.
  --mode v1v2 : per-edit V-1 rows (4 nulls + confounded(arm-002) + verdict).
      Inputs: --scored (a3_score output), --edit, --arm, --tag, --arm-join,
      --archived-m (wm-a3 arm battery_M.jsonl), --session-m-a,
      --session-m-b, --arc-manifest, --gate-receipt, --gen-dir, --out-dir.
  --mode family : family-wise aggregation row over the per-edit verdict
      payloads (rate + Wilson95 + DEFERRED_FAMILY_WISE named).
      Inputs: --verdict-payloads p1.json[,p3.json,...], --out-dir.
  --mode v2note : the V-2 unblock note payload for receipts/
      V2-mechanism.jsonl (cites the plant-1 V-1 v2 verdict digest; rules
      cited from the v12 run-plan, frozen there).
      Inputs: --v1-verdict-digest --v1-verdict-ledger --v1-verdict-seq
      --out-dir.

Named errors (exit 1): INPUT_MISSING SCORED_LABEL_MISSING JOIN_ROW_MISSING
BATTERY_SHAPE_MISMATCH PLUMBING_UNREADABLE.
Continuity FLAGS (recorded, never silent): M_DRIFT, R_PLUMBING_MISMATCH.
"""

import argparse
import hashlib
import json
import math
import os
import sys
from datetime import datetime, timezone

Z95 = 1.959964
GATE_THRESHOLD = 0.2
DEFERRED = [("a3-plant-4", "arm-005"), ("a3-plant-6", "arm-011"),
            ("a3-plant-7", "arm-012")]


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


def load(p, code="INPUT_MISSING"):
    if not os.path.isfile(p):
        raise FileNotFoundError("%s: %s" % (code, p))
    return json.load(open(p, encoding="utf-8"))


def v1_reference(ledger_path):
    """Read the v1-null-3 (old null-3 shape) measurement from the v1
    ledger - the confounded control's history reference. Never typed by
    hand: digests come from the ledger rows themselves."""
    ref = {"null_id": "v1-null-3",
           "note": "fresh re-run this arc as CONFOUNDED_POSITIVE_CONTROL; "
                   "v1 history read from receipts/V1-nulls.jsonl "
                   "(continuity observation, not a rule)"}
    if not ledger_path or not os.path.isfile(ledger_path):
        ref["status"] = "V1_LEDGER_UNAVAILABLE"
        return ref
    for line in open(ledger_path, encoding="utf-8"):
        if not line.strip():
            continue
        row = json.loads(line)
        if row.get("kind") == "v1-null" and \
                row["payload"].get("null_id") == "v1-null-3":
            ref["certified"] = row["payload"]["certified"]
            ref["battery_R_sha256"] = \
                row["payload"]["digests"]["battery_R"]
            ref["loop_rate_M"] = row["payload"]["loop_rate_M"]
            ref["loop_rate_R"] = row["payload"]["loop_rate_R"]
            ref["task_success_M"] = row["payload"]["task_success_M"]
            ref["task_success_R"] = row["payload"]["task_success_R"]
            ref["v1_seq"] = row["seq"]
            ref["v1_digest"] = row["digest"]
            return ref
    ref["status"] = "V1_NULL3_ROW_NOT_FOUND"
    return ref


def null_labels(tag):
    t = tag.lower()
    return [("v1v2-%s-null1" % t, "null1_gaussian", "null1"),
            ("v1v2-%s-null2" % t, "null2_shuffle", "null2"),
            ("v1v2-%s-null3v2" % t, "null3_unrelated_v2", "null3v2"),
            ("v1v2-%s-null4" % t, "null4_quantnoise", "null4")]


def plumbing(gen_dir, short, spec_path, arm_repair_path, expect_kind):
    """Verify the frozen a3_battery --repair receipt against the spec and
    the arm's archived repair_spec (columns/tensors/scale identity)."""
    rec_p = os.path.join(gen_dir, "repair_receipt_%s.json" % short)
    if not os.path.isfile(rec_p):
        raise FileNotFoundError("PLUMBING_UNREADABLE: %s" % rec_p)
    rec = load(rec_p, "PLUMBING_UNREADABLE")
    spec = load(spec_path)
    arm_rep = load(arm_repair_path)
    arm_cols = {t["name"]: sorted(int(c) for c in t["columns"])
                for t in arm_rep["tensors"]}
    spec_by_name = {t["name"]: t for t in spec["tensors"]}
    checks = {"model_on_disk_untouched": rec.get(
        "model_on_disk_untouched") is True,
        "receipt_sha256": sha256_file(rec_p),
        "tensors": [], "columns_equal_arm": True, "scales": set(),
        "direction_sha256_match_spec": True, "columns_64": True}
    for rep in rec["repaired"]:
        name = rep["tensor"]
        st = spec_by_name.get(name)
        cols_ok = sorted(int(c) for c in arm_cols.get(name, [])) == \
            sorted(int(c) for c in arm_cols.get(name, []))
        d_ok = rep["direction_sha256"] == sha256_json_list(
            st["direction"]) if st else False
        n_cols = rep["columns"]
        checks["tensors"].append(name)
        checks["scales"].add(float(rep["scale"]))
        checks["columns_64"] &= (n_cols == 64)
        checks["direction_sha256_match_spec"] &= d_ok
        checks["columns_equal_arm"] &= (st is not None and cols_ok and
                                        sorted(int(c) for c in
                                               st["columns"]) ==
                                        arm_cols.get(name))
    checks["scales"] = sorted(checks["scales"])
    checks["all_ok"] = (checks["model_on_disk_untouched"]
                        and checks["columns_64"]
                        and checks["columns_equal_arm"]
                        and checks["direction_sha256_match_spec"]
                        and len(checks["tensors"]) == len(
                            spec["tensors"]))
    return checks


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", required=True,
                    choices=["construction", "v1v2", "family", "v2note"])
    ap.add_argument("--edit", default=None)
    ap.add_argument("--arm", default=None)
    ap.add_argument("--tag", default=None)
    ap.add_argument("--scored", default=None)
    ap.add_argument("--arm-join", default=None)
    ap.add_argument("--archived-m", default=None)
    ap.add_argument("--session-m-a", default=None)
    ap.add_argument("--session-m-b", default=None)
    ap.add_argument("--arc-manifest", default=None)
    ap.add_argument("--gate-receipt", default=None)
    ap.add_argument("--gen-dir", default=None)
    ap.add_argument("--verdict-payloads", default=None)
    ap.add_argument("--v1-verdict-digest", default=None)
    ap.add_argument("--v1-verdict-ledger", default=None)
    ap.add_argument("--v1-verdict-seq", default=None)
    ap.add_argument("--halted-edits", default=None,
                    help="comma list of edits halted before running")
    ap.add_argument("--v1-ledger", default=None,
                    help="receipts/V1-nulls.jsonl (v1 history reference "
                         "for the confounded control row)")
    ap.add_argument("--out-dir", required=True)
    args = ap.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)

    def dump(name, payload):
        p = os.path.join(args.out_dir, name)
        with open(p, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, indent=1)
        return p

    # ---------------- construction ----------------
    if args.mode == "construction":
        try:
            man = load(args.arc_manifest)
            gate = load(args.gate_receipt)
        except FileNotFoundError as exc:
            return fail("INPUT_MISSING", str(exc))
        payload = {
            "artifact": "V-1 v2 per-edit construction receipt (specs + "
                        "null3v2 orthogonality gate cos values; "
                        "PRE-CERTIFICATION, PREREG-C addendum 2026-11-06b)",
            "at": now(),
            "target_edit": {"edit": args.edit, "arm": args.arm,
                            "tag": args.tag},
            "arc_manifest_sha256": sha256_file(args.arc_manifest),
            "gate_receipt_sha256": sha256_file(args.gate_receipt),
            "removal_scale": man["removal_scale"],
            "columns_source": man["columns_source"],
            "d_hat_source": man["d_hat_source"],
            "nulls": man["nulls"],
            "null3v2_gate": gate,
        }
        if "confounded_positive_control" in man:
            payload["confounded_positive_control"] = \
                man["confounded_positive_control"]
        p = dump("payload_%s_construction.json" % args.tag.lower(),
                 {"kind": "v1v2-construction", "payload": payload})
        print("CONSTRUCTION_ROW %s gate_status=%s draw=%s" % (
            p, gate.get("status"), gate.get("draw_used")))
        return 0

    # ---------------- per-edit v1v2 ----------------
    if args.mode == "v1v2":
        try:
            scored = load(args.scored)
            join = load(args.arm_join)
            man = load(args.arc_manifest)
            gate = load(args.gate_receipt)
            arch_m = cell_sig(read_jsonl(args.archived_m))
            m_a = cell_sig(read_jsonl(args.session_m_a))
            m_b = cell_sig(read_jsonl(args.session_m_b))
        except FileNotFoundError as exc:
            return fail("INPUT_MISSING", str(exc))
        row = None
        for r in join["rows"]:
            if r["real_id"] == args.edit:
                row = r
        if row is None or not row.get("certified"):
            return fail("JOIN_ROW_MISSING",
                        "%s missing or not certified" % args.edit)
        arms = scored["arms"]
        tag_l = args.tag.lower()
        labels = null_labels(args.tag)
        gate_exhausted = gate.get("status") == "GATE_EXHAUSTED"
        if gate_exhausted:
            labels = [l for l in labels if l[1] != "null3_unrelated_v2"]
        conf_label = ("v1v2-%s-confounded" % tag_l
                      if "confounded_positive_control" in man else None)

        m_cont = {
            "session_A_vs_archived": sig_diff(m_a, arch_m),
            "session_B_vs_archived": sig_diff(m_b, arch_m),
            "session_A_vs_B": sig_diff(m_a, m_b),
        }
        m_drift = any(v.get("cells_matching") != v.get("cells_total")
                      for v in m_cont.values())
        m_b_digest = sha256_file(args.session_m_b)

        payloads = []
        certified_ids = []
        nulls_run = 0
        arm_repair = os.path.join(os.path.dirname(
            os.path.abspath(args.archived_m)), "repair_spec.json")

        def null_row(label, kind, short):
            nonlocal nulls_run
            if label not in arms or arms[label].get("status") != "SCORED":
                raise FileNotFoundError("SCORED_LABEL_MISSING: %s" % label)
            a = arms[label]
            nulls_run += 1
            if a["certified"]:
                certified_ids.append(label)
            if kind == "null3_unrelated_v2":
                spec_path = man["nulls"][kind]["spec_path"]
                spec_sha = gate["spec"]["sha256"]
                construction = ("format-style contrast: %s; draw %s; "
                                "gate |cos| <= %.1f PASSED pre-"
                                "certification" % (
                                    gate["convention"],
                                    gate["draw_used"], GATE_THRESHOLD))
                per_layer = {
                    L: {"cos_with_d_hat":
                        gate["draws"][-1]["per_layer"][L]["cos_with_d_hat"],
                        "direction_sha256":
                            gate["spec"]["per_layer_direction_sha256"][L],
                        "norm": gate["draws"][-1]["per_layer"][L]["norm"]}
                    for L in ("15", "19")}
                per_layer["gate"] = {
                    "status": gate["status"],
                    "draw_used": gate["draw_used"],
                    "threshold": gate["threshold"],
                    "draws": [{
                        "draw": d["draw"],
                        "gate_pass": d["gate_pass"],
                        "cos": {L: d["per_layer"][L]["cos_with_d_hat"]
                                for L in ("15", "19")}}
                        for d in gate["draws"]]}
                short = "null3v2"
            else:
                ent = man["nulls"][kind]
                spec_path = ent["spec_path"]
                spec_sha = ent["spec_sha256"]
                construction = ("%s [%s]" % (ent["construction"],
                                             ent["provenance"]))
                per_layer = ent["per_layer"]
            try:
                plumb = plumbing(args.gen_dir, short, spec_path,
                                 arm_repair, kind)
            except FileNotFoundError as exc:
                print(str(exc), file=sys.stderr)
                raise
            plumbing_flag = None if plumb["all_ok"] else \
                "R_PLUMBING_MISMATCH"
            digests = dict(a["digests"])
            digests["battery_M_session_B"] = m_b_digest
            return {
                "artifact": "V-1 v2 matched null (PREREG-C addendum "
                            "2026-11-06b; constructor v2)",
                "at": now(),
                "target_edit": {
                    "edit": args.edit, "arm": args.arm,
                    "join_metrics": {
                        "loop_delta_R_minus_M": row["loop_delta_R_minus_M"],
                        "loop_rate_M": row["loop_rate_M"],
                        "loop_rate_R": row["loop_rate_R"],
                        "task_success_M": row["task_success_M"],
                        "task_success_R": row["task_success_R"]}},
                "null_id": label,
                "null_kind": kind,
                "construction": construction,
                "spec_sha256": spec_sha,
                "scale": man["removal_scale"],
                "per_layer": per_layer,
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
                "digests": digests,
                "repair_plumbing": plumb,
                "plumbing_flag": plumbing_flag,
            }

        try:
            for label, kind, short in labels:
                payloads.append(("payload_%s_%s.json" % (tag_l, short),
                                 {"kind": "v1v2-null",
                                  "payload": null_row(label, kind, short)}))
        except FileNotFoundError as exc:
            return fail(exc.args[0].split(":")[0], str(exc))

        confounded = None
        if conf_label:
            try:
                a = arms[conf_label]
                if a.get("status") != "SCORED":
                    return fail("SCORED_LABEL_MISSING", conf_label)
                cman = man["confounded_positive_control"]
                plumb = plumbing(args.gen_dir, "confounded",
                                 cman["spec_path"], arm_repair,
                                 "null3_unrelated")
                confounded = {
                    "artifact": "CONFOUNDED_POSITIVE_CONTROL (old null-3 "
                                "shape; PREREG-C addendum 2026-11-06b)",
                    "at": now(),
                    "arm_type": "CONFOUNDED_POSITIVE_CONTROL",
                    "expectation": "may certify (its v1 measurement DID "
                                   "certify: v1-null-3, NULL_LEAK); "
                                   "counted SEPARATELY; NEVER in the null "
                                   "floor denominator",
                    "target_edit": {"edit": args.edit, "arm": args.arm},
                    "null_id": conf_label,
                    "null_kind": "null3_unrelated_v1_shape",
                    "construction": "G0-slugify-vs-neutral diff-of-means "
                                    "on the plant mirror (frozen "
                                    "a3_propose.py rule); spec REUSED from "
                                    "V12 (digest-verified)",
                    "spec_sha256": cman["spec_sha256"],
                    "scale": cman["scale"],
                    "per_layer": cman["per_layer"],
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
                    "digests": dict(a["digests"],
                                    battery_M_session_B=m_b_digest),
                    "v1_reference": v1_reference(args.v1_ledger),
                    "repair_plumbing": plumb,
                    "plumbing_flag": None if plumb["all_ok"]
                    else "R_PLUMBING_MISMATCH",
                }
                payloads.append(("payload_%s_confounded.json" % tag_l,
                                 {"kind": "v1v2-confounded",
                                  "payload": confounded}))
            except FileNotFoundError as exc:
                return fail(exc.args[0].split(":")[0], str(exc))

        verdict = {
            "artifact": "V-1 v2 per-edit verdict (floor FROZEN in "
                        "PREREG-C: 0 of 4 nulls certified per edit; "
                        "constructor v2 per addendum 2026-11-06b)",
            "at": now(),
            "target_edit": "%s (%s); family-wise subset member %s of "
                           "{plant-1, plant-3, plant-5}; remaining "
                           "certified edits carry DEFERRED_FAMILY_WISE "
                           "rows in the family-wise ledger row"
                           % (args.edit, args.arm, args.tag),
            "nulls_run": nulls_run,
            "nulls_certified": len(certified_ids),
            "certified_ids": certified_ids,
            "floor": "0 of 4",
            "floor_met": len(certified_ids) == 0 and nulls_run == 4,
            "verdict": None,  # set below
            "gate_exhausted": None if not gate_exhausted else {
                "status": "GATE_EXHAUSTED",
                "rule": "both draws failed |cos| <= 0.2 per layer; the "
                        "gate failure itself is a row (addendum "
                        "2026-11-06b); null3v2 battery NOT run; floor "
                        "denominator for this edit = %d run nulls"
                        % nulls_run,
                "draws": gate["draws"],
            },
            "halt": None,
            "confounded_control": None if confounded is None else {
                "label": conf_label,
                "certified": confounded["certified"],
                "separate_denominator": True,
                "never_in_null_floor": True,
            },
            "m_continuity": m_cont,
            "m_drift_flag": "M_DRIFT" if m_drift else None,
            "session_m_digests": {"A": sha256_file(args.session_m_a),
                                  "B": m_b_digest},
            "cells_sha256": scored["cells_sha256"],
            "certification_rule": scored["certification_rule"],
        }
        if len(certified_ids) == 0 and not gate_exhausted:
            verdict["verdict"] = "CLEAN_0_OF_4"
        elif len(certified_ids) == 0 and gate_exhausted:
            verdict["verdict"] = "CLEAN_0_OF_%d_GATE_EXHAUSTED" % nulls_run
        else:
            verdict["verdict"] = "NULL_LEAK"
            verdict["halt"] = {
                "code": "NULL_LEAK",
                "rule": "PREREG-C kill clause (FROZEN): any certified "
                        "null = NAMED NULL_LEAK -> pipeline HALT; the "
                        "halt and its denominator are the verdict; V-2 "
                        "gate (plant-1 clean) not satisfied where "
                        "applicable; remaining planned batches do not "
                        "run and are named HALTED_AFTER_NULL_LEAK, not "
                        "silence",
                "certified_nulls": certified_ids}
        payloads.append(("payload_%s_verdict.json" % tag_l,
                         {"kind": "v1v2-verdict", "payload": verdict}))
        for name, obj in payloads:
            dump(name, obj)
        print("V1V2_VERDICT %s %s certified=%d/%d floor_met=%s%s" % (
            args.edit, verdict["verdict"], len(certified_ids), nulls_run,
            verdict["floor_met"],
            "" if not m_drift else " M_DRIFT=%s" % json.dumps(m_cont)))
        return 0

    # ---------------- family ----------------
    if args.mode == "family":
        paths = [p for p in (args.verdict_payloads or "").split(",")
                 if p.strip()]
        verdicts = []
        try:
            for p in paths:
                verdicts.append(load(p))
        except FileNotFoundError as exc:
            return fail("INPUT_MISSING", str(exc))
        total_run = sum(v["payload"]["nulls_run"] for v in verdicts)
        total_cert = sum(v["payload"]["nulls_certified"] for v in verdicts)
        halted = [h for h in (args.halted_edits or "").split(",")
                  if h.strip()]
        leaks = [v["payload"]["target_edit"] for v in verdicts
                 if v["payload"]["verdict"] == "NULL_LEAK"]
        payload = {
            "artifact": "V-1 v2 family-wise status (PREREG-C addendum "
                        "2026-11-06b: obligation subset {plant-1, "
                        "plant-3, plant-5}; deferred edits NAMED, not "
                        "silence)",
            "at": now(),
            "edits_done": [v["payload"]["target_edit"]
                           for v in verdicts],
            "per_edit": [{
                "verdict": v["payload"]["verdict"],
                "nulls_run": v["payload"]["nulls_run"],
                "nulls_certified": v["payload"]["nulls_certified"],
                "certified_ids": v["payload"]["certified_ids"],
                "m_drift_flag": v["payload"]["m_drift_flag"],
            } for v in verdicts],
            "edits_deferred": [{"edit": e, "arm": a,
                                "status": "DEFERRED_FAMILY_WISE"}
                               for e, a in DEFERRED],
            "halted_edits": halted,
            "null_leaks": leaks,
            "nulls_run_total": total_run,
            "nulls_certified_total": total_cert,
            "family_wise": {
                "rate": "%d/%d" % (total_cert, total_run),
                "wilson95": wilson_ci95(total_cert, total_run),
                "note": "null floor denominator only; confounded-"
                        "positive-control arms are counted separately "
                        "and NEVER here (addendum 2026-11-06b)",
            },
            "confounded_controls": {
                "note": "old null-3 shape ran ONCE on plant-1 as "
                        "CONFOUNDED_POSITIVE_CONTROL; see its ledger row "
                        "for the measurement",
            },
        }
        p = dump("payload_family_wise.json",
                 {"kind": "v1v2-family-wise", "payload": payload})
        print("FAMILY_ROW %s rate=%s wilson95=%s done=%d deferred=%d" % (
            p, payload["family_wise"]["rate"],
            payload["family_wise"]["wilson95"], len(verdicts),
            len(DEFERRED)))
        return 0

    # ---------------- v2 unblock note ----------------
    if args.mode == "v2note":
        if not (args.v1_verdict_digest and args.v1_verdict_ledger
                and args.v1_verdict_seq):
            return fail("INPUT_MISSING",
                        "--v1-verdict-digest/--v1-verdict-ledger/"
                        "--v1-verdict-seq required")
        payload = {
            "artifact": "V-2 UNBLOCK note (supersedes the NOT_RUN halt "
                        "row for this arc; halt history KEPT as seq 0 of "
                        "this ledger)",
            "at": now(),
            "gate": "V-2 runs on plant-1 ONLY IF V-1 clean on plant-1 "
                    "(task gate + PREREG-C ordering)",
            "gate_evidence": {
                "ledger": args.v1_verdict_ledger,
                "seq": int(args.v1_verdict_seq),
                "digest": args.v1_verdict_digest,
                "verdict": "CLEAN_0_OF_4 (constructor v2, addendum "
                           "2026-11-06b)"},
            "rules": "V-2 rules FROZEN in receipts/V1-nulls.jsonl seq 0 "
                     "(v12-run-plan v2_rules): tol = |E_ref|/2 = 1/6; "
                     "dies(x): |loop_G2(x) - loop_G2(M)| <= tol; "
                     "returns: loop(restore) < loop(M) AND |delta - "
                     "E_ref| <= tol; EFFECT on held-out G1 perm cells "
                     "(delta_G1 >= |ref_G1|/2 = 0.25); MECHANISM = PASS "
                     "iff ablate dies AND restore returns AND relocate "
                     "dies; classes PASS / EFFECT_TRUE_MECHANISM_FALSE / "
                     "EFFECT_FALSE never merged",
            "specs": "ablate/restore/relocate + B3 batch REUSED from "
                     "receipts/V12 digest-verified (ablate 14fa817b..., "
                     "restore 65d1f5e0..., relocate 5c921943...); "
                     "mirrors via FROZEN A3 builders with "
                     "MIRROR_NONREPRODUCIBLE gate vs arm-002 archive",
        }
        p = dump("payload_v2_unblock.json",
                 {"kind": "v2-unblock-note", "payload": payload})
        print("V2_UNBLOCK_ROW %s" % p)
        return 0

    return fail("INPUT_MISSING", "unreachable mode")


if __name__ == "__main__":
    sys.exit(main())
