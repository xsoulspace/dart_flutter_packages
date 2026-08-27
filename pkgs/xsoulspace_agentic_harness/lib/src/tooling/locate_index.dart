// ignore_for_file: lines_longer_than_80_chars

/// `locate` — the structural discovery tool of ADR 0014 §2 (the ray-cast).
///
/// Where `grep`/`glob` brute-force the filesystem, `locate` answers "where is
/// symbol X defined / used?" from a deterministic **identifier index** built
/// once over the workspace. The small model finds things in one cheap call
/// instead of recursively reading files. It is a *ray over an index* — the
/// same spirit as projection — never a projection replacement.
///
/// ## Design (deliberately heuristic, code-agnostic)
/// - No compiler/AST lifecycle: a lexical scanner records, for every source
///   file in the jail, the line number + snippet of each identifier token.
///   Marking a line as a `definition` candidate is a cheap line-shape
///   heuristic (`class X`, `function X`, `X =`, `const X`, `import X`…), not a
///   guarantee. Consumers treat it as the *matrix* view (world-affordance),
///   never as compiler truth.
/// - Deterministic: files are walked in sorted order; token order is stable.
/// - Token-bounded: [locate] caps the rows returned.
/// - Jailed: paths are root-relative, like every other fs tool.
///
/// The index serializes to JSON ([SymbolIndex.toJson]) so hosts can persist /
/// restore it (snapshot-friendly, AE-shaped: this is the "matrix" a
/// classifier `/structurizer` would feed, never the actor's memory truth).
library;

import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show FM, SchemaBundle, ToolDef, ToolName;

// Identifier token (covers most real-world code languages; not unicode-ID
// correct, honest and documented as a heuristic).
final RegExp _ident = RegExp('[A-Za-z_][A-Za-z0-9_]*');

const Set<String> _stopwords = {
  'if', 'else', 'for', 'while', 'package', 'import', 'export', 'the', 'is',
};

/// One occurrence of a symbol at a location.
class SymbolOccurrence {
  const SymbolOccurrence({required this.file, required this.line, this.snippet = '', this.isDefinition = false});
  final String file;
  final int line;
  final String snippet;
  final bool isDefinition;

  Map<String, Object?> toJson() => {
    'file': file, 'line': line,
    if (snippet.isNotEmpty) 'snippet': snippet,
    'def': isDefinition,
  };
}

/// A hit for a `locate` query — the answer the model sees.
class LocateResult {
  const LocateResult({
    required this.symbol,
    required this.total,
    required this.occurrences,
  });
  final String symbol;
  final int total;
  final List<SymbolOccurrence> occurrences;

  Map<String, Object?> toJson() => {
    'symbol': symbol,
    'total': total,
    'occurrences': [for (final o in occurrences) o.toJson()],
  };

  int get definitionCount => occurrences.where((o) => o.isDefinition).length;
}

/// The cached symbol→locations index for a jail root.
class SymbolIndex {
  SymbolIndex._(this.root, this._bySymbol);

