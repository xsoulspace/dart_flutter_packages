// ignore_for_file: lines_longer_than_80_chars

/// R7a — ETL as a harness seam (ADR 0023 §2): `repo_etl` is the actor-facing
/// "touch world" tool that scans the workspace and builds/refreshes the
/// meaning tree as WORLD state.
///
/// Before this tool, repo-scale ETL was an outer-agent script — the harness
/// loop could not do it. With it, the actor's loop is: `repo_etl` (scan) →
/// `meaning_zoom` (read, budgeted) → `meaning_impact` (decompose) → edit
/// moves (R7b, the span materializer). No file reads; the tree is the code
/// interface.
///
/// The tree is a RE-DERIVABLE projection (North Star): it is never
/// snapshotted. `scan` rebuilds (repo-scale: ~0.5s); `refresh` re-scans
/// files whose mtime changed (incremental, mechanical persist tick — R7c
/// wires it to the daemon loop).
library;

import 'dart:io';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart' show FM;

import 'code_etl.dart'
    show CodeFileScan, buildMeaningTreeFromCode, dartFiles;
import 'file_class_spec.dart' show fileClassSpecs, specForRel;
import 'fs_etl.dart'
    show
        FsScan,
        buildFsTier,
        refreshFsTier,
        scanWorkspaceFs;

/// Mutable scan bookkeeping for one workspace (staleness, file count).
class RepoEtlState {
  DateTime? lastScan;

  /// Files indexed by the fs tier (EVERY file — ADR 0024 §1).
  int files = 0;
  int dirs = 0;

  /// Dart files scanned by the code tier (the mtime-tick comparison base).
  int dartFiles = 0;
  int symbols = 0;
}

