"""scoring.py — the CANONICAL scoring rules for the nursery model-experiment lane.

WHY THIS FILE EXISTS. The lane's two worst defects were both DEFINITION
defects, not implementation defects:

  C-4  a bare-substring scorer that scored `abandoned` as `done`. The rule
       lived in `adapter_conditioning.py`; a second copy of it lived in
       `fast_score.py`; the two could disagree, and the disagreement would
       have been read as a finding.
  C-11 a gate that read ONE arm (`cond`) and therefore could not see its own
       controls (`untagged`, `permsolo`, `shared`). The control arms were
       DESIGNED as controls and the gate never asked about them.

A duplicated definition of a rule is a correctness hazard, not a speed
problem (META-LESSONS 18: the replay scorer answers ten cached cells in
~0.2 s, so there was never a performance reason to have two copies). So this
module holds ONE implementation of every rule, and both `adapter_conditioning.py`
(the run) and `fast_score.py` (the replay) import it.

THE LAWS THIS FILE ENCODES.

  * A number without its trivial baseline is not a number, and the baseline
    must come from the CACHE'S OWN `gold`, over EXACTLY the rows that were
    scored — never a re-derived split (L-G3 / META-LESSONS 19). See
    `trivial_from_items`.
  * A coverage number is part of the number. Every number carries
    `scored_rows / corpus_rows`; a number with coverage < 1.0 is `partial`
    and is NOT a gate input, in either direction (L-G3).
  * A difference of a few items is not a finding until a paired test says so.
    `mcnemar` is the exact two-sided test on the SAME items, with a 95 % CI.
  * The legacy extractor is kept ONLY for the item-by-item comparison — it is
    the defect under test, never a gate input (K'-G1).
  * A gate that reads one arm cannot see its own controls (C-11 /
    META-LESSONS 11). `evaluate_part4_gates` therefore evaluates every
    closing gate against its CONTROL arm and reports the reference arm's own
    standing, so a gate value can move when the control moves.

Nothing here touches the GPU. Everything is a pure function of the cached
per-item completions and the task corpora.
"""

import math


# The rule that decides a completion: STRICT (K'-G1). The stripped completion
# must EQUAL a label; a substring hit is a MISS.
#
# `abandoned` is not `done`; `transaction` is not `action`; `satisfaction` is
# not `fact`; `reopened` is not `open`.
#
# The think-block law is unchanged and is still applied: a think block that
# never closed is a MISS, never a nearest-label guess.
def normalise_completion(text):
    """The completion reduced to the string a label would be compared against.

    The think-block law: a think block that never closed is a MISS, never a
    nearest-label guess. A closed think block contributes only its tail.
    """
    if not text:
        return ""
    if "</think>" in text:
        text = text.split("</think>")[-1]
    elif "<think>" in text:
        return ""
    return text.strip().strip(".").strip()


def extract_label_strict(text, labels):
    """The label the completion ANSWERS, or None. The gate's scorer."""
    s = normalise_completion(text)
    if not s:
        return None
    low = s.lower()
    for lab in labels:
        if low == lab.lower():
            return lab
    return None


def extract_foreign_label(text, other_labels):
    """The FOREIGN label the completion names, or None.

    WHY THIS EXISTS (and why it is not just `extract_label_strict` with the
    other label set). The strict extractor only ever returns a label from
    THIS task's legal set, so a completion that answers in another task's
    vocabulary is indistinguishable from "no answer at all" in it. A leak
    metric built on the strict extractor can therefore never be non-zero —
    which would make L-G7 ("the foreign-label leak is 0") unfalsifiable, the
    same failure class as C-11 (a gate that cannot see its own control).

    So the leak is measured on the COMPLETION, against the other tasks'
    legal labels, with the same equality rule and the same think-block law.
    """
    s = normalise_completion(text)
    if not s:
        return None
    low = s.lower()
    for lab in other_labels or ():
        if low == lab.lower():
            return lab
    return None


