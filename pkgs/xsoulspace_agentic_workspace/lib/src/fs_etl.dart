// ignore_for_file: lines_longer_than_80_chars

/// The fs tier of the map-graph (ADR 0024 §1): ONE mechanical scan pass
/// indexes a `dir` node per directory and a `file` node per file — for
/// EVERY file class, not just Dart. Zero model tokens; the same mtime
/// refresh tick as the dart scan (R7c). A file class with a registered
/// materializer contributes TYPED sub-nodes on top (dart → symbols today;
/// md/yaml/json per ADR 0024 §2 as they land) — the dir/file tier itself
/// is class-agnostic.
///
/// Law notes (ADR 0023/0024):
/// - The tree is a RE-DERIVABLE projection — never snapshotted.
/// - NO file text lives in the tree; nodes carry structural props only
///   (path, class, bytes, mtime). `zoom` cuts are the only read.
/// - NO generic read/write/glob/grep returns to the meaning profile —
///   zoom over the map-graph IS the search.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show FsToolsRoot, JailWriteGateway, WriteGateMode;
import 'package:xsoulspace_agentic_harness/src/tools/meaning_query_tools.dart'
    show MeaningSpanReader;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show FM, SchemaBundle, ToolDef, ToolName;

/// Directories never indexed (VCS internals / build outputs / packages).
const fsSkipDirs = <String>[
  '.git',
  '.dart_tool',
  'build',
  'node_modules',
  '.symlinks',
  '.idea',
  '.gradle',
];

/// Files never indexed (OS noise).
const fsSkipFiles = <String>['.DS_Store'];

/// The file class of [rel] — the materializer-registry key (ADR 0024 §2).
/// `dart` is materialized today; md/yaml/json specs land per PLAN §NOW;
/// everything else is `other` (visible node, review-mode write only).
String fileClassOf(String relPath) {
  final lower = relPath.toLowerCase();
  if (lower.endsWith('.dart')) return 'dart';
  if (lower.endsWith('.md') || lower.endsWith('.mdx')) return 'md';
  if (lower.endsWith('.yaml') || lower.endsWith('.yml')) return 'yaml';
  if (lower.endsWith('.json')) return 'json';
  return 'other';
}

/// One workspace walk: every indexed directory and file (workspace-relative,
/// '/' separators). Dart files are listed in [dartFiles] so the code ETL
/// reuses the SAME pass — one scan, not two.
class FsScan {
  FsScan({required this.dirs, required this.files});

  /// Directory rel paths, root FIRST ('.'), parents before children.
  final List<String> dirs;

  final List<FsFileScan> files;

  /// The dart subset (the code ETL's input from this same walk).
  Iterable<FsFileScan> get dartFiles =>
      files.where((f) => f.fileClass == 'dart');
}

/// One indexed file: structural facts only — never content.
class FsFileScan {
  FsFileScan({
    required this.rel,
    required this.dir,
    required this.fileClass,
    required this.ext,
    required this.bytes,
    required this.modified,
  });

  final String rel; // workspace-relative, '/' separators
  final String dir; // parent directory rel ('.' = root)
  final String fileClass; // dart | md | yaml | json | other
  final String ext;
  final int bytes;
  final DateTime modified;

  /// The stable tree id (same `f_` space the code ETL uses for dart files).
  String get nodeId => 'f_${rel.replaceAll('/', '_')}';
}

String _dirId(String dir) => dir == '.' ? 'dir_root' : 'dir_${dir.replaceAll('/', '_')}';

/// Walks [workspace] once, skipping [fsSkipDirs]. Deterministic order:
/// directories sorted, files sorted (stable ids + stable edge order).
FsScan scanWorkspaceFs(Directory workspace) {
  final root = workspace.path;
  final dirs = <String>['.'];
  final files = <FsFileScan>[];
  final stack = <Directory>[workspace];
  while (stack.isNotEmpty) {
    final d = stack.removeLast();
    final entries = d.listSync()..sort((a, b) => a.path.compareTo(b.path));
    for (final e in entries) {
      final name = e.path.split('/').last;
      if (e is Directory) {
        if (fsSkipDirs.contains(name) || name.startsWith('.')) continue;
        final rel = _relOf(e.path, root);
        dirs.add(rel);
        stack.add(e);
      } else if (e is File) {
        if (fsSkipFiles.contains(name) || name.startsWith('.')) continue;
        // Do not follow symlinked files out of the workspace jail.
        if (FileSystemEntity.typeSync(e.path) == FileSystemEntityType.link) {
          continue;
        }
        final rel = _relOf(e.path, root);
        final stat = e.statSync();
        files.add(
          FsFileScan(
            rel: rel,
            dir: _parentOf(rel),
            fileClass: fileClassOf(rel),
            ext: rel.contains('.') ? rel.split('.').last.toLowerCase() : '',
            bytes: stat.size,
            modified: stat.modified,
          ),
        );
      }
    }
  }
  dirs.sort();
  files.sort((a, b) => a.rel.compareTo(b.rel));
  return FsScan(dirs: dirs, files: files);
}

