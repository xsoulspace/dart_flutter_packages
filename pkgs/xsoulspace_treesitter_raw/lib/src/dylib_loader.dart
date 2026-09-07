// ignore_for_file: lines_longer_as_80_chars

/// ADR 0035 §8 — the dylib search order for the compiled grammar
/// (tool/build_grammar.sh output). Missing dylib = an HONEST named signal
/// (run tool/build_grammar.sh), never a silent fallback.
library;

import 'dart:io';

/// Returns the built grammar dylib path, or null when not built yet.
///
/// Search order:
/// 1. `XS_TREESITTER_DYLIB` env var (explicit override);
/// 2. a `.dylibs/libtree_sitter_typescript.{dylib,so}` in the current
///    directory or any ancestor (tests run from the package root; the
///    ancestor walk covers running from a subdirectory).
String? findGrammarDylib() {
  final override = Platform.environment['XS_TREESITTER_DYLIB'];
  if (override != null && override.isNotEmpty) {
    if (!File(override).existsSync()) {
      throw StateError(
        'tree-sitter: XS_TREESITTER_DYLIB set but file missing: $override',
      );
    }
    return override;
  }
  var dir = Directory.current.path;
  for (var i = 0; i < 8; i++) {
    for (final name in const [
      'libtree_sitter_typescript.dylib', // macOS
      'libtree_sitter_typescript.so', // Linux
    ]) {
      final candidate = '$dir/.dylibs/$name';
      if (File(candidate).existsSync()) return candidate;
    }
    final parent = File(dir).parent.path;
    if (parent == dir) break;
    dir = parent;
  }
  return null;
}