def extract_label_legacy(text, labels):
    """The 2026-10-21 scorer, kept for the item-by-item COMPARISON.

    Not used for any gate: it is the defect under test (bare substring
    search, so `abandoned` scores as `done`).
    """
    if not text:
        return None
    if "</think>" in text:
        text = text.split("</think>")[-1]
    elif "<think>" in text:
        return None
    low = text.lower()
    best = None
    for lab in labels:
        pos = low.find(lab.lower())
        if pos >= 0 and (best is None or pos < best[0]):
            best = (pos, lab)
    return best[1] if best else None


def score_items(items, labels, other_labels=(), corpus_rows=None):
    """Score one cell (a list of cached per-item dicts) and collect EVERY
    reading the gates need.

    `items` are the cached rows: `{"id", "gold", "pred_strict", "pred_legacy",
    "completion"}`.

    `other_labels` are the legal labels of the OTHER tasks. A completion that
    EQUALS one of them, on a row of this task, is a FOREIGN-LABEL LEAK
    (L-G7): the model answered in another task's vocabulary. It is counted
    SEPARATELY from `outside_label_set` (any answer that is not one of this
    task's labels), because a leak is a specific, more damning thing than an
    out-of-set answer — and because the strict extractor cannot see a leak at
    all (it only ever returns this task's labels), so the leak has to be
    measured on the completion itself.

    `corpus_rows` is the size of the scored split (the number of rows the
    split HAS). It is used only for the coverage annotation; it never
    changes a number.
    """
    n = len(items)
    strict = legacy = outside = 0
    foreign = 0
    other = set(other_labels or ())
    hist = {}
    disagree = []
    truncation_drift = 0
    per_item = []

    for it in items:
        text = it.get("completion") or ""
        pred = extract_label_strict(text, labels)
        leg = extract_label_legacy(text, labels)
        if pred is None:
            outside += 1
        else:
            hist[pred] = hist.get(pred, 0) + 1
        # The leak is measured on the COMPLETION, not on `pred`: `pred` can
        # only ever be one of THIS task's labels, so a foreign answer would
        # be invisible there (and the leak would read 0 forever).
        leaked = extract_foreign_label(text, other)
        if leaked is not None:
            foreign += 1
        if pred == it.get("gold"):
            strict += 1
        if leg == it.get("gold"):
            legacy += 1
        if pred != leg:
            disagree.append(
                {
                    "id": it.get("id"),
                    "gold": it.get("gold"),
                    "strict": pred,
                    "legacy": leg,
                    "completion": text,
                }
            )
        # The run scored the FULL completion; the cache holds 200 chars. A
        # disagreement here means the cache is not sufficient to re-score.
        if pred != it.get("pred_strict") or leg != it.get("pred_legacy"):
            truncation_drift += 1
        per_item.append(
            {
                "id": it.get("id"),
                "gold": it.get("gold"),
                "pred": pred,
                "ok": pred == it.get("gold"),
            }
        )

    top = max(hist.values()) if hist else 0
    cell = {
        "n": n,
        "accuracy": strict / max(1, n),
        "accuracy_legacy_scorer": legacy / max(1, n),
        "outside_label_set": outside,
        "foreign_label_leak": foreign,
        "prediction_histogram": hist,
        "top_label_concentration": (top / max(1, n)) if hist else 0.0,
        "scorer_disagreements": len(disagree),
        "disagreement_rate": len(disagree) / max(1, n),
        "truncation_drift": truncation_drift,
        "_disagree": disagree,
        "_per_item": per_item,
    }
    cell["coverage"] = coverage_annotation(n, corpus_rows)
    return cell