String _relOf(String abs, String root) =>
    abs.startsWith('$root/') ? abs.substring(root.length + 1) : abs;

String _parentOf(String rel) {
  final slash = rel.lastIndexOf('/');
  return slash < 0 ? '.' : rel.substring(0, slash);
}

/// Indexes the fs tier into [world] (idempotent per node: an existing node —
/// e.g. a dart file node the code ETL already added — only gets its fs props
/// refreshed). Adds `dir --contains--> dir/file` edges over the SAME
/// relation the code tier uses, so one zoom/impact verb family serves every
/// class (ADR 0024 §1).
///
/// The MAP HALF (ADR 0024 §2, map-before-emitter): every file class with a
/// known map format gets its typed sub-nodes in the SAME pass, mechanical,
/// zero model tokens — md → `section` nodes (heading spans, fences inert),
/// yaml/json → `keypath` nodes. This is what makes ANY document readable as
/// meaning at any file size: the model zooms the outline, then reads ONE
/// anchor's span as a budgeted cut. Text never enters context outside a
/// meaning anchor. A class with no map format has node facts only — the
/// named bounce (`no_map_for_class`) is the intent-first signal to grow a
/// materializer, never a size refusal.
({int dirs, int files, int added}) buildFsTier(
  World world,
  Directory workspace, {
  FsScan? scan,
}) {
  final fs = scan ?? scanWorkspaceFs(workspace);
  var added = 0;
  for (final dir in fs.dirs) {
    final id = _dirId(dir);
    if (hasMeaningNode(world, id)) continue;
    final label = dir == '.' ? '/' : dir;
    addMeaningNode(
      world,
      kind: 'dir',
      label: label,
      id: id,
      props: {'path': dir},
    );
    added++;
  }
  for (final f in fs.files) {
    final props = <String, dynamic>{
      'path': f.rel,
      'class': f.fileClass,
      'ext': f.ext,
      'bytes': f.bytes,
      'mtime': f.modified.toIso8601String(),
      if (_mapClasses.contains(f.fileClass)) 'has_map': true,
    };
    if (hasMeaningNode(world, f.nodeId)) {
      // Existing node (dart file from the code ETL): refresh fs props only
      // when they changed — the refresh tick runs before EVERY prompt, so
      // unchanged files cost zero writes (and zero map rebuilds).
      final index = world.getResource<MeaningIndex>();
      final entity = index.entityOf(f.nodeId);
      var changed = false;
      if (entity != null) {
        final existing = meaningComponentOf<MeaningProps>(world, entity)?.props;
        changed = existing != null &&
            (existing['bytes'] != f.bytes ||
                existing['mtime'] != props['mtime'] ||
                existing['class'] != f.fileClass);
        if (changed) {
          // The file changed → its map is stale: drop sub-nodes, rebuild.
          _dropMapNodes(world, f.nodeId);
          for (final entry in props.entries) {
            setMeaningProp(world, id: f.nodeId, key: entry.key, value: entry.value);
          }
        }
      }
      _ensureContainsEdge(world, _dirId(f.dir), f.nodeId);
      if (changed) _buildMapHalf(world, workspace, f);
      continue;
    }
    addMeaningNode(world, kind: 'file', label: f.rel, id: f.nodeId, props: props);
    added++;
    _ensureContainsEdge(world, _dirId(f.dir), f.nodeId);
    _buildMapHalf(world, workspace, f);
  }
  // dir -> child dir edges (files were linked above).
  for (final dir in fs.dirs) {
    if (dir == '.') continue;
    _ensureContainsEdge(world, _dirId(_parentOf(dir)), _dirId(dir));
  }
  return (dirs: fs.dirs.length, files: fs.files.length, added: added);
}

/// The file classes with a mechanical map format today (ADR 0024 §2).
const _mapClasses = <String>{'md', 'yaml', 'json'};

/// Sub-node id prefixes per file node — the map is OWNED by its file node.
const _mapPrefixes = <String>['sec_', 'key_'];

