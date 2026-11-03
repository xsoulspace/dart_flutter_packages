"""Line SK — skeleton→fill on decompression-shaped generation.

Gates: MTP-GATES.md PART 7, SK-G0..SK-G5 (frozen 2026-11-03 BEFORE any run).

The owner's intent-first proposal in its generation-shaped form: pass 1
lists the key facts a one-line summary must retain (the skeleton), pass 2
fills the one-liner conditioned on it. The oracle is the lane's EXISTING
deterministic decompression law (one line, <=280 bytes, >=2 of 5 entity
hits), byte-continuous with `tool/model_bench_suite.dart`'s
`_runDecompression` — including its `_answerOf` normalisation (closed think
blocks removed; an unclosed `<think>` truncates; trim), mirrored below.

Arms (single variable = what pass 2 is conditioned on):
  base      one pass, the tracked lane prompt byte-identical
  skeleton  pass 1 authors the key-facts list (<=64 tokens); pass 2 fills
  generic   pass 2 conditioned on the CONSTANT pseudo-skeleton
            `the key facts and names from the record` (structure control)

Corpora: the generated 90 (GATING; sha-pinned by SK-G0) + the tracked
frozen 10 (continuity, SK-G2). Full per-case caches ⇒ CPU replay.

Usage:
  python tool/nursery/skeleton_fill.py --decider 1.7b
  python tool/nursery/skeleton_fill.py --decider 0.6b
  python tool/nursery/skeleton_fill.py --verdict
  python tool/nursery/skeleton_fill.py --decider 0.6b --smoke 3
"""

import argparse
import hashlib
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
from intent_conditioning import gen  # noqa: E402  (same frozen chat-template path)
from scoring import mcnemar  # noqa: E402

RUNS = os.path.join(PKG, "bench", "nursery", "experiments")
GENERATED = os.path.join(PKG, "bench", "nursery", "data", "decomp_skeleton_dataset.json")
TRACKED = os.path.join(PKG, "testdata", "bench", "decompression_lane.json")

DECIDERS = {
    "0.6b": "mlx-community/Qwen3-0.6B-4bit",
    "1.7b": "mlx-community/Qwen3-1.7B-4bit",
}

# ---------------------------------------------------------------------------
# Frozen by MTP-GATES.md Part 7.
# ---------------------------------------------------------------------------
GENERATED_SHA256 = (
    "cac823a79c9ce37535ce483e839ec5daa61db25b8d5fd633b0f23a04a42c5c2c"
)
N_GENERATED = 90
MAX_OUTPUT_BYTES = 280
MIN_ENTITY_HITS = 2
CASE_MAX_TOKENS = 96
SKELETON_MAX_TOKENS = 64
GENERIC_SKELETON = "the key facts and names from the record"

BASE_PROMPT = (
    "Summarize this memory record as ONE line of at most "
    f"{MAX_OUTPUT_BYTES} bytes (keep the key facts and names):\n"
    "{record}\nOne line:"
)
SKELETON_PROMPT = (
    "List the key facts and names that a one-line summary of this record "
    "must retain, at most 5, one per line. Stop after the list.\n\n"
    "Record: {record}\nKey facts:"
)
FILL_PROMPT = (
    f"Write ONE line of at most {MAX_OUTPUT_BYTES} bytes summarizing the "
    "record. Retain exactly these key facts and names:\n{skeleton}\n\n"
    "Record: {record}\nOne line:"
)

G1_DELTA_PP = 5.0
G1_P = 0.05
G1_HEADROOM = 0.90
G2_CONTINUITY_SLACK = 1
G2_HARM_PP = -5.0
G3_SKELETON_ENTITY_COVERAGE = 0.40
G4_INERT_BAND_PP = 5.0
G5_GENERIC_DELTA_PP = 2.0

THINK_CLOSED = re.compile(r"<think>.*?</think>", re.S)


def answer_of(text):
    """The Dart lane's `_answerOf`, mirrored byte-for-byte in rule."""
    stripped = THINK_CLOSED.sub("", text or "")
    open_at = stripped.find("<think>")
    if open_at >= 0:
        stripped = stripped[:open_at]
    return stripped.strip()


def utcnow():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")


