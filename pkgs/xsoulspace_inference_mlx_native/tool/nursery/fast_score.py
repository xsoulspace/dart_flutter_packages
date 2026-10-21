"""Fast, CPU-only, PARALLEL re-scoring of cached adapter completions.

WHY THIS EXISTS. The K' gates are questions about a COMPLETION SET, not about
the model: strict-vs-legacy scoring (K'-G1), the trivial baseline (K'-G6),
the prediction histogram (K'-G5), cross-task damage. Every one of those is a
pure function of (a) the per-item completions and (b) the task corpus. The
completions are ALREADY persisted per cell by `adapter_conditioning.py`
(`save_completions`), one JSONL per (arm, task).

So re-asking a scoring question does not need the GPU. It needs the JSONL.
Re-running the model to change a scorer costs ~18 minutes of training per
arm; replaying the completions costs seconds. This tool makes that split
explicit and executable:

  TIER 0 (GPU, serial, ~18 min/arm): train the adapter, cache completions.
  TIER 1 (CPU, parallel, <5 s/cell):  answer EVERY gate question.

A cell is a (arm, task) pair; cells are independent, so they fan out across
processes. On this box the GPU is saturated, so TIER 1 is the only lane that
can actually run in parallel right now.

WHAT IT ANSWERS PER CELL (this is the "fat" part — many readings per pass):

  - strict and legacy accuracy, and the ITEM-LEVEL DISAGREEMENT between them
    (the C-4 defect class: a bare substring search matching `abandoned` ->
    `done`). The disagreeing items are printed with their completions, so a
    NEW scoring artifact is visible before it becomes a verdict.
  - the trivial baseline computed ON THE SCORED ROWS — taken from the CACHE's
    own `gold` labels, so the baseline and the accuracy are over one sample
    set BY CONSTRUCTION. The run computes its baseline over ALL test rows
    while scoring only the first `eval_limit` rows; the two are different
    sample sets, so the reported "delta vs trivial" mixes them. This tool
    reports the matched baseline, and it also re-derives the run's split as
    a CROSS-CHECK only (see `row_check`), never as the source of truth.
  - prediction histogram + top-label concentration (K'-G5).
  - outside-label-set count (a cell that answers outside the legal labels).
  - a SHADOWED-LABEL audit: for every legal label, which other legal labels
    are substrings of it. A label set where `action` is a substring of
    `satisfaction` is a scorer waiting to fail.
  - a TRUNCATION audit: the cached completion is capped at 200 chars, so
    re-deriving the label from it can disagree with the label the run scored.
    Any disagreement is reported rather than silently absorbed.
  - a PAIRED comparison between arms (McNemar, exact two-sided): the
    control-arm question ("is the tag load-bearing?") is a question about
    DIFFERENCES on the same items, and a difference of 8/150 items is not
    a signal at one seed unless the paired test says so.

COMPLETENESS. The arm set this tool expects is reported against the arms
actually present, so a missing control arm is visible instead of silent.
The Part 4 CLOSING arms (`fewshot`, `noise`, `ranked`) are reported in
their own line: a closing gate that was never run is not a gate that
passed, and the gates themselves report `missing_arm` rather than a
verdict.

COVERAGE (L-G3, 2026-10-21). Every number this tool emits carries its
coverage (`scored_rows / corpus_rows`). A number whose coverage is below
1.0 is labelled `partial` and is NOT a gate input, in either direction:
it cannot pass, fail, hit or miss a gate, and it cannot move a threshold.
`--eval-rows {150,all}` chooses how many cached rows per cell to score;
'150' is the historical prefix and the default, 'all' is the only coverage
that can gate. The trivial baseline is always taken from the CACHE'S OWN
gold over exactly the rows that were scored.

THE CONTRACT STRING was bumped from `nursery.fast-score.manifest.v1` to
`nursery.fast-score.manifest.v2` (and the payload from
`nursery.fast-score.v2` to `nursery.fast-score.v3`) because the cell shape
gained the coverage annotation and the foreign-label leak count, and the
payload gained the Part 4 gate matrix. The NUMBERS are unchanged: the
refactor that moved the rules into `scoring.py` reproduced every cell
accuracy, every matched baseline, the whole K'-gate matrix and every
control-arm reading exactly.

PROVENANCE. `--manifest` writes a sha256 per cell plus the corpus digests
and the row identity, so a later reader can prove they re-derived the same
observations rather than a similar-looking set.

USAGE

    python tool/nursery/fast_score.py --completions /tmp/adapter_conditioning/completions
    python tool/nursery/fast_score.py --completions <dir> --jobs 8 --out gates.json
    python tool/nursery/fast_score.py --completions <dir> --audit --limit 12
    python tool/nursery/fast_score.py --completions <dir> --manifest manifest.json

The K'-G1..G6 gate matrix is evaluated with `adapter_conditioning.evaluate_gates`
— the SAME function the training run uses — so there is one gate definition,
not two. This tool only rebuilds its inputs from the cache.

ONE GAP THIS TOOL ALSO READS (the control arms). `evaluate_gates` reads the
`cond` arm ONLY. The run also trains `untagged` (both tasks, NO tag) and
`permsolo` (perm only, no tag) — the arms whose entire purpose is to isolate
the TAG from the multi-task training data. Those two cells are computed and
scored, but no gate reads them, so the pre-registered reading "selectivity IS
recoverable BY CONDITIONING" is unfalsifiable as encoded: an `untagged` arm
that scored the same would say the tag is not what worked, and the reading
would not notice. This tool reports the control comparison separately so the
reading can be checked against it. It does NOT change `evaluate_gates` — the
gate definition stays frozen; this is the evidence the reading needs.
"""

