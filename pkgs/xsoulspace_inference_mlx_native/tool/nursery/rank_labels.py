"""rank_labels.py — L-G6: RANK the legal labels instead of GENERATING them.

THE QUESTION (MTP-GATES.md Part 4, L-G6). Can the legal labels be RANKED
rather than generated? If a BASE model with a constrained ranking (score
every legal label, take the argmax, emit it) reaches the `untagged`
adapter's accuracy, then **the LoRA line is not bought**: a zero-training
path delivers the same capability, and the product question becomes "cost the
constrained-ranking path", not "train an adapter".

This arm does NO GENERATION AT ALL. That is the whole point: the comparison
is against the generation arm, so the arm under test must not generate.

THE API USED (read from the installed package, not guessed).
  * `mlx_lm.load(path)` — `mlx_lm/utils.py:610` — returns
    `(model, tokenizer)`. The SAME call `adapter_conditioning.py` makes, so
    the model and the tokenizer are the same objects the generation arm
    used. `mlx_lm.load(path, adapter_path=...)` also applies a LoRA adapter
    (`utils.py:610-618`), so the arm can be run against an adapter too.
  * `mlx_lm.models.cache.make_prompt_cache(model)` — `models/cache.py:15` —
    builds the KV cache the model expects.
  * `mlx.core` (`mx.array`, `mx.eval`, `mx.clear_cache`) and `mlx.nn`
    (`nn.log_softmax`) for the forward pass and the log-softmax.
  * The scoring PATTERN (prompt forward once, then the continuation tokens
    scored against a copy of the prompt cache) is `mlx_lm/evaluate.py`'s
    `MLXLM.loglikelihood` / `_process_prompt` / `_score_fn`
    (`evaluate.py:100-235`). That method is the package's own vetted
    implementation of "log P(continuation | context)", and this module
    follows it step for step.

TOKENIZATION BOUNDARY (the honest part). The label's log-probability is
only well defined if the tokens of `prompt + label` split cleanly into
"the prompt's tokens" and "the label's tokens". Two things are therefore
CHECKED and REPORTED per item, never assumed:

  1. `prefix_ok`  — `tokenize(prompt + label)` starts with
     `tokenize(prompt)`. If it does not, the boundary moved (the label's
     first character merged with the prompt's last), and the "label span"
     computed by slicing is not the label. Such items are counted in
     `boundary_violations` and the arm is flagged: a number scored over a
     different string than the one claimed is not a number.
  2. `suffix_ok`  — `tokenize(prompt + label)` ends with `tokenize(label)`.
     This says whether the label tokenizes the same way IN CONTEXT as it
     does STANDALONE.

THE LEADING-SPACE DECISION. The continuation is scored as the BARE label
(no leading space). The reason is the eval prompt itself: it ends with
`Answer:` (no trailing space) and the model's own generations in the cached
completions are bare labels (`allow_once`, not ` allow_once`). `mlx_lm`'s
`loglikelihood` docstring says to put a word-boundary space in the
continuation — that advice is for a prompt that ends with a word, and it
does not apply here: adding a space would score a string the model is
never asked to produce. Both `sum` and `mean` scores are recorded, so a
reader can see whether the space decision changed the answer.

LENGTH NORMALISATION. The labels have very different lengths
(`allow_once` vs `no_grant` vs `destructive_op`), and a raw SUM of token
log-probs systematically prefers short labels. Both are therefore computed:
  * `sum`  — the total log-probability of the label;
  * `mean` — that total divided by the number of label tokens.
The default is `--normalize mean` (the length-fair one). The choice is
recorded in the cell, and BOTH argmaxes are recorded next to the selected
one, so the other reading is re-derivable from the artifact without
re-running the GPU.

THE CELL FORMAT is the same one the rest of the lane reads, so
`fast_score.py` can score this arm with the SAME rules as every other arm:
`ranked__<task>.jsonl` with `{"id","gold","pred_strict","pred_legacy",
"completion"}` plus `pred_ranked`, `label_logprobs` and the boundary
flags. `completion` is the RANKED label (not a generation) and
`"mode": "ranked"` says so, so nobody reads the cell as a generation.

Usage:
  python tool/nursery/rank_labels.py --model mlx-community/Qwen3-0.6B-4bit \
      --tasks perm,veto --completions bench/nursery/experiments/ranking/completions
  python tool/nursery/rank_labels.py --normalize sum --eval-rows all ...
"""

import argparse
import copy
import json
import os
import sys
import time
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import adapter_conditioning as ac  # noqa: E402
from scoring import ranked_prediction  # noqa: E402,F401


