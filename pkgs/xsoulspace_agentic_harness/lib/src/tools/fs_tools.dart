// ignore_for_file: lines_longer_than_80_chars

/// Reusable, real tool definitions for the harness.
///
/// These are actual tool bodies (read/write/list files, clock, search) built
/// with structured [SchemaBundle] schemas — not string blobs — so they can be
/// shared across the scenario stress runner, the example host, and tests. If
/// you need a tool in more than one place, define it here and reuse it.
///
/// ## Platform
///
/// These tools use `dart:io` and only work on VM hosts (CLI, server,
/// desktop). They are NOT available on web or in restricted sandboxes.
///
/// ## Path jail
///
/// All paths are resolved against [FsToolsRoot.rootPath] and rejected if they
/// escape it. Always construct the suite with an explicit root — never expose
/// unrestricted filesystem access to a model.
library;

import 'dart:convert';
import 'dart:io';

import 'package:from_json_to_json/from_json_to_json.dart';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import '../tooling/tree_patch.dart';

/// The path jail for [fsTools]: every tool path is resolved against this root
/// and must stay inside it.
class FsToolsRoot {
  FsToolsRoot(this.rootPath) {
    final dir = Directory(rootPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    rootPath = dir.resolveSymbolicLinksSync();
  }

  /// Absolute path of the jail root. Created if missing; symlinks resolved.
  String rootPath;

  /// Resolve [path] (absolute or relative) inside the jail.
  ///
  /// Throws [ArgumentError] when the resolved path escapes the root. The
  /// error teaches the expected form: small models frequently hallucinate
  /// absolute workspace locations (`/tmp/config.dart`) — the rejection must
  /// say what to do instead, not just that it failed.
  String resolve(String path) {
    var raw = path.trim();
    // Strip one level of wrapping quotes some models add around arguments.
    if (raw.length >= 2 &&
        ((raw.startsWith('"') && raw.endsWith('"')) ||
            (raw.startsWith("'") && raw.endsWith("'")))) {
      raw = raw.substring(1, raw.length - 1);
      raw = raw.trim();
    }
    final candidate = _canonicalize(
      raw.startsWith('/') ? raw : '$rootPath/$raw',
    );
    if (candidate.startsWith(rootPath)) {
      return candidate;
    }
    // Symlink-tolerant containment: on macOS, /var ↔ /private/var differ
    // lexically but are the same directory. Accept an absolute path whose
    // REAL location is inside the root; reject everything else with a
    // bounce-explanation error naming the expected relative form.
    final real = _existingRealPath(candidate);
    if (real != null && real.startsWith(rootPath)) {
      return real;
    }
    throw ArgumentError(
      'Path escapes the allowed root: "$path". '
      'Use paths RELATIVE to the workspace root — for example "config.dart" '
      'or "src/lib.dart" — never absolute filesystem paths like "/tmp/..." or '
      '"/Users/...". Call list_dir with path "." to see the workspace.',
    );
  }

  /// Real path of the nearest existing ancestor of [path] (symlinks
  /// resolved), with the non-existent remainder rejoined lexically. Null
  /// when nothing up to the filesystem root exists (never in practice).
  static String? _existingRealPath(String path) {
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    for (var take = parts.length; take >= 1; take--) {
      try {
        final realAncestor = Directory(
          '/${parts.take(take).join('/')}',
        ).resolveSymbolicLinksSync();
        final rest = parts.skip(take).toList();
        return _canonicalize(
          rest.isEmpty ? realAncestor : '$realAncestor/${rest.join('/')}',
        );
      } on FileSystemException {
        continue;
      }
    }
    return null;
  }

  /// Lexical canonicalization (resolves `.`/`..`) without touching disk.
  static String _canonicalize(String path) {
    final parts = <String>[];
    for (final part in path.split('/')) {
      switch (part) {
        case '' || '.':
          continue;
        case '..':
          if (parts.isNotEmpty && parts.last != '..') {
            parts.removeLast();
          } else {
            parts.add('..');
          }
        default:
          parts.add(part);
      }
    }
    return '/${parts.join('/')}';
  }
}

/// A file-system tool suite: `read`, `write`, `list_dir`.
///
/// Real tools (they touch the disk), jailed under [root]. Each is built with a
/// structured [SchemaBundle].
List<ToolDef> fsTools(FsToolsRoot root) => [
  readTool(root),
  writeTool(root),
  listDirTool(root),
  grepTool(root),
  globTool(root),
  patchSymbolTool(root.rootPath),
  renameSymbolTool(root.rootPath),
];

/// Read a file's contents.
ToolDef readTool(FsToolsRoot root) => ToolDef(
  name: const ToolName('read'),
  description: 'Read a file',
  argsSchema: SchemaBundle(
    root: FM.object('read', properties: () => [FM.prop('path', FM.string())]),
  ),
  execute: (args) {
    final params = jsonDecodeMapAs(args);
    final path = root.resolve(jsonDecodeString(params['path']));
    return File(path).readAsString();
  },
);

/// Write content to a file.
ToolDef writeTool(FsToolsRoot root) => ToolDef(
  name: const ToolName('write'),
  description: 'Write a file',
  argsSchema: SchemaBundle(
    root: FM.object(
      'write',
      properties: () => [
        FM.prop('path', FM.string()),
        FM.prop('content', FM.string()),
      ],
    ),
  ),
  execute: (args) async {
    final params = jsonDecodeMapAs(args);
    final path = root.resolve(jsonDecodeString(params['path']));
    final content = jsonDecodeString(params['content']);
    // Create parent directories so nested paths (src/lib.dart) work in a
    // fresh workspace — the common case for a coding agent.
    await File(path).parent.create(recursive: true);
    await File(path).writeAsString(content);
    return 'wrote $path';
  },
);

/// List the entries of a directory.
ToolDef listDirTool(FsToolsRoot root) => ToolDef(
  name: const ToolName('list_dir'),
  description: 'List a directory',
  argsSchema: SchemaBundle(
    root: FM.object(
      'list_dir',
      properties: () => [FM.prop('path', FM.string())],
    ),
  ),
  execute: (args) async {
    final params = jsonDecodeMapAs(args);
    var raw = jsonDecodeString(params['path']).trim();
    if (raw.isEmpty) raw = '.';
    // Small models habitually append '/' to file paths ("config.dart/") and
    // get a confusing 'Not a directory' failure. Point at a file → list its
    // parent instead, so the model can recover without burning a round.
    var target = root.resolve(raw);
    if (!Directory(target).existsSync() && File(target).existsSync()) {
      target = File(target).parent.path;
    }
    final prefix = root.rootPath.endsWith('/')
        ? root.rootPath
        : '${root.rootPath}/';
    final entries = Directory(target).listSync().map((e) {
      // Jail-RELATIVE names: feeding absolute paths back into read/write is
      // how models end up constructing /tmp/... locations from priors.
      final rel = e.path.startsWith(prefix)
          ? e.path.substring(prefix.length)
          : e.path;
      return e is Directory ? '$rel/' : rel;
    }).toList()..sort();
    return jsonEncode(entries);
  },
);


/// Read-only regex search over the jail (discovery cut of ADR 0014 §2).
///
/// Deterministic and token-bounded: a find costs one call instead of a
/// recursive `list_dir`+`read` walk (the measured P2 bottleneck). Results are
/// capped and the scan budget-limited so a huge workspace cannot eat a tiny
/// model's budget.
ToolDef grepTool(FsToolsRoot root) => ToolDef.encode(
      name: const ToolName('grep'),
      description:
          'Search file contents under the workspace for a regular '
          'expression. Returns matching relative paths with a match count '
          'and one line snippet each. Cap: max_results (default 50). '
          'Arguments: pattern (regex, required), path (subdir or file to '
          'limit, default "."), max_results (optional), ignore_case '
          '(optional bool).',
      argsSchema: SchemaBundle(
        root: FM.object(
          'grep',
          properties: () => [
            FM.prop('pattern', FM.string()),
            FM.prop('path', FM.string()),
            FM.prop('max_results', FM.integer()),
          ],
        ),
      ),
      execute: (args) async {
        final params = _asMap(args);
        final pattern = _str(params, 'pattern');
        if (pattern == null || pattern.isEmpty) {
          return {'ok': false, 'code': 'bad_args', 'hint': 'required "pattern"'};
        }
        final maxResults = (_num(params, 'max_results') ?? 50).clamp(1, 200);
        final ignoreCase = params['ignore_case'] == true;
        final RegExp re;
        try {
          re = RegExp(pattern, caseSensitive: !ignoreCase);
        } on FormatException {
          return {'ok': false, 'code': 'bad_regex', 'pattern': pattern};
        }
        var raw = _str(params, 'path');
        if (raw == null || raw.isEmpty) raw = '.';
        final startDir = root.resolve(raw);
        final prefix = root.rootPath.endsWith('/')
            ? root.rootPath
            : '${root.rootPath}/';
        const maxScanned = 4000;
        var scanned = 0;
        final results = <Map<String, Object>>[];
        bool exhausted() =>
            results.length >= maxResults || scanned >= maxScanned;

        void scanFile(String path) {
          scanned++;
          try {
            final lines = File(path).readAsLinesSync();
            var count = 0;
            String? snippet;
            for (final ln in lines) {
              if (re.hasMatch(ln)) {
                count++;
                snippet ??= _clip(ln, 120);
              }
            }
            if (count > 0) {
              final rel = path.startsWith(prefix)
                  ? path.substring(prefix.length)
                  : path;
              results.add({
                'path': rel,
                'matches': count,
                'snippet': snippet ?? '',
              });
            }
          } on FileSystemException {
            // Unreadable file — skip rather than abort the search.
          }
        }

        void walk(String dir) {
          if (exhausted()) return;
          final entries = Directory(dir).listSync()
            ..sort((a, b) => a.path.compareTo(b.path));
          for (final e in entries) {
            if (exhausted()) return;
            if (e is Directory) {
              walk(e.path);
            } else if (e is File) {
              scanFile(e.path);
            }
          }
        }

        if (File(startDir).existsSync()) {
          scanFile(startDir);
        } else {
          walk(startDir);
        }
        return {
          'ok': true,
          'total': results.length,
          'results': results,
          if (scanned >= maxScanned)
            'hint': 'scan budget reached; narrow path or pattern',
        };
      },
    );

/// Glob-style file discovery — the cheap find sibling of [grepTool].
///
/// Supports `*` (any chars within one path segment), `?` (single char), and
/// `**` (any number of directories). Deterministic, read-only, jail-bounded.
ToolDef globTool(FsToolsRoot root) => ToolDef.encode(
      name: const ToolName('glob'),
      description:
          'Return workspace files whose path matches a glob pattern. '
          'Supports * (within a segment), ? (single char), ** (any '
          'directories). Examples: "*.dart", "tests/**/*_test.dart". Returns '
          'sorted relative paths, capped at max_results. Arguments: pattern '
          '(required), path (subdir, default "."), max_results (optional).',
      argsSchema: SchemaBundle(
        root: FM.object(
          'glob',
          properties: () => [
            FM.prop('pattern', FM.string()),
            FM.prop('path', FM.string()),
            FM.prop('max_results', FM.integer()),
          ],
        ),
      ),
      execute: (args) async {
        final params = _asMap(args);
        final pattern = _str(params, 'pattern');
        if (pattern == null || pattern.isEmpty) {
          return {'ok': false, 'code': 'bad_args', 'hint': 'required "pattern"'};
        }
        final maxResults = (_num(params, 'max_results') ?? 100).clamp(1, 500);
        var raw = _str(params, 'path');
        if (raw == null || raw.isEmpty) raw = '.';
        final startDir = root.resolve(raw);
        final prefix = root.rootPath.endsWith('/')
            ? root.rootPath
            : '${root.rootPath}/';
        final segs = pattern.split('/').where((s) => s.isNotEmpty).toList();
        final hits = <String>[];

        void addHit(File f) {
          if (hits.length >= maxResults) return;
          final p = f.path.startsWith(prefix)
              ? f.path.substring(prefix.length)
              : f.path;
          if (!hits.contains(p)) hits.add(p);
        }

        void walk(String path, List<String> rest) {
          if (hits.length >= maxResults) return;
          final entries = Directory(path).listSync()
            ..sort((a, b) => a.path.compareTo(b.path));
          for (final e in entries) {
            if (hits.length >= maxResults) return;
            final name = e.path.split('/').last;
            if (rest.isEmpty) return;
            final head = rest.first;
            if (head == '**') {
              // '**' consumes zero-or-more directories: keep expanding into
              // dirs, and also try the tail pattern against this entry.
              if (e is Directory) walk(e.path, rest);
              final tail = rest.sublist(1);
              if (tail.isEmpty) {
                if (e is File) addHit(e);
              } else if (_segMatches(tail.first, name)) {
                if (e is File && tail.length == 1) addHit(e);
                if (e is Directory) walk(e.path, tail);
              }
            } else if (_segMatches(head, name)) {
              final tail = rest.sublist(1);
              if (tail.isEmpty) {
                if (e is File) addHit(e);
              } else if (e is Directory) {
                walk(e.path, tail);
              }
            }
          }
        }

        if (Directory(startDir).existsSync()) walk(startDir, segs);
        hits.sort();
        return {'ok': true, 'total': hits.length, 'paths': hits};
      },
    );

/// Glob-segment matcher: `*` / `?` within a segment against [name].
bool _segMatches(String pat, String name) {
  final b = StringBuffer();
  for (final ch in pat.split('')) {
    switch (ch) {
      case '*':
        b.write('[^/]*');
      case '?':
        b.write('[^/]');
      default:
        b.write(RegExp.escape(ch));
    }
  }
  return RegExp('^$b\$').hasMatch(name);
}

String _clip(String s, [int max = 140]) =>
    s.length <= max ? s : '${s.substring(0, max)}…';

Map<String, Object?> _asMap(Object? args) => args is Map
    ? args.map((k, v) => MapEntry(k.toString(), v))
    : const {};

String? _str(Map<String, Object?> map, String key) {
  final v = map[key];
  return v is String ? v : null;
}

num? _num(Map<String, Object?> map, String key) {
  final v = map[key];
  return v is num ? v : (v is String ? num.tryParse(v) : null);
}
