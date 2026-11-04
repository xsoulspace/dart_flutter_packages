"""Line LB — completion@N loop-bench: S1 (closed-set decision loop) and
S3 (gated draft / decomposition loop). S2 (scoped tool tasks) runs through
the harness executor — see loop_bench/s2_drive.sh.

Gates: MTP-GATES.md PART 8 (frozen 2026-11-04 BEFORE any run; owner go
2026-11-04 "do phase 1 and freeze gates as recommended"). This file holds
the frozen constants; changing any of them after the first gated run makes
a NEW arm requiring a NEW frozen Part.

Shapes (program Phase 1):
  S1  closed-set decision — perm(293)/veto(227) test rows, the CONFIRMED
      0.6B+untagged-LoRA decider. Per row: greedy top-1 (the G0
      reproduction guard) + N=4 sampled candidates (temp 0.8, top_p 0.95)
      + the SELECTION loop: the ranker re-asked with the option list
      restricted to the distinct valid sampled candidates (its native
      closed-vocab shape), greedy. Malformed selection -> plurality
      fallback (counted loud); zero valid candidates -> greedy label
      (counted loud).
  S3  gated draft — the deterministic decompression oracle (one line,
      <=280 B, >=2-of-5 entities; corpus sha-guarded). Cast: Qwen3-0.6B
      BASE (the qwen decomposition cell has never been measured; the
      8-9/10 receipt is lfm's). Per case: greedy 1 + N=4 samples, cap 96.

Scoring: PRIMARY = scoring.extract_label_first_line (S1) and the
skeleton_fill oracle (S3) — both canonical, frozen before this run.
Full per-item completion caches; every verdict is CPU replay.

Usage:
  ~/.venvs/mlx-ref/bin/python tool/nursery/loop_bench.py --shape s1 --task perm
  ~/.venvs/mlx-ref/bin/python tool/nursery/loop_bench.py --shape s1 --task veto
  ~/.venvs/mlx-ref/bin/python tool/nursery/loop_bench.py --shape s3
  ~/.venvs/mlx-ref/bin/python tool/nursery/loop_bench.py --verdict --evidence DIR
  (--smoke N on any run shape; smoke runs are recorded as smoke, never gated)
"""

import argparse
import hashlib
import json
import math
import os
import sys
import time
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

from adapter_conditioning import BASE_PROMPT, TASKS, load_task, split_rows  # noqa: E402
import skeleton_fill as sk  # noqa: E402
from scoring import extract_label_first_line, mcnemar  # noqa: E402

# ---------------------------------------------------------------------------
# Frozen by MTP-GATES.md Part 8. Do not change after the first gated run.
# ---------------------------------------------------------------------------
S1_MODEL = "mlx-community/Qwen3-0.6B-4bit"
S1_ADAPTER = os.path.join(
    PKG,
    "bench/nursery/experiments/adapter-conditioning-2026-10-21",
    "adapter_untagged",
)
S3_MODEL = "mlx-community/Qwen3-0.6B-4bit"  # base, no adapter
N_SAMPLES = 4
TEMP = 0.8
TOP_P = 0.95
S1_CAP = 16
S3_CAP = 96
G0_BASELINE = {"perm": 0.8737201365187713, "veto": 0.7533039647577092}
G0_TOL_PP = 2.0
G1_SLACK_PP = 1.0
G3_TRACKED_MIN_PASSES = 9  # of 10, at pass@4


def utcnow():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")


def evidence_dir():
    d = os.path.join(
        PKG, "bench", "nursery", "experiments",
        "loop-bench-" + datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ"),
    )
    os.makedirs(d, exist_ok=True)
    return d


def chat(tok, prompt):
    return tok.apply_chat_template(
        [{"role": "user", "content": prompt}],
        add_generation_prompt=True,
        tokenize=False,
        enable_thinking=False,
    )


def gen_greedy(model, tok, prompt, cap):
    from mlx_lm import generate
    t0 = time.monotonic()
    out = generate(model, tok, prompt=chat(tok, prompt), max_tokens=cap,
                   verbose=False)
    return out, (time.monotonic() - t0) * 1000.0


def gen_sample(model, tok, prompt, cap):
    from mlx_lm import generate
    from mlx_lm.sample_utils import make_sampler
    sampler = make_sampler(temp=TEMP, top_p=TOP_P)
    t0 = time.monotonic()
    out = generate(model, tok, prompt=chat(tok, prompt), max_tokens=cap,
                   verbose=False, sampler=sampler)
    return out, (time.monotonic() - t0) * 1000.0


