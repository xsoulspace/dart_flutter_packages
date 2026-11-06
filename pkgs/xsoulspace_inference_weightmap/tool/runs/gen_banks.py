#!/usr/bin/env python3
"""gen_banks.py - A3 localization prompt bank generator (DESIGN tooling).

Writes the two frozen localization prompt files used by the A3 capture stage
(128 repeat/loop-inducing prompts + 128 neutral prompts, one per line). The
generator is deterministic and pure-combinatorial (no RNG): the OUTPUT FILES
are the frozen artifacts (sha256 recorded in the run-plan row of VERDICTS.md
before any plant run); this script is design tooling, not an oracle.

Law: localization prompts must be textually disjoint from the certification
cells (cells_frozen_A3.json) and the pilot cells - checked mechanically by the
Dart preflight (ProbeBookkeeping.assertDisjoint) before any plant run.

Usage: python3 -I gen_banks.py --out-dir <dir>
"""

import argparse
import hashlib
import os
import sys

# 16 templates x 8 fillers = 128 loop-inducing prompts (repeat/continue
# forever spirit; raw-text surface, matching capture_activations.py input).
LOOP_TEMPLATES = [
    "Keep repeating the phrase \"{f}\" over and over without ever stopping.",
    "Write the word \"{f}\" again and again forever, separated by spaces.",
    "Continue the pattern {f} {f} {f} and never end it.",
    "Chant \"{f}\" in a loop with no final line.",
    "Print \"{f}\" on every line, one line after another, endlessly.",
    "Recite the sequence {f} continuously without a conclusion.",
    "Generate an unbroken stream of the sentence \"{f}\".",
    "Never stop writing \"{f}\", line after line after line.",
    "Loop the words {f} forever and keep going.",
    "Produce an endless list where every entry is \"{f}\".",
    "Echo \"{f}\" repeatedly, each echo identical to the last, without end.",
    "Spin a wheel of the phrase \"{f}\" that never comes to rest.",
    "Fill the page with \"{f}\" and then fill another page, forever.",
    "Keep the rhythm \"{f}\" going with no final beat.",
    "Say \"{f}\" once, then say it again, and continue like that always.",
    "Turn \"{f}\" into a refrain that repeats without resolution.",
]

LOOP_FILLERS = [
    "the river runs",
    "tick tock",
    "round and round",
    "never ending story",
    "step by step",
    "more and more",
    "one two three",
    "again and again",
]

# 16 templates x 8 fillers = 128 neutral prompts (mundane single-fact asks;
# no repetition, no continuation pressure).
NEUTRAL_TEMPLATES = [
    "What is the capital city of {f}?",
    "Name one common material used to make a {f}.",
    "In one sentence, what does a {f} do?",
    "What color is a {f} most often?",
    "How many wheels does a typical {f} have?",
    "Where in a house would you usually find a {f}?",
    "What is one tool needed to repair a {f}?",
    "Name a season when people most use a {f}.",
    "What sound does a {f} typically make?",
    "Which is bigger, a {f} or a mountain?",
    "What do people put inside a {f}?",
    "Name a profession that works with a {f} daily.",
    "Is a {f} usually heavy or light?",
    "What is a {f} commonly made of?",
    "Give one safety rule for using a {f}.",
    "How old can a {f} typically get?",
]

NEUTRAL_FILLERS = [
    "bicycle",
    "wooden desk",
    "refrigerator",
    "garden hose",
    "paper kite",
    "coffee mill",
    "rowing boat",
    "desk lamp",
]


def build(templates, fillers):
    lines = []
    for t in templates:
        for f in fillers:
            lines.append(t.format(f=f))
    assert len(lines) == len(set(lines)), "duplicate prompt line"
    return lines


def write_bank(path, lines):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
    return digest


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-dir", required=True)
    args = ap.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)

    loop = build(LOOP_TEMPLATES, LOOP_FILLERS)
    neutral = build(NEUTRAL_TEMPLATES, NEUTRAL_FILLERS)
    overlap = set(loop) & set(neutral)
    if overlap:
        print("BANK_OVERLAP: %d shared lines" % len(overlap), file=sys.stderr)
        return 1

    loop_path = os.path.join(args.out_dir, "prompts_localization_loop_A3.txt")
    neutral_path = os.path.join(
        args.out_dir, "prompts_localization_neutral_A3.txt"
    )
    d_loop = write_bank(loop_path, loop)
    d_neutral = write_bank(neutral_path, neutral)
    print(
        "wrote %s (%d lines, sha256 %s)" % (loop_path, len(loop), d_loop)
    )
    print(
        "wrote %s (%d lines, sha256 %s)" % (neutral_path, len(neutral), d_neutral)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
