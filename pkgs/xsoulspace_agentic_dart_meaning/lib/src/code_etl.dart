// ignore_for_file: lines_longer_than_80_chars

/// Deterministic code ETL — repository-scale meaning trees without a model.
///
/// The ADR 0022 pipeline proved ETL-in/ETL-out for TEST suites at task
/// scale. This module proves the same discipline at REPOSITORY scale:
///
/// - **ETL-in (code → meaning tree)**: every Dart file becomes a `file`
///   node; every top-level declaration and class member becomes a `symbol`
///   node; `contains` / `member` / `imports` / `refs` edges make the
///   reference graph queryable by ray-cast.
/// - **ETL-out (meaning tree → manifest)**: the tree reconstructs the
///   declaration manifest; a fidelity check diffs it against a fresh scan
///   (the round-trip contract — the tree HOLDS the code's structure).
/// - **Decomposition without a model**: reverse-reference closure over the
///   tree yields an impact frontier; projected as first-class plan steps
///   (ADR 0009) and cut by `projectPlanFrontier` under a token budget.
///
/// Everything here is pure host code: deterministic, LLM-free, re-runnable.
/// Scaling flaws it surfaces (flush costs, index growth, projection
/// latency) are findings, recorded in `docs/agent/results_etl_scale.md`.
library;

import 'dart:io';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

/// One extracted declaration.
class CodeSymbol {
  CodeSymbol({
    required this.name,
    required this.declKind,
    required this.file,
    required this.line,
    required this.memberOf,
  });

  /// class | mixin | enum | extension | function | typedef | method | field
  final String declKind;
  final String name;
  final String file; // workspace-relative
  final int line;
  final String? memberOf; // enclosing class name
  String get stableId => 'sym_${file.replaceAll('/', '_')}_$name';
}

/// One scanned file.
class CodeFileScan {
  CodeFileScan({
    required this.relPath,
    required this.imports,
    required this.symbols,
  });
  final String relPath;
  final List<String> imports; // raw import URIs
  final List<CodeSymbol> symbols;
}

/// A deterministic structural scan of one Dart file (indentation-0
/// declarations + 2-space members inside class bodies — dart-formatted
/// sources, which this workspace enforces).
CodeFileScan scanDartFile(File f, String relPath) {
  final src = f.readAsStringSync();
  final lines = src.split('\n');
  final symbols = <CodeSymbol>[];
  final imports = <String>[];
  final importRe = RegExp("^import\\s+['\"]([^'\"]+)['\"];");
  final typeRe = RegExp(
    r'^(?:abstract\s+|sealed\s+|final\s+|base\s+|interface\s+)*'
    r'(class|enum|mixin|extension)\s+(\w+)',
  );
  RegExpMatch? fnDecl(String line) => RegExp(
    r'^([A-Za-z_][\w<>, ?]*?)\s+([A-Za-z_]\w*)\s*(<[^>]*>)?\s*\(',
  ).firstMatch(line);
  final typedefRe = RegExp(r'^typedef\s+(?:[\w<>, ?]+\s+)?(\w+)');
  final memberRe = RegExp(
    r'^  (?:static\s+|const\s+|final\s+|late\s+|override\s+)*'
    r'([A-Za-z_][\w<>, ?]*?)\s+([A-Za-z_]\w*)\s*(?:\(|=|;|\{)',
  );
  final getterRe = RegExp(r'^  ([\w<>, ?]+)\s+get\s+([A-Za-z_]\w*)');
  String? currentClass;
  var depth = 0;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.isEmpty || line.trimmed.startsWith('//')) continue;
    final imp = importRe.firstMatch(line);
    if (imp != null) {
      imports.add(imp.group(1)!);
      continue;
    }
    final type = typeRe.firstMatch(line);
    if (type != null && depth == 0) {
      currentClass = type.group(2)!;
      symbols.add(
        CodeSymbol(
          name: currentClass,
          declKind: type.group(1)!,
          file: relPath,
          line: i + 1,
          memberOf: null,
        ),
      );
      depth += _openBraces(line);
      continue;
    }
    if (depth == 0) {
      final td = typedefRe.firstMatch(line);
      if (td != null) {
        symbols.add(
          CodeSymbol(
            name: td.group(1)!,
            declKind: 'typedef',
            file: relPath,
            line: i + 1,
            memberOf: null,
          ),
        );
        continue;
      }
      // Skip declarations that are clearly not functions.
      final fn = fnDecl(line);
      if (fn != null &&
          !{
            'if',
            'for',
            'while',
            'switch',
            'return',
            'catch',
          }.contains(fn.group(2)) &&
          !line.trimmed.startsWith('}') &&
          (line.contains('{') || line.contains('=>'))) {
        symbols.add(
          CodeSymbol(
            name: fn.group(2)!,
            declKind: 'function',
            file: relPath,
            line: i + 1,
            memberOf: null,
          ),
        );
      }
      continue;
    }
    // Inside a class body: members at 2-space indent.
    if (currentClass != null && depth >= 1) {
      final gm = getterRe.firstMatch(line);
      if (gm != null) {
        symbols.add(
          CodeSymbol(
            name: gm.group(2)!,
            declKind: 'getter',
            file: relPath,
            line: i + 1,
            memberOf: currentClass,
          ),
        );
      } else {
        final mm = memberRe.firstMatch(line);
        if (mm != null) {
          final kind = line.contains('(') ? 'method' : 'field';
          symbols.add(
            CodeSymbol(
              name: mm.group(2)!,
              declKind: kind,
              file: relPath,
              line: i + 1,
              memberOf: currentClass,
            ),
          );
        }
      }
    }
    depth += _openBraces(line);
    if (depth <= 0) {
      depth = 0;
      currentClass = null;
    }
  }
  return CodeFileScan(relPath: relPath, imports: imports, symbols: symbols);
}

