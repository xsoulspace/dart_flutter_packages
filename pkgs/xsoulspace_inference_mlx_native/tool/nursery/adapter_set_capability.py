"""ADAPTER-SET CAPABILITY — the K-G3 experiment for the swappable-adapter line.

WHY THIS EXPERIMENT EXISTS. The previous adapter arm
(`bench/nursery/experiments/RESULTS-part2.md` §10) trained ONE adapter on ONE
task (Dart function completion) on ONE base (Qwen3-0.6B-4bit) and measured
format compliance (0.50 -> 0.83) and compilable output (0.00 -> 0.00). Its
verdict was "the adapter is the right mechanism for the wrong base" — a
FORMAT adapter, not a capability adapter.

That arm could not answer the question a SWAPPABLE adapter set exists to
answer. A set is only worth building if:

  (1) an adapter moves a MEASURED task metric on a base that can do the task
      (K-G3), and
  (2) different adapters are SELECTIVE: adapter A helps task A and does not
      damage task B, so one base can serve several tasks with the right
      adapter swapped in.

(2) is the property no prior arm measured, and it is the whole justification
for the Rust `AdapterSet` surface (src/lora_set.rs): if every adapter moved
every task, you would not need a SET — you would need a better model.

THE DESIGN. Two tasks the 0.6B base can plausibly do (both are short
CLASSIFICATION tasks, which is exactly the task-narrowing the previous arm
recommended), one base, two adapters:

  task PERM   2-way  (allow_once / abstain)  from bench/nursery/data/perm_corpus_clause.jsonl
  task CLAUSE 4-way  (fact / done / open / action) from bench/nursery/data/clause_dataset.jsonl

  adapter PERM   trained on PERM
  adapter CLAUSE trained on CLAUSE

The metric is ACCURACY of the label, measured by constrained decoding: the
model is asked for one label and we score the label it produces. That is
hardware-independent, needs no sampling, and is the same measurement for
every cell, so the 2x2 matrix is directly comparable.

The matrix (the deliverable):

                    task PERM        task CLAUSE
  base                x                 y
  + adapter PERM      x'                y'     <- selectivity: x' > x, y' ~ y
  + adapter CLAUSE    x''               y''    <- the mirror

A swappable set is justified only if the diagonal moves UP and the
off-diagonal does not move DOWN. If the off-diagonal drops, the adapters
interfere and a set cannot serve both tasks from one base.

GATES (MTP-GATES.md, frozen before this run):
  K-G3 capability: the adapter must move a MEASURED task metric on a base
       that can do the task. Concretely: the adapter's own task accuracy
       must exceed the base's own task accuracy by a margin above the
       seed's run-to-run spread.
  K-G3 selectivity: the off-diagonal must not fall below the base by more
       than the same margin. (A selectivity failure re-scopes the line: the
       set is not a set.)
  Non-claims: no claim about a 4-bit base being usable with the native
       merge surface (K-G4 — the merge path is refused there); this arm
       runs the PYTHON mlx-lm adapter path, which applies the adapter
       without merging.

Usage:
  python tool/nursery/adapter_set_capability.py --model mlx-community/Qwen3-0.6B-4bit \
      --iters 300 --out bench/nursery/experiments/adapter-set-capability.json
"""

import argparse
import json
import os
import random
import sys
import time
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import power_snapshot  # noqa: E402

DATA = os.path.join(PKG, "bench", "nursery", "data")

# The labels, in the order the prompt presents them. The label set is the
# contract: a task's accuracy is "did the model name the right label".
TASKS = {
    "perm": {"file": "perm_corpus_clause.jsonl", "labels": ["allow_once", "abstain"]},
    "clause": {
        "file": "clause_dataset.jsonl",
        "labels": ["fact", "done", "open", "action"],
    },
}

PROMPT = (
    "Classify the text. Answer with exactly one of: {labels}\n\nText: {text}\nAnswer:"
)

# The base model is a Qwen3 with a reasoning template: asked through the
# chat template it answers with a `<think>` block FIRST, so the label is NOT
# the first line of the completion. The scorer must look past the think
# block, and the training turns must teach the LABEL as the completion (the
# trainer applies the chat template itself, so a plain prompt/completion
# pair is the right shape).