/// Drops every map sub-node of one file (stale on change, gone on delete).
void _dropMapNodes(World world, String fileNodeId) {
  final stale = [
    for (final id in world.getResource<MeaningIndex>().byId.keys)
      if (_mapPrefixes.any((p) => id.startsWith(p)) && id.contains(fileNodeId)) id,
  ];
  for (final id in stale) {
    dropMeaningNode(world, id);
  }
}

/// Builds one mapped file's sub-nodes (mechanical, zero model tokens).
void _buildMapHalf(World world, Directory workspace, FsFileScan f) {
  if (!_mapClasses.contains(f.fileClass)) return;
  if (f.bytes > maxMapFileBytes) {
    // Honest green-screen fact — the map omits this file, named.
    setMeaningProp(world, id: f.nodeId, key: 'map_skipped', value: 'too_large');
    return;
  }
  final content = File('${workspace.path}/${f.rel}').readAsStringSync();
  final built = switch (f.fileClass) {
    'md' => _indexMdSections(world, f, content),
    'yaml' || 'json' => _indexKeypaths(world, f, content, isJson: f.fileClass == 'json'),
    _ => 0,
  };
  if (built >= maxMapNodesPerFile) {
    setMeaningProp(world, id: f.nodeId, key: 'map_truncated', value: built);
  }
  setMeaningProp(world, id: f.nodeId, key: 'map_nodes', value: built);
}

/// Map caps (green-screen facts when hit — never a silent omission).
const maxMapNodesPerFile = 512;
const maxMapFileBytes = 2 * 1024 * 1024;

/// Ensures a `contains` edge exists without duplicating the triple.
bool _ensureContainsEdge(World world, String fromId, String toId) {
  final index = world.getResource<MeaningIndex>();
  if (index.triples.contains((fromId, 'contains', toId))) return false;
  return linkMeaning(world, from: fromId, relation: 'contains', to: toId);
}

/// The refresh tick for the fs tier (same mechanical mtime tick as dart):
/// adds new nodes, refreshes changed props, DROPS file nodes whose file no
/// longer exists (the tree must not lie about the workspace). Directory
/// deletions are left to the next full rescan and recorded honestly.
({int added, int dropped, int refreshed, int files, int dirs}) refreshFsTier(
  World world,
  Directory workspace, {
  DateTime? cutoff,
  FsScan? scan,
}) {
  final fs = scan ?? scanWorkspaceFs(workspace);
  final index = world.getResource<MeaningIndex>();
  final onDisk = {for (final f in fs.files) f.nodeId: f};
  var added = 0;
  var dropped = 0;
  var refreshed = 0;
  // ADR 0027 dogfood fix: with a cutoff, the node rebuild processes ONLY
  // files modified since the last tick — the old path re-built props and
  // re-looked-up EVERY node per prompt (measured: ~5–8 s no-op ticks on
  // the monorepo). Adds (mtime > cutoff) and the stale drop above cover
  // the rest of the lifecycle.
  final changedScan = cutoff == null
      ? fs
      : FsScan(
          files: [
            for (final f in fs.files)
              if (f.modified.isAfter(cutoff)) f,
          ],
          dirs: fs.dirs,
        );
  // 1) files gone from disk → drop the node (entity + edges) and its map.
  final staleIds = [
    for (final id in index.byId.keys)
      if (id.startsWith('f_') && !onDisk.containsKey(id)) id,
  ];
  for (final id in staleIds) {
    _dropMapNodes(world, id);
    if (dropMeaningNode(world, id)) dropped++;
  }
  // 2) new/changed files → add or refresh (buildFsTier is idempotent).
  final built = buildFsTier(world, workspace, scan: changedScan);
  added = built.added;
  for (final f in fs.files) {
    if (cutoff == null) continue;
    if (f.modified.isAfter(cutoff)) refreshed++;
  }
  return (
    added: added,
    dropped: dropped,
    refreshed: refreshed,
    files: fs.files.length,
    dirs: fs.dirs.length,
  );
}

