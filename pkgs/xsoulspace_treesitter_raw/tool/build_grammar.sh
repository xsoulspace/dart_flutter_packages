#!/usr/bin/env bash
# ADR 0035 §8 — grammar build script for the tree-sitter spike.
#
# Fetches tree-sitter (runtime) and tree-sitter-typescript at PINNED
# revisions (shallow clones into a local cache) and compiles the grammar's
# parser.c (+ scanner.c if present) TOGETHER WITH the tree-sitter runtime
# into ONE dylib. macOS (.dylib) and Linux (.so) first — no windows path
# until the native path proves on the dev platform (ADR 0035 §8 non-goal).
#
# Output: <pkg>/.dylibs/libtree_sitter_typescript.{dylib,so}
# The Dart loader (lib/src/dylib_loader.dart) searches that directory.
#
# Bumping a pin = re-running the ParserConformance battery; the delta table
# in results_etl_grammar.md is the record (ADR 0022 invariant).
set -euo pipefail

# --- pinned revisions (do not bump without re-running conformance) ---------
TS_RUNTIME_REV="v0.25.8" # https://github.com/tree-sitter/tree-sitter
GRAMMAR_REV="v0.23.2"    # https://github.com/tree-sitter/tree-sitter-typescript

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${XSTS_GRAMMAR_CACHE:-$ROOT/.grammar-src}"
OUT_DIR="$ROOT/.dylibs"
mkdir -p "$CACHE" "$OUT_DIR"

OS="$(uname -s)"
case "$OS" in
  Darwin) OUT="$OUT_DIR/libtree_sitter_typescript.dylib" ;;
  Linux) OUT="$OUT_DIR/libtree_sitter_typescript.so" ;;
  *)
    echo "BLOCKED: unsupported platform '$OS' (macOS/Linux first per ADR 0035 §8)" >&2
    exit 2
    ;;
esac

if [ -f "$OUT" ]; then
  echo "dylib already built: $OUT (delete it to force a rebuild)"
  exit 0
fi

clone() { # clone <url> <rev> <dir>
  local url="$1" rev="$2" dir="$3"
  if [ -d "$dir/.git" ]; then
    local current
    current="$(git -C "$dir" describe --tags --exact-match 2>/dev/null || true)"
    if [ "$current" = "$rev" ]; then
      return 0
    fi
    rm -rf "$dir"
  fi
  echo "cloning $url @ $rev (shallow)"
  git clone --quiet --depth 1 --branch "$rev" "$url" "$dir"
}

clone https://github.com/tree-sitter/tree-sitter "$TS_RUNTIME_REV" "$CACHE/tree-sitter"
clone https://github.com/tree-sitter/tree-sitter-typescript "$GRAMMAR_REV" "$CACHE/tree-sitter-typescript"

GRAMMAR_SRC="$CACHE/tree-sitter-typescript/typescript/src"
[ -f "$GRAMMAR_SRC/parser.c" ] || {
  echo "BLOCKED: parser.c not found at $GRAMMAR_SRC" >&2
  exit 2
}

SOURCES=("$GRAMMAR_SRC/parser.c")
if [ -f "$GRAMMAR_SRC/scanner.c" ]; then
  SOURCES+=("$GRAMMAR_SRC/scanner.c")
elif [ -f "$GRAMMAR_SRC/scanner.cc" ]; then
  echo "BLOCKED: C++ scanner (scanner.cc) found — needs a C++ toolchain decision" >&2
  exit 2
fi

echo "compiling ${SOURCES[*]} + tree-sitter runtime ($TS_RUNTIME_REV) -> $OUT"
# The runtime is compiled INTO the grammar dylib so the Dart side opens ONE
# library and looks up both ts_parser_* and tree_sitter_typescript().
cc -O2 -shared -fPIC \
  "${SOURCES[@]}" \
  "$CACHE/tree-sitter/lib/src/lib.c" \
  -I "$GRAMMAR_SRC" \
  -I "$CACHE/tree-sitter/lib/include" \
  -I "$CACHE/tree-sitter/lib/src" \
  -o "$OUT"

echo "OK: $OUT"