def coverage_annotation(scored_rows, corpus_rows):
    """The coverage of a number (L-G3).

    `scored_rows` / `corpus_rows` over the scored split. A number with
    coverage < 1.0 is `partial`: it is NOT a gate input, in either direction
    — it cannot pass, fail, hit or miss a gate, and it cannot move a
    threshold.

    An UNKNOWN corpus size (None) is treated as partial, because the
    conservative reading of an unknown coverage is the one that refuses to
    let a number gate anything.
    """
    if corpus_rows is None or corpus_rows <= 0:
        return {
            "scored_rows": scored_rows,
            "corpus_rows": None,
            "coverage": None,
            "partial": True,
            "coverage_known": False,
        }
    cov = scored_rows / corpus_rows
    return {
        "scored_rows": scored_rows,
        "corpus_rows": corpus_rows,
        "coverage": cov,
        "partial": cov < 1.0,
        "coverage_known": True,
    }


def ranked_prediction(item, normalization="mean"):
    """The label the RANKING arm picked, recomputed from the cached cell.

    The ranking cell stores the per-label log-probabilities, so the OTHER
    length-normalization's reading is re-derivable from the artifact — with
    no GPU re-run. The gate reads the cell's `completion` (the normalization
    chosen BEFORE the run); this helper exists so a reader can check the
    other reading without re-running anything.
    """
    lps = item.get("label_logprobs") or {}
    if not lps:
        return None
    if normalization not in ("sum", "mean"):
        raise ValueError(
            f"normalization must be 'sum' or 'mean', not {normalization!r}"
        )
    return max(lps.keys(), key=lambda k: lps[k][normalization])


def trivial_from_gold(gold, labels):
    """The trivial baseline over an explicit list of gold labels.

    The baseline is a property of the ROWS, not of a split: the majority
    class and the first-option class, over exactly the rows that were
    scored.
    """
    gold = [g for g in gold if g is not None]
    n = max(1, len(gold))
    dist = {}
    for g in gold:
        dist[g] = dist.get(g, 0) + 1
    majority_label = max(dist.items(), key=lambda kv: kv[1])[0] if dist else ""
    majority = (dist.get(majority_label, 0) / n) if dist else 0.0
    first = gold.count(labels[0]) / n if gold else 0.0
    return {
        "n": len(gold),
        "distribution": dist,
        "majority_label": majority_label,
        "majority_accuracy": majority,
        "first_option_label": labels[0],
        "first_option_accuracy": first,
        "strongest_trivial": max(majority, first),
    }


def trivial_from_items(items, labels):
    """The trivial baseline over EXACTLY the rows that were scored.

    The cache's items carry the `gold` label the run scored against, so the
    baseline and the accuracy are over ONE sample set BY CONSTRUCTION — no
    split re-derivation, no `--seed` coupling, nothing that can silently
    describe different rows than the ones that were scored.

    This is the only baseline a gate number may cite (L-G3). The
    re-derived split is a CROSS-CHECK only.
    """
    return trivial_from_gold([it.get("gold") for it in items], labels)


def trivial_on_scored_rows(rows, labels):
    """The trivial baseline over a list of task rows (the re-derived split).

    Retained for the CROSS-CHECK only. The matched baseline the tools report
    comes from `trivial_from_items` (the cache's own rows) — see
    `fast_score.py`'s module docstring.
    """
    return trivial_from_gold([r["kind"] for r in rows], labels)


def shadowed_labels(labels):
    """Which legal labels are substrings of which other legal labels.

    A substring pair is a scorer defect waiting to happen: the strict scorer
    is safe against it, the legacy one is not. Reported so a NEW defect of
    the C-4 class is visible before it becomes a number.
    """
    pairs = []
    for a in labels:
        for b in labels:
            if a != b and b.lower() in a.lower():
                pairs.append({"label": a, "contains": b})
    return pairs


