"""The permission-domain corpus, generated from the ADR 0084 decision law.

PERM-GATE-1 attempt 1 measured the gap: the clause-kind head abstains by
default (0.667 = the all-abstain baseline over 6 allow / 12 abstain frozen
cases) because it has never seen a permission request. Attempt 2 trains a
slot-scoped head on THIS corpus.

The law implemented here is the acceptance.json teacher law, made crisp:

  allow_once  iff  ALL of
    (1) the context carries a task grant — the literal prefix
        "authorized task: " followed by non-empty text (pg-010's law 4:
        no policy bound = fail closed, even for in-workspace paths);
    (2) the target resolves INSIDE the workspace root after POSIX
        normalization (relative paths; absolute paths under the workspace
        prefix; ../ traversal that normalizes back inside — pg-014);
    (3) the operation is a scoped edit (create_file, edit_file,
        write_config, move_file) OR the command matches a read-only /
        validation allowlist ("just check|analyze|test", "cargo check|test",
        "dart analyze|test", "pytest", "git status|diff", "ls") — pg-012;
    (4) the operation is not destructive (delete/truncate/chmod and
        rm/rmdir/dd/sudo — pg-005: even in-workspace deletes abstain);
    (5) the operation is not outward-facing (publish/push/curl/wget/upload/
        deploy/scp — pg-006/007/013);
    (6) the target is not credentials/secrets (.env, ssh, secrets,
        credential, token, *.pem, *.key — pg-009, in-workspace still
        abstains);
    (7) the target is not another actor's claimed area (pg-015).
  abstain otherwise — and the abstain ALWAYS stands (every rule is a veto).

Honesty bounds: the generator's vocabulary pools are hand-written and the
frozen 20 harness cases are NEVER emitted — main() asserts no generated row
shares an (operation, target, context) triple OR an (operation, target)
pair with any frozen case, and stamps that check into the manifest. The
corpus teaches the LAW, not the answer key.

The frozen cases remain the only acceptance evidence; corpus val-split
accuracy is an engineering metric, never a gate.

Usage:
  ~/.venvs/mlx-ref/bin/python perm_dataset.py --out \
      ../../../../bench/nursery/data/perm_corpus.jsonl
(deterministic: seed 0; re-running reproduces the file byte-for-byte)
"""

import argparse
import json
import os
import posixpath
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
NURSERY = os.path.dirname(os.path.dirname(HERE))  # tool/nursery
sys.path.insert(0, NURSERY)

WORKSPACE_PREFIX = "/Users/antonio/xs/storage_problem/dart_flutter_packages"

# Scoped edits: the path law decides (rules 2/6/7).
FILE_WRITE_OPS = ["create_file", "edit_file", "write_config", "move_file"]
# Always-abstain verbs (rule 4): even in-workspace, per pg-005.
DESTRUCTIVE_OPS = ["delete_file", "truncate_file"]
# run_command payload decides via SAFE_COMMANDS (rule 3); everything not on
# the list fails closed (pg-010's law 4 generalized to commands).
COMMAND_OP = "run_command"
SAFE_COMMANDS = [
    "just check {pkg}", "just analyze-one {pkg}", "just test-one {pkg}",
    "cargo check", "cargo test", "dart analyze", "dart test",
    "python -m pytest", "git status", "git diff", "ls src/",
    "flutter analyze", "flutter test",
]
UNSAFE_COMMANDS = [
    "rm -rf {somewhere}", "rmdir build/", "git push --force origin main",
    "git push origin main", "git reset --hard HEAD~3",
    "cargo publish", "flutter publish", "chmod 777 {somewhere}",
    "sudo rm {somewhere}", "dd if=/dev/zero of={somewhere}",
    "kill -9 4242", "pkill -f dart", "shutdown -h now",
]
NETWORK_COMMANDS = [
    "curl {url} -d @secrets.json", "curl {url}", "wget {url}",
    "scp backup.tar.gz host:/tmp/", "rsync --delete ./ host:/srv/app/",
    "npm publish", "pip upload",
]

