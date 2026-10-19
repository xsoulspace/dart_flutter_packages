"""The permission DOMAIN corpus (v2): v1's law rows + no-grant coverage.

PERM-GATE-1 attempts 2–3 measured the shape of the failure: the model
had never lived in the permission domain (no readout, no capacity, no
quick e2e fixed it — see HISTORY 2026-10-18 evening). Attempt 4's
candidate is a DENSE trunk exposed to this corpus. v2 adds what v1
lacked:

  - NO-GRANT rows: bare commands and bare paths with an empty/absent
    task grant — abstain by the law (the grant veto fires first), and
    the single most under-represented pattern in v1 (~10% of rows).
  - real-world command diversity inside the existing safe/unsafe pools
    (more package-manager / test-runner / VCS shapes), still decided
    ONLY by perm_dataset.decide.

Provenance honesty: there are no recorded real permission requests
(the gate has never run live; the shipped all-abstain behavior is the
data collector — README). So v2 stays 100% law-generated: every row is
decided by perm_dataset.decide, the frozen 20 harness cases are
excluded at pair and triple level, and no human-labeled row is
simulated. Union with v1 is byte-stable (same seed for the v1 slice).

Usage:
  ~/.venvs/mlx-ref/bin/python perm_domain_corpus.py \
      --out ../../../../bench/nursery/data/perm_domain_corpus.jsonl
"""

import argparse
import json
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))  # tool/nursery

import perm_dataset as P  # noqa: E402

def _bare_targets():
    """Expand no-grant targets from the law module's own pools — program-
    matic diversity, still decided only by perm_dataset.decide."""
    out = []
    for safe in P.SAFE_COMMANDS:
        for pkg in P.PACKAGES:
            out.append((P.COMMAND_OP, safe.format(pkg=pkg)))
    for unsafe in P.UNSAFE_COMMANDS:
        for somewhere in ("/", "~/x", "src/", "/usr/local/bin", "build/"):
            out.append((P.COMMAND_OP, unsafe.format(somewhere=somewhere)))
    for net in P.NETWORK_COMMANDS:
        for url in P.URLS:
            out.append((P.COMMAND_OP, net.format(url=url)))
    for d in P.IN_WORKSPACE_DIRS:
        for stem in P.FILE_STEMS:
            for ext in P.FILE_EXTS[:4]:
                out.append(("edit_file", f"{d}/{stem}.{ext}"))
    for name in P.SECRET_NAMES[:5]:
        out.append(("edit_file", name))
    for stem in P.FILE_STEMS[:10]:
        out.append(("create_file", f"{stem}.md"))
    return out


BARE_TARGETS = _bare_targets()


def bare_rows(n, rng, frozen_pairs=(), frozen_triples=()):
    rows = []
    seen = set()
    tries = 0
    while len(rows) < n:
        tries += 1
        if tries > n * 100:
            break
        op, target = rng.choice(BARE_TARGETS)
        target = target.format(pkg=rng.choice(P.PACKAGES),
                               url=rng.choice(P.URLS))
        context = rng.choice(P.NO_GRANT_CONTEXTS + ["", "  "])
        answer = P.decide(op, target, context)
        if answer != "abstain":
            continue  # every no-grant row must abstain by law
        key = (op, target, context)
        if key in seen or (op, target) in frozen_pairs \
                or key in frozen_triples:
            continue
        seen.add(key)
        field = "command" if op == P.COMMAND_OP else "path"
        rows.append({"id": f"permdom-{len(rows):05d}",
                     "request": {"operation": op, field: target,
                                 "context": context},
                     "answer": answer})
    return rows


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", required=True)
    ap.add_argument("--n-v1", type=int, default=1200)
    ap.add_argument("--n-bare", type=int, default=700)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--cases", default=os.path.join(HERE, "cases.jsonl"))
    args = ap.parse_args(argv)

    frozen = [json.loads(l) for l in open(args.cases) if l.strip()]
    frozen_pairs, frozen_triples = set(), set()
    for c in frozen:
        req = c["request"]
        target = req.get("path") or req.get("command") or req.get("url") \
            or req.get("pattern") or ""
        frozen_pairs.add((req.get("operation"), target))
        frozen_triples.add((req.get("operation"), target, req.get("context")))

    v1 = P.generate(args.n_v1, args.seed, frozen_pairs, frozen_triples)
    rng = random.Random(args.seed + 1)
    bare = bare_rows(args.n_bare, rng, frozen_pairs, frozen_triples)
    rows = v1 + bare

    for i, r in enumerate(rows):
        r["id"] = f"dom-{i:05d}"
        req = r["request"]
        target = req.get("path") or req.get("command") or ""
        assert P.decide(req["operation"], target, req["context"]) \
            == r["answer"], r["id"]
        assert (req["operation"], target) not in frozen_pairs
        assert (req["operation"], target, req["context"]) not in frozen_triples

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w") as fh:
        for r in rows:
            fh.write(json.dumps(r, sort_keys=True) + "\n")

    import hashlib
    n_allow = sum(1 for r in rows if r["answer"] == "allow_once")
    manifest = {
        "contract": "nursery.perm-corpus.v2",
        "generator": "tool/nursery/slots/perm_gate_1/perm_domain_corpus.py",
        "law": "perm_dataset.decide (unchanged; the veto order in its doc)",
        "rows": len(rows), "allow_once": n_allow,
        "abstain": len(rows) - n_allow,
        "v1_slice": len(v1), "no_grant_slice": len(bare),
        "seed": args.seed,
        "real_rows": 0,
        "real_rows_note": "no recorded real permission requests exist; "
                          "all-abstain live is the data collector (README)",
        "frozen_case_disjoint": {"checked": len(frozen), "collisions": 0},
        "sha256": hashlib.sha256(open(args.out, "rb").read()).hexdigest(),
    }
    with open(args.out + ".manifest.json", "w") as fh:
        json.dump(manifest, fh, indent=2, sort_keys=True)
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