def mcnemar(a_items, b_items):
    """Paired comparison of two cells over the items they share.

    `a_items` / `b_items` are the per-item dicts from `score_items`. Returns
    the discordant counts, the exact two-sided binomial p under H0 (the two
    arms are equally often right), and a 95% CI on the paired difference.

    Why this and not a difference of accuracies: the two arms are scored on
    the SAME items, so the unpaired variance overstates the uncertainty and a
    difference of a few items can be noise. The paired test asks the
    question the control arms actually pose: on the items where the arms
    DISAGREE, is the split worse than a coin flip?

    It also reports `common_ids` so a caller can prove the two arms were
    scored on the SAME rows (a gate that compares arms over different row
    sets is comparing two experiments).
    """
    by_a = {it["id"]: it for it in a_items if it.get("id") is not None}
    by_b = {it["id"]: it for it in b_items if it.get("id") is not None}
    common = [i for i in by_a if i in by_b]
    a_only = b_only = 0
    for i in common:
        a_ok = by_a[i]["ok"]
        b_ok = by_b[i]["ok"]
        if a_ok and not b_ok:
            a_only += 1
        elif b_ok and not a_ok:
            b_only += 1
    n_disc = a_only + b_only
    n_pairs = len(common)
    if n_disc == 0:
        p = 1.0
    else:
        k = min(a_only, b_only)
        tail = sum(math.comb(n_disc, i) for i in range(0, k + 1))
        p = min(1.0, 2.0 * tail / (2**n_disc))
    diff = (a_only - b_only) / n_pairs if n_pairs else 0.0
    if n_pairs and n_disc:
        se = math.sqrt((n_disc) - ((a_only - b_only) ** 2) / n_pairs) / n_pairs
    else:
        se = 0.0
    return {
        "n_pairs": n_pairs,
        "discordant": n_disc,
        "a_only_correct": a_only,
        "b_only_correct": b_only,
        "paired_diff": diff,
        "ci95": [diff - 1.96 * se, diff + 1.96 * se],
        "p_two_sided_exact": p,
        "common_ids": common,
    }


# ---------------------------------------------------------------------------
# The K' gate matrix (K'-G1..K'-G6), moved here VERBATIM from
# `adapter_conditioning.py` so that there is exactly one definition.
# Written BEFORE the run (frozen).
# ---------------------------------------------------------------------------
def evaluate_gates(results, baselines, task_names):
    """K'-G1..K'-G6, read off the matrix. Written BEFORE the run (frozen)."""
    g = {}
    base = results.get("base", {})
    arms = results.get("arms", {})

    def deltas(arm):
        out = {}
        cells = (arms.get(arm) or {}).get("cells") or {}
        for task in task_names:
            cell = cells.get(task)
            if not cell:
                continue
            out[task] = {
                "own_task_delta_vs_trivial": cell["accuracy"]
                - baselines[task]["strongest_trivial"],
                "own_task_delta_vs_base": cell["accuracy"]
                - base.get(task, {}).get("accuracy", 0.0),
                "off_task_delta_vs_trivial": None,
                "top_label_concentration": cell["top_label_concentration"],
                "outside_label_set": cell["outside_label_set"],
            }
        # the OFF-task delta for task T is what the OTHER adapter does to T;
        # with a single multi-task adapter the off-task reading is the OTHER
        # task's cell scored under the same adapter.
        return out

    g["per_arm"] = {
        arm: deltas(arm) for arm in arms if "cells" in (arms.get(arm) or {})
    }

    cond = (arms.get("cond") or {}).get("cells") or {}
    if not cond:
        g["K-G_capability_retained"] = None
        return g

    # K'-G1: the strict scorer must be the one that decides.
    # K'-G2: the artifacts must exist.
    g["K_G2_artifacts"] = {
        "adapter_config_written": True,
        "per_item_completions_written": True,
    }

    # K'-G1/K'-G4: capability retained on BOTH tasks.
    cap = {}
    for task in task_names:
        cell = cond.get(task)
        if not cell:
            continue
        cap[task] = {
            "accuracy": cell["accuracy"],
            "trivial": baselines[task]["strongest_trivial"],
            "delta_vs_trivial": cell["accuracy"] - baselines[task]["strongest_trivial"],
            "passes_capability": (
                cell["accuracy"] - baselines[task]["strongest_trivial"]
            )
            >= 0.10,
        }
    g["K_G4_capability_retained"] = cap

    # K'-G5: no unconditional prior.
    g["K_G5_no_unconditional_prior"] = {
        task: {
            "top_label_concentration": cond[task]["top_label_concentration"],
            "passes": cond[task]["top_label_concentration"] <= 0.90,
        }
        for task in task_names
        if task in cond
    }

    # K'-G6: interference. With ONE adapter over both tasks, the off-task
    # reading is the OTHER task's cell under the SAME adapter: if the adapter
    # learned a single unconditional prior, one task's cell collapses to the
    # other's labels and the concentration on one label is extreme.
    inter = {}
    for task in task_names:
        cell = cond.get(task)
        if not cell:
            continue
        inter[task] = {
            "accuracy": cell["accuracy"],
            "trivial": baselines[task]["strongest_trivial"],
            "delta_vs_trivial": cell["accuracy"] - baselines[task]["strongest_trivial"],
            "passes_no_damage": (
                cell["accuracy"] - baselines[task]["strongest_trivial"]
            )
            >= -0.05,
        }
    g["K_G6_interference"] = inter

    # the reading (pre-registered in MTP-GATES.md)
    cap_ok = bool(cap) and all(v["passes_capability"] for v in cap.values())
    prior_ok = bool(g["K_G5_no_unconditional_prior"]) and all(
        v["passes"] for v in g["K_G5_no_unconditional_prior"].values()
    )
    inter_ok = bool(inter) and all(v["passes_no_damage"] for v in inter.values())
    if cap_ok and prior_ok and inter_ok:
        g["reading"] = (
            "K'-G1+G4 pass, K'-G5+G6 pass => selectivity IS recoverable by "
            "conditioning; the product shape is ONE task-conditioned adapter per "
            "base, not a set of swappable specialists."
        )
    elif cap_ok and not (prior_ok and inter_ok):
        g["reading"] = (
            "K'-G1+G4 pass, K'-G5 or K'-G6 fail => conditioning is insufficient; "
            "the prior is unconditional at the weight level; the honest product is "
            "ONE adapter per task, never swapped on a resident base."
        )
    else:
        g["reading"] = (
            "K'-G1 fails (no adapter beats the trivial baseline under strict "
            "scoring) => the 2026-10-21 +0.153 was a scoring artifact; the "
            "adapter line closes on CAPABILITY, not selectivity."
        )
    return g