def wilson(k, n, z=1.959963984540054):
    if n == 0:
        return (0.0, 0.0)
    p = k / n
    d = 1 + z * z / n
    c = p + z * z / (2 * n)
    m = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return ((c - m) / d, (c + m) / d)


def plurality(cands, samples_labels):
    counts = {}
    for lab in samples_labels:
        counts[lab] = counts.get(lab, 0) + 1
    best = max(counts.values())
    for lab in cands:  # first-appearance order breaks ties (frozen)
        if counts.get(lab, 0) == best:
            return lab
    return cands[0]


# ---------------------------------------------------------------------------
# S1 — closed-set decision loop
# ---------------------------------------------------------------------------

def run_s1(task, smoke, out_dir):
    from mlx_lm import load
    rows_all = load_task(task)
    _, test = split_rows(rows_all)
    if smoke:
        test = test[:smoke]
    labels = TASKS[task]["labels"]
    print(f"[{utcnow()}] S1 {task}: {len(test)} rows, decider 0.6b_adapter, "
          f"N={N_SAMPLES} temp={TEMP} top_p={TOP_P} cap={S1_CAP} "
          f"smoke={smoke or 0}")
    model, tok = load(S1_MODEL, adapter_path=S1_ADAPTER)
    items = []
    for i, r in enumerate(test):
        prompt = BASE_PROMPT.format(labels=", ".join(labels), text=r["text"])
        greedy, g_ms = gen_greedy(model, tok, prompt, S1_CAP)
        samples = []
        for _ in range(N_SAMPLES):
            out, ms = gen_sample(model, tok, prompt, S1_CAP)
            samples.append({"completion": out, "ms": ms})
        sample_labels = [extract_label_first_line(s["completion"], labels)
                         for s in samples]
        valid = []
        for lab in sample_labels:
            if lab is not None and lab not in valid:
                valid.append(lab)
        flags = []
        sel_completion = None
        if not valid:
            sel = extract_label_first_line(greedy, labels)
            flags.append("zero_valid_candidates")
        else:
            sel_prompt = BASE_PROMPT.format(labels=", ".join(valid),
                                            text=r["text"])
            sel_out, s_ms = gen_greedy(model, tok, sel_prompt, S1_CAP)
            sel_completion = {"completion": sel_out, "ms": s_ms}
            sel = extract_label_first_line(sel_out, valid)
            if sel is None:
                sel = plurality(valid, [l for l in sample_labels if l])
                flags.append("selection_malformed_plurality_fallback")
        items.append({
            "id": r["id"], "gold": r["kind"],
            "greedy": {"completion": greedy, "ms": g_ms},
            "samples": samples,
            "sample_labels": sample_labels,
            "valid_candidates": valid,
            "selection": sel_completion,
            "selected": sel,
            "flags": flags,
        })
        if (i + 1) % 25 == 0:
            print(f"  [{utcnow()}] {i + 1}/{len(test)}")
    path = os.path.join(out_dir, f"s1_{task}.json")
    with open(path, "w") as fh:
        json.dump({"shape": "s1", "task": task, "n": len(test),
                   "smoke": smoke or 0, "frozen": {
                       "model": S1_MODEL, "adapter": S1_ADAPTER,
                       "n_samples": N_SAMPLES, "temp": TEMP, "top_p": TOP_P,
                       "cap": S1_CAP},
                   "items": items}, fh, indent=1)
    print(f"[{utcnow()}] S1 {task} cached -> {path}")


# ---------------------------------------------------------------------------
# S3 — gated draft / decomposition loop
# ---------------------------------------------------------------------------

def run_s3(smoke, out_dir):
    from mlx_lm import load
    gen_ds, tracked, sha = sk.load_corpora()  # refuses sha drift (SK-G0 law)
    cases = [("tracked", c) for c in tracked["cases"]] + \
            [("generated", c) for c in gen_ds["cases"]]
    if smoke:
        cases = cases[:smoke]
    print(f"[{utcnow()}] S3: {len(cases)} cases (corpus sha {sha[:12]}…), "
          f"cast 0.6B base, N={N_SAMPLES} temp={TEMP} top_p={TOP_P} cap={S3_CAP}")
    model, tok = load(S3_MODEL)
    items = []
    for i, (src, c) in enumerate(cases):
        prompt = sk.BASE_PROMPT.format(record=c["record"])
        greedy, g_ms = gen_greedy(model, tok, prompt, S3_CAP)
        g_pass = sk.oracle(greedy, c["entities"])["ok"]
        samples = []
        s_passes = []
        for _ in range(N_SAMPLES):
            out, ms = gen_sample(model, tok, prompt, S3_CAP)
            ok = sk.oracle(out, c["entities"])["ok"]
            samples.append({"completion": out, "ms": ms, "pass": ok})
            s_passes.append(ok)
        items.append({
            "source": src, "id": c.get("id", i),
            "greedy": {"completion": greedy, "ms": g_ms, "pass": g_pass},
            "samples": samples,
            "pass_at_4": any(s_passes),
        })
        if (i + 1) % 20 == 0:
            print(f"  [{utcnow()}] {i + 1}/{len(cases)}")
    path = os.path.join(out_dir, "s3.json")
    with open(path, "w") as fh:
        json.dump({"shape": "s3", "n": len(cases), "smoke": smoke or 0,
                   "corpus_sha256": sha, "frozen": {
                       "model": S3_MODEL, "n_samples": N_SAMPLES,
                       "temp": TEMP, "top_p": TOP_P, "cap": S3_CAP},
                   "items": items}, fh, indent=1)
    print(f"[{utcnow()}] S3 cached -> {path}")


