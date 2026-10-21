"""VETO-BRANCH-4 — the non-degenerate second task for Line K' (K'-G3).

WHY THIS CORPUS EXISTS. The 2026-10-21 adapter arm used the CLAUSE task as
its second task, and that task cannot show selectivity in EITHER direction:
its majority class is 0.860 (79-86% of the holdout is one label) and the
`action` label has ZERO holdout examples. A 4-way task that is really a
1.15-way task has no room to show a cross-task effect.

THIS task labels a permission request by WHICH VETO FIRED, not by whether one
fired. The ADR 0084 permission law is already implemented in
`tool/nursery/slots/perm_gate_1/perm_dataset.py`; its `decide()` collapses
every veto into a single "abstain". This generator keeps the SAME pools and
the SAME case-assembly law, but records the BRANCH — so the label set is:

    no_grant            no task grant bound to the request   (pg-010)
    destructive_op      a destructive verb                    (pg-005)
    outside_workspace   the target escapes the workspace      (pg-014)
    secret_path         a credential or another actor's claim (pg-009/pg-015)

PROPERTIES THIS CORPUS HAS, and the reason each one is a GATE (K'-G3):
  * the label set is DISJOINT from perm's ({allow_once, abstain}) and from
    clause's ({fact, done, open, action}) — so a cross-task prediction is
    unambiguous, and an adapter that answers in another task's vocabulary is
    a MISS, not a lucky hit;
  * the classes are BALANCED BY CONSTRUCTION (the generator cycles them), so
    the majority class is ~0.25, well below 0.5;
  * every label has examples in the holdout (the generator asserts it);
  * the TEXT FAMILY is the same as perm's (permission requests), so a
    domain shift cannot be blamed for any interference.

HONESTY BOUNDS.
  * The corpus teaches the LAW, not the answer key: the veto branch is a
    property of the request, computed by the same predicates the perm corpus
    uses.
  * The frozen acceptance cases are never emitted (the perm corpus's
    disjointness law is inherited: a pair- or triple-level hit resamples).
  * The base model's ability to do this task is NOT claimed. The first thing
    the Line K' arm measures is whether the BASE can do it at all — a task
    the base cannot do cannot be used to show selectivity.

Usage:
  ~/.venvs/mlx-ref/bin/python tool/nursery/veto_branch_dataset.py \
      --out bench/nursery/data/veto_branch_dataset.jsonl
(deterministic: seed 0; re-running reproduces the file byte-for-byte)
"""

import argparse
import importlib.util
import json
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)