int _openBraces(String line) {
  var d = 0;
  var inStr = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (inStr) {
      if (c == r'\') continue;
      if (c == "'") inStr = false;
      continue;
    }
    if (c == "'") inStr = true;
    if (c == '{') d++;
    if (c == '}') d--;
  }
  return d;
}

extension on String {
  String get trimmed => trim();
}

/// Recursively lists dart files under [root], skipping build/generated dirs.
List<File> dartFiles(Directory root) {
  if (!root.existsSync()) return const [];
  const skip = ['.dart_tool', 'build', 'node_modules', '.symlinks'];
  final out = <File>[];
  final stack = <Directory>[root];
  while (stack.isNotEmpty) {
    final d = stack.removeLast();
    for (final e in d.listSync()) {
      if (e is Directory) {
        if (skip.any((s) => e.path.endsWith('/$s') || e.path.endsWith('.$s'))) {
          continue;
        }
        stack.add(e);
      } else if (e is File &&
          e.path.endsWith('.dart') &&
          !e.path.endsWith('.g.dart') &&
          !e.path.endsWith('.freezed.dart') &&
          !e.path.endsWith('.gr.dart')) {
        out.add(e);
      }
    }
  }
  return out;
}

/// Scans every package under [repoRoot]/pkgs (tier 2) or one package
/// (tier 1). Returns per-package scans.
Map<String, List<CodeFileScan>> scanTree(Directory repoRoot) {
  final out = <String, List<CodeFileScan>>{};
  final pkgsDir = Directory('${repoRoot.path}/pkgs');
  for (final pkg in pkgsDir.listSync().whereType<Directory>()) {
    final files = [
      ...dartFiles(Directory('${pkg.path}/lib')),
      ...dartFiles(Directory('${pkg.path}/test')),
      ...dartFiles(Directory('${pkg.path}/bin')),
    ];
    if (files.isEmpty) continue;
    final pkgName = pkg.path.split('/').last;
    out[pkgName] = [
      for (final f in files)
        scanDartFile(f, f.path.substring(repoRoot.path.length + 1)),
    ];
  }
  return out;
}

