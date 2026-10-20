"""Build a Dart function-completion task set from a real repo.

The task is the one an adapter is supposed to own: given a signature and a
one-line requirement, produce the body. Two prompt shapes are emitted so the
adapter can be measured on the thing that actually matters here — how much
CONTEXT the job needs, not just whether it passes:

  minimal  signature + requirement only
  rich     signature + requirement + the file's imports and enclosing type

If an adapter moves `minimal` more than `rich`, it has moved knowledge from
the prompt into the weights — which is the only reason to build one.

Usage:
  python tool/nursery/build_dart_tasks.py --root <repo> --out <dir>
"""

import argparse
import json
import os
import re
import sys

SIG = re.compile(
    r"^(?P<indent>[ ]{0,2})(?P<sig>(?:Future<[^>]*>|void|int|double|bool|String|"
    r"List<[^>]*>|Map<[^>]*>|Set<[^>]*>|dynamic|Object\??|[\w<>?,\s]+?)\s+"
    r"(?P<name>[a-zA-Z_]\w*)\s*\((?P<params>[^;{}]*)\)\s*(?:async\s*)?\{)\s*$"
)


def doc_above(lines, i):
    """The contiguous /// block immediately above line i, if any."""
    out = []
    j = i - 1
    while j >= 0 and lines[j].strip().startswith("///"):
        out.append(lines[j].strip()[3:].strip())
        j -= 1
    return " ".join(reversed(out)).strip()


def imports_of(text):
    return "\n".join(
        ln
        for ln in text.splitlines()
        if ln.startswith("import ") or ln.startswith("part ")
    )


def enclosing_type(lines, i):
    for j in range(i, -1, -1):
        m = re.match(r"^(?:abstract |final |sealed )?class\s+(\w+)", lines[j])
        if m:
            return m.group(1)
    return None


def types_of(text):
    """Top-level type declarations (class/enum/typedef/mixin) — the context a
    completion needs to type-check, and the thing a minimal prompt omits."""
    out = []
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        ln = lines[i]
        if re.match(
            r"^(?:abstract |final |sealed |base )?(?:class|enum|mixin|typedef)\s+\w+",
            ln,
        ):
            depth = 0
            started = False
            block = []
            for k in range(i, min(len(lines), i + 60)):
                for ch in lines[k]:
                    if ch == "{":
                        depth += 1
                        started = True
                    elif ch == "}":
                        depth -= 1
                block.append(lines[k])
                if started and depth == 0:
                    break
            out.append("\n".join(block))
            i = k + 1
            continue
        i += 1
    return "\n\n".join(out)


def extract(path, text):
    lines = text.splitlines()
    imports = imports_of(text)
    types = types_of(text)
    tasks = []
    for i, line in enumerate(lines):
        m = SIG.match(line)
        if not m:
            continue
        # brace-match the body
        depth = 0
        body = []
        started = False
        for k in range(i, len(lines)):
            for ch in lines[k]:
                if ch == "{":
                    depth += 1
                    started = True
                elif ch == "}":
                    depth -= 1
            if started:
                body.append(lines[k])
            if started and depth == 0:
                break
        if depth != 0 or len(body) < 3:
            continue
        body_text = "\n".join(body)
        if len(body_text) > 1200:
            continue
        doc = doc_above(lines, i)
        if len(doc) < 15:
            continue
        owner = enclosing_type(lines, i)
        tasks.append(
            {
                "id": f"{os.path.basename(path)}::{m.group('name')}",
                "name": m.group("name"),
                "signature": m.group("sig").strip(),
                "requirement": doc,
                "body": body_text,
                "imports": imports,
                "types": types,
                "owner": owner,
            }
        )
    return tasks


EXAMPLE = (
    "Example:\n"
    "Requirement: Return the sum of a list of integers.\n"
    "Signature: int sum(List<int> xs) {\n"
    "Answer:\n"
    "{ return xs.fold(0, (a, b) => a + b); }\n"
)


def prompt(task, shape):
    head = (
        "Complete this Dart function. Reply with the function body only "
        "(the code between the braces, braces included).\n\n"
        + EXAMPLE
        + "\nNow do the same for this function.\n\n"
    )
    if shape == "rich":
        ctx = []
        if task["imports"]:
            ctx.append("File imports:\n" + task["imports"])
        if task.get("types"):
            ctx.append("Types declared in this file:\n" + task["types"])
        if task["owner"]:
            ctx.append(f"Enclosing type: {task['owner']}")
        ctx.append("Requirement: " + task["requirement"])
        ctx.append("Signature: " + task["signature"])
        return head + "\n\n".join(ctx)
    return (
        head
        + "Requirement: "
        + task["requirement"]
        + "\nSignature: "
        + task["signature"]
    )


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--limit", type=int, default=400)
    args = ap.parse_args(argv)

    files = []
    for dirpath, _dirs, names in os.walk(args.root):
        if "/.dart_tool" in dirpath or "/build" in dirpath:
            continue
        for n in names:
            if n.endswith(".dart"):
                files.append(os.path.join(dirpath, n))
    files.sort()

    tasks = []
    for f in files:
        try:
            text = open(f, encoding="utf-8").read()
        except Exception:
            continue
        tasks.extend(extract(f, text))
        if len(tasks) >= args.limit:
            break

    if not tasks:
        raise SystemExit("no tasks extracted — check the signature regex")

    os.makedirs(args.out, exist_ok=True)
    # deterministic split by id hash
    import hashlib

    train, valid = [], []
    for t in tasks:
        h = int(hashlib.sha256(t["id"].encode()).hexdigest(), 16)
        (valid if h % 10 == 9 else train).append(t)

    def write(path, rows, shape):
        with open(path, "w") as fh:
            for t in rows:
                fh.write(
                    json.dumps(
                        {
                            "messages": [
                                {"role": "user", "content": prompt(t, shape)},
                                {"role": "assistant", "content": t["body"]},
                            ]
                        }
                    )
                    + "\n"
                )

    data = os.path.join(args.out, "data")
    os.makedirs(data, exist_ok=True)
    write(os.path.join(data, "train.jsonl"), train, "minimal")
    write(os.path.join(data, "valid.jsonl"), valid, "minimal")
    with open(os.path.join(args.out, "eval.jsonl"), "w") as fh:
        for t in valid:
            fh.write(json.dumps(t) + "\n")

    print(
        json.dumps(
            {
                "files": len(files),
                "tasks": len(tasks),
                "train": len(train),
                "valid": len(valid),
                "out": os.path.abspath(args.out),
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
