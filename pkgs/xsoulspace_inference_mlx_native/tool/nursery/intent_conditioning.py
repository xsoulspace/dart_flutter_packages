"""Line IC — intent conditioning on the AR stack (no training, no diffusion).

Gates: MTP-GATES.md PART 5, IC-G1..IC-G5 (frozen 2026-11-02 BEFORE this arm).

The owner's 2026-11-02 proposal (generate an intent first, then fill the
completion conditioned on it) splits into claim A (intent conditioning
helps — THIS tool) and claim B (diffusion fill — closed by the Stage-0
compute verdict, not re-opened here). See MTP-GATES.md Part 5 for the frozen
design, vocabulary, prompts, fallback rules and pre-registered readings.

Design recap (frozen):
  casts     Qwen3-0.6B-4bit, Qwen3-1.7B-4bit (one process per cast)
  regimes   base   the K' BASE_PROMPT, unconditioned
            closed pass 1 picks one of 4 procedural intents (strict
                   extraction, frozen vocabulary, frozen fallback);
                   pass 2 answers conditioned on the chosen intent
            self   pass 1 authors a <=48-token procedure;
                   pass 2 answers conditioned on it
  tasks     perm (PRIMARY, all test rows), veto (secondary, all test rows),
            clause (DESCRIPTIVE ONLY, first 150 test rows, coverage-limited)

Laws this tool inherits and enforces:
  * ONE definition of every scoring rule — extractors, score_items, mcnemar,
    trivial baselines and coverage all come from scoring.py (C-4/C-11).
  * ONE definition of the corpora, split law and base prompt — imported from
    adapter_conditioning.py, never copied.
  * Coverage is part of every number; a clause cell (150 rows) is `partial`
    by construction and cannot gate anything (L-G3).
  * Per-item completions are cached FULL (no 200-char truncation) so every
    scoring re-ask is CPU replay and truncation_drift is 0 by construction.
  * Power snapshot at run start (ADR 0061): quality gates are not power-
    conditioned, but the state is recorded and tok/s is informational only.
  * Greedy decoding (mlx_lm default temp 0), base and intent arms scored on
    the SAME items in the SAME process, so the paired test is exact.

Usage:
  # full run, one cast at a time (GPU work is serial):
  python tool/nursery/intent_conditioning.py --cast 0.6b
  python tool/nursery/intent_conditioning.py --cast 1.7b
  # verdict (CPU only, after both casts):
  python tool/nursery/intent_conditioning.py --verdict
  # plumbing smoke (6 rows/task; recorded as smoke, coverage-partial,
  # can never be a gate input):
  python tool/nursery/intent_conditioning.py --cast 0.6b --smoke 6
"""

import argparse
import json
import os
import re
import sys
import time
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import power_snapshot  # noqa: E402
from adapter_conditioning import (  # noqa: E402
    BASE_PROMPT,
    TASKS,
    load_task,
    split_rows,
)
from scoring import (  # noqa: E402
    coverage_annotation,
    extract_label_legacy,
    extract_label_strict,
    mcnemar,
    score_items,
    trivial_from_items,
)

CASTS = {
    "0.6b": "mlx-community/Qwen3-0.6B-4bit",
    "1.7b": "mlx-community/Qwen3-1.7B-4bit",
}

RUNS = os.path.join(PKG, "bench", "nursery", "experiments")

# ---------------------------------------------------------------------------
# Frozen by MTP-GATES.md Part 5. Changing ANY string below after the first
# gated run makes this a NEW arm requiring a NEW frozen Part.
# ---------------------------------------------------------------------------

INTENT_VOCAB = [
    "match_against_policy",
    "scan_for_risk_markers",
    "check_scope_boundaries",
    "assess_reversibility",
]
INTENT_FALLBACK = INTENT_VOCAB[0]  # frozen fallback for a malformed pick