def build_chat(tok, prompt):
    """The eval prompt, rendered EXACTLY as the generation arm renders it.

    Same template, same chat application, same flags — the ranking arm must
    be scored on the same distribution the generation arm was sampled from,
    or the comparison is between two different prompts.
    """
    return tok.apply_chat_template(
        [{"role": "user", "content": prompt}],
        add_generation_prompt=True,
        tokenize=False,
        enable_thinking=False,
    )


def label_span(prompt_ids, full_ids, label_ids):
    """The label's token span inside `tokenize(prompt + label)`, and the
    boundary verdict.

    Returns (span, prefix_ok, suffix_ok).

    This is PURE (no model, no mlx), so the boundary law can be tested on its
    own — the law is the part that can silently score a different string
    than the one claimed, so it must not be untestable.

      * `prefix_ok` — `tokenize(prompt + label)` starts with
        `tokenize(prompt)`. If it does not, the boundary MOVED (the label's
        first characters merged with the prompt's last), and slicing at
        len(prompt_ids) would not be the label's span. The fallback is the
        LONGEST COMMON PREFIX, and the violation is counted and reported.
      * `suffix_ok` — `tokenize(prompt + label)` ends with `tokenize(label)`:
        does the label tokenize the same way IN CONTEXT as STANDALONE?
    """
    prefix_ok = len(full_ids) >= len(prompt_ids) and (
        full_ids[: len(prompt_ids)] == prompt_ids
    )
    suffix_ok = len(full_ids) >= len(label_ids) and (
        full_ids[-len(label_ids) :] == label_ids
    )
    if prefix_ok:
        span = full_ids[len(prompt_ids) :]
    else:
        common = 0
        while (
            common < len(prompt_ids)
            and common < len(full_ids)
            and prompt_ids[common] == full_ids[common]
        ):
            common += 1
        span = full_ids[common:]
    return span, prefix_ok, suffix_ok


def choose_label(scores, normalize):
    """The argmax label under a length normalization, plus the log-softmax.

    `scores` is `{label: {"sum": float, "mean": float, ...}}`. The softmax is
    applied in LOG SPACE over the labels' log-probabilities, which is what
    makes the probabilities readable without ever exponentiating a large
    negative number.
    """
    import math

    keys = list(scores.keys())
    raw = [scores[k][normalize] for k in keys]
    m = max(raw)
    lse = m + math.log(sum(math.exp(v - m) for v in raw))
    lp = [v - lse for v in raw]
    best = max(range(len(keys)), key=lambda i: raw[i])
    return {
        "pred": keys[best],
        "logprobs": {k: v for k, v in zip(keys, lp)},
        "probs": {k: math.exp(v) for k, v in zip(keys, lp)},
    }


def make_filled_prompt_cache(model, tok, chat):
    """Forward the prompt ONCE and keep its cache and last logits.

    The cache is CONSUMED as continuations are fed into it, so every label
    is scored against a COPY of this one (the same discipline
    `mlx_lm/evaluate.py` uses). Forwarding the prompt once per label would
    also be WRONG in a second way: a second forward into the same cache
    would DOUBLE the prompt's keys and values.
    """
    import mlx.core as mx
    from mlx_lm.models.cache import make_prompt_cache

    prompt_ids = tok.encode(chat, add_special_tokens=False)
    cache = make_prompt_cache(model)
    logits = model(mx.array(prompt_ids)[None, :], cache=cache)
    mx.eval([c.state for c in cache])
    return prompt_ids, logits, cache


def continuation_logprob(model, tok, chat, label, prompt_ids, prompt_logits, cache):
    """log P(label | chat), with the label tokenized IN CONTEXT.

    Returns a dict:
      {"sum": float, "mean": float, "n_tokens": int, "prefix_ok": bool,
       "suffix_ok": bool, "span": [token ids]}

    The scoring follows `mlx_lm/evaluate.py`'s `MLXLM.loglikelihood`:
    the prompt is forwarded once into a KV cache, the first label token is
    scored from the prompt's last logits, and the remaining label tokens
    are scored by feeding them through a COPY of that cache.
    """
    import mlx.core as mx
    import mlx.nn as nn

    full_ids = tok.encode(chat + label, add_special_tokens=False)
    label_ids = tok.encode(label, add_special_tokens=False)

    span, prefix_ok, suffix_ok = label_span(prompt_ids, full_ids, label_ids)
    if not span:
        raise ValueError(f"empty continuation span for label {label!r}")

    # The first label token, scored from the prompt's LAST position.
    last = nn.log_softmax(prompt_logits[:, -1, :].astype(mx.float32))[0]
    total = float(last[span[0]].item())

    if len(span) > 1:
        # The remaining label tokens, scored against a COPY of the prompt
        # cache (the copy is what `mlx_lm/evaluate.py` does too: the cache
        # is consumed as the continuation is fed in).
        c2 = copy.deepcopy(cache)
        inp = span[:-1]
        logits2 = model(mx.array(inp)[None, :], cache=c2)
        mx.eval([c.state for c in c2])
        lp = nn.log_softmax(logits2.astype(mx.float32), axis=-1)[0]
        targets = mx.array(span[1:])
        tok_lp = mx.take_along_axis(lp, targets[:, None], axis=-1)[:, 0]
        total += float(mx.sum(tok_lp).item())

    return {
        "sum": total,
        "mean": total / len(span),
        "n_tokens": len(span),
        "prefix_ok": prefix_ok,
        "suffix_ok": suffix_ok,
        "span": list(span),
    }


