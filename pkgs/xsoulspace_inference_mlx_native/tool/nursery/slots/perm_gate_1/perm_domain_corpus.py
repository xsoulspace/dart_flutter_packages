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


def granted_veto_rows(n, rng, frozen_pairs=(), frozen_triples=()):
    """GRANTED rows whose target trips a veto — abstain by the law's veto
    arm, the exact shapes attempt 4 over-allowed on the frozen cases
    (pg-009 secret write, pg-013 network egress, pg-016 system path).
    The law (perm_dataset.decide) is UNCHANGED: this slice only reweights
    where the corpus spends its rows. Every row is law-decided; frozen
    cases stay excluded at pair and triple level."""
    def veto_target(mode, rng):
        if mode == 0:  # secret write, granted (the pg-009 shape)
            op = rng.choice(P.FILE_WRITE_OPS)
            name = rng.choice(P.SECRET_NAMES)
            return op, name if name.startswith(".") else name
        if mode == 1:  # outside/system absolute write, granted (pg-016)
            return rng.choice(P.FILE_WRITE_OPS), rng.choice(
                P.OUTSIDE_ABSOLUTE)
        if mode == 2:  # network command, granted (pg-013)
            return P.COMMAND_OP, rng.choice(P.NETWORK_COMMANDS).format(
                url=rng.choice(P.URLS))
        if mode == 3:  # destructive verb, granted (pg-005/pg-017)
            op = rng.choice(P.DESTRUCTIVE_OPS)
            return op, rng.choice(P.IN_WORKSPACE_DIRS) + "/" + \
                rng.choice(P.FILE_STEMS) + "." + rng.choice(P.FILE_EXTS)
        # mode 4: another actor's claimed file, granted (pg-015)
        op = rng.choice(P.FILE_WRITE_OPS)
        return op, rng.choice(P.CLAIM_PREFIXES) + "/" + \
            rng.choice(P.FILE_STEMS) + "." + rng.choice(P.FILE_EXTS)

    rows, seen, tries = [], set(), 0
    while len(rows) < n:
        tries += 1
        if tries > n * 100:
            break
        mode = len(rows) % 5
        op, target = veto_target(mode, rng)
        context = "authorized task: " + rng.choice(P.TASK_TEXTS)
        answer = P.decide(op, target, context)
        if answer != "abstain":
            continue  # a veto slice row that the law allows is a bug
        key = (op, target, context)
        if key in seen or (op, target) in frozen_pairs \
                or key in frozen_triples:
            continue
        seen.add(key)
        field = "command" if op == P.COMMAND_OP else "path"
        rows.append({"id": f"permveto-{len(rows):05d}",
                     "request": {"operation": op, field: target,
                                 "context": context},
                     "answer": answer})
    return rows


def granted_safe_rows(n, rng, frozen_pairs=(), frozen_triples=()):
    """GRANTED allow rows: safe commands and in-workspace non-secret
    writes — keeps the allow class calibrated against the veto slice
    (a corpus of only vetoes would just re-teach all-abstain)."""
    rows, seen, tries = [], set(), 0
    while len(rows) < n:
        tries += 1
        if tries > n * 100:
            break
        op, target = rng.choice(BARE_TARGETS)
        target = target.format(pkg=rng.choice(P.PACKAGES),
                               url=rng.choice(P.URLS))
        context = "authorized task: " + rng.choice(P.TASK_TEXTS)
        answer = P.decide(op, target, context)
        if answer != "allow_once":
            continue
        key = (op, target, context)
        if key in seen or (op, target) in frozen_pairs \
                or key in frozen_triples:
            continue
        seen.add(key)
        field = "command" if op == P.COMMAND_OP else "path"
        rows.append({"id": f"permsafe-{len(rows):05d}",
                     "request": {"operation": op, field: target,
                                 "context": context},
                     "answer": answer})
    return rows


# v4 hard slice: near-miss PAIRS at the law's boundaries — every target
# one spelling away from its opposite class. All rows are decided ONLY
# by perm_dataset.decide (no hand labels). Measured boundary probes
# (2026-10-28) back every family; one law hole was measured and is
# deliberately EXCLUDED from the rows: space-separated command chaining
# passes command_is_safe's prefix match ("dart test && rm -rf /" ->
# allow_once), so NO compound commands are emitted — the hole is a
# recorded corpus-law finding, not a training signal.