/// The SPAN reader factory (ADR 0024, as amended — the only way text
/// enters model context): a meaning anchor (`section`/`key` node) declares
/// its source span; the reader serves EXACTLY that span, budget-clamped
/// (budget tokens × 4 chars) with the green-screen fact. ANY file size
/// works — the view is what's bounded, never the artifact. The reader is
/// jail-bounded through [FsToolsRoot.resolve]; bounces are NAMED data.
MeaningSpanReader meaningSpanReader(FsToolsRoot root) => (props, budgetTokens) {
      final path = props['path'];
      final start = (props['span_start'] as num?)?.toInt();
      final end = (props['span_end'] as num?)?.toInt();
      if (path is! String || start == null || end == null || end < start) {
        return <String, Object?>{
          'ok': false,
          'error': 'span_unreadable',
          'hint': 'the node does not declare a usable source span',
        };
      }
      final String abs;
      try {
        abs = root.resolve(path);
        // ignore: avoid_catching_errors
      } on ArgumentError catch (e) {
        return <String, Object?>{
          'ok': false,
          'error': 'path_escapes_workspace',
          'path': path,
          'message': '$e',
        };
      }
      final f = File(abs);
      if (!f.existsSync()) {
        return <String, Object?>{'ok': false, 'error': 'file_not_found', 'path': path};
      }
      final raf = f.openSync();
      try {
        final clampedEnd = min(end, f.lengthSync());
        final clampedStart = min(start, clampedEnd);
        raf.setPositionSync(clampedStart);
        final bytes = raf.readSync(clampedEnd - clampedStart);
        final text = utf8.decode(bytes, allowMalformed: true);
        // Budget is a property of the VIEW: the span is clamped to the
        // decision's budget with the green-screen fact — the model can
        // re-zoom or narrow the anchor; it is never refused by file size.
        final maxChars = budgetTokens * 4;
        final truncated = text.length > maxChars;
        return <String, Object?>{
          'ok': true,
          'path': path,
          'span_start': clampedStart,
          'span_end': clampedEnd,
          'text': truncated ? text.substring(0, maxChars) : text,
          'truncated': truncated,
          if (truncated)
            'hint': 'span clamped to the view budget — narrow the anchor '
                '(zoom a child section/keypath) or raise the budget',
        };
      } finally {
        raf.closeSync();
      }
    };

/// --- The MAP HALF (ADR 0024 §2, map-before-emitter) -----------------------
///
/// Mechanical, zero-model-token indexers: md → heading sections (fences
/// inert per ADR 0019), yaml/json → keypath trees. Each sub-node declares
/// its source span — the anchor the model zooms, reads (budgeted span cut)
/// and later edits (the materializer's emitter splices by these offsets).

/// Indexes an md file's ATX headings (outside code fences) as `section`
/// nodes. A section spans from its heading to the next heading (any level)
/// or EOF. Setext headings are honestly skipped (v1 map limitation).
int _indexMdSections(World world, FsFileScan f, String content) {
  final unitRe = RegExp(r'^(#{1,6})\s+(.*?)\s*#*\s*$', multiLine: true);
  final fenceRe = RegExp(r'^\s*(```|~~~)');
  var offset = 0;
  var inFence = false;
  final headings = <(int, int, String)>[]; // (start, level, title)
  for (final line in content.split('\n')) {
    final lineStart = offset;
    offset += line.length + 1;
    if (fenceRe.hasMatch(line)) {
      inFence = !inFence; // ``` and ~~~ toggle (an opening fence's marker)
      continue;
    }
    if (inFence) continue; // fences are INERT (ADR 0019)
    final m = unitRe.firstMatch(line);
    if (m == null) continue;
    headings.add((lineStart, m.group(1)!.length, m.group(2)!));
  }
  var built = 0;
  for (var i = 0; i < headings.length && built < maxMapNodesPerFile; i++) {
    final (start, level, title) = headings[i];
    final end = i + 1 < headings.length ? headings[i + 1].$1 : content.length;
    final id = 'sec_${f.nodeId}_${i + 1}';
    addMeaningNode(
      world,
      kind: 'section',
      label: title.length > 80 ? title.substring(0, 80) : title,
      id: id,
      props: {
        'path': f.rel,
        'class': 'md',
        'level': level,
        'ordinal': i + 1,
        'span_start': start,
        'span_end': end,
        'line': content.substring(0, start).split('\n').length,
      },
    );
    _ensureContainsEdge(world, f.nodeId, id);
    built++;
  }
  return built;
}