def load_corpora():
    sha = hashlib.sha256(open(GENERATED, "rb").read()).hexdigest()
    if sha != GENERATED_SHA256:
        raise SystemExit(
            f"SK-G0 REFUSAL: generated corpus sha256 {sha} != frozen "
            f"{GENERATED_SHA256} — regenerate with the frozen generator or "
            "register a NEW Part; the run refuses stale/corpus drift"
        )
    with open(GENERATED) as fh:
        gen_ds = json.load(fh)
    if len(gen_ds["cases"]) != N_GENERATED:
        raise SystemExit(f"SK-G0 REFUSAL: n={len(gen_ds['cases'])} != {N_GENERATED}")
    for key, want in (
        ("max_output_bytes", MAX_OUTPUT_BYTES),
        ("min_entity_hits", MIN_ENTITY_HITS),
    ):
        if gen_ds[key] != want:
            raise SystemExit(f"SK-G0 REFUSAL: {key}={gen_ds[key]} != {want}")
    with open(TRACKED) as fh:
        tracked = json.load(fh)
    if (
        tracked["max_output_bytes"] != MAX_OUTPUT_BYTES
        or tracked["min_entity_hits"] != MIN_ENTITY_HITS
    ):
        raise SystemExit("SK-G0 REFUSAL: tracked lane constants drifted")
    return gen_ds, tracked, sha


def oracle(text, entities):
    """The decompression law: one line, <= cap bytes, >= min entity hits."""
    answer = answer_of(text)
    nbytes = len(answer.encode("utf-8"))
    one_line = "\n" not in answer
    hits = [e for e in entities if e in answer]
    reasons = []
    if nbytes > MAX_OUTPUT_BYTES:
        reasons.append(f"output {nbytes} bytes > {MAX_OUTPUT_BYTES} cap")
    if not one_line:
        reasons.append("output is not a single line")
    if len(hits) < MIN_ENTITY_HITS:
        reasons.append(f"entity recall {len(hits)}/{MIN_ENTITY_HITS} of {len(entities)}")
    return {
        "ok": not reasons,
        "reason": "; ".join(reasons) or None,
        "bytes": nbytes,
        "one_line": one_line,
        "hits": hits,
        "answer": answer,
    }


def run_arm(model, tok, arm, cases, cache_path):
    items = []
    total_ms = 0.0
    skel_entity_mentions = 0
    skel_entity_total = 0
    for c in cases:
        record = c["record"]
        entities = c["entities"]
        skeleton = None
        if arm == "skeleton":
            raw, ms = gen(
                model, tok, SKELETON_PROMPT.format(record=record),
                SKELETON_MAX_TOKENS,
            )
            total_ms += ms
            skeleton = answer_of(raw)
            skel_entity_mentions += sum(1 for e in entities if e in (skeleton or ""))
            skel_entity_total += len(entities)
        if arm == "base":
            prompt = BASE_PROMPT.format(record=record)
        else:
            cond = skeleton if arm == "skeleton" else GENERIC_SKELETON
            if arm == "skeleton" and not cond:
                cond = GENERIC_SKELETON  # loud fallback, counted below
            prompt = FILL_PROMPT.format(skeleton=cond, record=record)
        out, ms = gen(model, tok, prompt, CASE_MAX_TOKENS)
        total_ms += ms
        verdict = oracle(out, entities)
        items.append(
            {
                "id": c["id"],
                "arm": arm,
                "skeleton": skeleton,
                "fill_raw": out or "",
                "ok": verdict["ok"],
                "reason": verdict["reason"],
                "bytes": verdict["bytes"],
                "one_line": verdict["one_line"],
                "hits": verdict["hits"],
                "answer": verdict["answer"],
            }
        )
    os.makedirs(os.path.dirname(cache_path), exist_ok=True)
    with open(cache_path, "w") as fh:
        for it in items:
            fh.write(json.dumps(it) + "\n")
    n = len(items)
    passes = sum(1 for it in items if it["ok"])
    return {
        "n": n,
        "pass_rate": passes / max(1, n),
        "passes": passes,
        "gen_ms_total": round(total_ms, 1),
        "skeleton_entity_coverage": (
            skel_entity_mentions / skel_entity_total if skel_entity_total else None
        ),
        "empty_skeleton": sum(
            1 for it in items if arm == "skeleton" and not (it["skeleton"] or "").strip()
        ),
        "items": items,
    }


def per_item(res):
    return [
        {"id": it["id"], "gold": None, "pred": None, "ok": it["ok"]}
        for it in res["items"]
    ]


