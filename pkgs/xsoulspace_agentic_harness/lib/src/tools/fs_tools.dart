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

  /// Optional HOST write policy ([JailWriteGateway]) attached after
  /// construction (`root.writeGateway = gateway`). Null = writes apply
  /// immediately (zero behavior change). The gateway is a host-side policy:
  /// the MODEL surface is unchanged — the model never learns it exists
  /// (ADR 0015-clean; the model never writes code tokens through a new
  /// parameter).
  JailWriteGateway? writeGateway;

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

/// A file-system tool suite: `read`, `write`, `list_dir`, `grep`, `glob`,
/// `run`.
///
/// Real tools (they touch the disk), jailed under [root]. Each is built with a
/// structured [SchemaBundle]. The legacy anchor-patch / symbol-rename edit
/// paths are deleted (hard cut): editing happens through the model's own
/// `write` moves or (preferred) the meaning pipeline (`act_with_project` +
/// `intent_define`), never through AST surgery.
List<ToolDef> fsTools(FsToolsRoot root) => [
  readTool(root),
  writeTool(root),
  listDirTool(root),
  grepTool(root),
  globTool(root),
  runTool(root),
  gitStatusTool(root),
  gitDiffTool(root),
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
///
/// When the host attached a [JailWriteGateway] to [root], the mutation flows
/// through it (review/diff/approval is a HOST decision — the tool's schema
/// and ack shape stay model-stable).
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
    final gateway = root.writeGateway;
    if (gateway != null) return gateway.interceptWrite(path, content);
    // Create parent directories so nested paths (src/lib.dart) work in a
    // fresh workspace — the common case for a coding agent.
    await File(path).parent.create(recursive: true);
    await File(path).writeAsString(content);
    return 'wrote $path';
  },
);

/// One captured file mutation — a HOST-side record, never part of a model
/// projection.
class CapturedWrite {
  CapturedWrite({
    required this.relativePath,
    required this.absolutePath,
    required this.oldContent,
    required this.newContent,
  });

  /// Jail-relative path (stable, loggable).
  final String relativePath;
  final String absolutePath;

  /// Content BEFORE the write; null when the file is new.
  final String? oldContent;
  final String newContent;

  bool approved = false;
  bool applied = false;

  bool get isNewFile => oldContent == null;
}

/// The host write gate for the coding agent (P3, revised).
///
/// EVERY jail file mutation — model `write` moves AND host materializer
/// output — flows through here when the host attaches it. Two modes:
///
/// - [WriteGateMode.apply]: write immediately (default; zero behavior
///   change), recording each mutation for the audit log.
/// - [WriteGateMode.review]: render a unified diff, ask the [approver],
///   apply ONLY on approval. The approver is a host callable (CLI:
///   `--auto-approve` or an interactive y/n prompt; tests: scripted).
///   The model sees only a structured ack ('wrote …' / 'REJECTED …').
///
/// Law note: this is a HOST policy wrapping the write path. It does NOT add
/// a model-visible parameter; the model never writes new content kinds. The
/// durable fix for whole-file writes is P4's span-anchored meaning edits.
enum WriteGateMode { apply, review }

/// Stage N2 — per-file single-writer lock table shared by every gateway in
/// one squad. Real fs is shared mutable state OUTSIDE the ECS graph; two
/// actors editing one file is a race the flush coherence point does not
/// cover. The squad driver claims each task's file set for its actor; a
/// write to a file claimed by ANOTHER owner is rejected with a structured
/// ack (the model adjusts or the driver reassigns).
class FileLockTable {
  final _locks = <String, Object>{};

  /// Claims [rel] for [owner]. Returns false when another owner holds it.
  bool claim(String rel, Object owner) {
    final current = _locks[rel];
    if (current != null) return current == owner;
    _locks[rel] = owner;
    return true;
  }

  void release(String rel, Object owner) {
    if (_locks[rel] == owner) _locks.remove(rel);
  }

  Object? ownerOf(String rel) => _locks[rel];
}

class JailWriteGateway {
  JailWriteGateway(
    this.root, {
    this.mode = WriteGateMode.apply,
    this._approver,
    this.locks,
    this.owner,
  });

