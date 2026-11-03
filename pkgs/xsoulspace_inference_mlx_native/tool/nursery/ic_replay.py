"""ic_replay.py — DESCRIPTIVE CPU-replay reads over the Line IC caches.

NOT A GATE INPUT. The Line IC verdict (MTP-GATES.md Part 5: FAIL, no SIGNAL
cell) was computed by the frozen strict scorer and STANDS; nothing here can
move it. This tool exists for the post-run question the owner asked
(2026-11-03): "criticize the experiment — what would we do differently?"
Three criticisms are testable against the cached completions with zero GPU:

  D1 FORMAT-NORMALIZED READS. The strict scorer judges the WHOLE completion;
     the Procedure line flipped 1.7B into `label\\n\\njustification` prose, so
     the strict collapse conflates judgment with format compliance. Re-read
     every cell with two C-4-safe format-normalized extractors:
       first_line  the completion's first line, exactly equal to a label
       starts_with the completion begins with a label at a word boundary
     Paired McNemar vs the in-run base is reported as DESCRIPTIVE (these
     extractors were NOT frozen before the run; a scorer chosen after seeing
     data is a knob, so these numbers can inform a NEW arm's design but can
     never reopen this one).

  D2 INTENT CONTENT. IC-G4 checked intent DIVERSITY, never intent TYPE. Was
     the self-authored intent a procedure, a paraphrase, or an answer leak?
     Mechanical read: does the intent mention a task label (gold => leak,
     non-gold => mislead, neither => neutral/procedural)?

  D3 CONSTANT-PREFIX CHECK. If the closed arm picked one intent for ~all
     items, it conditioned on a near-constant string — i.e., it was the
     fixed-procedure control arm by accident, and "intent content" was never
     actually varied. Pick distributions + pick->gold contingency per cell.

Usage:
  python tool/nursery/ic_replay.py            # both casts, latest runs
  python tool/nursery/ic_replay.py --run-06b <dir> --run-17b <dir>
"""

import argparse
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

from adapter_conditioning import TASKS  # noqa: E402
from scoring import mcnemar  # noqa: E402

RUNS = os.path.join(PKG, "bench", "nursery", "experiments")


def first_line_extract(text, labels):
    """The first line of the completion, exactly equal to a label."""
    if not text:
        return None
    line = text.split("\n")[0].strip().strip(".").strip("*").strip()
    low = line.lower()
    for lab in labels:
        if low == lab.lower():
            return lab
    return None


def starts_with_extract(text, labels):
    """The label the completion STARTS with, at a word boundary (C-4-safe:
    `abstained` does not match `abstain`)."""
    if not text:
        return None
    low = text.lower().lstrip()
    for lab in labels:  # no label is a prefix of another in any task set
        if low.startswith(lab):
            nxt = low[len(lab) : len(lab) + 1]
            if not nxt or not re.match(r"[a-z0-9_]", nxt):
                return lab
    return None


def load_run(cast, run_dir=None):
    if run_dir:
        d = run_dir
    else:
        cands = sorted(
            x
            for x in os.listdir(RUNS)
            if x.startswith(f"intent-conditioning-{cast}-")
            and not x.endswith("SMOKE")
        )
        if not cands:
            raise SystemExit(f"no run for {cast}")
        d = cands[-1]
    path = os.path.join(RUNS, d)
    js = glob.glob(os.path.join(path, "intent-conditioning*.json"))
    with open(sorted(js)[-1]) as fh:
        return json.load(fh), path


def cache_items(path, regime, task):
    p = os.path.join(path, f"{regime}_{task}.jsonl")
    with open(p) as fh:
        return [json.loads(l) for l in fh if l.strip()]


def per_item(items, labels, extractor):
    out = []
    for it in items:
        pred = extractor(it.get("completion") or "", labels)
        out.append({"id": it["id"], "gold": it["gold"], "pred": pred,
                    "ok": pred == it["gold"]})
    return out