# ---------------------------------------------------------------------------
# The Part 4 gates (L-G1, L-G2, L-G6, L-G7) — the CLOSING controls.
# MTP-GATES.md Part 4, frozen 2026-10-21 BEFORE any of these arms ran.
# ---------------------------------------------------------------------------

# The reference arm for every Part 4 gate. `untagged` is the reference, not
# `cond`: Part 3 established that the tag is not load-bearing, so a gate that
# compared against `cond` would compare against the worse of two equivalent
# arms.
L_REFERENCE_ARM = "untagged"

# L-G1: few-shot control. PASS closes the training line.
L_G1 = {
    "id": "L_G1_fewshot",
    "control_arm": "fewshot",
    "reference_arm": L_REFERENCE_ARM,
    "margin": 0.05,
    "rule": "fewshot >= untagged - 0.05",
    "scope": "both tasks",
    "all_tasks": True,
    "reading": (
        "PASS (few-shot clears untagged - 0.05 on BOTH tasks) => the line is a "
        "prompt-format workaround; NO further training arms are bought and the "
        "lane closes. FAIL => the adapter contributes beyond exemplars at this "
        "budget and the line continues."
    ),
}

# L-G2: the noise-adapter control (labels randomized).
L_G2 = {
    "id": "L_G2_noise_adapter",
    "control_arm": "noise",
    "reference_arm": L_REFERENCE_ARM,
    "margin": 0.10,
    "rule": "noise >= untagged - 0.10",
    "scope": "either task",
    "all_tasks": False,
    "reading": (
        "HIT (noise clears untagged - 0.10 on EITHER task) => the capability is a "
        "FORMAT capability; the product must not claim decision capability and "
        "the noise arm becomes the mandatory floor every future arm is measured "
        "against. MISS (on both tasks) => the gain is not explained by format "
        "alone."
    ),
}