  final FsToolsRoot root;
  final WriteGateMode mode;
  final Future<bool> Function(CapturedWrite write)? _approver;

  /// Stage N2 single-writer: null (default) = legacy single-agent behavior
  /// (no locking). When set, writes to files claimed by another [owner] are
  /// rejected with a structured ack before ANY diff/approval happens.
  final FileLockTable? locks;
  final Object? owner;

  final List<CapturedWrite> captured = [];

  String _rel(String absolutePath) {
    final prefix = root.rootPath.endsWith('/')
        ? root.rootPath
        : '${root.rootPath}/';
    return absolutePath.startsWith(prefix)
        ? absolutePath.substring(prefix.length)
        : absolutePath;
  }

  /// Intercepts a `write` tool move. Returns the tool ack (model-stable).
  Future<String> interceptWrite(String absolutePath, String content) async {
    final rel = _rel(absolutePath);
    // Stage N2 single-writer: reject cross-owner writes BEFORE the gate —
    // the model sees a structured ack and can adjust (or the driver
    // reassigns the task). The write never lands.
    final table = locks;
    if (table != null && owner != null) {
      final holder = table.ownerOf(rel);
      if (holder != null && holder != owner) {
        return 'REJECTED $rel: single-writer violation — the file is '
            'currently owned by another actor. Do not modify it; report '
            'the conflict and finish.';
      }
    }
    final old = File(absolutePath).existsSync()
        ? File(absolutePath).readAsStringSync()
        : null;
    final write = CapturedWrite(
      relativePath: rel,
      absolutePath: absolutePath,
      oldContent: old,
      newContent: content,
    );
    if (mode == WriteGateMode.apply) {
      write.approved = true;
      _apply(write);
      return 'wrote $rel';
    }
    final approve = _approver ?? _defaultInteractiveApprover;
    write.approved = await approve(write);
    if (!write.approved) {
      captured.add(write);
      return 'REJECTED $rel by host write policy — the change was NOT '
          'applied. Adjust the change or continue without it.';
    }
    _apply(write);
    return 'wrote $rel';
  }

  /// Intercepts a HOST materializer write (host code, not a model move).
  /// Same gate; host writes default to approval via [approver] too.
  String interceptHostWrite(String absolutePath, String content) {
    final rel = _rel(absolutePath);
    final old = File(absolutePath).existsSync()
        ? File(absolutePath).readAsStringSync()
        : null;
    final write = CapturedWrite(
      relativePath: rel,
      absolutePath: absolutePath,
      oldContent: old,
      newContent: content,
    )..approved = true; // host-authored output is trusted
    _apply(write);
    return 'wrote $rel';
  }

  void _apply(CapturedWrite write) {
    File(write.absolutePath).parent.createSync(recursive: true);
    File(write.absolutePath).writeAsStringSync(write.newContent);
    write.applied = true;
    captured.add(write);
  }

  Future<bool> _defaultInteractiveApprover(CapturedWrite write) async {
    stdout
      ..writeln('[write-gate] ${write.relativePath}')
      ..write(unifiedDiff(write));
    stdout.write('Apply this write? [y/N] ');
    final line = stdin.readLineSync();
    return line != null && (line.trim().toLowerCase() == 'y');
  }

  /// All captured writes as unified diffs with per-write verdicts (for the
  /// run log / CLI audit).
  String renderDiffs() => [
    for (final w in captured)
      '[${w.applied ? "APPLIED" : "REJECTED"}] ${w.relativePath}\n'
          '${unifiedDiff(w)}',
  ].join('\n');

  int get appliedCount => captured.where((w) => w.applied).length;
  int get rejectedCount => captured.where((w) => !w.applied).length;