def run_decider(args):
    model_id = DECIDERS[args.decider]
    gen_ds, tracked, sha = load_corpora()
    ts = utcnow()
    tag = f"sk-fill-{args.decider}-{ts}"
    if args.smoke:
        tag += "-SMOKE"
    out_dir = os.path.join(RUNS, tag)
    os.makedirs(out_dir, exist_ok=True)

    record = {
        "line": "SK",
        "gates": "MTP-GATES.md PART 7 (SK-G0..SK-G5)",
        "decider": args.decider,
        "model": model_id,
        "smoke": bool(args.smoke),
        "started_utc": ts,
        "power": power_snapshot.snapshot(),
        "argv": sys.argv,
        "sk_g0": {
            "generated_sha256": sha,
            "frozen_sha256": GENERATED_SHA256,
            "n_generated": len(gen_ds["cases"]),
            "n_tracked": len(tracked["cases"]),
            "oracle_law": {
                "max_output_bytes": MAX_OUTPUT_BYTES,
                "min_entity_hits": MIN_ENTITY_HITS,
                "case_max_tokens": CASE_MAX_TOKENS,
                "skeleton_max_tokens": SKELETON_MAX_TOKENS,
            },
            "generator_sha256": hashlib.sha256(
                open(os.path.join(HERE, "decomp_skeleton_dataset.py"), "rb").read()
            ).hexdigest(),
        },
        "frozen": {
            "base_prompt": BASE_PROMPT,
            "skeleton_prompt": SKELETON_PROMPT,
            "fill_prompt": FILL_PROMPT,
            "generic_skeleton": GENERIC_SKELETON,
            "thresholds": {
                "G1_delta_pp": G1_DELTA_PP, "G1_p": G1_P,
                "G1_headroom": G1_HEADROOM,
                "G2_continuity_slack": G2_CONTINUITY_SLACK,
                "G2_harm_pp": G2_HARM_PP,
                "G3_skeleton_entity_coverage": G3_SKELETON_ENTITY_COVERAGE,
                "G4_inert_band_pp": G4_INERT_BAND_PP,
                "G5_generic_delta_pp": G5_GENERIC_DELTA_PP,
            },
        },
        "corpora": {},
    }

    print(f"[sk] decider={args.decider} model={model_id}", flush=True)
    from mlx_lm import load

    t0 = time.monotonic()
    model, tok = load(model_id)
    print(f"[sk] loaded in {time.monotonic() - t0:.1f}s", flush=True)

    arms = args.arms.split(",") if args.arms else ["base", "skeleton", "generic"]
    corpora = {"generated": gen_ds["cases"], "tracked": tracked["cases"]}
    if args.smoke:
        corpora = {k: v[: args.smoke] for k, v in corpora.items()}

    for cname, cases in corpora.items():
        for arm in arms:
            cache = os.path.join(out_dir, f"{arm}_{cname}.jsonl")
            print(f"[sk] {args.decider} {arm}/{cname} n={len(cases)}", flush=True)
            res = run_arm(model, tok, arm, cases, cache)
            items = res.pop("items")
            record["corpora"].setdefault(cname, {})[arm] = {
                "cell": res,
                "per_item": per_item({"items": items}),
                "cache": os.path.relpath(cache, PKG),
            }
            print(
                f"[sk]   pass={res['pass_rate']:.4f} ({res['passes']}/{res['n']})"
                + (
                    f" skel_cov={res['skeleton_entity_coverage']:.3f}"
                    if res["skeleton_entity_coverage"] is not None
                    else ""
                ),
                flush=True,
            )

    record["paired"] = {}
    for cname in corpora:
        cells = record["corpora"].get(cname, {})
        if "base" not in cells:
            continue
        for arm in ("skeleton", "generic"):
            if arm not in cells:
                continue
            record["paired"].setdefault(cname, {})[arm] = mcnemar(
                cells["base"]["per_item"], cells[arm]["per_item"]
            )

    record["finished_utc"] = utcnow()
    out_path = args.out or os.path.join(out_dir, f"{tag}.json")
    with open(out_path, "w") as fh:
        json.dump(record, fh, indent=2)
    print(f"[sk] wrote {out_path}", flush=True)
    return record


# ---------------------------------------------------------------------------
# SK-G0..G5 evaluation (CPU; Part 7 is the authority)
# ---------------------------------------------------------------------------