CLOSED_INTENT_PROMPT = (
    "Choose the procedure for deciding about the text. Answer with exactly "
    "one of: {vocab}\n\nText: {text}\nAnswer:"
)
SELF_INTENT_PROMPT = (
    "Write one short sentence describing the procedure you will use to "
    "classify the text below, then stop.\n\nText: {text}\nProcedure:"
)
INTENT_ANSWER_PROMPT = (
    "Procedure: {intent}\nClassify the text. Answer with exactly one of: "
    "{labels}\n\nText: {text}\nAnswer:"
)

MAX_TOKENS_CLOSED_INTENT = 16
MAX_TOKENS_SELF_INTENT = 48
MAX_TOKENS_ANSWER = 64

CLAUSE_ROW_LIMIT = 150  # descriptive-only limit, frozen in Part 5

# Gate thresholds (mirrors of Part 5; the .md is the authority).
G1_DELTA_PP = 5.0
G1_P = 0.05
G2_VETO_FLOOR_PP = -3.0
G4_SELF_MIN_UNIQUE = 5
G4_SELF_MAX_SHARE = 0.90
G4_CLOSED_MAX_MALFORMED = 0.10
G5_OUTSIDE_SLACK = 2


def utcnow():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")


def normalise_intent(text):
    """The histogram key for a self-authored intent (IC-G4)."""
    s = re.sub(r"\s+", " ", (text or "").strip())
    return s[:240]


def gen(model, tok, prompt, max_tokens):
    from mlx_lm import generate

    messages = [{"role": "user", "content": prompt}]
    chat = tok.apply_chat_template(
        messages,
        add_generation_prompt=True,
        tokenize=False,
        enable_thinking=False,
    )
    t0 = time.monotonic()
    out = generate(model, tok, prompt=chat, max_tokens=max_tokens, verbose=False)
    return out, (time.monotonic() - t0) * 1000.0


def scored_split(task, smoke):
    """The exact rows this run scores: the test split under the K' hash law.

    perm/veto: ALL test rows (coverage 1.0). clause: first 150 (partial by
    construction). smoke overrides everything and is recorded as such.
    """
    rows = load_task(task)
    _, test = split_rows(rows)
    if smoke:
        test = test[:smoke]
    elif task == "clause":
        test = test[:CLAUSE_ROW_LIMIT]
    return test, len(split_rows(rows)[1])


def run_cell(model, tok, regime, task, rows, labels, cache_path):
    items = []
    intents = []
    malformed = 0
    degenerate = 0
    total_ms = 0.0
    for r in rows:
        intent = None
        intent_meta = {}
        if regime == "closed":
            raw, ms = gen(
                model,
                tok,
                CLOSED_INTENT_PROMPT.format(
                    vocab=", ".join(INTENT_VOCAB), text=r["text"]
                ),
                MAX_TOKENS_CLOSED_INTENT,
            )
            total_ms += ms
            pick = extract_label_strict(raw, INTENT_VOCAB)
            if pick is None:
                malformed += 1
                pick = INTENT_FALLBACK
                intent_meta["malformed_pick"] = True
                intent_meta["intent_raw"] = (raw or "")[:240]
            intent = pick
        elif regime == "self":
            raw, ms = gen(
                model, tok, SELF_INTENT_PROMPT.format(text=r["text"]),
                MAX_TOKENS_SELF_INTENT,
            )
            total_ms += ms
            intent = normalise_intent(raw)
            if not intent:
                degenerate += 1
                intent_meta["degenerate_intent"] = True

        if regime == "base" or (regime == "self" and not intent):
            prompt = BASE_PROMPT.format(labels=", ".join(labels), text=r["text"])
        else:
            prompt = INTENT_ANSWER_PROMPT.format(
                intent=intent, labels=", ".join(labels), text=r["text"]
            )
        out, ms = gen(model, tok, prompt, MAX_TOKENS_ANSWER)
        total_ms += ms

        item = {
            "id": r["id"],
            "gold": r["kind"],
            "pred_strict": extract_label_strict(out, labels),
            "pred_legacy": extract_label_legacy(out, labels),
            "completion": out or "",
        }
        if intent is not None:
            item["intent"] = intent
        item.update(intent_meta)
        items.append(item)
        if intent is not None:
            intents.append(intent)

    os.makedirs(os.path.dirname(cache_path), exist_ok=True)
    with open(cache_path, "w") as fh:
        for it in items:
            fh.write(json.dumps(it) + "\n")

    intent_hist = {}
    for i in intents:
        intent_hist[i] = intent_hist.get(i, 0) + 1
    top = max(intent_hist.values()) if intent_hist else 0
    return {
        "items": items,
        "gen_ms_total": round(total_ms, 1),
        "intent_unique": len(intent_hist),
        "intent_top_share": (top / len(intents)) if intents else None,
        "malformed_pick_rate": (malformed / len(rows)) if rows else None,
        "degenerate_intent_rate": (degenerate / len(rows)) if rows else None,
        "_intent_hist": intent_hist,
    }