  /// Unified diff for one write. New files diff against /dev/null. A small
  /// LCS over lines keeps the diff minimal without external deps.
  static String unifiedDiff(CapturedWrite w) {
    final oldLines = (w.oldContent ?? '').split('\n');
    if (w.isNewFile) oldLines.clear();
    final newLines = w.newContent.split('\n');
    final hunks = _lineDiff(oldLines, newLines);
    final from = w.isNewFile ? '/dev/null' : 'a/${w.relativePath}';
    final to = 'b/${w.relativePath}';
    final buf = StringBuffer('--- $from\n+++ $to\n');
    if (hunks.isEmpty) {
      buf.writeln('@@ -0,0 +1,0 @@ (no changes)');
      return buf.toString();
    }
    for (final hunk in hunks) {
      buf
        ..writeln(
          '@@ -${hunk.oldStart},${hunk.oldCount} '
          '+${hunk.newStart},${hunk.newCount} @@',
        )
        ..write(hunk.body);
    }
    return buf.toString();
  }
}

class _DiffHunk {
  _DiffHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.body,
  });
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final String body;
}

/// LCS-based line diff producing ONE hunk with context lines (small files —
/// the jail's whole purpose). Good enough for a review gate; not a general
/// diff engine.
List<_DiffHunk> _lineDiff(List<String> a, List<String> b) {
  final n = a.length;
  final m = b.length;
  // LCS table (O(n*m) — fine for source files in a jail).
  final lcs = List.generate(
    n + 1,
    (_) => List.filled(m + 1, 0),
  );
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : _max(lcs[i + 1][j], lcs[i][j + 1]);
    }
  }
  final body = StringBuffer();
  var oldCount = 0;
  var newCount = 0;
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      body.writeln(' ${a[i]}');
      oldCount++;
      newCount++;
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      body.writeln('-${a[i]}');
      oldCount++;
      i++;
    } else {
      body.writeln('+${b[j]}');
      newCount++;
      j++;
    }
  }
  while (i < n) {
    body.writeln('-${a[i]}');
    oldCount++;
    i++;
  }
  while (j < m) {
    body.writeln('+${b[j]}');
    newCount++;
    j++;
  }
  return [
    _DiffHunk(
      oldStart: n == 0 ? 0 : 1,
      oldCount: oldCount,
      newStart: m == 0 ? 0 : 1,
      newCount: newCount,
      body: body.toString(),
    ),
  ];
}

int _max(int x, int y) => x > y ? x : y;

