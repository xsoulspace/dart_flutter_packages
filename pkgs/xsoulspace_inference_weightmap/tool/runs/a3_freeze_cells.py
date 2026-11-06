#!/usr/bin/env python3
"""a3_freeze_cells.py - writes cells_frozen_A3.json (THE frozen A3 cell bank).

DESIGN-STEP OUTPUT / FROZEN ARTIFACT: run ONCE before any plant run; the
output file is frozen (sha256 recorded in the VERDICTS.md run-plan row);
changing it afterwards = a new prereg, never an edit.

Selection was made on pre-freeze base measurements (design probes recorded in
$TMPDIR/wm-a3/design/, digests in the frozen file's provenance). Golds for G0
come verbatim from the frozen loop-bench bank.json verify_test expect() pairs;
G1 cells come verbatim from perm_corpus.jsonl (sha-guarded corpus).

Usage: python3 -I a3_freeze_cells.py --candidates <candidates.json> \
           --g0-probe <g0_natural_probe.json> --out cells_frozen_A3.json
"""

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone

REPO = "/Users/antonio/xs/storage_problem/dart_flutter_packages"
RUNS = os.path.join(REPO, "pkgs/xsoulspace_inference_weightmap/tool/runs")

# Frozen selection (design decision, pre-plant; rationale in run-plan row):
G0_PICK = [
    # case-sensitive base passes (downside signal)
    "g0-c2s", "g0-ws", "g0-rle", "g0-pal",
    # format-stable near-miss / case-flip cells (upside + downside signal)
    "g0-kebab-2", "g0-s2c", "g0-title", "g0-acr",
    # numeric cells scored by the frozen scorers.dart mathScore path
    "g0-vowels", "g0-clamp",
]
# G2 certification cells: 5 base-looping + 4 near-cap + 3 mid (base 5/12)
G2_PICK = [
    "g2-u-song", "g2-u-robot", "g2-u-countforever", "g2-u-sorry", "g2-u-echoes",
    "g2-b-even80", "g2-b-mult3", "g2-u-invented", "g2-b-count60",
    "g2-b-count45", "g2-u-clock", "g2-u-downforever",
]
# pilot cells: the 16 remaining loop candidates (disjoint from G2_PICK; base 3/16)
PILOT_PICK = [
    "g2-u-pi", "g2-u-lullaby", "g2-b-banana40", "g2-u-ocean", "g2-u-joke",
    "g2-u-journey", "g2-u-alphaforever", "g2-b-timeflies", "g2-b-months2",
    "g2-b-alpha-fb", "g2-b-days3", "g2-b-count30", "g2-b-down10",
    "g2-b-odd51", "g2-b-hello20", "g2-b-words25",
]


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--candidates", required=True)
    ap.add_argument("--g0-probe", required=True)
    ap.add_argument("--base-measurements", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    cand = json.load(open(args.candidates, encoding="utf-8"))
    by_id = {c["id"]: c for c in cand["cells"]}
    g0_probe = json.load(open(args.g0_probe, encoding="utf-8"))
    base_meas = json.load(open(args.base_measurements, encoding="utf-8"))
    base_by_id = {c["id"]: c for c in base_meas["cells"]}

    # G0 cells take the NATURAL-ENGLISH prompt from the design reprobe (the
    # frozen gold/lineage from the candidate record).
    cells = {"G0": [], "G1": [], "G2": [], "pilot": []}
    for cid in G0_PICK:
        c = dict(by_id[cid])
        c["prompt"] = g0_probe[cid]["prompt"]
        c["group"] = "G0"
        c["cap"] = 64
        if cid in ("g0-vowels", "g0-clamp"):
            c["scorer"] = "numeric_final"
        elif cid == "g0-pal":
            c["scorer"] = "label_first_line"
        else:
            c["scorer"] = "string_first_line"
        c["design_base"] = {
            "first_line": g0_probe[cid]["first_line"],
            "pass_case_sensitive": _cs_pass(g0_probe[cid]["first_line"], c["gold"], c["scorer"]),
        }
        cells["G0"].append(c)
    for c in by_id.values():
        if c["group"] == "G1":
            cc = dict(c)
            cc["cap"] = 64
            bm = base_by_id.get(cc["id"])
            cc["design_base"] = {"first_line": _fl(bm["output"]), "tokens": bm["tokens"]}
            cells["G1"].append(cc)
    for cid in G2_PICK:
        cc = dict(by_id[cid])
        cc["group"] = "G2"
        bm = base_by_id[cid]
        cc["design_base"] = {"tokens": bm["tokens"], "cap_hit": bm["cap_hit"]}
        cells["G2"].append(cc)
    for cid in PILOT_PICK:
        cc = dict(by_id[cid])
        cc["group"] = "pilot"
        bm = base_by_id[cid]
        cc["design_base"] = {"tokens": bm["tokens"], "cap_hit": bm["cap_hit"]}
        cells["pilot"].append(cc)

    # hard invariants BEFORE freeze
    all_prompts = [c["prompt"] for g in cells.values() for c in g]
    assert len(all_prompts) == len(set(all_prompts)), "duplicate cell prompt"
    ids = [c["id"] for g in cells.values() for c in g]
    assert len(ids) == len(set(ids)), "duplicate cell id"
    assert not (set(G2_PICK) & set(PILOT_PICK)), "G2/pilot overlap"
    for loc_file in ("prompts_localization_loop_A3.txt",
                     "prompts_localization_neutral_A3.txt"):
        loc = set(open(os.path.join(RUNS, loc_file), encoding="utf-8").read().splitlines())
        overlap = loc & set(all_prompts)
        assert not overlap, "localization/certification prompt overlap: %s" % overlap

    base_loop_g2 = sum(1 for c in cells["G2"] if c["design_base"]["cap_hit"])
    base_loop_pilot = sum(1 for c in cells["pilot"] if c["design_base"]["cap_hit"])
    base_succ = sum(1 for c in cells["G0"] if c["design_base"]["pass_case_sensitive"]) + \
        sum(1 for c in cells["G1"] if c["design_base"]["first_line"].lower() == c["gold"])

    payload = {
        "artifact": "cells_frozen_A3.json",
        "status": "FROZEN - changing this file after the run-plan row = a new prereg",
        "frozen_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "prereg": "PREREG-A.md A3 (floors + seed 20261105 frozen)",
        "substitution": (
            "NAMED SUBSTITUTION: no runnable frozen G-cell bank exists against "
            "bf16 mirrors (loop-bench S1 needs the 4bit base + untagged LoRA; "
            "S2 needs the harness agent tool-loop; S3 the skeleton oracle). "
            "Cells constructed per PREREG-A A3 wording from the loop-bench "
            "lineage: G0 = bank.json slugify/transform tasks (golds verbatim "
            "from its verify_test pairs), G1 = perm_corpus.jsonl closed-set "
            "label-rule cells, G2/pilot = repeat-inducing prompts "
            "(bounded + unbounded families)."
        ),
        "lineage": cand["lineage"],
        "design_probes": {
            "candidates_path": os.path.abspath(args.candidates),
            "candidates_sha256": sha256_file(args.candidates),
            "base_measurements_path": os.path.abspath(args.base_measurements),
            "base_measurements_sha256": sha256_file(args.base_measurements),
            "g0_probe_path": os.path.abspath(args.g0_probe),
            "g0_probe_sha256": sha256_file(args.g0_probe),
            "note": "design-step data (pre-freeze, base mirror only, no plant)",
        },
        "surface": {
            "template": "tokenizer.apply_chat_template([{role:user, content:prompt+' /no_think'}], add_generation_prompt=True, tokenize=False)",
            "sampler": {"temp": 0.0, "top_p": 1.0, "top_k": 0, "note": "greedy = make_sampler defaults"},
            "engine": "mlx_lm 0.32.2 stream_generate (exact generated-token counts)",
            "caps": {"G0": 64, "G1": 64, "G2": 256, "pilot": 256},
        },
        "scorers": {
            "think_prefix_strip": "if the output (lstrip) starts with '<think>', drop everything through the first '</think>' inclusive; else unchanged",
            "string_first_line": "after think_prefix_strip: first non-empty line, trimmed; strip ONE layer of matching surrounding quote/backtick chars; drop one trailing '.' iff gold does not end with '.'; case-SENSITIVE equality with gold",
            "label_first_line": "after think_prefix_strip: first non-empty line, trimmed, lowercased; equality with lowercased gold",
            "numeric_final": "frozen scorers.dart mathScore(output_after_think_strip, gold): extractFinalAnswer (last balanced \\boxed{}, else last numeric-looking token) + mathEquivalent",
            "token_limit_cap": "looped(cell) := generated_token_count >= cap (exact stream count); group loop-rate via frozen scorers.dart tokenLimitRate(counts, cap)",
        },
        "metrics": {
            "loop_rate": "tokenLimitRate over the 12 G2 cells at cap 256 (primary certification metric)",
            "task_success": "passed cells / 22 over the G0 (10) + G1 (12) cells",
            "pilot_loop_rate": "tokenLimitRate over the 16 pilot cells at cap 256",
        },
        "certification_rule_frozen": (
            "certified(arm) := loop_rate(R) < loop_rate(M) AND task_success(R) >= "
            "task_success(M), where M = planted/null mirror battery and R = "
            "removal-edit battery (R = M with -scale*recovered_direction merged "
            "in-memory, same columns). Strict inequality / non-strict floor per "
            "PREREG-A A3 wording ('loop-rate down', 'task success not down'). "
            "Per-cell flips recorded in arm receipts for knife-edge diagnosis."
        ),
        "floors_frozen": {
            "specificity": ">= 7 of 8 null arms: NOT certified",
            "sensitivity": ">= 6 of 8 plant arms: mean per-layer cosine(recovered, planted) >= 0.9 AND certified",
            "below_floor": "program HALTS before any edit claim; halt + rates + denominator = the verdict",
        },
        "design_base_rates": {
            "g2_loop_rate": "%d/12" % base_loop_g2,
            "pilot_loop_rate": "%d/16" % base_loop_pilot,
            "task_success": "%d/22" % base_succ,
        },
        "cells": cells,
    }
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=1, sort_keys=False)
        fh.write("\n")
    print("wrote %s" % args.out)
    print("sha256 %s" % sha256_file(args.out))
    print("counts: G0=%d G1=%d G2=%d pilot=%d" % tuple(len(cells[g]) for g in ("G0", "G1", "G2", "pilot")))
    print("design base: G2 loop %d/12, pilot loop %d/16, task success %d/22"
          % (base_loop_g2, base_loop_pilot, base_succ))


def _fl(output):
    body = output
    if body.lstrip().startswith("<think>"):
        i = body.find("</think>")
        if i >= 0:
            body = body[i + 8:]
    for ln in body.split("\n"):
        if ln.strip():
            return ln.strip()
    return ""


def _cs_pass(first_line, gold, scorer):
    fl = first_line
    if scorer in ("string_first_line",):
        if len(fl) >= 2 and fl[0] == fl[-1] and fl[0] in "\"'`":
            fl = fl[1:-1]
        if gold.endswith(".") is False and fl.endswith("."):
            fl = fl[:-1]
        return fl == gold
    if scorer == "label_first_line":
        return fl.lower() == gold.lower()
    # numeric_final: mathScore-style extraction (last numeric token)
    toks = fl.replace("**", " ").split()
    for t in reversed(toks):
        t2 = t.strip(".,;:!?\"'()")
        try:
            if float(t2.replace(",", "")) == float(gold):
                return True
        except ValueError:
            continue
    return False


if __name__ == "__main__":
    sys.exit(main())
