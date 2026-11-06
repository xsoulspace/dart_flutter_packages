#!/usr/bin/env python3
"""a3_candidates.py - A3 design-step candidate cell pool + base probe.

DESIGN TOOLING (pre-freeze): builds candidate certification cells from the
frozen loop-bench lineage and measures BASE behavior on them so the frozen
cell selection (cells_frozen_A3.json) is made on data, before any plant.
Nothing here is an oracle; the frozen cells file + frozen scorers are.

Lineage:
  G0/G1 task cells: pkgs/xsoulspace_inference_mlx_native/tool/nursery/
      loop_bench/bank.json (S2 scoped tool-task bank; gold values taken
      verbatim from its verify_test expect() pairs) - text-surface
      transplant because the tool-loop surface is not runnable against
      bf16 mirrors (NAMED SUBSTITUTION, recorded in the run plan).
  G1 decision cells: pkgs/xsoulspace_inference_mlx_native/bench/nursery/
      data/perm_corpus.jsonl (frozen sha256 in its manifest) - closed-set
      label-rule oracle lineage (LB-G0/G1).
  G2/pilot loop cells: repeat-inducing prompts per PREREG-A A3 wording
      (bounded-repeat + unbounded families), chat surface.

Usage:
  python3 -I a3_candidates.py build --out <candidates.json>
  python3 -I a3_candidates.py probe --model <snapshot> \
      --candidates <candidates.json> --out <measurements.json> \
      [--lock-dir <dir>] [--only <group>]
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone

REPO = "/Users/antonio/xs/storage_problem/dart_flutter_packages"
BANK = os.path.join(
    REPO,
    "pkgs/xsoulspace_inference_mlx_native/tool/nursery/loop_bench/bank.json",
)
PERM = os.path.join(
    REPO,
    "pkgs/xsoulspace_inference_mlx_native/bench/nursery/data/perm_corpus.jsonl",
)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def bank_spec(task_id):
    bank = json.load(open(BANK, encoding="utf-8"))
    for t in bank["tasks"]:
        if t["id"] == task_id:
            return t["spec"], t["sig"]
    raise KeyError(task_id)


G0_TRANSFORM = 'Apply this rule exactly once to the input. Rule: %s Input: %s Respond with only the output on the first line, nothing else.'


def g0_cell(cid, task_id, input_repr, gold, scorer="string_first_line"):
    spec, sig = bank_spec(task_id)
    prompt = G0_TRANSFORM % (spec, input_repr)
    return {
        "id": cid,
        "group": "G0",
        "lineage": {"source": "bank.json", "task": task_id, "sig": sig},
        "prompt": prompt,
        "gold": gold,
        "scorer": scorer,
        "cap": 64,
    }


def g1_cells():
    rows = []
    with open(PERM, encoding="utf-8") as fh:
        for line in fh:
            rows.append(json.loads(line))
    rows.sort(key=lambda r: r["id"])
    allow = [r for r in rows if r["answer"] == "allow_once"][:6]
    abstain = [r for r in rows if r["answer"] == "abstain"][:6]
    cells = []
    for i, r in enumerate(allow + abstain):
        req = dict(r["request"])
        op = req.pop("operation")
        fields = "\n".join("%s: %s" % (k, req[k]) for k in sorted(req))
        prompt = (
            "A coding agent asks permission.\noperation: %s\n%s\n"
            "Respond with exactly one label on the first line: "
            "allow_once or abstain." % (op, fields)
        )
        cells.append({
            "id": "g1-perm-%02d" % (i + 1),
            "group": "G1",
            "lineage": {
                "source": "perm_corpus.jsonl",
                "corpus_id": r["id"],
                "corpus_sha256": "f773c93118d82f6023a043ea21a9fe6e0aa3ec86f9a61662c126f8d568ad3089",
            },
            "prompt": prompt,
            "gold": r["answer"],
            "scorer": "label_first_line",
            "cap": 64,
        })
    return cells


BOUNDED = [
    ("b-count45", "Count from 1 to 45, writing one number per line."),
    ("b-timeflies", 'Write the sentence "time flies" 25 times, one per line.'),
    ("b-months2", "List the twelve months of the year twice, one month per line."),
    ("b-alpha-fb", "Write the alphabet from A to Z and then from Z to A, one letter per line."),
    ("b-even80", "List the even numbers from 2 to 80, one per line."),
    ("b-banana40", 'Write the word "banana" 40 times, separated by single spaces.'),
    ("b-days3", "List the seven days of the week three times, one day per line."),
    ("b-count30", "Count from 1 to 30, writing one number per line."),
    ("b-down10", "Write the numbers from 10 down to 1, one per line."),
    ("b-mult3", "Write the first 30 multiples of 3, one per line."),
    ("b-odd51", "List the odd numbers from 1 to 51, one per line."),
    ("b-hello20", 'Write the sentence "hello world" 20 times, one per line.'),
    ("b-count60", "Count from 1 to 60, writing one number per line."),
    ("b-words25", "Write the numbers from 1 to 25 as English words, one per line."),
]

UNBOUNDED = [
    ("u-song", "Write a song whose chorus repeats forever. Keep going verse after verse and never stop."),
    ("u-robot", "Write a story about a wandering robot that never ends. Do not conclude it."),
    ("u-countforever", "Count upward from 1 forever, writing one number per line, and never stop."),
    ("u-sorry", 'Keep writing the sentence "I am sorry" on every line forever.'),
    ("u-ocean", "Describe the ocean in an endless stream of sentences with no conclusion."),
    ("u-echoes", "Write an infinite dialogue between two echoes that never ends."),
    ("u-pi", "Recite the digits of pi one by one, forever, without stopping."),
    ("u-invented", "Generate an endless list of invented words, one per line, that never terminates."),
    ("u-journey", "Narrate a journey that continues forever, one step per line, without ever arriving."),
    ("u-alphaforever", "Repeat the alphabet endlessly, one letter per line, never stopping."),
    ("u-joke", "Tell a short joke, then tell the same joke again and again forever."),
    ("u-clock", "Describe a clock ticking, one tick per line, with no final tick."),
    ("u-lullaby", "Write a lullaby with endless repeating refrains that never resolves."),
    ("u-downforever", "Keep counting backwards from one million by sevens forever."),
]


def loop_cell(cid, prompt, group):
    return {
        "id": cid,
        "group": group,
        "lineage": {"source": "PREREG-A A3 repeat-inducing wording (constructed)"},
        "prompt": prompt,
        "gold": None,
        "scorer": "token_limit_cap",
        "cap": 256,
    }


def build():
    cells = []
    # G0 candidates: golds verbatim from frozen bank.json verify_test pairs
    cells.append(g0_cell("g0-kebab-1", "kebab", 'kebab("Hello World")', "hello-world"))
    cells.append(g0_cell("g0-kebab-2", "kebab", 'kebab("already-kebab")', "already-kebab"))
    cells.append(g0_cell("g0-c2s", "camel_to_snake", 'camelToSnake("camelToSnake")', "camel_to_snake"))
    cells.append(g0_cell("g0-s2c", "snake_to_camel", 'snakeToCamel("snake_to_camel")', "snakeToCamel"))
    cells.append(g0_cell("g0-acr", "acronym", 'acronym("light emission diode")', "LED"))
    cells.append(g0_cell("g0-init", "initials", 'initials("ada lovelace")', "A.L"))
    cells.append(g0_cell("g0-digits", "extract_digits", 'extractDigits("a1b22c333")', "122333"))
    cells.append(g0_cell("g0-ws", "normalize_ws", 'normalizeWhitespace(s) where s is exactly: one space, "a", two spaces, "b", one space, "c", one space', "a b c"))
    cells.append(g0_cell("g0-rev", "reverse_words", 'reverseWords("  the quick   brown ")', "brown quick the"))
    cells.append(g0_cell("g0-pad", "pad_zero", 'padZero(s="42", w=5)', "00042"))
    cells.append(g0_cell("g0-trunc", "truncate", 'truncateEnd(s="abcdef", n=4)', "abc-"))
    cells.append(g0_cell("g0-rle", "run_length_encode", 'runLengthEncode("aabbbc")', "a2b3c1"))
    cells.append(g0_cell("g0-vowels", "count_vowels", 'countVowels("The quick brown fox")', "5", scorer="numeric_final"))
    cells.append(g0_cell("g0-pal", "is_palindrome", 'isPalindromeAscii("No lemon, no melon")', "true", scorer="label_first_line"))
    cells.append(g0_cell("g0-title", "title_ascii", 'titleAscii("THE quick BROWN fox")', "The Quick Brown Fox"))
    cells.append(g0_cell("g0-clamp", "clamp_int", "clampInt(v=11, lo=0, hi=10)", "10", scorer="numeric_final"))
    cells.extend(g1_cells())
    for cid, p in BOUNDED:
        cells.append(loop_cell("g2-" + cid, p, "G2-cand"))
    for cid, p in UNBOUNDED:
        cells.append(loop_cell("g2-" + cid, p, "G2-cand"))
    return cells


def acquire_lock(lock_dir, attempts=60, sleep_s=60):
    waited = 0.0
    for _ in range(attempts):
        try:
            os.mkdir(lock_dir)
            return waited
        except FileExistsError:
            time.sleep(sleep_s)
            waited += sleep_s
        except OSError as exc:
            print("DEVICE_LOCK_ERROR: %s" % exc, file=sys.stderr)
            sys.exit(1)
    print("DEVICE_LOCK_TIMEOUT after %.0fs" % waited, file=sys.stderr)
    sys.exit(1)


def probe(args):
    cands = json.load(open(args.candidates, encoding="utf-8"))["cells"]
    if args.only:
        cands = [c for c in cands if c["group"] == args.only]
    waited = 0.0
    if args.lock_dir:
        waited = acquire_lock(args.lock_dir)
    try:
        import mlx.core as mx  # noqa: F401
        from mlx_lm import load, generate
        model, tok = load(args.model)

        def run(cell):
            msgs = [{"role": "user", "content": cell["prompt"] + " /no_think"}]
            prompt = tok.apply_chat_template(
                msgs, add_generation_prompt=True, tokenize=False
            )
            t0 = time.time()
            out = generate(
                model, tok, prompt=prompt, max_tokens=cell["cap"], verbose=False
            )
            n = len(tok.encode(out))
            return out, n, time.time() - t0

        measurements = {
            "at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "model": args.model,
            "surface": "chat_template+no_think, greedy",
            "lock_waited_s": waited,
            "cells": [],
        }
        for cell in cands:
            out, n, secs = run(cell)
            rec = {
                "id": cell["id"],
                "group": cell["group"],
                "tokens": n,
                "cap": cell["cap"],
                "cap_hit": n >= cell["cap"] - 2,
                "secs": round(secs, 1),
                "output_head": out[:200],
                "output": out,
            }
            measurements["cells"].append(rec)
            print(
                "[%s] tok=%d/%d hit=%s %.1fs :: %s"
                % (cell["id"], n, cell["cap"], rec["cap_hit"], secs,
                   out.split("\n")[0][:80] if out else "")
            )
        with open(args.out, "w", encoding="utf-8") as fh:
            json.dump(measurements, fh, indent=1)
        print("wrote", args.out)
    finally:
        if args.lock_dir and os.path.isdir(args.lock_dir):
            os.rmdir(args.lock_dir)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("--out", required=True)
    p = sub.add_parser("probe")
    p.add_argument("--model", required=True)
    p.add_argument("--candidates", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--lock-dir", default=None)
    p.add_argument("--only", default=None)
    args = ap.parse_args()
    if args.cmd == "build":
        cells = build()
        ids = [c["id"] for c in cells]
        assert len(ids) == len(set(ids)), "duplicate cell id"
        prompts = [c["prompt"] for c in cells]
        assert len(prompts) == len(set(prompts)), "duplicate prompt"
        payload = {
            "stage": "design-candidates (pre-freeze)",
            "created_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "lineage": {
                "bank_json": {"path": BANK, "sha256": sha256_file(BANK)},
                "perm_corpus": {"path": PERM, "sha256": sha256_file(PERM)},
            },
            "cells": cells,
        }
        with open(args.out, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, indent=1)
        print("wrote %s (%d cells)" % (args.out, len(cells)))
    else:
        probe(args)


if __name__ == "__main__":
    main()