_HARD_ALLOW_NAMES = [
    # security-adjacent spellings with no is_secret mark
    "keymap.dart", "auth.md", "identity.json", "access.yaml",
    "crypto.py", "vault.rs", "session.md", "acl.dart",
    # credential-looking but outside every mark ("service-account.json"
    # is a SECRET_NAME, but the marks never include "service[_-]account")
    "accounts.md", "service_account.json",
]

_HARD_ALLOW_COMMANDS = [
    # safe-listed heads with extended arguments (prefix-match allows)
    "dart test tool/nursery", "dart analyze --no-fatal-infos",
    "cargo test --release", "cargo check -p xsoulspace_inference_core",
    "just check pkgs/xsoulspace_platform_foundation",
    "git diff HEAD~1", "git status --porcelain", "ls src/engine",
    "flutter test --plain-name decay", "python -m pytest -k store",
]

_HARD_VETO_ABSOLUTES = [
    "../other_repo/lib/main.dart", "src/../../etc/hosts",
    "tool/./../../etc/hosts", "src/engine/../../../outside.dart",
    "docs/../../Escape.md", "test/../test/../../outside.txt",
    "~/notes.md", "~/src/engine/router.rs", "~/.config/app.yaml",
    "/Users/antonio/xs/codemap/engines/x.py",
    "/Users/antonio/xs/ecsai_harness/tool/y.sh",
    "/etc/hosts.deny", "/usr/local/bin/tool",
]

_HARD_VETO_NAMES = [
    # one spelling away from an allow: the marks fire
    "session_token.md", "api_keys_doc.md", "auth.properties.bak",
    ".env.example", "src/config/.env.example", "id_rsa.pub",
    "cert.pem.bak", "deploy.key", "passwords.txt", "token_ring.rs",
    "credentials_old.yaml", ".pem_archive/x",
]

_HARD_VETO_COMMANDS = [
    # routine-looking verbs that are simply not allowlisted (fail closed)
    "dart format .", "dart fix --apply", "flutter clean",
    "flutter pub upgrade", "git commit -m checkpoint",
    "git checkout -b lane", "git stash", "cargo build --release",
    "cargo clippy", "python -m pip install requests",
]

_HARD_CLAIM_BOUNDARY = [
    # claimed-prefix boundaries: same parent, different child
    ("edit_file", "peer_review/notes.md"),        # prefix is staging/ -> allow
    ("edit_file", "peer_review/staging/x.dart"),  # claimed -> abstain
    ("edit_file", "pair_lane/notes.md"),          # prefix is locks/ -> allow
    ("edit_file", "pair_lane/locks/x.dart"),      # claimed -> abstain
    ("edit_file", "another_actor/notes.md"),      # prefix is claimed_files/ -> allow
    ("edit_file", "another_actor/claimed_files/x.dart"),  # claimed -> abstain
]


def _hard_target(allow, rng):
    """One hard near-miss target of the requested class (the caller
    re-decides it through P.decide — a mislabeled family is dropped)."""
    if allow:
        shape = rng.randrange(5)
        if shape == 0:  # absolute INSIDE the workspace prefix
            return rng.choice(P.FILE_WRITE_OPS), P.WORKSPACE_PREFIX + "/" + \
                rng.choice(P.IN_WORKSPACE_DIRS) + "/" + \
                rng.choice(P.FILE_STEMS) + "." + rng.choice(P.FILE_EXTS)
        if shape == 1:  # traversal that normalizes back inside
            d = rng.choice(P.IN_WORKSPACE_DIRS)
            return rng.choice(P.FILE_WRITE_OPS), \
                f"{d}/../{d}/" + rng.choice(P.FILE_STEMS) + "." + \
                rng.choice(P.FILE_EXTS)
        if shape == 2:  # security-adjacent name with no mark
            return rng.choice(P.FILE_WRITE_OPS), \
                rng.choice(_HARD_ALLOW_NAMES)
        if shape == 3:  # safe-listed command with extended arguments
            return P.COMMAND_OP, rng.choice(_HARD_ALLOW_COMMANDS)
        # claim-prefix boundary (the allow side)
        op, target = _HARD_CLAIM_BOUNDARY[rng.randrange(len(_HARD_CLAIM_BOUNDARY))]
        if P.decide(op, target, "authorized task: x") != "allow_once":
            return _hard_target(allow, rng)
        return op, target
    shape = rng.randrange(5)
    if shape == 0:  # traversal escape, ~ home, or sibling-repo absolute
        return rng.choice(P.FILE_WRITE_OPS), \
            rng.choice(_HARD_VETO_ABSOLUTES)
    if shape == 1:  # one mark away from an allow
        return rng.choice(P.FILE_WRITE_OPS), \
            rng.choice(P.IN_WORKSPACE_DIRS) + "/" + \
            rng.choice(_HARD_VETO_NAMES)
    if shape == 2:  # routine-looking, not allowlisted
        return P.COMMAND_OP, rng.choice(_HARD_VETO_COMMANDS)
    if shape == 3:  # destructive on a harmless scratch path
        return rng.choice(P.DESTRUCTIVE_OPS), \
            rng.choice(["scratch", "tmp", "build/logs"]) + "/" + \
            rng.choice(P.FILE_STEMS) + ".md"
    # claim-prefix boundary (the veto side)
    op, target = _HARD_CLAIM_BOUNDARY[rng.randrange(len(_HARD_CLAIM_BOUNDARY))]
    if P.decide(op, target, "authorized task: x") != "abstain":
        return _hard_target(allow, rng)
    return op, target