# L-G6: ranking versus generation. PASS closes the training line.
L_G6 = {
    "id": "L_G6_ranked_vs_generated",
    "control_arm": "ranked",
    "reference_arm": L_REFERENCE_ARM,
    "margin": 0.05,
    "rule": "ranked >= untagged - 0.05",
    "scope": "both tasks",
    "all_tasks": True,
    "reading": (
        "PASS (ranked(base) clears untagged - 0.05 on BOTH tasks) => the LoRA "
        "line is NOT bought: a base model with constrained ranking delivers the "
        "same capability with zero training. FAIL => generation, and therefore "
        "the adapter, is load-bearing."
    ),
}

# L-G7: the third, dissimilar task. A leak test, not an accuracy test.
L_G7 = {
    "id": "L_G7_third_task",
    "control_arm": "shared",
    "reference_arm": L_REFERENCE_ARM,
    "margin": 0.05,
    "rule": "shared >= untagged - 0.05 AND foreign_label_leak == 0",
    "scope": "the third (dissimilar) task only",
    "all_tasks": False,
    "reading": (
        "Both hold => a shared answer space is legal for a semantically "
        "dissimilar group. A leak > 0 => the rule is 'a shared answer space is "
        "legal only within a semantically dissimilar group' and the per-task "
        "default is confirmed."
    ),
}


def _same_rows(cell_a, cell_b):
    """True when two cells were scored on exactly the same items."""
    ids_a = [it.get("id") for it in (cell_a or {}).get("_per_item", [])]
    ids_b = [it.get("id") for it in (cell_b or {}).get("_per_item", [])]
    return ids_a == ids_b and bool(ids_a)


def _gate_status(cells, control, reference, tasks, required_tasks=None):
    """Common preconditions for a Part 4 gate.

    Returns (status, reason, per_task). `status` is one of:
      "ok"             — every precondition holds, the gate can be read;
      "missing_arm"    — an arm's cells are not in the cache;
      "partial_coverage" — a cell's coverage is < 1.0 (L-G3: NOT a gate input);
      "different_rows" — the two arms were not scored on the same items.
    """
    need = required_tasks if required_tasks is not None else tasks
    for arm in (control, reference):
        for task in need:
            if task not in (cells.get(arm) or {}):
                return (
                    "missing_arm",
                    f"arm {arm!r} has no cell for task {task!r}",
                    {},
                )
    per_task = {}
    for task in need:
        c = cells[control][task]
        r = cells[reference][task]
        cov_c = (c.get("coverage") or {}).get("coverage")
        cov_r = (r.get("coverage") or {}).get("coverage")
        if cov_c is None or cov_r is None or cov_c < 1.0 or cov_r < 1.0:
            return (
                "partial_coverage",
                (
                    f"task {task!r}: coverage "
                    f"{control}={cov_c} {reference}={cov_r} (< 1.0). L-G3: a "
                    "partial number is NOT a gate input, in either direction. "
                    "Re-run with --eval-rows all."
                ),
                per_task,
            )
        if not _same_rows(c, r):
            return (
                "different_rows",
                f"task {task!r}: {control} and {reference} were not scored on the "
                "same items",
                per_task,
            )
        per_task[task] = {"control": c, "reference": r}
    return ("ok", "", per_task)