def rank_cell(model, tok, rows, labels, task, normalize, other_labels=()):
    """Rank the legal labels for every row of one task.

    Returns (items, summary). `items` are the cached per-item rows the rest
    of the lane reads; `summary` carries the boundary audit.
    """
    items = []
    boundary_violations = 0
    suffix_violations = 0
    per_label = {}
    for r in rows:
        prompt = ac.build_prompt(r, labels, task, tagged=False)
        chat = build_chat(tok, prompt)
        prompt_ids, prompt_logits, cache = make_filled_prompt_cache(model, tok, chat)
        scores = {}
        for lab in labels:
            s = continuation_logprob(
                model, tok, chat, lab, prompt_ids, prompt_logits, cache
            )
            scores[lab] = s
            if not s["prefix_ok"]:
                boundary_violations += 1
            if not s["suffix_ok"]:
                suffix_violations += 1
        # The softmax in log space over the legal labels.
        keys = list(scores.keys())
        chosen = choose_label(scores, normalize)
        lp = chosen["logprobs"]
        probs = chosen["probs"]
        pred = chosen["pred"]
        pred_sum = max(keys, key=lambda k: scores[k]["sum"])
        pred_mean = max(keys, key=lambda k: scores[k]["mean"])
        # How close was the model to a FOREIGN label? The ranked prediction
        # is always one of this task's own labels, so the leak metric cannot
        # fire here; the closest foreign score is the honest way to say
        # "the model was not tempted to answer in another task's vocabulary".
        best_foreign = None
        for lab in other_labels or ():
            if lab in scores:
                continue
            s = continuation_logprob(
                model, tok, chat, lab, prompt_ids, prompt_logits, cache
            )
            if not s["prefix_ok"]:
                boundary_violations += 1
            if best_foreign is None or s[normalize] > best_foreign[1]:
                best_foreign = (lab, s[normalize])
        del cache
        items.append(
            {
                "id": r["id"],
                "gold": r["kind"],
                # `completion` is the RANKED label, so the ordinary scorer
                # reads this arm with the ordinary rules. `mode` says it was
                # not generated.
                "completion": pred,
                "pred_strict": pred,
                "pred_legacy": pred,
                "pred_ranked": pred,
                "pred_ranked_sum": pred_sum,
                "pred_ranked_mean": pred_mean,
                "mode": "ranked",
                "normalization": normalize,
                "best_foreign_label": (
                    {"label": best_foreign[0], "score": best_foreign[1]}
                    if best_foreign
                    else None
                ),
                "label_logprobs": {
                    k: {
                        "sum": scores[k]["sum"],
                        "mean": scores[k]["mean"],
                        "n_tokens": scores[k]["n_tokens"],
                        "logprob": lp[k],
                        "prob": probs[k],
                        "prefix_ok": scores[k]["prefix_ok"],
                        "suffix_ok": scores[k]["suffix_ok"],
                    }
                    for k in keys
                },
            }
        )
        for k in keys:
            per_label.setdefault(k, {"n": 0, "argmax": 0})
            per_label[k]["n"] += 1
            if k == pred:
                per_label[k]["argmax"] += 1
    summary = {
        "rows": len(items),
        "labels": list(labels),
        "normalization": normalize,
        "boundary_violations": boundary_violations,
        "suffix_violations": suffix_violations,
        "per_label_argmax": per_label,
        "continuation_space": False,
        "continuation_form": "the bare label, no leading space",
    }
    return items, summary


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--model", default="mlx-community/Qwen3-0.6B-4bit")
    ap.add_argument(
        "--adapter-path",
        default=None,
        help="optional LoRA adapter dir (the L-G6 gate is about the BASE model)",
    )
    ap.add_argument("--tasks", default="perm,veto")
    ap.add_argument(
        "--completions",
        default=os.path.join(
            PKG, "bench", "nursery", "experiments", "ranking", "completions"
        ),
        help="output dir for the <arm>__<task>.jsonl cells",
    )
    ap.add_argument("--arm", default="ranked", help="the arm name in the cell file")
    ap.add_argument(
        "--normalize",
        choices=["sum", "mean"],
        default="mean",
        help=(
            "length normalization of the label log-probs. 'mean' (the default) "
            "divides by the label's token count, so a long label is not "
            "penalised for being long; 'sum' is the raw total."
        ),
    )
    ap.add_argument(
        "--eval-rows",
        choices=["150", "all"],
        default="150",
        help="how many rows of the scored split to evaluate (L-G3)",
    )
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--limit", type=int, default=None, help="cap the rows (debug)")
    ap.add_argument("--out", default=None, help="write the run summary here")
    args = ap.parse_args(argv)

    from mlx_lm import load

    task_names = [t for t in args.tasks.split(",") if t]
    for t in task_names:
        if t not in ac.TASKS:
            raise SystemExit(f"unknown task {t}")
    rows_limit = 150 if args.eval_rows == "150" else None

    print(
        f"ranking arm '{args.arm}': model {args.model}"
        + (f" + adapter {args.adapter_path}" if args.adapter_path else " (base)")
        + f" | normalize={args.normalize} | eval-rows={args.eval_rows}",
        flush=True,
    )
    print(
        "NOTE: this arm performs NO generation. It scores the legal labels "
        "with the model's own forward pass and takes the argmax.",
        flush=True,
    )

    if args.adapter_path:
        model, tok = load(args.model, adapter_path=args.adapter_path)
    else:
        model, tok = load(args.model)

    os.makedirs(args.completions, exist_ok=True)
    summary = {
        "contract": "nursery.rank-labels.v1",
        "when_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "model": args.model,
        "adapter_path": args.adapter_path,
        "arm": args.arm,
        "tasks": task_names,
        "normalize": args.normalize,
        "eval_rows": args.eval_rows,
        "seed": args.seed,
        "generation": False,
        "cells": {},
    }
    t0 = time.perf_counter()
    for task in task_names:
        labels = ac.TASKS[task]["labels"]
        other = [
            l
            for t2, ls in ac.TASKS.items()
            if t2 != task
            for l in ls
            if t2 in task_names
        ]
        rows = ac.load_task(task)
        _tr, te = ac.split_rows(rows, holdout=0.25, seed=args.seed)
        scored = te[:rows_limit] if rows_limit else te
        if args.limit:
            scored = scored[: args.limit]
        items, cell_summary = rank_cell(
            model, tok, scored, labels, task, args.normalize, other_labels=other
        )
        path = os.path.join(args.completions, f"{args.arm}__{task}.jsonl")
        with open(path, "w") as fh:
            for it in items:
                fh.write(json.dumps(it) + "\n")
        correct = sum(1 for it in items if it["pred_ranked"] == it["gold"])
        correct_sum = sum(1 for it in items if it["pred_ranked_sum"] == it["gold"])
        correct_mean = sum(1 for it in items if it["pred_ranked_mean"] == it["gold"])
        n = max(1, len(items))
        cell_summary.update(
            {
                "path": path,
                "accuracy": correct / n,
                "accuracy_sum": correct_sum / n,
                "accuracy_mean": correct_mean / n,
                "coverage_rows": len(items),
                "split_rows": len(te),
            }
        )
        summary["cells"][task] = cell_summary
        print(
            f"  {args.arm} / {task}: n={len(items)} (split {len(te)}) | "
            f"accuracy[{args.normalize}] {correct / n:.4f} | "
            f"sum {correct_sum / n:.4f} | mean {correct_mean / n:.4f} | "
            f"boundary violations {cell_summary['boundary_violations']} | "
            f"suffix violations {cell_summary['suffix_violations']}",
            flush=True,
        )
        if cell_summary["boundary_violations"]:
            print(
                f"    *** {cell_summary['boundary_violations']} tokenization "
                "BOUNDARY VIOLATIONS: the concatenation did not split at the "
                "prompt's end, so the scored string is not the claimed one. "
                "This arm's number is NOT clean.",
                flush=True,
            )
    summary["elapsed_s"] = round(time.perf_counter() - t0, 2)
    print(f"\nranking arm done in {summary['elapsed_s']}s (no generation)")
    if args.out:
        with open(args.out, "w") as fh:
            json.dump(summary, fh, indent=2)
        print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