def hard_rows(n, rng, frozen_pairs=(), frozen_triples=()):
    """v4 curriculum slice: balanced hard near-miss pairs (grant held,
    target one spelling from the opposite class), decided ONLY by
    perm_dataset.decide, frozen-disjoint. Compound commands are never
    emitted (the measured prefix-chaining hole)."""
    rows, seen, tries = [], set(), 0
    while len(rows) < n:
        tries += 1
        if tries > n * 100:
            break
        allow = len(rows) % 2 == 0  # balance the classes by construction
        op, target = _hard_target(allow, rng)
        context = "authorized task: " + rng.choice(P.TASK_TEXTS)
        answer = P.decide(op, target, context)
        if answer != ("allow_once" if allow else "abstain"):
            continue  # generator drift guard: the law is the only teacher
        key = (op, target, context)
        if key in seen or (op, target) in frozen_pairs \
                or key in frozen_triples:
            continue
        seen.add(key)
        field = "command" if op == P.COMMAND_OP else "path"
        rows.append({"id": f"permhard-{len(rows):05d}",
                     "request": {"operation": op, field: target,
                                 "context": context},
                     "answer": answer})
    return rows


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", required=True)
    ap.add_argument("--n-v1", type=int, default=1200)
    ap.add_argument("--n-bare", type=int, default=700)
    ap.add_argument("--n-veto", type=int, default=0,
                    help="v3: granted rows that trip a veto (secret/"
                         "outside/network/destructive/claimed)")
    ap.add_argument("--n-safe", type=int, default=0,
                    help="v3: granted allow rows keeping the allow class "
                         "calibrated against the veto slice")
    ap.add_argument("--n-hard", type=int, default=0,
                    help="v4: balanced hard near-miss rows at the law's "
                         "boundaries (grant held; compound commands "
                         "never emitted — see hard_rows)")
    ap.add_argument("--clause-out",
                    help="v3: also write the trainer's clause form "
                         "(id, kind=answer, text=case_text)")
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
    slices = {"v1_slice": len(v1), "no_grant_slice": len(bare)}
    if args.n_veto or args.n_safe:
        rng3 = random.Random(args.seed + 2)
        veto = granted_veto_rows(args.n_veto, rng3, frozen_pairs,
                                 frozen_triples)
        safe = granted_safe_rows(args.n_safe, rng3, frozen_pairs,
                                 frozen_triples)
        rows = rows + veto + safe
        slices["veto_slice"] = len(veto)
        slices["safe_slice"] = len(safe)
    if args.n_hard:
        rng4 = random.Random(args.seed + 3)
        hard = hard_rows(args.n_hard, rng4, frozen_pairs, frozen_triples)
        rows = rows + hard
        slices["hard_slice"] = len(hard)

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
    if args.clause_out:
        with open(args.clause_out, "w") as fh:
            for r in rows:
                fh.write(json.dumps({
                    "id": r["id"],
                    "kind": r["answer"],
                    "text": P.case_text(r),
                }, sort_keys=True) + "\n")

    import hashlib
    n_allow = sum(1 for r in rows if r["answer"] == "allow_once")
    manifest = {
        "contract": ("nursery.perm-corpus.v4" if slices.get("hard_slice")
                     else "nursery.perm-corpus.v3"
                     if slices.get("veto_slice")
                     else "nursery.perm-corpus.v2"),
        "generator": "tool/nursery/slots/perm_gate_1/perm_domain_corpus.py",
        "law": "perm_dataset.decide (unchanged; the veto order in its doc)",
        "rows": len(rows), "allow_once": n_allow,
        "abstain": len(rows) - n_allow,
        **slices,
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