/// Builds the meaning tree from scans. Edges:
/// - `file --contains--> symbol`
/// - `symbol --member--> symbol` (class member)
/// - `file --imports--> file` (resolved within the scanned set)
/// - `file --refs--> symbol` (same-package, identifier intersection,
///   capped per file)
({int files, int symbols, int edges}) buildMeaningTreeFromCode(
  World world,
  Map<String, List<CodeFileScan>> scans, {
  int maxRefsPerFile = 200,
}) {
  var files = 0;
  var symbols = 0;
  var edges = 0;
  // Global symbol-name index (name → stable ids) for refs resolution,
  // per package to keep locality and edge count bounded.
  final nameIndex = <String, Map<String, List<String>>>{};
  // Pass 1: file + symbol nodes.
  for (final entry in scans.entries) {
    final pkg = entry.key;
    final perPkg = nameIndex.putIfAbsent(pkg, () => {});
    for (final scan in entry.value) {
      addMeaningNode(
        world,
        kind: 'file',
        label: scan.relPath,
        id: 'f_${scan.relPath.replaceAll('/', '_')}',
      );
      files++;
      for (final s in scan.symbols) {
        // FINDING (scale probe): same-name declarations in one file (e.g.
        // private handlers in separate class scopes) collide on the stable
        // id — disambiguate with a per-file ordinal.
        var id = s.stableId;
        var ordinal = 1;
        final index = world.getResource<MeaningIndex>();
        while (index.byId.containsKey(id)) {
          id = '${s.stableId}_${ordinal++}';
        }
        addMeaningNode(
          world,
          kind: 'symbol',
          label: s.name,
          props: {
            'file': s.file,
            'line': s.line,
            'decl': s.declKind,
            if (s.memberOf != null) 'member_of': s.memberOf,
          },
          id: id,
        );
        symbols++;
        (perPkg[s.name] ??= []).add(s.stableId);
        linkMeaning(
          world,
          from: 'f_${scan.relPath.replaceAll('/', '_')}',
          relation: 'contains',
          to: s.stableId,
        );
        edges++;
      }
    }
  }
  // Pass 2: imports + members + refs.
  final idRe = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');
  for (final entry in scans.entries) {
    final pkg = entry.key;
    final perPkg = nameIndex[pkg]!;
    final fileId = (String rel) => 'f_${rel.replaceAll('/', '_')}';
    for (final scan in entry.value) {
      final fromId = fileId(scan.relPath);
      // imports (same-scan-set resolution)
      for (final imp in scan.imports) {
        final rel = _resolveImport(imp, scan.relPath, scans);
        if (rel != null && scans[entry.key]!.any((s) => s.relPath == rel)) {
          if (linkMeaning(
            world,
            from: fromId,
            relation: 'imports',
            to: fileId(rel),
          )) {
            edges++;
          }
        }
      }
      // members
      for (final s in scan.symbols) {
        if (s.memberOf != null) {
          final owner = scan.symbols
              .where((o) => o.name == s.memberOf && o.memberOf == null)
              .firstOrNull;
          if (owner != null) {
            if (linkMeaning(
              world,
              from: owner.stableId,
              relation: 'member',
              to: s.stableId,
            )) {
              edges++;
            }
          }
        }
      }
      // refs: tokenize the file, intersect with same-package symbol names.
      final src = File('${_repoRootOf(scan.relPath)}/${scan.relPath}');
      if (!src.existsSync()) continue;
      final tokens = RegExp(
        r'[A-Za-z_$][A-Za-z0-9_$]*',
      ).allMatches(src.readAsStringSync()).map((m) => m.group(0)!).toSet();
      var refs = 0;
      for (final t in tokens) {
        if (!idRe.hasMatch(t) || t.length < 4) continue;
        final ids = perPkg[t];
        if (ids == null) continue;
        for (final id in ids) {
          if (refs >= maxRefsPerFile) break;
          if (linkMeaning(world, from: fromId, relation: 'refs', to: id)) {
            edges++;
            refs++;
          }
        }
        if (refs >= maxRefsPerFile) break;
      }
    }
  }
  return (files: files, symbols: symbols, edges: edges);
}

final Directory? _cachedRepoRoot = _findRepoRoot();

Directory? _findRepoRoot() {
  // The probe runs from the package dir; walk up to the workspace root
  // (pubspec.yaml with a `workspace:` key).
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('workspace:')) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

String? _repoRootOf(String relPath) => _cachedRepoRoot?.path;

/// Resolves an import URI to a scanned relative path when possible.
String? _resolveImport(
  String uri,
  String fromRel,
  Map<String, List<CodeFileScan>> scans,
) {
  if (uri.startsWith('dart:')) return null;
  if (uri.startsWith('package:')) {
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    if (slash == -1) return null;
    final pkg = rest.substring(0, slash);
    final within = rest.substring(slash + 1);
    final candidate = 'pkgs/$pkg/lib/$within';
    for (final entry in scans.entries) {
      for (final s in entry.value) {
        if (s.relPath == candidate || s.relPath.endsWith(within)) {
          return s.relPath;
        }
      }
    }
    return null;
  }
  // relative import
  final parts = fromRel.split('/')..removeLast();
  for (final seg in uri.split('/')) {
    if (seg == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (seg != '.') {
      parts.add(seg);
    }
  }
  return parts.join('/');
}

/// The structural manifest reconstructed FROM the meaning tree (ETL-out).
Map<String, List<(String, String, int)>> manifestFromTree(World world) {
  final view = meaningView(world);
  final out = <String, List<(String, String, int)>>{};
  for (final n in view.nodes) {
    if (n['kind'] != 'symbol') continue;
    final props = (n['props'] as Map?) ?? const {};
    final file = props['file'] as String?;
    if (file == null) continue;
    out.putIfAbsent(file, () => []).add((
      n['label'] as String,
      props['decl'] as String? ?? '?',
      (props['line'] as num?)?.toInt() ?? 0,
    ));
  }
  return out;
}

/// Fidelity: the tree must hold what the scan extracted — every scanned
/// symbol present in the tree manifest with the same file/line/kind.
({int checked, int mismatches, List<String> samples}) fidelityCheck(
  World world,
  Map<String, List<CodeFileScan>> scans,
) {
  final manifest = manifestFromTree(world);
  var checked = 0;
  var mismatches = 0;
  final samples = <String>[];
  for (final entry in scans.entries) {
    for (final scan in entry.value) {
      for (final s in scan.symbols) {
        checked++;
        final found = manifest[s.file]?.any(
          (m) => m.$1 == s.name && m.$2 == s.declKind && m.$3 == s.line,
        );
        if (found != true) {
          mismatches++;
          if (samples.length < 10) {
            samples.add('${s.file}:${s.line} ${s.declKind} ${s.name}');
          }
        }
      }
    }
  }
  return (checked: checked, mismatches: mismatches, samples: samples);
}
