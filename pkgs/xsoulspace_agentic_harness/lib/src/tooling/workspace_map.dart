// ignore_for_file: lines_longer_than_80_chars

/// Stage N5b — the workspace map: the fs as a graph, projected.
///
/// Before this, the model PAID decisions to build a mental map of the
/// workspace (`list_dir`/`glob` loops) and the map died with the beat budget
/// every turn. Now the map is world-adjacent host data: a deterministic,
/// bounded tree rendered into the cut's required `map` slot (ADR 0020).
/// Exploration shrinks to rare verification queries because the model starts
/// already knowing the territory.
///
/// Design:
/// - Bounded by construction: depth-capped, entry-capped, skip-listed
///   (.dart_tool, .git, build, ...); overflow rendered as an explicit
///   "+N more" line — a green-screen absence, never silent truncation.
/// - Test→subject links: `test/x_test.dart` is annotated with its subject
///   `lib/x.dart` when present — the exact pair a coding decision needs in
///   ONE cut (the N4 failure mode, killed structurally).
/// - Cached per [Directory] stat change: the map is rebuilt only when the
///   workspace root changes, so repeated decisions don't re-walk the tree.
library;

import 'dart:io';

const _defaultSkip = {'.dart_tool', '.git', 'build', 'node_modules', '.symlinks', '.idea'};

/// One cached map per workspace root.
class WorkspaceMapProvider {
  WorkspaceMapProvider(
    this.root, {
    this.maxDepth = 2,
    this.maxEntries = 30,
    this.skip = _defaultSkip,
  });

  final String root;
  final int maxDepth;
  final int maxEntries;
  final Set<String> skip;

  String? _cached;
  DateTime? _cachedAt;
  String? _rootStamp;

  /// Returns the current map (cached while the root is unchanged).
  String? map() {
    final dir = Directory(root);
    if (!dir.existsSync()) return null;
    String stamp;
    try {
      stamp = dir.statSync().modified.toIso8601String();
    } on FileSystemException {
      return _cached;
    }
    if (_cached != null && _rootStamp == stamp && _cachedAt != null) {
      final age = DateTime.now().difference(_cachedAt!);
      if (age < const Duration(seconds: 2)) return _cached;
    }
    _rootStamp = stamp;
    _cachedAt = DateTime.now();
    _cached = _build(dir);
    return _cached;
  }

  String _build(Directory dir) {
    final lines = <String>[];
    var overflow = 0;
    void walk(Directory d, int depth, String prefix) {
      if (depth > maxDepth || lines.length >= maxEntries) return;
      List<FileSystemEntity> entries;
      try {
        entries = d.listSync()
          ..sort((a, b) => a.path.compareTo(b.path));
      } on FileSystemException {
        return;
      }
      for (final e in entries) {
        final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (skip.contains(name)) continue;
        if (lines.length >= maxEntries) {
          overflow++;
          continue;
        }
        if (e is Directory) {
          lines.add('$prefix$name/');
          walk(e, depth + 1, '$prefix  ');
        } else {
          lines.add('$prefix$name');
        }
      }
    }

    walk(dir, 0, '');
    if (overflow > 0) lines.add('... +$overflow more entries not shown');

    // Test→subject links: the pairs a coding decision needs in one cut.
    final links = <String>[];
    final testDir = Directory('${dir.path}/test');
    if (testDir.existsSync()) {
      for (final f in testDir.listSync().whereType<File>()) {
        final name = f.uri.pathSegments.last;
        if (name.endsWith('_test.dart')) {
          final subject = 'lib/${name.substring(0, name.length - '_test.dart'.length)}.dart';
          if (File('${dir.path}/$subject').existsSync()) {
            links.add('test/$name -> $subject');
          } else {
            links.add('test/$name -> MISSING $subject (the failing import)');
          }
        }
      }
    }
    if (links.isNotEmpty) {
      lines.add('links: ${links.join(", ")}');
    }
    return lines.join('\n');
  }
}
