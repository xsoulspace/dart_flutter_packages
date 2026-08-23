#!/usr/bin/env python3
"""Audit Dart sources for bare `return <Future expr>` inside `async` functions.

In async Dart, `return someFuture` inside a `try` block BYPASSES the
surrounding catch clauses: the error completes the function's future
directly without being raised inside the try. This caused the Universal
Storage saveFile race-guard bug (fixed by using `return await ...`).

This is a heuristic review tool, not compiler-grade analysis: it flags
`return <expr>` statements that (a) are lexically inside an `async`
function body and (b) whose expression is not `await ...` but contains a
call-like parenthesized expression (likely returning a Future). Results
are candidates for human review — prefer rewriting as
`return await <expr>` whenever the expression may be a Future.

Usage:
  tool/universal_storage_async_return_audit.py [paths...]   # default: pkgs/*/lib
Exit code 1 if any candidate found.
"""
import re
import sys
from pathlib import Path

# Rough strip of comments and string literals so brace counting and
# keyword detection aren't fooled by code inside strings.
LINE_COMMENT = re.compile(r"//[^\n]*")
BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)
STRING_LIT = re.compile(
    r"'''.*?'''|\"\"\".*?\"\"\"|r?'(?:\\.|[^'\\])'|r?\"(?:\\.|[^\"\\])\"",
    re.DOTALL,
)
ASYNC_DECL = re.compile(r"\basync\b[^{\n]*\{|\basync\b\s*\n?\s*\{")
RETURN_STMT = re.compile(r"(?<![\w.])return\s+([^;]+);")


def strip_noise(src: str) -> str:
    src = LINE_COMMENT.sub("", src)
    src = BLOCK_COMMENT.sub("", src)
    # Replace string contents with spaces to preserve offsets/newlines.
    def blank(match: re.Match) -> str:
        return "".join("\n" if c == "\n" else " " for c in match.group(0))

    return STRING_LIT.sub(blank, src)


def audit_file(path: Path) -> list[tuple[int, str]]:
    findings: list[tuple[int, str]] = []
    src = strip_noise(path.read_text(encoding="utf-8"))
    lines = src.splitlines()

    # Track brace depth and whether each enclosing brace belongs to an
    # async function declaration.
    depth_async: list[bool] = []
    pending_async = False
    for lineno, line in enumerate(lines, start=1):
        i = 0
        while i < len(line):
            ch = line[i]
            if ch == "{":
                depth_async.append(pending_async)
                pending_async = ASYNC_DECL.search(line[max(0, i - 120) : i + 1]) is not None
            elif ch == "}":
                if depth_async:
                    pending_async = depth_async.pop()
            i += 1

        in_async = any(depth_async) or pending_async
        if not in_async:
            continue
        for match in RETURN_STMT.finditer(line):
            expr = match.group(1).strip()
            if expr.startswith("await"):
                continue
            # Skip non-call returns: identifiers, literals, this, throw etc.
            if "(" not in expr:
                continue
            # Heuristic: a call expression that likely returns a Future.
            findings.append((lineno, line.strip()[:160]))
    return findings


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parent.parent
    patterns = argv[1:] or ["pkgs/*/lib"]
    files: list[Path] = []
    for pattern in patterns:
        p = root / pattern if not pattern.startswith("/") else Path(pattern)
        if p.is_file():
            files.append(p)
        else:
            base = p.parent if "*" in str(p) else p
            suffix = p.name if "*" in str(p) else "**/*.dart"
            files.extend(sorted(base.glob(suffix)) if base.exists() else [])
    dart_files = [f for f in files if f.suffix == ".dart"]

    total = 0
    for path in dart_files:
        for lineno, snippet in audit_file(path):
            try:
                rel = path.relative_to(root)
            except ValueError:
                rel = path
            print(f"{rel}:{lineno}: {snippet}")
            total += 1

    print(
        f"\n{total} candidate(s) in {len(dart_files)} file(s). "
        "Candidates are review hints: rewrite as 'return await' if the "
        "expression can complete with an error inside a try block."
    )
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