import argparse
import hashlib
import json
import math
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import adapter_conditioning as ac  # noqa: E402

# ONE definition of every scoring rule (C-4, C-11, META-LESSONS 18). This
# tool used to carry its OWN copies of the label extractors, the trivial
# baseline and McNemar, while `adapter_conditioning.py` carried another copy.
# Two copies of a rule is a correctness hazard: the lane already paid once
# for a bare-substring scorer that scored `abandoned` as `done`. Every rule
# now lives in `tool/nursery/scoring.py` and both tools import it.
from scoring import (  # noqa: E402
    coverage_annotation,
    evaluate_gates,
    evaluate_part4_gates,
    mcnemar,
    score_items,
    shadowed_labels,
    trivial_from_items,
    trivial_on_scored_rows,
)

# The arms `adapter_conditioning.main` defines. Kept here as a constant (not
# imported) so this tool can report a MISSING arm without running the trainer.
EXPECTED_ARMS = ("base", "cond", "untagged", "permsolo", "shared")

# The Part 4 CLOSING arms (MTP-GATES.md Part 4). They are reported
# SEPARATELY from EXPECTED_ARMS: the K' matrix is a fixed set, and the
# closing arms are the ones that can END the line. Their absence is printed
# loudly, because "the gate arm was never run" must not look like "the gate
# arm was not needed".
CLOSING_ARMS = ("fewshot", "noise", "ranked")

# The arms the frozen gate reads, and each control arm's REFERENCE arm.
#
# The reference is per-control on purpose: a control isolates ONE variable, so
# it must be compared against the arm that differs from it by exactly that
# variable.
#   untagged vs cond     -> isolates the TAG (same two-task training)
#   permsolo vs cond     -> isolates the SECOND TASK'S DATA (and the tag)
#   shared   vs untagged -> isolates the OPTION LIST (both untagged, both tasks)
# Comparing `shared` against `cond` would conflate the option list with the
# tag, which is the mistake this table exists to prevent.
GATE_ARM = "cond"
CONTROL_ARMS = {
    "untagged": "cond",
    "permsolo": "cond",
    "shared": "untagged",
}


def load_cell(path):
    """One cell = the per-item completions of one (arm, task) pair."""
    items = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if line:
                items.append(json.loads(line))
    return items


def score_cell(items, labels, other_labels=(), corpus_rows=None):
    """Re-score a cell and collect every reading the gates need.

    A thin wrapper over `scoring.score_items` — the rule lives in ONE place.
    """
    return score_items(
        items, labels, other_labels=other_labels, corpus_rows=corpus_rows
    )