/// Jailed read-only `git status --porcelain` — repo-state PROJECTION for the
/// coding agent (same pattern as grep/glob: read-only, structured, clipped).
/// A coding agent on a real repo needs git visibility; without it it re-reads
/// files to guess state. Rejects when the jail root has no .git.
ToolDef gitStatusTool(FsToolsRoot root) => ToolDef.encode(
      name: const ToolName('git_status'),
      description:
          'Read-only git status of the workspace (git status --porcelain '
          'with the branch line). Returns structured entries '
          '(index/worktree status + path). Fails with code not_a_git_repo '
          'outside a repository. Arguments: none.',
      argsSchema: SchemaBundle(
        root: FM.object('git_status', properties: () => []),
      ),
      execute: (args) async {
        if (!_isGitRepo(root.rootPath)) {
          return const {
            'ok': false,
            'code': 'not_a_git_repo',
            'hint': 'this workspace has no .git',
          };
        }
        final result = await Process.run(
          'git',
          ['status', '--porcelain=v1', '-b'],
          workingDirectory: root.rootPath,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        if (result.exitCode != 0) {
          return {
            'ok': false,
            'code': 'git_error',
            'stderr': _clip(result.stderr.toString(), 200),
          };
        }
        final lines = result.stdout
            .toString()
            .split('\n')
            .map((l) => l.trimRight())
            .where((l) => l.isNotEmpty)
            .take(100)
            .toList();
        return {
          'ok': true,
          'branch': lines.isEmpty ? '' : lines.first,
          'entries': lines.skip(1).toList(),
        };
      },
    );

/// Jailed read-only `git diff` — bounded change visibility for the coding
/// agent. Never mutates anything; output is clipped.
ToolDef gitDiffTool(FsToolsRoot root) => ToolDef.encode(
      name: const ToolName('git_diff'),
      description:
          'Read-only unified diff of uncommitted changes in the workspace '
          '(git diff; with staged=true also/--cached instead). Output is '
          'clipped. Fails with code not_a_git_repo outside a repository. '
          'Arguments: staged (optional bool), path (optional subdir/file '
          'limit, relative).',
      argsSchema: SchemaBundle(
        root: FM.object(
          'git_diff',
          properties: () => [
            FM.prop('staged', FM.string()),
            FM.prop('path', FM.string()),
          ],
        ),
      ),
      execute: (args) async {
        final params = _asMap(args);
        if (!_isGitRepo(root.rootPath)) {
          return const {
            'ok': false,
            'code': 'not_a_git_repo',
            'hint': 'this workspace has no .git',
          };
        }
        final staged = switch (_str(params, 'staged')?.toLowerCase()) {
          'true' || '1' || 'yes' => true,
          _ => false,
        };
        final cmd = ['diff', if (staged) '--cached'];
        final pathArg = _str(params, 'path');
        if (pathArg != null && pathArg.isNotEmpty) {
          cmd.add('--');
          cmd.add(root.resolve(pathArg));
        }
        final result = await Process.run(
          'git',
          cmd,
          workingDirectory: root.rootPath,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        if (result.exitCode != 0) {
          return {
            'ok': false,
            'code': 'git_error',
            'stderr': _clip(result.stderr.toString(), 200),
          };
        }
        return {
          'ok': true,
          'diff': _clip(result.stdout.toString(), 4000),
        };
      },
    );

bool _isGitRepo(String rootPath) {
  final dotGit = FileSystemEntity.typeSync('$rootPath/.git');
  return dotGit == FileSystemEntityType.directory ||
      dotGit == FileSystemEntityType.file; // worktrees keep a .git FILE
}

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
/// Execute a command inside the jail (cwd = jail root or a resolved subdir).
///
/// The loop's missing capability (Gate A): a coding agent can run its own
/// output (e.g. `dart run main.dart`), capture stdout/stderr/exit code, and
/// thus observe whether what it built actually works. Time-bounded and
/// jailed, so a running program can never hang the loop or escape the root.
ToolDef runTool(FsToolsRoot root) => ToolDef.encode(
      name: const ToolName('run'),
      description:
          'Run a command or script inside the workspace and capture its '
          'output and exit code. Command is an argv list (e.g. ["dart", '
          '"run", "main.dart"]). Optional cwd (relative subdir, default "."), '
          'optional timeout_ms (default 30000, max 120000). Does NOT hang: '
          'timeouts return a structured failure. Use to compile/run/test the '
          'code you are building.',
      argsSchema: SchemaBundle(
        root: FM.object(
          'run',
          properties: () => [
            FM.prop('command', FM.array(FM.string())),
            FM.prop('cwd', FM.string()),
            FM.prop('timeout_ms', FM.integer()),
          ],
        ),
      ),
      execute: (args) async {
        final params = _asMap(args);
        final cmdRaw = params['command'];
        final cmd = switch (cmdRaw) {
          final List l => l.map((e) => e.toString()).toList(),
          final String s when s.isNotEmpty => [s],
          _ => const <String>[],
        };
        if (cmd.isEmpty) {
          return const {'ok': false, 'code': 'bad_args', 'hint': 'command is required'};
        }
        final cwd = _str(params, 'cwd');
        final resolvedCwd = (cwd == null || cwd.isEmpty) ? root.rootPath : root.resolve(cwd);
        final timeoutMs = (_num(params, 'timeout_ms') ?? 30000).clamp(1, 120000).toInt();
        try {
          final result = await Process.run(
            cmd.first,
            cmd.sublist(1),
            workingDirectory: resolvedCwd,
            stdoutEncoding: utf8,
            stderrEncoding: utf8,
          ).timeout(
            Duration(milliseconds: timeoutMs),
            onTimeout: () => ProcessResult(0, -1, '', 'timeout'),
          );
          return {
            'ok': result.exitCode == 0,
            'exit_code': result.exitCode,
            'stdout': _clip(result.stdout.toString()),
            'stderr': _clip(result.stderr.toString()),
            if (result.exitCode == -1) 'code': 'timeout',
          };
        } on ProcessException catch (e) {
          return {'ok': false, 'code': 'spawn_error', 'message': e.message};
        }
      },
    );

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