def run_cast(args):
    cast_id = CASTS[args.cast]
    ts = utcnow()
    tag = f"intent-conditioning-{args.cast}-{ts}"
    if args.smoke:
        tag += "-SMOKE"
    out_dir = os.path.join(RUNS, tag)
    os.makedirs(out_dir, exist_ok=True)

    record = {
        "line": "IC",
        "gates": "MTP-GATES.md PART 5 (IC-G1..IC-G5)",
        "cast": args.cast,
        "model": cast_id,
        "smoke": bool(args.smoke),
        "started_utc": ts,
        "power": power_snapshot.snapshot(),
        "argv": sys.argv,
        "frozen": {
            "intent_vocab": INTENT_VOCAB,
            "closed_intent_prompt": CLOSED_INTENT_PROMPT,
            "self_intent_prompt": SELF_INTENT_PROMPT,
            "intent_answer_prompt": INTENT_ANSWER_PROMPT,
            "max_tokens": {
                "closed_intent": MAX_TOKENS_CLOSED_INTENT,
                "self_intent": MAX_TOKENS_SELF_INTENT,
                "answer": MAX_TOKENS_ANSWER,
            },
            "thresholds": {
                "G1_delta_pp": G1_DELTA_PP,
                "G1_p": G1_P,
                "G2_veto_floor_pp": G2_VETO_FLOOR_PP,
                "G4_self_min_unique": G4_SELF_MIN_UNIQUE,
                "G4_self_max_share": G4_SELF_MAX_SHARE,
                "G4_closed_max_malformed": G4_CLOSED_MAX_MALFORMED,
                "G5_outside_slack": G5_OUTSIDE_SLACK,
            },
        },
        "cells": {},
    }

    print(f"[ic] cast={args.cast} model={cast_id} out={out_dir}", flush=True)
    from mlx_lm import load

    t0 = time.monotonic()
    model, tok = load(cast_id)
    print(f"[ic] model loaded in {time.monotonic() - t0:.1f}s", flush=True)

    tasks = args.tasks.split(",") if args.tasks else ["perm", "veto", "clause"]
    regimes = (
        args.regimes.split(",") if args.regimes else ["base", "closed", "self"]
    )

    for task in tasks:
        labels = TASKS[task]["labels"]
        other = tuple(
            l for t2 in TASKS if t2 != task for l in TASKS[t2]["labels"]
        )
        rows, corpus_rows = scored_split(task, args.smoke)
        for regime in regimes:
            cache = os.path.join(out_dir, f"{regime}_{task}.jsonl")
            print(f"[ic] {args.cast} {regime}/{task} n={len(rows)}", flush=True)
            res = run_cell(model, tok, regime, task, rows, labels, cache)
            items = res.pop("items")
            intent_hist = res.pop("_intent_hist")
            cell = score_items(
                items, labels, other_labels=other, corpus_rows=corpus_rows
            )
            per_item = cell.pop("_per_item")
            cell.pop("_disagree", None)
            cell["trivial_baseline"] = trivial_from_items(items, labels)
            cell.update(res)
            cell["cache"] = os.path.relpath(cache, PKG)
            record["cells"].setdefault(task, {})[regime] = {
                "cell": cell,
                "per_item": per_item,
                "intent_hist_top": dict(
                    sorted(intent_hist.items(), key=lambda kv: -kv[1])[:20]
                ),
            }
            print(
                f"[ic]   acc={cell['accuracy']:.4f} n={cell['n']} "
                f"outside={cell['outside_label_set']} "
                f"coverage={cell['coverage']['coverage']}",
                flush=True,
            )

    # paired contrasts vs the in-run base, per task
    record["paired"] = {}
    for task in tasks:
        cells = record["cells"].get(task, {})
        if "base" not in cells:
            continue
        base_items = cells["base"]["per_item"]
        for regime in ("closed", "self"):
            if regime not in cells:
                continue
            record["paired"].setdefault(task, {})[regime] = mcnemar(
                base_items, cells[regime]["per_item"]
            )

    record["finished_utc"] = utcnow()
    out_path = args.out or os.path.join(out_dir, f"{tag}.json")
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, "w") as fh:
        json.dump(record, fh, indent=2)
    print(f"[ic] wrote {out_path}", flush=True)
    return record


