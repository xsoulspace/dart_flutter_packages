"""Context-sensitivity sweep: at what context size does a lane's pass rate break?

The question this answers is NOT "how fast is the model" — it is "how much
context does this job actually need before quality degrades". That decides
whether a long-context design (MLA / sparse attention / linear state) is
worth building, and whether a 4k budget is a real constraint or an
artificial one.

Design (deliberately adversarial to the "4k is enough" hypothesis):

  placement=end     distractor + question. Pure length degradation: the
                    question is the most recent thing the model sees.
  placement=middle  distractor_a + question + distractor_b. Retrieval: the
                    question is buried, which is the harness's real shape
                    (the decisive requirement is rarely the last message).

Distractor text is real repo prose (the clause dataset), not lorem ipsum —
synthetic filler under-tests because it is too easy to ignore.

Usage:
  python tool/nursery/context_sweep.py --model mlx-community/Qwen3-0.6B-4bit \
      --lanes chat decompression --sizes 1024 2048 4096 8192 16384 \
      --placement end middle --out sweep.json
"""

import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(os.path.dirname(HERE))
BENCH = os.path.join(PKG, "testdata", "bench")
DATA = os.path.join(PKG, "bench", "nursery", "data", "clause_dataset.jsonl")


def load_distractor():
    """Filler from a DIFFERENT domain than the target (code-structure units),
    so a failure means the model lost the target, not that it could not tell
    two similar records apart."""
    path = os.path.join(PKG, "bench", "nursery", "data", "codemap_units.jsonl")
    texts = []
    if os.path.exists(path):
        with open(path) as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                d = json.loads(line)
                t = d.get("text", "")
                if len(t) > 40:
                    texts.append(t)
    if not texts:
        with open(DATA) as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                d = json.loads(line)
                t = d.get("text", "")
                if len(t) > 40:
                    texts.append(t)
    texts.sort(key=len, reverse=True)
    return texts


def filler_to_tokens(texts, n_tokens, tok):
    """Concatenate real prose until it covers ~n_tokens (rough 4 chars/token)."""
    target_chars = n_tokens * 4
    out, n = [], 0
    i = 0
    while n < target_chars:
        t = texts[i % len(texts)]
        out.append(t)
        n += len(t) + 1
        i += 1
    return "\n".join(out)


def question_of(case):
    """The lane's user-facing question, whatever shape the lane file uses."""
    if "messages" in case:
        return "\n".join(m["content"] for m in case["messages"])
    if "record" in case:
        return (
            "Summarize this record in one line of at most 280 bytes, "
            "keeping the named entities:\n" + case["record"]
        )
    return case.get("prompt", "")


def check(text, case):
    """The lane's own deterministic check (same law as the bench suite)."""
    reasons = []
    if "entities" in case or "min_entity_hits" in case:
        ents = case.get("entities") or []
        hits = [e for e in ents if e in text]
        need = int(case.get("min_entity_hits", 2))
        if len(hits) < need:
            reasons.append(f"entity recall {len(hits)}/{need} of {len(ents)}")
        cap = int(case.get("max_output_bytes", 280))
        if len(text.encode("utf-8")) > cap:
            reasons.append(f"over {cap} bytes")
        if "\n" in text.strip():
            reasons.append("not one line")
        return (not reasons), reasons
    for e in case.get("expect_all", []) or []:
        if e not in text:
            reasons.append(f'missing "{e}"')
    any_list = case.get("expect_any") or []
    if any_list and not any(t in text for t in any_list):
        reasons.append("none of " + str(any_list) + " found")
    if case.get("expect_tool"):
        if case["expect_tool"] not in text:
            reasons.append(f"tool {case['expect_tool']} not named")
    return (not reasons), reasons


def run_case(model, tok, case, size, placement, distractor):
    from mlx_lm import generate

    question = question_of(case)
    # The target is fenced so a miss means "lost in context", not "could not
    # tell the target from the filler".
    fenced = "=== TARGET ===\n" + question + "\n=== END TARGET ==="
    if placement == "end":
        prompt = filler_to_tokens(distractor, size, tok) + "\n\n" + fenced
    else:
        half = size // 2
        prompt = (
            filler_to_tokens(distractor, half, tok)
            + "\n\n"
            + fenced
            + "\n\n"
            + filler_to_tokens(distractor[1:], half, tok)
        )
    t0 = time.time()
    text = generate(
        model,
        tok,
        prompt=prompt,
        max_tokens=int(case.get("max_tokens", 64)),
        verbose=False,
    )
    wall = time.time() - t0
    ok, reasons = check(text, case)
    return {
        "case": case["id"],
        "size": size,
        "placement": placement,
        "ok": ok,
        "reasons": reasons,
        "wall_s": round(wall, 2),
        "prompt_chars": len(prompt),
        "answer": text[:160],
    }


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--model", default="mlx-community/Qwen3-0.6B-4bit")
    ap.add_argument("--lanes", nargs="+", default=["chat", "decompression"])
    ap.add_argument(
        "--sizes", nargs="+", type=int, default=[1024, 2048, 4096, 8192, 16384]
    )
    ap.add_argument("--placement", nargs="+", default=["end", "middle"])
    ap.add_argument(
        "--max-cases",
        type=int,
        default=2,
        help="cases per lane (keep the sweep bounded)",
    )
    ap.add_argument("--out")
    args = ap.parse_args(argv)

    from mlx_lm import load

    model, tok = load(args.model)
    distractor = load_distractor()
    rows = []
    for lane in args.lanes:
        with open(os.path.join(BENCH, f"{lane}_lane.json")) as fh:
            spec = json.load(fh)
        for case in spec["cases"][: args.max_cases]:
            for placement in args.placement:
                for size in args.sizes:
                    r = run_case(model, tok, case, size, placement, distractor)
                    r["lane"] = lane
                    rows.append(r)
                    print(json.dumps(r), flush=True)

    # rollup: pass rate per (lane, placement, size)
    roll = {}
    for r in rows:
        k = (r["lane"], r["placement"], r["size"])
        roll.setdefault(k, []).append(r["ok"])
    table = [
        {
            "lane": k[0],
            "placement": k[1],
            "size": k[2],
            "pass": sum(v),
            "n": len(v),
            "rate": sum(v) / len(v),
        }
        for k, v in sorted(roll.items())
    ]
    payload = {"model": args.model, "rows": rows, "rollup": table}
    text = json.dumps(payload, indent=2)
    if args.out:
        with open(args.out, "w") as fh:
            fh.write(text + "\n")
    print("\n== rollup ==")
    for t in table:
        print(
            f"{t['lane']:<14} {t['placement']:<7} {t['size']:>6}  {t['pass']}/{t['n']}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