/// Registers the `repo_etl` tool against [world] + [workspace].
///
/// `scan` rebuilds the tree from scratch (idempotent within a fresh world;
/// across calls it REFUSES to double-build — the caller drops the world or
/// uses `refresh`). `status` reports staleness; `refresh` re-scans changed
/// files only (mtime-based).
ToolDef repoEtlTool(
  World world,
  Directory workspace, {
  RepoEtlState? state,
}) {
  final st = state ?? RepoEtlState();
  return ToolDef.encode(
    name: const ToolName('repo_etl'),
    description:
        'Scan the workspace into the meaning tree — the ONE map-graph you '
        'work through (code symbols + dir/file nodes for EVERY file; md/'
        'yaml/json carry section/keypath anchors). Actions: scan (once '
        'before zooming), status, refresh (mtime tick). Then '
        'meaning_zoom/meaning_impact — never file reads.',
    argsSchema: SchemaBundle(
      root: FM.object('repo_etl', properties: () => [
            FM.prop(
              'action',
              FM.enum_('action', const ['scan', 'status', 'refresh']),
            ),
          ]),
    ),
    execute: (args) async {
      final map = args is Map ? args : const {};
      switch (map['action'] ?? 'status') {
        case 'status':
          return {
            'ok': true,
            'scanned': st.lastScan != null,
            'lastScan': st.lastScan?.toIso8601String(),
            'files': st.files,
            'dirs': st.dirs,
            'dart_files': st.dartFiles,
            'symbols': st.symbols,
            'tree_nodes':
                world.maybeGetResource<MeaningIndex>()?.nodeCount ?? 0,
          };
        case 'refresh':
          if (st.lastScan == null) {
            // R7c persistent world: the tree may already live in the
            // restored world (built once per workspace) while this tool
            // instance's state is fresh — treat as a full refresh pass.
            final existing = world.maybeGetResource<MeaningIndex>();
            if (existing != null && existing.nodeCount > 0) {
              // Fresh state over a restored tree: no cutoff — every tree
              // file re-derives and every NEW dart file parses (it was
              // never in the tree).
              final fsScan = scanWorkspaceFs(workspace);
              final touched = _changedFiles(world, workspace, st, fsScan);
              var syms = 0;
              for (final f in touched) {
                final rel = f.path.startsWith('${workspace.path}/')
                    ? f.path.substring(workspace.path.length + 1)
                    : f.path;
                syms += _rescanParse(world, f, rel);
              }
              // Fs tier (ADR 0024): the same walk keeps dir/file nodes
              // honest for EVERY file class.
              final fs = refreshFsTier(world, workspace, scan: fsScan);
              st
                ..lastScan = DateTime.now()
                ..files = fs.files
                ..dirs = fs.dirs;
              return {
                'ok': true,
                'refreshed_files': touched.length,
                'symbols_touched': syms,
                'files': st.files,
                'fs_added': fs.added,
                'fs_dropped': fs.dropped,
                'note': 'persistent tree refreshed (world carried it)',
              };
            }
            return {
              'ok': false,
              'error': 'nothing scanned yet — action scan',
            };
          }
          // ONE walk per tick, shared by the code tick and the fs tier.
          final fsScan = scanWorkspaceFs(workspace);
          final touched = _changedFiles(
            world,
            workspace,
            st,
            fsScan,
          );
          var syms = 0;
          for (final f in touched) {
            final rel = f.path.startsWith('${workspace.path}/')
                ? f.path.substring(workspace.path.length + 1)
                : f.path;
            syms += _rescanParse(world, f, rel);
          }
          // Fs tier: same walk — new nodes added, stale nodes dropped,
          // unchanged nodes skipped (cutoff-gated rebuild).
          final fs = refreshFsTier(
            world,
            workspace,
            cutoff: st.lastScan,
            scan: fsScan,
          );
          st
            ..lastScan = DateTime.now()
            ..files = fs.files
            ..dirs = fs.dirs;
          return {
            'ok': true,
            'refreshed_files': touched.length,
            'symbols_touched': syms,
            'files': st.files,
            'fs_added': fs.added,
            'fs_dropped': fs.dropped,
          };
        case 'scan':
        default:
          if (st.lastScan != null) {
            return {
              'ok': false,
              'error': 'tree already built — use action refresh',
              'files': st.files,
            };
          }
          // R7c persistent world: the restored world may already carry the
          // tree — never double-build (ids would collide). The daemon's
          // mechanical tick refreshes mtimes before the prompt.
          final preexisting = world.maybeGetResource<MeaningIndex>();
          if (preexisting != null && preexisting.nodeCount > 0) {
            st
              ..lastScan = DateTime.now()
              ..files = preexisting.byId.keys
                  .where((id) => id.startsWith('f_'))
                  .length
              ..dirs = preexisting.byId.keys
                  .where((id) => id.startsWith('dir_'))
                  .length
              ..dartFiles = _countDartFiles(workspace)
              ..symbols = preexisting.byId.keys
                  .where((id) => id.startsWith('sym_'))
                  .length;
            return {
              'ok': true,
              'already': true,
              'files': st.files,
              'symbols': st.symbols,
              'note': 'tree already present in this persistent world — the '
                  'host refreshes it mechanically; zoom/impact away',
            };
          }
          // ONE scan pass (ADR 0024 §1): the fs walk yields every file; the
          // code ETL reuses the dart subset — zero model tokens, same tick.
          final fsScan = scanWorkspaceFs(workspace);
          // Class-generic: every spec WITH a parse fn contributes its
          // extraction to the code tier (dart today; md/yaml/json anchor
          // builders land as parse fns when their spec families mature).
          final scans = <String, List<CodeFileScan>>{
            'workspace': [
              for (final f in fsScan.files)
                if (specForRel(f.rel).parse != null)
                  specForRel(f.rel).parse!(
                    File('${workspace.path}/${f.rel}'),
                    f.rel,
                  ),
            ],
          };
          final built = buildMeaningTreeFromCode(world, scans, repoRoot: workspace.path);
          final fs = buildFsTier(world, workspace, scan: fsScan);
          st
            ..lastScan = DateTime.now()
            ..files = fs.files
            ..dirs = fs.dirs
            ..dartFiles = built.files
            ..symbols = built.symbols;
          return {
            'ok': true,
            'files': fs.files,
            'dirs': fs.dirs,
            'dart_files': built.files,
            'symbols': built.symbols,
            'edges': built.edges,
            'note': 'tree is world state (code graph + fs tier) — use '
                'meaning_zoom / meaning_impact to read it; it is '
                're-derivable and never snapshotted',
          };
      }
    },
  );
}