# ---------------------------------------------------------------------------
# IC-G1..G5 evaluation (CPU; the .md is the authority, this mirrors it)
# ---------------------------------------------------------------------------

def _delta_pp(cell, base_cell):
    return (cell["accuracy"] - base_cell["accuracy"]) * 100.0


def evaluate_gates(records):
    """records: {cast_key: run_record}. Returns the gate table + verdict."""
    out = {"cells": [], "signal_cells": [], "violations": []}
    for cast, rec in records.items():
        if rec.get("smoke"):
            out["violations"].append(
                f"{cast}: run is a SMOKE run — refused as gate input"
            )
            continue
        cells = rec.get("cells", {})
        paired = rec.get("paired", {})
        for regime in ("closed", "self"):
            row = {"cast": cast, "regime": regime}
            ok_g4 = ok_g5 = True
            notes = []

            # IC-G4 intent quality (measured on perm, frozen)
            perm_cells = cells.get("perm", {})
            if regime in perm_cells:
                c = perm_cells[regime]["cell"]
                if regime == "self":
                    uniq = c.get("intent_unique", 0)
                    share = c.get("intent_top_share") or 0.0
                    ok_g4 = uniq >= G4_SELF_MIN_UNIQUE and share <= G4_SELF_MAX_SHARE
                    notes.append(f"G4: unique={uniq} top_share={share:.3f}")
                else:
                    mal = c.get("malformed_pick_rate") or 0.0
                    ok_g4 = mal <= G4_CLOSED_MAX_MALFORMED
                    notes.append(f"G4: malformed={mal:.3f}")
            else:
                ok_g4 = False
                notes.append("G4: no perm cell")

            # IC-G1/G2 on perm + veto at coverage 1.0
            signal = None
            for task, floor in (("perm", G1_DELTA_PP), ("veto", None)):
                if task not in cells or regime not in cells[task]:
                    continue
                base = cells[task]["base"]["cell"]
                c = cells[task][regime]["cell"]
                cov = (c.get("coverage") or {}).get("coverage")
                d = _delta_pp(c, base)
                m = paired.get(task, {}).get(regime, {})
                row[task] = {
                    "delta_pp": round(d, 3),
                    "mcnemar_p": m.get("p_two_sided_exact"),
                    "paired_diff": m.get("paired_diff"),
                    "discordant": {
                        "base_only_correct": m.get("a_only_correct"),
                        "regime_only_correct": m.get("b_only_correct"),
                    },
                    "common_ids_n": m.get("n_pairs"),
                    "coverage": cov,
                    "outside_base": base.get("outside_label_set"),
                    "outside_intent": c.get("outside_label_set"),
                }
                if task == "perm" and cov == 1.0:
                    ok_g5 = ok_g5 and (
                        c.get("outside_label_set", 0)
                        <= base.get("outside_label_set", 0) + G5_OUTSIDE_SLACK
                    )
                    p_val = m.get("p_two_sided_exact")
                    signal = (
                        d >= G1_DELTA_PP
                        and (p_val is not None and p_val <= G1_P)
                    )
                if task == "veto" and cov == 1.0:
                    ok_g5 = ok_g5 and (
                        c.get("outside_label_set", 0)
                        <= base.get("outside_label_set", 0) + G5_OUTSIDE_SLACK
                    )
                    if signal is not None:
                        signal = signal and d >= G2_VETO_FLOOR_PP
            row["ic_g4"] = "pass" if ok_g4 else "FAIL"
            row["ic_g5"] = "pass" if ok_g5 else "FAIL"
            row["signal"] = bool(signal and ok_g4 and ok_g5)
            row["notes"] = notes
            out["cells"].append(row)
            if row["signal"]:
                out["signal_cells"].append(f"{cast}/{regime}")

    out["verdict"] = "PASS" if out["signal_cells"] else "FAIL"
    # the pre-registered readings (Part 5)
    sig = set(out["signal_cells"])
    readings = []
    if any(s.endswith("/closed") and s.startswith("0.6b") for s in sig):
        readings.append("reading 1: closed-set intent signals at 0.6B — the "
                        "productizable shape is ranker/laya-supplied intent")
    if "1.7b/self" in sig and "0.6b/self" not in sig:
        readings.append("reading 2: self-authored intent is scale-gated "
                        "(signals at 1.7B only)")
    if not sig:
        readings.append("reading 3: no SIGNAL cell — intent conditioning "
                        "closes WITH DATA on closed-set decision shapes; "
                        "claim B stays closed (Stage-0); the remaining "
                        "intent-first route is a generation-shaped arm "
                        "(NEW oracle, NOT scheduled)")
    if "0.6b/self" in sig and "1.7b/self" in sig and "0.6b/closed" in sig \
            and "1.7b/closed" in sig:
        readings.append("reading 5: every cell signals — the mechanism is the "
                        "procedure line itself; trained-intent arm is the "
                        "registered follow-up")
    out["readings_fired"] = readings
    return out