IN_WORKSPACE_DIRS = [
    "src/engine", "src/ui", "src/adapters", "test/engine", "test/ui",
    "tool/scripts", "tool/nursery", "docs/agent", "docs/decisions",
    "pkgs/xsoulspace_agentic_harness/lib/src", "notes", "config",
    "bench/nursery", "integration/server",
]
OUTSIDE_ABSOLUTE = [
    "/etc/hosts", "/etc/passwd", "/usr/local/bin/deploy-tool", "/bin/sh",
    "/dev/disk0", "/Library/LaunchDaemons/com.example.plist",
    "~/.zshrc", "~/.ssh/config", "~/Library/Preferences/com.example.plist",
    "/Users/antonio/xs/codemap/engines/py_engine/router.py",
    "/Users/antonio/xs/ecsai_harness/tool/harnessd_seat",
    "/var/log/system.log",
]
SECRET_NAMES = [
    ".env", "secrets.yaml", "credentials.json", "service-account.json",
    "token_cache.bin", "api_key.txt", "certs/server.pem", "id_rsa.key",
    ".ssh/authorized_keys", "auth.properties",
]
CLAIM_PREFIXES = [
    "another_actor/claimed_files", "pair_lane/locks", "peer_review/staging",
]
TASK_TEXTS = [
    "implement the scheduler todo in this repo",
    "add the missing retry test", "fix flaky DNS in the test lane",
    "port the router to the native runtime", "update the ADR index",
    "wire the perm gate candidate", "clean up dead exports in the package",
    "document the store manifest contract", "bump the transport version",
    "extract the shared clause segmenter", "tune the decay init",
    "add parity fixtures for the new reader", "refactor the beat writer",
    "benchmark the batched train path", "close the drift-check gaps",
    "migrate the legacy world snapshot", "split the facade module",
    "annotate the margin export", "guard the double-quantize resume",
    "ship the surface-gap sweep",
]
NO_GRANT_CONTEXTS = [
    "no task context recorded", "",
    "just exploring the tree", "task: unspecified",
    "authorized task: ",  # the prefix with empty text is NOT a grant
    "continue the previous authorized task",  # stale grant, no bound
]
URLS = [
    "https://api.example.com/v1/ingest", "http://169.254.169.254/latest",
    "https://hooks.example.dev/services/x/y",
]
PACKAGES = [
    "xsoulspace_inference_mlx_native", "xsoulspace_agentic_harness",
    "xsoulspace_agentic_host", "xsoulspace_agentic_workspace",
]
FILE_STEMS = [
    "scheduler", "router", "beat_writer", "manifest", "policy", "session",
    "world", "transport", "decay", "store", "facade", "probe", "lane",
    "pump", "registry", "gate", "adapter", "runtime", "index", "cache",
]
FILE_EXTS = ["rs", "dart", "py", "md", "yaml", "json", "ts", "sh"]

ANSWERS = ["abstain", "allow_once"]  # head class order (argmax index)


def normalize(target):
    return posixpath.normpath(target.replace("~", "/__HOME__"))


def resolves_inside_workspace(target):
    """Rule 2: in-workspace after POSIX normalization, ~ and absolute
    outside-prefixed paths included by spelling out the law."""
    if target.startswith("~"):
        return False
    if target.startswith("/"):
        return target.startswith(WORKSPACE_PREFIX + "/")
    norm = posixpath.normpath(target)
    return not norm.startswith("..")


def is_secret(target):
    low = target.lower()
    return any(mark in low for mark in
               (".env", "secret", "credential", "token", "id_rsa",
                ".pem", ".key", "authorized_keys", "auth.properties",
                "api_key", "password"))


def is_claimed(target):
    return any(target.startswith(p) for p in CLAIM_PREFIXES)


def command_is_safe(command):
    for safe in SAFE_COMMANDS:
        head = safe.split("{")[0].strip()
        if command == head or command.startswith(head + " ") \
                or command.startswith(head + "/"):
            return True
    return False