# ---------------------------------------------------------------------------
# Verdict — CPU replay only (LB-G5)
# ---------------------------------------------------------------------------

def verdict(ev):
    res = {"evidence": ev, "at": utcnow(), "gates": {}, "readings": {}}
    refuse = None

    s1 = {}
    for task in ("perm", "veto"):
        p = os.path.join(ev, f"s1_{task}.json")
        if os.path.exists(p):
            with open(p) as fh:
                s1[task] = json.load(fh)
    for task, rec in s1.items():
        items = rec["items"]
        n = len(items)
        smoke = rec.get("smoke", 0)
        g = sum(1 for it in items
                if extract_label_first_line(it["greedy"]["completion"],
                                            TASKS[task]["labels"]) == it["gold"])
        greedy_acc = g / max(1, n)
        sel_ok = sum(1 for it in items if it["selected"] == it["gold"])
        sel_acc = sel_ok / max(1, n)
        pass4 = sum(1 for it in items if it["gold"] in it["valid_candidates"])
        pass4_rate = pass4 / max(1, n)
        zero_valid = sum(1 for it in items
                         if "zero_valid_candidates" in it["flags"])
        sel_malformed = sum(1 for it in items
                            if "selection_malformed_plurality_fallback"
                            in it["flags"])
        mc = mcnemar(
            [{"id": it["id"], "ok": extract_label_first_line(
                it["greedy"]["completion"], TASKS[task]["labels"]) == it["gold"]}
             for it in items],
            [{"id": it["id"], "ok": it["selected"] == it["gold"]}
             for it in items],
        )
        base = G0_BASELINE[task]
        g0_ok = abs(greedy_acc - base) * 100 <= G0_TOL_PP and not smoke
        g1_ok = (sel_acc * 100 >= greedy_acc * 100 - G1_SLACK_PP
                 and sel_malformed == 0 and not smoke)
        res["readings"][f"s1_{task}"] = {
            "n": n, "smoke": smoke, "greedy_acc": greedy_acc,
            "g0_baseline": base, "g0_delta_pp": (greedy_acc - base) * 100,
            "selection_acc": sel_acc,
            "selection_minus_greedy_pp": (sel_acc - greedy_acc) * 100,
            "selection_ci95": mc.get("ci95"),
            "mcnemar_p": mc.get("p_two_sided_exact"),
            "pass_at_4_rate": pass4_rate,
            "pass_at_4_ci95": wilson(pass4, n),
            "zero_valid_candidates": zero_valid,
            "selection_malformed": sel_malformed,
        }
        res["gates"][f"LB-G0[{task}]"] = "PASS" if g0_ok else (
            "SMOKE" if smoke else "FAIL")
        res["gates"][f"LB-G1[{task}]"] = "PASS" if g1_ok else (
            "SMOKE" if smoke else "FAIL")
        if not g0_ok and not smoke:
            refuse = (f"LB-G0 REFUSAL [{task}]: greedy {greedy_acc:.4f} vs "
                      f"frozen baseline {base:.4f} (>{G0_TOL_PP}pp) — "
                      "instrument drift; no gate may pass on this run")
    if s1 and any(not os.path.exists(os.path.join(ev, f"s1_{t}.json"))
                  for t in ("perm", "veto")):
        res["gates"]["LB-G1"] = "PARTIAL (missing task cell)"

    p = os.path.join(ev, "s3.json")
    if os.path.exists(p):
        with open(p) as fh:
            rec = json.load(fh)
        items = rec["items"]
        smoke = rec.get("smoke", 0)
        if rec.get("corpus_sha256") != sk.GENERATED_SHA256:
            refuse = refuse or "LB-G3 REFUSAL: corpus sha drift"
        tracked = [it for it in items if it["source"] == "tracked"]
        generated = [it for it in items if it["source"] == "generated"]
        t_pass4 = sum(1 for it in tracked if it["pass_at_4"])
        g1_pass = sum(1 for it in generated if it["greedy"]["pass"])
        g4_pass = sum(1 for it in generated if it["pass_at_4"])
        ng = len(generated)
        res["readings"]["s3"] = {
            "n_tracked": len(tracked), "n_generated": ng, "smoke": smoke,
            "tracked_pass_at_4": f"{t_pass4}/{len(tracked)}",
            "tracked_greedy_pass": sum(1 for it in tracked
                                       if it["greedy"]["pass"]),
            "generated_pass_at_1": g1_pass / max(1, ng),
            "generated_pass_at_1_ci95": wilson(g1_pass, ng),
            "generated_pass_at_4": g4_pass / max(1, ng),
            "generated_pass_at_4_ci95": wilson(g4_pass, ng),
        }
        g3_ok = (t_pass4 >= G3_TRACKED_MIN_PASSES and len(tracked) == 10
                 and not smoke)
        res["gates"]["LB-G3"] = "PASS" if g3_ok else ("SMOKE" if smoke
                                                      else "FAIL")
    # S2 receipts (written by s2_drive.sh) — scored here, CPU only.
    s2p = os.path.join(ev, "s2_receipts.json")
    if os.path.exists(s2p):
        with open(s2p) as fh:
            s2 = json.load(fh)
        trials = s2["trials"]
        by_task = {}
        integrity_bad = 0
        for tr in trials:
            by_task.setdefault(tr["task"], []).append(tr)
            if not tr.get("verify_sha_intact", False):
                integrity_bad += 1
        n_tasks = len(by_task)
        per_rep = {}
        pass3_tasks = 0
        first_pass = 0
        for tid, trs in sorted(by_task.items()):
            states = {tr["rep"]: tr["succeeded"] for tr in trs}
            per_rep[tid] = states
            if states.get(1):
                first_pass += 1
            if any(states.get(r) for r in (1, 2, 3)):
                pass3_tasks += 1
        coverage = n_tasks / s2.get("n_bank", n_tasks) if n_tasks else 0.0
        pass3 = pass3_tasks / max(1, n_tasks)
        res["readings"]["s2"] = {
            "n_tasks": n_tasks, "n_bank": s2.get("n_bank"),
            "coverage": coverage,
            "trials": len(trials),
            "first_attempt_pass_rate": first_pass / max(1, n_tasks),
            "first_attempt_ci95": wilson(first_pass, n_tasks),
            "pass_at_3": pass3, "pass_at_3_ci95": wilson(pass3_tasks, n_tasks),
            "integrity_violations": integrity_bad,
            "failure_reasons": {
                reason: sum(1 for tr in trials
                            if not tr["succeeded"] and tr.get("reason") == reason)
                for reason in sorted({tr.get("reason") for tr in trials
                                      if not tr["succeeded"]
                                      and tr.get("reason")})
            },
            "per_task": per_rep,
        }
        g2_ok = (coverage == 1.0 and integrity_bad == 0
                 and pass3 >= 0.50 and not s2.get("smoke"))
        if coverage < 1.0 and not s2.get("smoke"):
            res["gates"]["LB-G2"] = (f"C (partial coverage {coverage:.2f} — "
                                     "never gates input, L-G3)")
        else:
            res["gates"]["LB-G2"] = "PASS" if g2_ok else (
                "SMOKE" if s2.get("smoke") else "FAIL")
    res["refusal"] = refuse
    out = os.path.join(ev, "verdict.json")
    with open(out, "w") as fh:
        json.dump(res, fh, indent=1)
    print(json.dumps(res, indent=1))
    print(f"verdict -> {out}")
    return 1 if refuse else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shape", choices=["s1", "s3"])
    ap.add_argument("--task", choices=["perm", "veto"])
    ap.add_argument("--smoke", type=int, default=0)
    ap.add_argument("--verdict", action="store_true")
    ap.add_argument("--evidence")
    args = ap.parse_args()
    if args.verdict:
        if not args.evidence:
            raise SystemExit("--verdict needs --evidence DIR")
        sys.exit(verdict(args.evidence))
    out_dir = args.evidence or evidence_dir()
    os.makedirs(out_dir, exist_ok=True)
    print(f"evidence dir: {out_dir}")
    if args.shape == "s1":
        if not args.task:
            raise SystemExit("--shape s1 needs --task perm|veto")
        run_s1(args.task, args.smoke, out_dir)
    elif args.shape == "s3":
        run_s3(args.smoke, out_dir)
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