def label_words(task):
    """The label surface forms searched inside intent text (D2)."""
    words = set()
    for lab in TASKS[task]["labels"]:
        words.add(lab)
        words.add(lab.replace("_", " "))
    if task == "perm":
        words |= {"allow", "abstain"}
    return words


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-06b")
    ap.add_argument("--run-17b")
    args = ap.parse_args()

    runs = {
        "0.6b": load_run("0.6b", args.run_06b),
        "1.7b": load_run("1.7b", args.run_17b),
    }

    print("=" * 78)
    print("D1 — FORMAT-NORMALIZED READS (DESCRIPTIVE; the frozen strict verdict stands)")
    print("=" * 78)
    for cast, (rec, path) in runs.items():
        for task in ("perm", "veto", "clause"):
            labels = TASKS[task]["labels"]
            rows = {}
            for regime in ("base", "closed", "self"):
                items = cache_items(path, regime, task)
                rows[regime] = {
                    "strict": rec["cells"][task][regime]["cell"]["accuracy"],
                    "first_line_items": per_item(items, labels, first_line_extract),
                    "starts_items": per_item(items, labels, starts_with_extract),
                }
            base_f = rows["base"]["first_line_items"]
            base_s = rows["base"]["starts_items"]
            line = f"{cast:5s} {task:7s} strict: " + " ".join(
                f"{r}={rows[r]['strict']:.4f}" for r in rows
            )
            print(line)
            for name, key, bkey in (
                ("first_line", "first_line_items", None),
                ("starts_with", "starts_items", None),
            ):
                parts = []
                for r in ("base", "closed", "self"):
                    acc = sum(1 for x in rows[r][key] if x["ok"]) / len(rows[r][key])
                    parts.append(f"{r}={acc:.4f}")
                extra = ""
                for r in ("closed", "self"):
                    m = mcnemar(
                        base_f if key == "first_line_items" else base_s,
                        rows[r][key],
                    )
                    extra += (
                        f" | {r}: d={(sum(x['ok'] for x in rows[r][key]) - sum(x['ok'] for x in (base_f if key == 'first_line_items' else base_s))) / len(rows[r][key]) * 100:+.2f}pp"
                        f" p={m['p_two_sided_exact']:.2e} disc={m['discordant']}"
                        f" (base_only={m['a_only_correct']}, reg_only={m['b_only_correct']})"
                    )
                print(f"      {name:11s} " + " ".join(parts) + extra)

    print()
    print("=" * 78)
    print("D2 — INTENT CONTENT: leak / mislead / neutral rates (self arm; descriptive)")
    print("=" * 78)
    for cast, (rec, path) in runs.items():
        for task in ("perm", "veto", "clause"):
            labels = TASKS[task]["labels"]
            words = label_words(task)
            items = cache_items(path, "self", task)
            leak = mislead = neutral = 0
            leak_correct = leak_n = 0
            for it in items:
                intent = (it.get("intent") or "").lower()
                mentioned = {w for w in words if w in intent}
                gold_words = {
                    w
                    for w in mentioned
                    if w == it["gold"] or w == it["gold"].replace("_", " ")
                    or (it["gold"] in w and len(w) > 3)
                }
                if gold_words:
                    leak += 1
                    leak_n += 1
                    leak_correct += int(it["pred_strict"] == it["gold"])
                elif mentioned:
                    mislead += 1
                else:
                    neutral += 1
            n = len(items)
            print(
                f"{cast:5s} {task:7s} leak={leak / n:.3f} ({leak}) "
                f"mislead={mislead / n:.3f} ({mislead}) "
                f"neutral={neutral / n:.3f} ({neutral})"
                + (f" | leak->strict-correct {leak_correct}/{leak_n}" if leak_n else "")
            )

    print()
    print("=" * 78)
    print("D3 — CONSTANT-PREFIX CHECK: closed-arm pick distribution + pick->gold")
    print("=" * 78)
    for cast, (rec, path) in runs.items():
        for task in ("perm", "veto"):
            items = cache_items(path, "closed", task)
            dist = {}
            cont = {}
            for it in items:
                p = it.get("intent") or "<none>"
                dist[p] = dist.get(p, 0) + 1
                cont.setdefault(p, {}).setdefault(it["gold"], 0)
                cont[p][it["gold"]] += 1
            n = len(items)
            top = max(dist.values())
            print(f"{cast:5s} {task:7s} top_share={top / n:.3f} dist={dist}")
            for p, g in sorted(cont.items()):
                print(f"        pick={p:24s} gold={g}")

    print()
    print("All reads above are DESCRIPTIVE (post-hoc extractors). The gating")
    print("verdict is MTP-GATES.md Part 5 + intent-conditioning-verdict-*.json.")


if __name__ == "__main__":
    main()