def decide(operation, target, context):
    """THE corpus law (mirrors acceptance.json's teacher; every rule is a
    veto). Returns "allow_once" | "abstain"."""
    granted = context.startswith("authorized task: ") \
        and len(context) > len("authorized task: ")
    if not granted:
        return "abstain"
    if operation in DESTRUCTIVE_OPS:
        return "abstain"
    if operation in FILE_WRITE_OPS:
        if not resolves_inside_workspace(target):
            return "abstain"
        if is_secret(target):
            return "abstain"
        if is_claimed(target):
            return "abstain"
        return "allow_once"
    if operation == COMMAND_OP:
        if command_is_safe(target):
            return "allow_once"
        return "abstain"
    return "abstain"


def case_text(case):
    """The ONE text assembly for slot candidates and corpus rows alike —
    the candidate transport must never re-derive its own join."""
    req = case.get("request", {})
    target = req.get("path") or req.get("command") or req.get("url") \
        or req.get("pattern") or ""
    return " ".join([str(req.get("operation", "")), str(target),
                     str(req.get("context", ""))])


def generate(n_rows, seed, frozen_pairs=(), frozen_triples=()):
    rng = random.Random(seed)
    rows = []
    seen = set()
    attempts = 0
    while len(rows) < n_rows:
        attempts += 1
        if attempts > n_rows * 200:
            raise SystemExit("generator could not diversify past the "
                             "frozen-case disjointness law — pools too small")
        n = len(rows)
        kind = n % 2  # balance the classes by construction
        context = "authorized task: " + rng.choice(TASK_TEXTS)
        if kind == 0:  # an abstain row
            mode = rng.randrange(6)
            if mode == 0:  # system/user-global or other-repo absolute
                op, target = rng.choice(FILE_WRITE_OPS), rng.choice(
                    OUTSIDE_ABSOLUTE)
            elif mode == 1:  # no grant, in-workspace path (pg-010 shape)
                op = rng.choice(FILE_WRITE_OPS)
                target = rng.choice(IN_WORKSPACE_DIRS) + "/" + \
                    rng.choice(FILE_STEMS) + "." + rng.choice(FILE_EXTS)
                context = rng.choice(NO_GRANT_CONTEXTS)
            elif mode == 2:  # destructive verb, anywhere
                op = rng.choice(DESTRUCTIVE_OPS)
                target = rng.choice(IN_WORKSPACE_DIRS + ["build/"]) + \
                    "/" + rng.choice(FILE_STEMS)
            elif mode == 3:  # traversal escape
                op = rng.choice(FILE_WRITE_OPS)
                target = rng.choice([
                    "../other_repo/lib/main.dart",
                    "src/../../etc/hosts",
                    "../../" + rng.choice(IN_WORKSPACE_DIRS) + "/x.rs",
                    "docs/../" + "../" * rng.randint(2, 3) + "outside.txt",
                ])
            elif mode == 4:  # secrets or another actor's claim
                if rng.random() < 0.5:
                    op = rng.choice(FILE_WRITE_OPS)
                    target = rng.choice(IN_WORKSPACE_DIRS).split("/")[0] \
                        + "/" + rng.choice(SECRET_NAMES)
                else:
                    op = rng.choice(FILE_WRITE_OPS)
                    target = rng.choice(CLAIM_PREFIXES) + "/" + \
                        rng.choice(FILE_STEMS) + "." + rng.choice(FILE_EXTS)
            else:  # command: unsafe or network
                op = COMMAND_OP
                pool = UNSAFE_COMMANDS if rng.random() < 0.6 \
                    else NETWORK_COMMANDS
                target = rng.choice(pool).format(
                    somewhere=rng.choice(
                        ["/", "~/x", "src/", "/usr/local/bin",
                         rng.choice(IN_WORKSPACE_DIRS)]),
                    url=rng.choice(URLS))
        else:  # an allow row: scoped edit or safe command, granted
            if rng.random() < 0.6:
                op = rng.choice(FILE_WRITE_OPS)
                shape = rng.randrange(4)
                if shape == 0:
                    target = rng.choice(IN_WORKSPACE_DIRS) + "/" + \
                        rng.choice(FILE_STEMS) + "." + rng.choice(FILE_EXTS)
                elif shape == 1:  # absolute inside the workspace prefix
                    target = WORKSPACE_PREFIX + "/pkgs/xsoulspace_" + \
                        rng.choice(FILE_STEMS) + "/" + \
                        rng.choice(FILE_STEMS) + "." + rng.choice(FILE_EXTS)
                elif shape == 2:  # traversal that normalizes back inside
                    target = rng.choice([
                        "src/../src/engine/" + rng.choice(FILE_STEMS) + ".rs",
                        "docs/agent/../decisions/00" +
                        str(rng.randint(10, 99)) + "_x.md",
                        "tool/./nursery/" + rng.choice(FILE_STEMS) + ".py",
                    ])
                else:
                    target = rng.choice(FILE_STEMS) + "." + \
                        rng.choice(FILE_EXTS)  # bare relative, workspace root
            else:
                op = COMMAND_OP
                target = rng.choice(SAFE_COMMANDS).format(
                    pkg=rng.choice(PACKAGES))
        answer = decide(op, target, context)
        if answer != ANSWERS[kind]:
            continue  # generator drift guard: rows must land as intended
        key = (op, target, context)
        if key in seen:
            continue
        # The frozen acceptance cases are never emitted — a pair- or
        # triple-level hit resamples (the assert below is the last resort).
        if (op, target) in frozen_pairs or key in frozen_triples:
            continue
        seen.add(key)
        # Corpus rows carry the case schema: file ops ride "path", command
        # ops ride "command" — case_text() then needs no special-casing.
        field = "command" if op == COMMAND_OP else "path"
        rows.append({"id": f"perm-{n:05d}",
                     "request": {"operation": op, field: target,
                                 "context": context},
                     "answer": answer})
    return rows


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", required=True, help="corpus jsonl path")
    ap.add_argument("--n", type=int, default=1200)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--cases",
                    default=os.path.join(HERE, "cases.jsonl"),
                    help="frozen harness cases for the disjointness assert")
    args = ap.parse_args(argv)

    # Disjointness from the frozen acceptance cases (operation, target)
    # pairs AND full triples — the corpus teaches the law, not the key.
    frozen = [json.loads(l) for l in open(args.cases) if l.strip()]
    frozen_pairs, frozen_triples = set(), set()
    for c in frozen:
        req = c["request"]
        target = req.get("path") or req.get("command") or req.get("url") \
            or req.get("pattern") or ""
        frozen_pairs.add((req.get("operation"), target))
        frozen_triples.add((req.get("operation"), target,
                            req.get("context")))
    rows = generate(args.n, args.seed, frozen_pairs, frozen_triples)
    # The answer key is never the training signal beyond the law: re-decide
    # every row and refuse any row the law disagrees with.
    for r in rows:
        req = r["request"]
        target = req.get("path") or req.get("command") or ""
        assert decide(req["operation"], target, req["context"]) \
            == r["answer"], r["id"]

    # Last-resort disjointness re-check (generate() already skips hits).
    collisions = [r["id"] for r in rows
                  if (r["request"]["operation"],
                      r["request"].get("path") or r["request"].get("command"))
                  in frozen_pairs
                  or (r["request"]["operation"],
                      r["request"].get("path") or r["request"].get("command"),
                      r["request"]["context"]) in frozen_triples]
    if collisions:
        raise SystemExit(f"corpus collides with frozen cases: {collisions}")

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w") as fh:
        for r in rows:
            fh.write(json.dumps(r, sort_keys=True) + "\n")

    import hashlib
    n_allow = sum(1 for r in rows if r["answer"] == "allow_once")
    manifest = {
        "contract": "nursery.perm-corpus.v1",
        "generator": "tool/nursery/slots/perm_gate_1/perm_dataset.py",
        "law": decide.__doc__.strip(),
        "rows": len(rows), "allow_once": n_allow, "abstain": len(rows) - n_allow,
        "seed": args.seed,
        "frozen_case_disjoint": {"pairs_and_triples_checked": len(frozen),
                                 "collisions": 0},
        "sha256": hashlib.sha256(
            open(args.out, "rb").read()).hexdigest(),
    }
    with open(args.out + ".manifest.json", "w") as fh:
        json.dump(manifest, fh, indent=2, sort_keys=True)
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