def _part4_gate(gate, cells, baselines, tasks, third_task=None):
    """Evaluate one Part 4 gate, with its control ENCODED (C-11)."""
    control = gate["control_arm"]
    reference = gate["reference_arm"]
    required = None
    if gate["id"] == L_G7["id"]:
        if not third_task:
            return {
                "gate": gate["id"],
                "status": "not_evaluable",
                "reason": "the third (dissimilar) task is not in this run",
                "rule": gate["rule"],
                "verdict": None,
            }
        required = [third_task]
    status, reason, per_task = _gate_status(
        cells, control, reference, tasks, required_tasks=required
    )
    out = {
        "gate": gate["id"],
        "status": status,
        "reason": reason,
        "rule": gate["rule"],
        "margin": gate["margin"],
        "scope": gate["scope"],
        "control_arm": control,
        "reference_arm": reference,
        "verdict": None,
    }
    if status != "ok":
        return out

    detail = {}
    for task, pair in per_task.items():
        c = pair["control"]
        r = pair["reference"]
        trivial = baselines.get(task, {}).get("strongest_trivial")
        detail[task] = {
            "control_accuracy": c["accuracy"],
            "reference_accuracy": r["accuracy"],
            "reference_minus_control": r["accuracy"] - c["accuracy"],
            "control_minus_threshold": c["accuracy"] - (r["accuracy"] - gate["margin"]),
            "clears": c["accuracy"] >= (r["accuracy"] - gate["margin"]),
            "trivial": trivial,
            "control_delta_vs_trivial": (
                c["accuracy"] - trivial if trivial is not None else None
            ),
            "control_coverage": c.get("coverage"),
            "reference_coverage": r.get("coverage"),
            "control_foreign_label_leak": c.get("foreign_label_leak"),
            "reference_foreign_label_leak": r.get("foreign_label_leak"),
        }
        if gate["id"] == L_G7["id"]:
            detail[task]["leak_is_zero"] = (c.get("foreign_label_leak") or 0) == 0
    out["per_task"] = detail

    clears = [v["clears"] for v in detail.values()]
    if gate["all_tasks"]:
        ok = bool(clears) and all(clears)
    else:
        ok = bool(clears) and any(clears)
    if gate["id"] == L_G7["id"]:
        # The leak condition is AND, not OR: a shared answer space is only
        # legal for a dissimilar group if it also leaks nothing.
        leak_ok = all(v.get("leak_is_zero") for v in detail.values())
        ok = ok and leak_ok
        out["leak_is_zero"] = leak_ok
    out["verdict"] = (
        ("PASS" if ok else "FAIL")
        if gate["id"] != L_G2["id"]
        else ("HIT" if ok else "MISS")
    )
    out["reading"] = gate["reading"]
    return out


def evaluate_part4_gates(cells, baselines, tasks, third_task=None):
    """The Part 4 closing gates, read off the cached cells (no GPU).

    `cells` is `{arm: {task: cell_dict}}`, `baselines` is `{task: trivial}`
    (the MATCHED baselines, from the cache's own gold), `tasks` is the list
    of tasks in the run, and `third_task` names the dissimilar task for L-G7.

    Every gate is evaluated against its CONTROL arm and the reference arm is
    `untagged` (Part 3: the tag is not load-bearing, so `cond` would be the
    worse of two equivalent arms).
    """
    gates = {}
    for gate in (L_G1, L_G2, L_G6, L_G7):
        gates[gate["id"]] = _part4_gate(
            gate, cells, baselines, tasks, third_task=third_task
        )

    # C-11, applied to the reference arm itself: the reader must be able to
    # see whether the REFERENCE the closing gates are measured against is
    # itself stable against its own control (`cond`). If `untagged` moved, the
    # closing gates' thresholds moved with it, and that must be visible here
    # rather than hidden inside the gate arithmetic.
    ref = {}
    if L_REFERENCE_ARM in cells and "cond" in cells:
        for task in tasks:
            if task not in cells[L_REFERENCE_ARM] or task not in cells["cond"]:
                continue
            ref[task] = {
                "untagged": cells[L_REFERENCE_ARM][task]["accuracy"],
                "cond": cells["cond"][task]["accuracy"],
                "untagged_minus_cond": cells[L_REFERENCE_ARM][task]["accuracy"]
                - cells["cond"][task]["accuracy"],
                "note": (
                    "The reference arm's own standing. Part 3 measured the tag "
                    "as NOT load-bearing (paired p = 0.185 / 1.000), so `cond` "
                    "is the worse of two equivalent arms and is not the gate "
                    "reference. If this number MOVES, the closing gates' "
                    "thresholds move with it."
                ),
            }
    gates["reference_arm_standing"] = ref
    return gates