def file_digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _work(job):
    """One cell, in a worker process."""
    arm, task, path, eval_limit, seed, rows_limit, all_labels = job
    labels = ac.TASKS[task]["labels"]
    # The legal labels of the OTHER tasks: a prediction in that set, on a row
    # of THIS task, is a FOREIGN-LABEL LEAK (L-G7).
    other = [l for t, ls in all_labels.items() if t != task for l in ls]
    items = load_cell(path)
    cache_n = len(items)
    if rows_limit is not None:
        items = items[:rows_limit]
    # The MATCHED baseline: the cache's own scored rows.
    matched = trivial_from_items(items, labels)
    # The re-derived split is a CROSS-CHECK, not the source of the baseline.
    # It also supplies the SIZE of the scored split, which the coverage
    # annotation needs — but only if the re-derivation actually matches the
    # cache. If it does not, the split size is not trustworthy, so the
    # coverage is UNKNOWN (and an unknown coverage is partial: it cannot
    # gate anything).
    corpus_rows = None
    try:
        rows = ac.split_rows(ac.load_task(task), holdout=0.25, seed=seed)[1]
        rederived = rows[: len(items)]
        rederived_trivial = trivial_on_scored_rows(rederived, labels)
        ids_match = [i.get("id") for i in items] == [r["id"] for r in rederived]
        gold_match = [i.get("gold") for i in items] == [r["kind"] for r in rederived]
        row_check = {
            "rederived_n": len(rederived),
            "cache_n": len(items),
            "cache_rows_on_disk": cache_n,
            "scored_split_rows": len(rows),
            "ids_match": ids_match,
            "gold_match": gold_match,
            "rederived_strongest_trivial": rederived_trivial["strongest_trivial"],
            "cache_strongest_trivial": matched["strongest_trivial"],
        }
        row_check["baseline_agrees"] = (
            abs(
                row_check["rederived_strongest_trivial"]
                - row_check["cache_strongest_trivial"]
            )
            < 1e-9
        )
        if ids_match:
            corpus_rows = len(rows)
    except Exception as exc:  # noqa: BLE001 - the cross-check must never
        # take down the measurement it is checking.
        row_check = {"error": f"{type(exc).__name__}: {exc}"}
    cell = score_cell(items, labels, other_labels=other, corpus_rows=corpus_rows)
    cell["_disagree"] = cell["_disagree"][:12]
    return {
        "arm": arm,
        "task": task,
        "path": path,
        "cell": cell,
        "matched_trivial": matched,
        "shadowed_labels": shadowed_labels(labels),
        "row_check": row_check,
    }