def load_task(name, limit=None):
    path = os.path.join(DATA, TASKS[name]["file"])
    labels = TASKS[name]["labels"]
    rows = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            d = json.loads(line)
            kind = d.get("kind")
            text = (d.get("text") or "").strip()
            if kind not in labels or not text:
                continue
            rows.append({"id": d.get("id", ""), "kind": kind, "text": text})
            if limit and len(rows) >= limit:
                break
    return rows


def to_chat(row, labels):
    """One training/eval turn: the prompt, then the bare label.

    The `prompt`/`completion` form is the mlx-lm CompletionsDataset shape
    (the trainer applies the chat template itself).
    """
    return {
        "prompt": PROMPT.format(labels=", ".join(labels), text=row["text"]),
        "completion": row["kind"],
    }


def split_rows(rows, holdout=0.25, seed=0):
    """Deterministic split by id hash (the same law the perm corpus uses)."""
    import hashlib

    train, test = [], []
    for r in rows:
        h = int(hashlib.sha256(str(r["id"]).encode()).hexdigest(), 16)
        (test if (h % 100) < int(holdout * 100) else train).append(r)
    return train, test


def write_jsonl(path, rows, labels):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        for r in rows:
            fh.write(json.dumps(to_chat(r, labels)) + "\n")


def write_split_dir(out_dir, task, train_rows, valid_rows, labels):
    """The mlx-lm local dataset layout: a DIRECTORY with train/valid jsonl."""
    d = os.path.join(out_dir, task)
    os.makedirs(d, exist_ok=True)
    write_jsonl(os.path.join(d, "train.jsonl"), train_rows, labels)
    write_jsonl(os.path.join(d, "valid.jsonl"), valid_rows, labels)
    return d


def extract_label(text, labels):
    """The label the completion ANSWERS, or None.

    THE SCORING LAW (a measured defect, not a guess): with thinking ON, the
    base model's completion is a `<think>` block that ECHOES THE OPTION LIST
    ("classify the given text into one of the options: fact, done, ..."), so
    scoring the earliest label mention anywhere in the completion scored an
    ECHO OF THE PROMPT, not an answer — it made the base look like it
    always picked the first option, which for a skewed task IS the majority
    class. That inflated the base to 0.847 on the clause task, whose
    majority class is 0.787.

    Two defences, both applied:
      * the prompt is rendered with thinking OFF, so the completion IS the
        answer;
      * and if a think block IS present, only the text AFTER the closing
        `</think>` is scored. A think block that never closed is a MISS.

    A miss is counted WRONG. It is never coerced into the nearest label.
    """
    if not text:
        return None
    if "</think>" in text:
        text = text.split("</think>")[-1]
    elif "<think>" in text:
        # The think block never closed: the model never reached an answer.
        return None
    low = text.lower()
    best = None
    for lab in labels:
        pos = low.find(lab.lower())
        if pos >= 0 and (best is None or pos < best[0]):
            best = (pos, lab)
    return best[1] if best else None


def score(model, tok, rows, labels, limit=None, args_max_tokens=64):
    """Constrained accuracy: the model answers, we compare the label.

    The prompt is rendered with `enable_thinking=False`. WITHOUT it the base
    model answers with a long `<think>` block that ECHOES THE OPTION LIST
    ("classify the given text into one of the options: fact, done, ..."), so
    any label-matching scorer reads the ECHO rather than an answer — the
    base then looks like it always picks the first option, which for a
    skewed task IS the majority class. With thinking off, the base and a
    trained adapter both answer with the label directly, and the comparison
    is between ANSWERS.
    """
    from mlx_lm import generate

    n = 0
    correct = 0
    outside = 0
    for r in rows[: limit or len(rows)]:
        prompt = PROMPT.format(labels=", ".join(labels), text=r["text"])
        chat = tok.apply_chat_template(
            [{"role": "user", "content": prompt}],
            add_generation_prompt=True,
            tokenize=False,
            enable_thinking=False,
        )
        out = generate(
            model, tok, prompt=chat, max_tokens=args_max_tokens, verbose=False
        )
        n += 1
        pred = extract_label(out, labels)
        if pred is None:
            outside += 1
        elif pred == r["kind"]:
            correct += 1
    return {
        "n": n,
        "accuracy": correct / max(1, n),
        "outside_label_set": outside,
    }