/// Indexes a yaml/json file's keys as `keypath` nodes (indentation-based;
/// comments are lines of the file — the map records spans, it never
/// re-serializes). A key's span covers its whole block (key line through
/// the last line of its nested content) — the anchor the materializer's
/// offset-splice emitter will edit by (PLAN item 5).
int _indexKeypaths(World world, FsFileScan f, String content, {required bool isJson}) {
  final lines = content.split('\n');
  final keyRe = isJson
      ? RegExp(r'^([ ]*)"([^"]+)"\s*:')
      : RegExp(r'^([ ]*)([A-Za-z_][\w.\- ]*)\s*:');
  final offsetOf = <int>[];
  var off = 0;
  for (final line in lines) {
    offsetOf.add(off);
    off += line.length + 1;
  }
  // Pass 1: key lines with (indent, key, lineIdx).
  final keys = <(int, String, int)>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty || line.trim().startsWith('#')) continue;
    final m = keyRe.firstMatch(line);
    if (m == null) continue;
    keys.add((m.group(1)!.length, isJson ? m.group(2)! : m.group(2)!.trim(), i));
  }
  // Pass 2: spans (to the next key with indent <= this one) + nodes.
  var built = 0;
  final stack = <(int, String)>[]; // (indent, keypath) frames
  for (var i = 0; i < keys.length && built < maxMapNodesPerFile; i++) {
    final (indent, key, lineIdx) = keys[i];
    while (stack.isNotEmpty && stack.last.$1 >= indent) {
      stack.removeLast();
    }
    final keypath = [
      for (final (_, k) in stack) k,
      key,
    ].join('.');
    stack.add((indent, key));
    var endLine = lines.length - 1;
    for (var j = i + 1; j < keys.length; j++) {
      if (keys[j].$1 <= indent) {
        endLine = keys[j].$3 - 1;
        break;
      }
    }
    final slug = keypath.replaceAll(RegExp(r'[^\w]'), '_');
    final id = 'key_${f.nodeId}_$slug';
    if (hasMeaningNode(world, id)) continue;
    addMeaningNode(
      world,
      kind: 'key',
      label: keypath,
      id: id,
      props: {
        'path': f.rel,
        'class': f.fileClass,
        'keypath': keypath,
        'indent': indent,
        'span_start': offsetOf[lineIdx],
        'span_end': offsetOf[endLine] + lines[endLine].length,
        'line': lineIdx + 1,
      },
    );
    _ensureContainsEdge(world, f.nodeId, id);
    built++;
  }
  return built;
}

/// The fs-tier ESCAPE HATCH (ADR 0024 §4): whole-file write for file classes
/// WITHOUT a materializer — review mode ONLY. The gateway renders the
/// unified diff and asks the approver (over ACP: `session/request_permission`
/// — the human allows/rejects; a reject NEVER lands). Deny-by-default is
/// STRUCTURAL: the verb refuses any gateway not in review mode, and hosts
/// register it only when a consent approver is wired — no approver, no verb.
///
/// This is NOT a generic `write` returning to the meaning profile (ADR 0023
/// demotion stands): Dart code never routes here — code moves through
/// `edit_symbol` only, and the ack/diff audit lands in the write-gate log.
ToolDef writeReviewTool(FsToolsRoot root, JailWriteGateway gateway) =>
    ToolDef.encode(
      name: const ToolName('write_review'),
      description:
          'Whole-file write through the review gate (ESCAPE HATCH for '
          'files without a materializer). The human consents via the '
          'unified diff; a reject NEVER lands. Never for Dart — code '
          'moves through edit_symbol. Args: path (relative), content '
          '(full new file text).',
      argsSchema: SchemaBundle(
        root: FM.object('write_review', properties: () => [
              FM.prop('path', FM.string()),
              FM.prop('content', FM.string()),
            ]),
      ),
      execute: (args) async {
        final map = args is Map ? args : const {};
        final path = map['path'];
        final content = map['content'];
        if (path is! String || path.isEmpty) {
          return {
            'ok': false,
            'error': 'invalid_path',
            'hint': 'write_review requires a workspace-relative path',
          };
        }
        if (content is! String) {
          return {
            'ok': false,
            'error': 'invalid_content',
            'hint': 'write_review carries the FULL new file text as a '
                'string slot — never a diff, never a fragment',
          };
        }
        if (gateway.mode != WriteGateMode.review) {
          // Deny-by-default is structural: without review mode there is no
          // consent path, so the verb refuses before touching any byte.
          return const {
            'ok': false,
            'error': 'review_mode_required',
            'hint': 'write_review exists only under review-mode consent — '
                'attach an approver (session/request_permission) or use a '
                'materializer verb',
          };
        }
        if (fileClassOf(path) == 'dart') {
          return {
            'ok': false,
            'error': 'dart_not_via_escape_hatch',
            'path': path,
            'hint': 'code law (ADR 0019/0023): Dart moves through '
                'edit_symbol (meaning moves) — never through whole-file '
                'writes, gated or not',
          };
        }
        final String abs;
        try {
          abs = root.resolve(path);
          // ignore: avoid_catching_errors
        } on ArgumentError catch (e) {
          return {
            'ok': false,
            'error': 'path_escapes_workspace',
            'path': path,
            'message': '$e',
          };
        }
        final ack = await gateway.interceptWrite(abs, content);
        return {
          'ok': ack.startsWith('wrote'),
          'ack': ack,
          'path': path,
          'consent': 'review',
        };
      },
    );