/// ADR 0027 dogfood fix — the tick enumerates from the TREE, not from a
/// second walker. The old path re-walked with `dartFiles()`, whose skip
/// rules differ from the fs walk's (`1,071` vs `1,123` on this repo) — the
/// count mismatch forced a FULL re-parse on every no-op tick (measured:
/// 5.8 s per prompt on the monorepo).
List<File> _changedFiles(
  World world,
  Directory workspace,
  RepoEtlState st,
  FsScan fsScan,
) {
  // Tree dart files: parse only when mtime > cutoff (fresh tool state over
  // a restored tree → cutoff null → the honest pass is ALL tree files).
  final cutoff = st.lastScan;
  final inTree = <String>{};
  final touched = <File>[];
  for (final entry in world.getResource<MeaningIndex>().byId.entries) {
    if (!entry.key.startsWith('f_')) continue;
    final node = meaningComponentOf<MeaningNode>(world, entry.value);
    if (node == null) continue;
    // Only classes with a mechanical extractor enter the code tick; the
    // fs tier owns the rest (md/yaml/json anchors, other).
    if (specForRel(node.label).parse == null) continue;
    inTree.add(node.label);
    final f = File('${workspace.path}/${node.label}');
    if (!f.existsSync()) continue; // dropped — pruned by the fs tier below
    if (cutoff == null || f.statSync().modified.isAfter(cutoff)) {
      touched.add(f);
    }
  }
  // NEW dart files (never in the tree) ALWAYS parse — the ambiguity and
  // refs fences only work when every symbol is in the tree.
  for (final f in fsScan.files) {
    if (inTree.contains(f.rel)) continue;
    if (specForRel(f.rel).parse == null) continue;
    touched.add(File('${workspace.path}/${f.rel}'));
  }
  return touched;
}



int _countDartFiles(Directory workspace) =>
    fsFilesByParseableClass(workspace).length;

/// Dart files enumerated the SAME way the scan's spec dispatch does — the
/// legacy `_changedFiles` comparison base (kept honest with the registry).
List<File> fsFilesByParseableClass(Directory workspace) => [
      for (final f in dartFiles(workspace))
        if (specForRel(_relOf(workspace, f)).parse != null) f,
    ];

String _relOf(Directory workspace, File f) =>
    f.path.startsWith('${workspace.path}/')
        ? f.path.substring(workspace.path.length + 1)
        : f.path;

/// Runs the file-class spec's mechanical extractor (registry dispatch —
/// no hardcoded scanDartFile, no `.dart` suffix filters).
int _rescanParse(World world, File f, String rel) {
  final parse = specForRel(rel).parse;
  if (parse == null) return 0;
  return _rescanFile(world, parse(f, rel));
}

/// Re-extracts one file's symbols into the tree (best-effort incremental:
/// new symbols are added; dropped ones are left stale until a full rescan
/// — recorded honestly in the result).
int _rescanFile(World world, CodeFileScan scan) {
  for (final s in scan.symbols) {
    final id = 'sym_${s.file.replaceAll('/', '_')}_${s.name}';
    if (world.getResource<MeaningIndex>().byId.containsKey(id)) continue;
    addMeaningNode(
      world,
      kind: 'symbol',
      label: s.name,
      props: {'file': s.file, 'line': s.line, 'decl': s.declKind},
      id: id,
    );
  }
  return scan.symbols.length;
}