def train_adapter(model, tok, task, train_rows, labels, out_dir, args):
    """Train one LoRA adapter for one task with the mlx-lm tuner.

    The tuner API (mlx_lm.tuner.utils / .trainer): convert the model's
    linear layers to LoRA layers, freeze the base, train only the adapter,
    then save the adapter weights AND the adapter_config.json the loader
    needs (mlx_lm's `load(model, adapter_path=...)` reads that config).
    """
    from pathlib import Path

    from mlx_lm.tuner import linear_to_lora_layers
    from mlx_lm.tuner.datasets import CacheDataset, load_local_dataset
    from mlx_lm.tuner.trainer import TrainingArgs, train

    data_dir = write_split_dir(
        os.path.join(out_dir, "data"), task, train_rows, train_rows[:16], labels
    )

    # The base model is frozen; only the LoRA parameters train.
    model.freeze()
    # linear_to_lora_layers converts the model's linear layers IN PLACE,
    # returns None, and unfreezes the new LoRA parameters as it goes — so
    # the converted model IS the tunable one and needs no further thaw.
    linear_to_lora_layers(
        model,
        args.num_layers,
        {"rank": args.rank, "scale": args.scale, "dropout": 0.0},
    )
    tunable = model

    adapter_file = os.path.join(out_dir, "adapters.safetensors")
    train_args = TrainingArgs(
        batch_size=args.batch,
        iters=args.iters,
        val_batches=0,
        steps_per_report=50,
        steps_per_eval=10_000,
        steps_per_save=args.iters,
        max_seq_length=args.max_seq_length,
        adapter_file=adapter_file,
        grad_checkpoint=False,
        grad_accumulation_steps=1,
        clear_cache_threshold=0,
    )
    ds = load_local_dataset(Path(data_dir), tok, train_args)

    optimizer = __import__("mlx.optimizers", fromlist=["Adam"]).Adam(
        learning_rate=args.lr
    )
    # The trainer wants CACHED datasets (the raw dataset is tokenized once).
    train(
        tunable,
        optimizer,
        CacheDataset(ds[0]),
        val_dataset=None,
        args=train_args,
    )

    # The adapter loader needs the config next to the weights.
    import json as _json

    cfg = {
        "adapter_path": out_dir,
        "batch_size": args.batch,
        "clear_cache_threshold": 0,
        "config": None,
        "fine_tune_type": "lora",
        "grad_accumulation_steps": 1,
        "grad_checkpoint": False,
        "iters": args.iters,
        "learning_rate": args.lr,
        "lora_parameters": {"rank": args.rank, "dropout": 0.0, "scale": args.scale},
        "lr_schedule": None,
        "mask_prompt": False,
        "max_seq_length": args.max_seq_length,
        "model": args.model,
        "num_layers": args.num_layers,
        "optimizer": "adam",
        "optimizer_config": {"adam": {}},
        "project_name": None,
        "report_to": None,
        "resume_adapter_file": None,
        "save_every": args.iters,
        "seed": args.seed,
        "steps_per_eval": 200,
        "steps_per_report": 10,
        "test": False,
        "test_batches": 500,
        "train": True,
        "trust_remote_code": False,
        "val_batches": 25,
    }
    with open(os.path.join(out_dir, "adapter_config.json"), "w") as fh:
        _json.dump(cfg, fh, indent=2)

    return out_dir


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--model", default="mlx-community/Qwen3-0.6B-4bit")
    ap.add_argument("--out", default=None)
    ap.add_argument("--work-dir", default="/tmp/adapter_set_capability")
    ap.add_argument("--iters", type=int, default=300)
    ap.add_argument("--batch", type=int, default=4)
    ap.add_argument("--lr", type=float, default=1e-5)
    ap.add_argument("--rank", type=int, default=8)
    ap.add_argument(
        "--scale", type=int, default=20, help="mlx-lm LoRA 'scale' (not 'alpha')"
    )
    ap.add_argument("--num-layers", type=int, default=8)
    ap.add_argument("--max-seq-length", type=int, default=256)
    ap.add_argument("--eval-limit", type=int, default=120)
    ap.add_argument(
        "--max-tokens",
        type=int,
        default=64,
        help="completion budget; the prompt is rendered with thinking OFF, so "
        "the answer is the label itself",
    )
    ap.add_argument("--train-limit", type=int, default=900)
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args(argv)

    import mlx.core as mx
    from mlx_lm import load

    t_start = time.time()
    model, tok = load(args.model)
    print(f"loaded {args.model}", flush=True)

    os.makedirs(args.work_dir, exist_ok=True)

    # ---- the data ------------------------------------------------------
    task_rows = {}
    for name, spec in TASKS.items():
        rows = load_task(name, args.train_limit + args.eval_limit)
        tr, te = split_rows(rows, seed=args.seed)
        task_rows[name] = {"train": tr, "test": te, "labels": spec["labels"]}
        print(
            f"task {name}: {len(tr)} train / {len(te)} test, labels={spec['labels']}",
            flush=True,
        )

    # ---- the BASE row of the matrix ------------------------------------
    matrix = {}
    base_scores = {}
    for name, t in task_rows.items():
        s = score(model, tok, t["test"], t["labels"], args.eval_limit, args.max_tokens)
        base_scores[name] = s
        print(f"base on {name}: accuracy {s['accuracy']:.3f} (n={s['n']})", flush=True)

    # ---- the TRIVIAL baselines ----------------------------------------
    # Without these, an accuracy number is uninterpretable: a task whose
    # majority class is 79% makes any "accuracy 0.85" look like competence.
    # Two trivial predictors are recorded per task:
    #   majority    — always answer the most common label
    #   first_option— always answer the FIRST label the prompt lists
    # The second is the one that caught the scoring defect: the base model's
    # reasoning ECHOED the option list, so the broken scorer measured it.
    baselines = {}
    for name, t in task_rows.items():
        labels = t["labels"]
        counts = {}
        for r in t["test"][: args.eval_limit]:
            counts[r["kind"]] = counts.get(r["kind"], 0) + 1
        n = sum(counts.values()) or 1
        majority = max(counts, key=counts.get) if counts else labels[0]
        baselines[name] = {
            "n": n,
            "distribution": counts,
            "majority_label": majority,
            "majority_accuracy": counts.get(majority, 0) / n,
            "first_option_label": labels[0],
            "first_option_accuracy": counts.get(labels[0], 0) / n,
        }
        print(
            f"baselines on {name}: majority({majority})={baselines[name]['majority_accuracy']:.3f} "
            f"first_option({labels[0]})={baselines[name]['first_option_accuracy']:.3f}",
            flush=True,
        )

    # ---- train one adapter per task ------------------------------------
    # Each adapter trains on a FRESH model: converting the model's linear
    # layers to LoRA layers mutates the model, and a second adapter built on
    # the FIRST would inherit its LoRA weights. A trained adapter is CACHED in
    # the work dir, so a re-run of the matrix does not retrain it.
    #
    # Each adapter gets its OWN DIRECTORY: the mlx-lm loader reads
    # `<dir>/adapters.safetensors` + `<dir>/adapter_config.json`, so a
    # per-task directory is what makes two adapters loadable side by side —
    # which is the whole point of a SET.
    adapter_paths = {}
    for name, t in task_rows.items():
        out_dir = os.path.join(args.work_dir, f"adapter_{name}")
        adapter_paths[name] = out_dir
        if os.path.exists(os.path.join(out_dir, "adapters.safetensors")):
            print(f"reusing trained adapter for {name} ({out_dir})", flush=True)
            continue
        print(f"training adapter for {name} ...", flush=True)
        m, t_tok = load(args.model)
        os.makedirs(out_dir, exist_ok=True)
        train_adapter(m, t_tok, name, t["train"], t["labels"], out_dir, args)
        del m
        print(f"  -> {adapter_paths[name]}", flush=True)

    # ---- the ADAPTER rows ----------------------------------------------
    for adapter_task in task_rows:
        path = adapter_paths[adapter_task]
        # A FRESH model per adapter: the adapter is applied to the loaded
        # model, and a mutated model would leak into the next cell.
        # Freshness is what makes the off-diagonal meaningful.
        m, t = load(args.model, adapter_path=path)
        row = {}
        for eval_task, spec in task_rows.items():
            s = score(
                m, t, spec["test"], spec["labels"], args.eval_limit, args.max_tokens
            )
            row[eval_task] = s
            b = baselines[eval_task]
            print(
                f"+ adapter {adapter_task} on {eval_task}: accuracy {s['accuracy']:.3f} "
                f"(n={s['n']}) [majority baseline {b['majority_accuracy']:.3f}]",
                flush=True,
            )
        matrix[adapter_task] = row
        del m

    # ---- the verdict ---------------------------------------------------
    #
    # The comparison is BASELINE-RELATIVE, and it has to be: a task whose
    # majority class is 0.79 makes any raw accuracy look like competence, and
    # the base model's own reasoning echoed the option list (the scoring
    # defect above). So every delta is measured against the STRONGEST
    # trivial predictor for that task, and a capability claim requires the
    # adapter to beat it.
    def trivial(task):
        b = baselines[task]
        return max(b["majority_accuracy"], b["first_option_accuracy"])

    deltas = {}
    for adapter_task, row in matrix.items():
        deltas[adapter_task] = {
            "own_task_delta_vs_base": row[adapter_task]["accuracy"]
            - base_scores[adapter_task]["accuracy"],
            "own_task_delta_vs_trivial": row[adapter_task]["accuracy"]
            - trivial(adapter_task),
            "off_task_deltas_vs_base": {
                k: row[k]["accuracy"] - base_scores[k]["accuracy"]
                for k in task_rows
                if k != adapter_task
            },
            "off_task_deltas_vs_trivial": {
                k: row[k]["accuracy"] - trivial(k)
                for k in task_rows
                if k != adapter_task
            },
        }

    # A capability claim: the adapter must beat the trivial baseline on its
    # OWN task by a margin (0.05 — five points above "always guess"), and
    # must not push the OTHER task below its trivial baseline.
    capability = {}
    for adapter_task, d in deltas.items():
        own = d["own_task_delta_vs_trivial"]
        worst_off = (
            min(d["off_task_deltas_vs_trivial"].values())
            if d["off_task_deltas_vs_trivial"]
            else 0.0
        )
        capability[adapter_task] = {
            "own_task_delta_vs_trivial": own,
            "worst_off_task_delta_vs_trivial": worst_off,
            "beats_trivial_on_own_task": own > 0.05,
            "damages_off_task": worst_off < -0.05,
            "selective": own > 0.05 and worst_off >= -0.05,
        }

    verdict = {
        "contract": "nursery.adapter-set-capability.v1",
        "when_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "model": args.model,
        "iters": args.iters,
        "rank": args.rank,
        "scale": args.scale,
        "seed": args.seed,
        "base": base_scores,
        "baselines": baselines,
        "matrix": matrix,
        "deltas": deltas,
        "gates": {
            "K-G3_capability": capability,
            "K-G3_any_capability": any(
                c["beats_trivial_on_own_task"] for c in capability.values()
            ),
            "K-G3_any_selective": any(c["selective"] for c in capability.values()),
            "K-G3_set_justified": all(c["selective"] for c in capability.values()),
        },
        "elapsed_s": round(time.time() - t_start, 1),
        "power": power_snapshot.snapshot(),
        "non_claims": [
            "this arm runs the PYTHON mlx-lm adapter path; the native merge "
            "surface refuses a 4-bit base (K-G4), so nothing here claims the "
            "4-bit product checkpoint is usable with the native merge path",
            "accuracy is measured on one held-out split, one seed",
            "no claim about a task the base cannot do at all",
            "the clause task's majority class is 0.79, so its absolute "
            "accuracy is near-degenerate; the baseline-relative delta is the "
            "readable number, not the raw accuracy",
        ],
    }
    text = json.dumps(verdict, indent=2, sort_keys=True)
    print(text)
    if args.out:
        os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
        with open(args.out, "w") as fh:
            fh.write(text + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