def collect(completions_dir):
    """Find the cells: `<arm>__<task>.jsonl`."""
    found = []
    for name in sorted(os.listdir(completions_dir)):
        if not name.endswith(".jsonl"):
            continue
        stem = name[: -len(".jsonl")]
        if "__" not in stem:
            continue
        arm, task = stem.split("__", 1)
        if task not in ac.TASKS:
            continue
        found.append((arm, task, os.path.join(completions_dir, name)))
    return found


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument(
        "--completions", required=True, help="directory of <arm>__<task>.jsonl"
    )
    ap.add_argument("--out", default=None, help="write the full JSON here")
    ap.add_argument("--manifest", default=None, help="write a provenance manifest here")
    ap.add_argument("--jobs", type=int, default=8)
    ap.add_argument(
        "--eval-limit",
        type=int,
        default=150,
        help="the run's eval limit; used ONLY to cross-check the re-derived "
        "split against the cache, never to source the baseline",
    )
    ap.add_argument(
        "--eval-rows",
        choices=["150", "all"],
        default="150",
        help=(
            "L-G3 (coverage completeness): how many cached rows per cell to "
            "SCORE. '150' is the historical prefix and the default, for "
            "reproducibility; 'all' scores every cached row, which is the "
            "only coverage that can be a GATE INPUT. A number whose coverage "
            "is below 1.0 is labelled 'partial' and cannot pass, fail, hit or "
            "miss a gate."
        ),
    )
    ap.add_argument(
        "--seed", type=int, default=0, help="the run's seed (cross-check only)"
    )
    ap.add_argument("--audit", action="store_true", help="print disagreeing items")
    ap.add_argument("--limit", type=int, default=12, help="items printed per cell")
    args = ap.parse_args(argv)

    t0 = time.perf_counter()
    cells = collect(args.completions)
    if not cells:
        print(f"no cells found in {args.completions}")
        return 1

    rows_limit = 150 if args.eval_rows == "150" else None
    # The legal labels of the tasks IN THIS RUN. A leak is an answer in
    # another task's vocabulary — a task that is not in this run is not in
    # the answer space, so its labels must not be counted as leaks.
    tasks_present = sorted({task for _arm, task, _path in cells})
    all_labels = {t: ac.TASKS[t]["labels"] for t in tasks_present}
    jobs = [
        (arm, task, path, args.eval_limit, args.seed, rows_limit, all_labels)
        for arm, task, path in cells
    ]
    results = []
    if args.jobs > 1 and len(jobs) > 1:
        with ProcessPoolExecutor(max_workers=args.jobs) as pool:
            results = list(pool.map(_work, jobs))
    else:
        results = [_work(j) for j in jobs]
    elapsed = time.perf_counter() - t0

    # Rebuild the shape `evaluate_gates` expects, with the MATCHED baselines.
    base_cells = {}
    arm_cells = {}
    matched_baselines = {}
    per_item_by = {}
    for r in results:
        if r["arm"] == "base":
            base_cells[r["task"]] = r["cell"]
        else:
            arm_cells.setdefault(r["arm"], {})[r["task"]] = r["cell"]
        matched_baselines[r["task"]] = r["matched_trivial"]
        per_item_by[(r["arm"], r["task"])] = r["cell"]["_per_item"]

    arms_present = sorted({r["arm"] for r in results})
    arms_missing = [a for a in EXPECTED_ARMS if a not in arms_present]
    closing_present = [a for a in CLOSING_ARMS if a in arms_present]
    closing_missing = [a for a in CLOSING_ARMS if a not in arms_present]

    print("=" * 78)
    print("PER-CELL READINGS (CPU replay; no GPU)")
    print("=" * 78)
    for r in results:
        c = r["cell"]
        m = r["matched_trivial"]
        cov = c.get("coverage") or {}
        flag = "  *** PARTIAL COVERAGE ***" if cov.get("partial") else ""
        print(
            f"{r['arm']:>10} / {r['task']:<7} n={c['n']:<4} "
            f"strict {c['accuracy']:.4f} | legacy {c['accuracy_legacy_scorer']:.4f} "
            f"| scorer-disagree {c['scorer_disagreements']:<3} "
            f"| outside {c['outside_label_set']:<3} "
            f"| leak {c.get('foreign_label_leak', 0):<3} "
            f"| top-label {c['top_label_concentration']:.3f} "
            f"| trunc-drift {c['truncation_drift']}"
        )
        print(
            f"{'':>10}   trivial(matched, n={m['n']}) {m['strongest_trivial']:.4f} "
            f"(majority {m['majority_accuracy']:.4f} / first {m['first_option_accuracy']:.4f}) "
            f"| delta {c['accuracy'] - m['strongest_trivial']:+.4f} "
            f"| coverage {c['n']}/{cov.get('corpus_rows')} = {cov.get('coverage')}"
            f"{flag}"
        )
        rc = r.get("row_check") or {}
        if rc.get("ids_match") is False:
            print(
                f"{'':>10}   ROW-CHECK MISMATCH: the re-derived split does not "
                f"match the cache (cache n={rc.get('cache_n')}, re-derived "
                f"n={rc.get('rederived_n')}). The cache is the authority; the "
                f"re-derivation is stale."
            )
        if r["shadowed_labels"]:
            pairs = ", ".join(
                f"{s['label']}~{s['contains']}" for s in r["shadowed_labels"]
            )
            print(f"{'':>10}   SHADOWED LABELS: {pairs}")
        if args.audit and c["_disagree"]:
            for d in c["_disagree"][: args.limit]:
                print(
                    f"{'':>12} gold={d['gold']:<18} strict={d['strict']:<12} "
                    f"legacy={d['legacy']:<12} {d['completion'][:60]!r}"
                )

    gates = evaluate_gates(
        {"base": base_cells, "arms": {a: {"cells": c} for a, c in arm_cells.items()}},
        matched_baselines,
        sorted(matched_baselines),
    )
    print()
    print("=" * 78)
    print(
        "K'-GATE MATRIX (matched baselines; evaluate_gates, the same function the run uses)"
    )
    print("=" * 78)
    print(json.dumps(gates, indent=2))

    # ---- the control arms: what is actually load-bearing? ----
    # `evaluate_gates` reads `cond` only. Each control arm isolates ONE
    # variable against its reference arm; if the control matches the
    # reference, that variable is not what worked.
    controls = {}
    for ctl, ref in CONTROL_ARMS.items():
        if ctl not in arm_cells or ref not in arm_cells:
            continue
        cmp = {}
        for task in sorted(matched_baselines):
            c = arm_cells[ref].get(task)
            k = arm_cells[ctl].get(task)
            if not c or not k:
                continue
            test = mcnemar(
                per_item_by.get((ref, task), []),
                per_item_by.get((ctl, task), []),
            )
            cmp[task] = {
                "reference": ref,
                "reference_accuracy": c["accuracy"],
                "control": ctl,
                "control_accuracy": k["accuracy"],
                "reference_minus_control": c["accuracy"] - k["accuracy"],
                "trivial": matched_baselines[task]["strongest_trivial"],
                "control_vs_trivial": k["accuracy"]
                - matched_baselines[task]["strongest_trivial"],
                "control_beats_trivial": k["accuracy"]
                - matched_baselines[task]["strongest_trivial"]
                > 0,
                "reference_scores_higher": c["accuracy"] > k["accuracy"],
                "paired": test,
            }
        controls[ctl] = cmp
    if controls:
        print()
        print("=" * 78)
        print("CONTROL ARMS (no gate reads these; the reading needs them)")
        print("=" * 78)
        for ctl, cmp in controls.items():
            for task, v in cmp.items():
                p = v["paired"]
                print(
                    f"{ctl:>9} / {task:<7} control {v['control_accuracy']:.4f} "
                    f"vs {v['reference']} {v['reference_accuracy']:.4f} "
                    f"-> ref-control {v['reference_minus_control']:+.4f} | "
                    f"control vs trivial {v['control_vs_trivial']:+.4f} "
                    f"({'control ALSO beats trivial' if v['control_beats_trivial'] else 'control does NOT beat trivial'}) "
                    f"| reference scores higher: {v['reference_scores_higher']}"
                )
                print(
                    f"{'':>9}   paired (McNemar, same items): discordant "
                    f"{p['discordant']} (ref-only {p['a_only_correct']}, "
                    f"control-only {p['b_only_correct']}) | diff {p['paired_diff']:+.4f} "
                    f"95% CI [{p['ci95'][0]:+.4f}, {p['ci95'][1]:+.4f}] | "
                    f"p={p['p_two_sided_exact']:.4f}"
                )
    if arms_missing:
        print()
        print(
            "ARMS MISSING (a control arm that was not run): " + ", ".join(arms_missing)
        )

    # ---- the Part 4 closing gates (L-G1, L-G2, L-G6, L-G7) ----
    # These are read off the SAME cache, with the SAME matched baselines and
    # the SAME coverage annotation. A gate whose arms are absent is reported
    # as NOT EVALUABLE — never as a pass (META-LESSONS 16: a skipped test
    # still reports "ok"; the skip must be loud).
    task_list = sorted(matched_baselines)
    third_task = "third" if "third" in task_list else None
    part4 = evaluate_part4_gates(
        {a: c for a, c in arm_cells.items()},
        matched_baselines,
        task_list,
        third_task=third_task,
    )
    print()
    print("=" * 78)
    print(
        "PART 4 CLOSING GATES (L-G1, L-G2, L-G6, L-G7) — matched baselines, "
        "coverage-checked"
    )
    print("=" * 78)
    for gid, g in part4.items():
        if gid == "reference_arm_standing":
            continue
        status = g.get("status")
        line = f"{gid}: {status}"
        if status == "ok":
            line += f" -> {g.get('verdict')}"
        elif g.get("reason"):
            line += f" — {g['reason']}"
        print(line)
        for task, v in (g.get("per_task") or {}).items():
            print(
                f"{'':>4} {task:<8} control {v['control_accuracy']:.4f} vs "
                f"{g['reference_arm']} {v['reference_accuracy']:.4f} | "
                f"clears({g['rule']}): {v['clears']} | "
                f"trivial {v['trivial']} | "
                f"control delta vs trivial {v['control_delta_vs_trivial']:+.4f} | "
                f"leak {v['control_foreign_label_leak']}"
            )
        if g.get("reading"):
            print(f"{'':>4} reading: {g['reading']}")
    ref_standing = part4.get("reference_arm_standing") or {}
    if ref_standing:
        print()
        print(
            "REFERENCE ARM STANDING (the `untagged` arm the closing gates are "
            "measured against, and its own control `cond`)"
        )
        for task, v in ref_standing.items():
            print(
                f"{'':>4} {task:<8} untagged {v['untagged']:.4f} | cond "
                f"{v['cond']:.4f} | untagged-cond {v['untagged_minus_cond']:+.4f}"
            )

    # ---- the noise arm's persisted label map (L-G2) ----
    noise_labels = {}
    for task in task_list:
        p = os.path.join(args.completions, f"noise__{task}_noise_labels.json")
        if not os.path.exists(p):
            continue
        try:
            with open(p) as fh:
                noise_labels[task] = json.load(fh)
        except (OSError, ValueError) as exc:
            noise_labels[task] = {"error": f"{type(exc).__name__}: {exc}"}
    if noise_labels:
        print()
        print("=" * 78)
        print("NOISE ARM LABEL MAP (L-G2) — the random labels it was trained on")
        print("=" * 78)
        for task, meta in noise_labels.items():
            if "error" in meta:
                print(f"{task:>10}: UNREADABLE ({meta['error']})")
                continue
            print(
                f"{task:>10}: noise_seed {meta.get('noise_seed')} | "
                f"{meta.get('n')} rows | legal labels {meta.get('labels')} | "
                f"distribution {meta.get('distribution')}"
            )

    if closing_missing:
        print()
        print(
            "CLOSING ARMS NOT RUN (a Part 4 gate that was never run is not a "
            "gate that passed): " + ", ".join(closing_missing)
        )

    payload = {
        # v3 (2026-10-21, Part 4): the cells gained `coverage` and
        # `foreign_label_leak`, and the payload gained the Part 4 closing
        # gates, the closing-arm inventory and the noise label map. The
        # contract string is bumped so the two shapes are distinguishable.
        "contract": "nursery.fast-score.v3",
        "completions_dir": args.completions,
        "eval_limit": args.eval_limit,
        "eval_rows": args.eval_rows,
        "seed": args.seed,
        "arms_present": arms_present,
        "arms_missing": arms_missing,
        "closing_arms_present": closing_present,
        "closing_arms_missing": closing_missing,
        "replay_seconds": round(elapsed, 3),
        "cells": [
            {k: v for k, v in r.items() if k != "cell"} | {"cell": r["cell"]}
            for r in results
        ],
        "matched_baselines": matched_baselines,
        "gates": gates,
        "part4_gates": part4,
        "noise_labels": noise_labels,
        "controls": controls,
    }
    if args.out:
        with open(args.out, "w") as fh:
            json.dump(payload, fh, indent=2)
        print(f"\nwrote {args.out}")

    if args.manifest:
        manifest = {
            # v2 (2026-10-21, Part 4): the cells gained the coverage
            # annotation, so the manifest shape changed and the contract
            # string is bumped. The numbers in the cells are unchanged.
            "contract": "nursery.fast-score.manifest.v2",
            "completions_dir": args.completions,
            "eval_rows": args.eval_rows,
            "replay_seconds": round(elapsed, 3),
            "arms_present": arms_present,
            "arms_missing": arms_missing,
            "closing_arms_present": closing_present,
            "closing_arms_missing": closing_missing,
            "cells": {
                f"{r['arm']}__{r['task']}": {
                    "sha256": file_digest(r["path"]),
                    "n": r["cell"]["n"],
                    "ids_sha256": hashlib.sha256(
                        "\n".join(
                            str(i.get("id")) for i in r["cell"]["_per_item"]
                        ).encode()
                    ).hexdigest(),
                    "gold_distribution": r["matched_trivial"]["distribution"],
                    "coverage": r["cell"].get("coverage"),
                }
                for r in results
            },
            "corpora": {
                t: {
                    "path": os.path.join(ac.DATA, ac.TASKS[t]["file"]),
                    "sha256": file_digest(os.path.join(ac.DATA, ac.TASKS[t]["file"])),
                    "labels": ac.TASKS[t]["labels"],
                }
                for t in sorted(matched_baselines)
            },
        }
        with open(args.manifest, "w") as fh:
            json.dump(manifest, fh, indent=2)
        print(f"wrote {args.manifest}")

    print(f"replay: {len(results)} cells in {elapsed:.2f}s (no GPU)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