  /// Build an index over [root] by lexically walking source-ish files.
  /// [includeExts] limits which files to index (default a broadly useful set);
  /// pass `null` to accept every file. [maxFileChars] bounds a single file.
  ///
  /// Deterministic: sorted directory walk + per-file token order.
  factory SymbolIndex.build(
    String root, {
    Set<String>? includeExts,
    int? maxFiles,
  }) {
    final bySymbol = <String, List<SymbolOccurrence>>{};
    void add(String file, int line, String token, String snippet, {bool definition = false}) {
      final occ = SymbolOccurrence(
        file: file, line: line, snippet: snippet, isDefinition: definition);
      (bySymbol[token] ??= []).add(occ);
    }

    int scanned = 0;
    const budget = 6000;
    void walk(String dir) {
      final entries = Directory(dir).listSync()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final e in entries) {
        if (scanned >= (maxFiles ?? budget)) return;
        if (e is Directory) {
          walk(e.path);
        } else if (e is File) {
          final ext = e.path.split('.').last;
          if (includeExts != null && !includeExts.contains(ext)) continue;
          scanned++;
          try {
            final lines = e.readAsLinesSync();
            final rel = _relative(root, e.path);
            for (var i = 0; i < lines.length; i++) {
              final text = lines[i];
              for (final m in _ident.allMatches(text)) {
                final token = m.group(0)!;
                if (_stopwords.contains(token)) continue;
                add(rel, i + 1, token, _clip(text),
                    definition: _isDefLike(text, token));
              }
            }
          } on FileSystemException {
            // skip unreadable
          }
        }
      }
    }
    walk(root);
    return SymbolIndex._(root, bySymbol);
  }

  /// Load from previously-persisted JSON (see [toJson]).
  factory SymbolIndex.fromJson(String root, String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    final bySymbol = <String, List<SymbolOccurrence>>{};
    for (final e in (data['entries'] as Map).entries) {
      final key = e.key;
      final list = (e.value as List).cast<Map<String, dynamic>>();
      bySymbol[key] = [
        for (final m in list)
          SymbolOccurrence(
            file: m['file'] as String,
            line: m['line'] as int,
            snippet: m['snippet'] as String? ?? '',
            isDefinition: m['def'] as bool? ?? false,
          ),
      ];
    }
    return SymbolIndex._(root, bySymbol);
  }

  /// Jail root (absolute).
  final String root;

  /// symbol → occurrences, in build (sorted) order.
  final Map<String, List<SymbolOccurrence>> _bySymbol;

  /// Serialize for persistence/AE-shaped affordance.
  Map<String, Object?> toJson() => {
    'root': root,
    'entries': {
      for (final e in _bySymbol.entries)
        e.key: [for (final o in e.value) o.toJson()],
    },
  };

  /// Answer `where is [query]` from the index — a ray, capped, no I/O.
  ///
  /// Returns at most [maxResults] occurrences, definitions first, then by
  /// file (stable). Null when the symbol is absent (not an error — a miss).
  LocateResult? locate(String query, {int maxResults = 30}) {
    final hits = _bySymbol[query];
    if (hits == null || hits.isEmpty) return null;
    final capped = [...hits]
      ..sort((a, b) {
        if (a.isDefinition != b.isDefinition) return a.isDefinition ? -1 : 1;
        final f = a.file.compareTo(b.file);
        return f != 0 ? f : a.line.compareTo(b.line);
      });
    final trimmed = capped.take(maxResults).toList();
    return LocateResult(symbol: query, total: hits.length, occurrences: trimmed);
  }

  bool get isEmpty => _bySymbol.isEmpty;
  int get symbolCount => _bySymbol.length;
}

String _relative(String root, String path) =>
    path.startsWith(root.endsWith('/') ? root : '$root/')
        ? path.substring((root.endsWith('/') ? root : '$root/').length)
        : path;

/// Definition-looking lines — a cheap, honest heuristic.
bool _isDefLike(String line, String token) =>
    line.contains('class $token') ||
    (line.contains('function $token') || line.contains('fn $token')) ||
    line.replaceFirst(' const', '').contains(' $token =') ||
    line.contains('final $token') ||
    RegExp(r'\b(import)\b.*\b$token\b').hasMatch(line);

String _clip(String s, [int max = 120]) =>
    s.length <= max ? s : '${s.substring(0, max)}…';

/// Root wrapper carrying a [SymbolIndex] (pre-built by the host).
class LocateRoot {
  LocateRoot(this.index);
  final SymbolIndex index;
}

/// Registers a `locate` seam-3 tool over a prebuilt [SymbolIndex].
///
/// `execute` returns a compact, capped answer: definitions first, then uses,
/// all jail-relative. Never touches the filesystem at call time — pure index.
ToolDef locateTool(LocateRoot root) => ToolDef.encode(
      name: const ToolName('locate'),
      description:
          'Find where a symbol is defined and used in the workspace. '
          'Returns a ranked, capped list of occurrences (definitions first) '
          'from a prebuilt index. Arguments: symbol (required), '
          'max_results (optional). Sources are confined to the workspace.',
      argsSchema: SchemaBundle(
        root: FM.object(
          'locate',
          properties: () => [FM.prop('symbol', FM.string())],
        ),
      ),
      execute: (args) async {
        final map = args is Map ? args : const <String, dynamic>{};
        final sym = switch (map['symbol']) {
          final String s => s,
          _ => null,
        };
        if (sym == null || sym.isEmpty) {
          return {'ok': false, 'code': 'bad_args', 'hint': 'required "symbol"'};
        }
        final r = root.index.locate(sym);
        if (r == null) {
          return {'ok': true, 'symbol': sym, 'found': false, 'total': 0};
        }
        return {
          'ok': true,
          'symbol': r.symbol,
          'found': true,
          'total': r.total,
          'definitions': r.definitionCount,
          'occurrences': [for (final o in r.occurrences) o.toJson()],
        };
      },
    );