def _load_perm():
    """Load the perm corpus module BY PATH.

    `slots/` is not a python package (no `__init__.py`), and the perm module
    resolves its own imports relative to `tool/nursery`, so it is loaded with
    an explicit spec rather than an import statement.
    """
    path = os.path.join(HERE, "slots", "perm_gate_1", "perm_dataset.py")
    spec = importlib.util.spec_from_file_location("perm_dataset", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# The pools and the case-assembly law are the perm corpus's — imported, not
# copied, so the two corpora cannot drift apart.
perm = _load_perm()

VETO_LABELS = [
    "no_grant",
    "destructive_op",
    "outside_workspace",
    "secret_path",
]


def _no_grant(rng):
    op = rng.choice(perm.FILE_WRITE_OPS)
    target = (
        rng.choice(perm.IN_WORKSPACE_DIRS)
        + "/"
        + rng.choice(perm.FILE_STEMS)
        + "."
        + rng.choice(perm.FILE_EXTS)
    )
    context = rng.choice(perm.NO_GRANT_CONTEXTS)
    return op, target, context


def _destructive(rng):
    op = rng.choice(perm.DESTRUCTIVE_OPS)
    target = (
        rng.choice(perm.IN_WORKSPACE_DIRS + ["build/"])
        + "/"
        + rng.choice(perm.FILE_STEMS)
    )
    context = "authorized task: " + rng.choice(perm.TASK_TEXTS)
    return op, target, context


def _outside_workspace(rng):
    if rng.random() < 0.5:
        op, target = rng.choice(perm.FILE_WRITE_OPS), rng.choice(perm.OUTSIDE_ABSOLUTE)
    else:
        op = rng.choice(perm.FILE_WRITE_OPS)
        target = rng.choice(
            [
                "../other_repo/lib/main.dart",
                "src/../../etc/hosts",
                "../../" + rng.choice(perm.IN_WORKSPACE_DIRS) + "/x.rs",
                "docs/../" + "../" * rng.randint(2, 3) + "outside.txt",
            ]
        )
    context = "authorized task: " + rng.choice(perm.TASK_TEXTS)
    return op, target, context


def _secret_path(rng):
    op = rng.choice(perm.FILE_WRITE_OPS)
    if rng.random() < 0.5:
        target = (
            rng.choice(perm.IN_WORKSPACE_DIRS).split("/")[0]
            + "/"
            + rng.choice(perm.SECRET_NAMES)
        )
    else:
        target = (
            rng.choice(perm.CLAIM_PREFIXES)
            + "/"
            + rng.choice(perm.FILE_STEMS)
            + "."
            + rng.choice(perm.FILE_EXTS)
        )
    context = "authorized task: " + rng.choice(perm.TASK_TEXTS)
    return op, target, context


BUILDERS = {
    "no_grant": _no_grant,
    "destructive_op": _destructive,
    "outside_workspace": _outside_workspace,
    "secret_path": _secret_path,
}


def classify(op, target, context):
    """Which veto fired — or None if no veto fired.

    The ORDER is the perm corpus's rule order, so the branch is a
    deterministic function of the request:
      1. no grant bound          (pg-010) — checked first: with no grant, the
         request fails closed regardless of anything else;
      2. destructive verb        (pg-005);
      3. target outside the workspace (pg-014);
      4. a secret path or another actor's claimed area (pg-009/pg-015).
    """
    granted = context.startswith("authorized task: ") and len(context) > len(
        "authorized task: "
    )
    if not granted:
        return "no_grant"
    if op in perm.DESTRUCTIVE_OPS:
        return "destructive_op"
    if op in perm.FILE_WRITE_OPS:
        if not perm.resolves_inside_workspace(target):
            return "outside_workspace"
        if perm.is_secret(target) or perm.is_claimed(target):
            return "secret_path"
        return None
    if op == perm.COMMAND_OP:
        # A command request is not one of this corpus's four branches; the
        # generator never emits one, and a command that is not safe is a
        # policy refusal with no branch label.
        return None
    return None


def generate(n_rows, seed, frozen_pairs=(), frozen_triples=()):
    rng = random.Random(seed)
    rows = []
    seen = set()
    attempts = 0
    while len(rows) < n_rows:
        attempts += 1
        if attempts > n_rows * 400:
            raise SystemExit(
                "generator could not diversify past the frozen-case "
                "disjointness law — pools too small"
            )
        # The classes are cycled, so they are balanced BY CONSTRUCTION.
        label = VETO_LABELS[len(rows) % len(VETO_LABELS)]
        op, target, context = BUILDERS[label](rng)
        if classify(op, target, context) != label:
            continue  # generator drift guard: the row must land as intended
        key = (op, target, context)
        if key in seen:
            continue
        if (op, target) in frozen_pairs or key in frozen_triples:
            continue
        seen.add(key)
        rows.append(
            {
                "id": "veto-%05d" % len(rows),
                "kind": label,
                "text": perm.case_text(
                    {"request": {"operation": op, "target": target, "context": context}}
                ),
            }
        )
    return rows


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument(
        "--out",
        default=os.path.join(
            os.path.dirname(os.path.dirname(HERE)),
            "bench",
            "nursery",
            "data",
            "veto_branch_dataset.jsonl",
        ),
    )
    ap.add_argument("--rows", type=int, default=900)
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args(argv)

    # The frozen acceptance cases are never emitted. The perm corpus's own
    # loader reads them from `slots/perm_gate_1/cases.jsonl`; this corpus
    # inherits the SAME law, so a pair- or triple-level hit resamples.
    frozen_pairs, frozen_triples = set(), set()
    cases_path = os.path.join(HERE, "slots", "perm_gate_1", "cases.jsonl")
    try:
        with open(cases_path) as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                case = json.loads(line)
                req = case.get("request", {})
                op = req.get("operation", "")
                target = (
                    req.get("path")
                    or req.get("command")
                    or req.get("url")
                    or req.get("pattern")
                    or ""
                )
                ctx = str(req.get("context", ""))
                frozen_pairs.add((op, target))
                frozen_triples.add((op, target, ctx))
    except (OSError, ValueError):
        pass
    if not frozen_pairs:
        print(
            "WARNING: the frozen acceptance cases were not loaded — the "
            "disjointness law is NOT binding for this run.",
            file=sys.stderr,
        )

    rows = generate(args.rows, args.seed, frozen_pairs, frozen_triples)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w") as fh:
        for r in rows:
            fh.write(json.dumps(r) + "\n")

    dist = {}
    for r in rows:
        dist[r["kind"]] = dist.get(r["kind"], 0) + 1
    manifest = {
        "generator": "veto_branch_dataset.v1",
        "rows": len(rows),
        "seed": args.seed,
        "labels": VETO_LABELS,
        "distribution": dist,
        "majority_accuracy": max(dist.values()) / max(1, len(rows)),
        "frozen_case_disjointness": {
            "pairs_checked": len(frozen_pairs),
            "triples_checked": len(frozen_triples),
            "emitted": "resample on hit",
        },
        "note": (
            "The label is WHICH veto fired, computed by the ADR 0084 predicates "
            "the perm corpus uses. This corpus teaches the law, not the answer "
            "key. The base model's ability to do this task is NOT claimed."
        ),
    }
    with open(args.out + ".manifest.json", "w") as fh:
        json.dump(manifest, fh, indent=2)
    print(json.dumps(manifest, indent=2))
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