def find_latest(cast):
    cands = sorted(
        d
        for d in os.listdir(RUNS)
        if d.startswith(f"intent-conditioning-{cast}-") and not d.endswith("SMOKE")
    )
    if not cands:
        raise SystemExit(f"no completed non-smoke run for cast {cast} in {RUNS}")
    return cands[-1]


def verdict(args):
    records = {}
    for cast in ("0.6b", "1.7b"):
        if args.run_dirs and args.run_dirs.get(cast):
            d = args.run_dirs[cast]
        else:
            d = find_latest(cast)
        path = os.path.join(RUNS, d)
        js = [f for f in os.listdir(path) if f.endswith(".json") and f.startswith("intent-conditioning")]
        if not js:
            raise SystemExit(f"no run record json in {path}")
        with open(os.path.join(path, sorted(js)[-1])) as fh:
            records[cast] = json.load(fh)
    g = evaluate_gates(records)
    out_path = args.out or os.path.join(
        RUNS, f"intent-conditioning-verdict-{utcnow()}.json"
    )
    with open(out_path, "w") as fh:
        json.dump({"gates": g, "runs": {k: v.get("run_dir") for k, v in records.items()}}, fh, indent=2)
    print(json.dumps(g, indent=2))
    print(f"[ic] verdict record: {out_path}")
    return g


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--cast", choices=sorted(CASTS))
    ap.add_argument("--tasks")
    ap.add_argument("--regimes")
    ap.add_argument("--smoke", type=int, default=0)
    ap.add_argument("--out")
    ap.add_argument("--verdict", action="store_true")
    ap.add_argument("--run-06b")
    ap.add_argument("--run-17b")
    args = ap.parse_args(argv)
    if args.verdict:
        args.run_dirs = {"0.6b": args.run_06b, "1.7b": args.run_17b}
        verdict(args)
        return 0
    if not args.cast:
        ap.error("--cast is required for a run (or use --verdict)")
    run_cast(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