def evaluate(records):
    out = {"cells": [], "signal_cells": [], "harm_cells": [], "inert_cells": [],
           "violations": [], "continuity": [], "g3": []}
    for dec, rec in records.items():
        if rec.get("smoke"):
            out["violations"].append(f"{dec}: SMOKE run — refused as gate input")
            continue
        if rec["sk_g0"]["generated_sha256"] != rec["sk_g0"]["frozen_sha256"]:
            out["violations"].append(f"{dec}: SK-G0 sha mismatch")
            continue
        corp = rec.get("corpora", {})
        paired = rec.get("paired", {})
        g = corp.get("generated", {})
        if not g:
            continue
        base_rate = g["base"]["cell"]["pass_rate"]
        headroom = base_rate <= G1_HEADROOM
        for arm in ("skeleton", "generic"):
            if arm not in g:
                continue
            p = paired.get("generated", {}).get(arm, {})
            d = -p["paired_diff"] * 100.0  # arm − base, pp
            ci = [-p["ci95"][1] * 100.0, -p["ci95"][0] * 100.0]
            cell = g[arm]["cell"]
            g3_ok = True
            if arm == "skeleton":
                cov = cell.get("skeleton_entity_coverage")
                g3_ok = cov is not None and cov >= G3_SKELETON_ENTITY_COVERAGE
                out["g3"].append({"decider": dec, "coverage": cov,
                                  "ok": g3_ok,
                                  "empty_skeleton": cell.get("empty_skeleton")})
            signal = bool(
                headroom and g3_ok and d >= G1_DELTA_PP
                and p["p_two_sided_exact"] <= G1_P
            )
            inert = bool(ci[0] >= -G4_INERT_BAND_PP and ci[1] <= G4_INERT_BAND_PP)
            harm = bool(d <= G2_HARM_PP and p["p_two_sided_exact"] <= G1_P)
            row = {
                "decider": dec, "arm": arm,
                "base_pass": round(base_rate, 4),
                "arm_pass": round(cell["pass_rate"], 4),
                "delta_pp": round(d, 3),
                "ci95_pp": [round(ci[0], 3), round(ci[1], 3)],
                "p": p["p_two_sided_exact"],
                "discordant": {"base_only": p["a_only_correct"],
                               "arm_only": p["b_only_correct"]},
                "headroom_ok": headroom,
                "sk_g3": "pass" if g3_ok else "FAIL",
                "signal": signal, "inert": inert, "harm": harm,
            }
            out["cells"].append(row)
            key = f"{dec}/{arm}"
            if signal:
                out["signal_cells"].append(key)
            if inert:
                out["inert_cells"].append(key)
            if harm:
                out["harm_cells"].append(key)
        # SK-G2 continuity on the tracked 10
        t = corp.get("tracked", {})
        if {"base", "skeleton"} <= set(t):
            bp = t["base"]["cell"]["passes"]
            sp = t["skeleton"]["cell"]["passes"]
            ok = sp >= bp - G2_CONTINUITY_SLACK
            out["continuity"].append(
                {"decider": dec, "base_passes": bp, "skeleton_passes": sp,
                 "n": t["base"]["cell"]["n"], "ok": ok}
            )
            if not ok:
                out["violations"].append(
                    f"{dec}: SK-G2 continuity — skeleton {sp} < base {bp} − 1 "
                    "on the tracked 10 (two-pass shape artifact; recorded)"
                )

    # SK-G5 interpretation law
    sig = set(out["signal_cells"])
    readings = []
    for dec in DECIDERS:
        sk, gn = f"{dec}/skeleton" in sig, f"{dec}/generic" in sig
        gcell = next((r for r in out["cells"] if r["decider"] == dec
                      and r["arm"] == "generic"), None)
        generic_signals = gn or (
            gcell is not None and gcell["delta_pp"] >= G5_GENERIC_DELTA_PP
            and gcell["p"] <= G1_P
        )
        if sk and not generic_signals:
            readings.append(
                f"SK-G5({dec}): skeleton SIGNAL without generic ⇒ the "
                "SKELETON CONTENT matters — intent-first survives in "
                "generation shape")
        elif sk and generic_signals:
            readings.append(
                f"SK-G5({dec}): skeleton ≈ generic both signal ⇒ two-pass "
                "STRUCTURE/priming, not skeleton content")
    if not sig:
        readings.append(
            "SK-G5: neither arm signals ⇒ the intent-first line closes WITH "
            "DATA on constrained generation as well; only the open-form "
            "route (owed blind-rubric oracle) remains")
    if out["harm_cells"]:
        readings.append(f"SK-G2 harm law fired: {out['harm_cells']}")
    out["verdict"] = "PASS" if out["signal_cells"] else "FAIL"
    out["readings_fired"] = readings
    return out


def find_latest(decider):
    cands = sorted(
        d for d in os.listdir(RUNS)
        if d.startswith(f"sk-fill-{decider}-") and not d.endswith("SMOKE")
    )
    if not cands:
        raise SystemExit(f"no completed non-smoke SK run for {decider}")
    return cands[-1]


def verdict(args):
    records = {}
    for dec in DECIDERS:
        d = (args.run_dirs or {}).get(dec) or find_latest(dec)
        path = os.path.join(RUNS, d)
        js = sorted(f for f in os.listdir(path)
                    if f.startswith("sk-fill") and f.endswith(".json"))
        with open(os.path.join(path, js[-1])) as fh:
            records[dec] = json.load(fh)
        records[dec]["run_dir"] = d
    g = evaluate(records)
    out_path = args.out or os.path.join(RUNS, f"sk-fill-verdict-{utcnow()}.json")
    with open(out_path, "w") as fh:
        json.dump({"gates": g,
                   "runs": {k: v.get("run_dir") for k, v in records.items()}},
                  fh, indent=2)
    print(json.dumps(g, indent=2))
    print(f"[sk] verdict record: {out_path}")
    return g


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--decider", choices=sorted(DECIDERS))
    ap.add_argument("--arms")
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
    if not args.decider:
        ap.error("--decider is required for a run (or use --verdict)")
    run_decider(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
