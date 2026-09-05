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
    show CodeFileScan, buildMeaningTreeFromCode, dartFiles, scanDartFile;
import 'fs_etl.dart'
    show buildFsTier, refreshFsTier, scanWorkspaceFs;

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
              final touched = _changedFiles(workspace, st);
              var syms = 0;
              for (final f in touched) {
                final rel = f.path.startsWith('${workspace.path}/')
                    ? f.path.substring(workspace.path.length + 1)
                    : f.path;
                syms += _rescanFile(
                  world,
                  scanDartFile(f, rel),
                );
              }
              // Fs tier (ADR 0024): the same mechanical tick keeps dir/file
              // nodes honest for EVERY file class (no cutoff — full pass).
              final fs = refreshFsTier(world, workspace);
              st
                ..lastScan = DateTime.now()
                ..files = fs.files
                ..dirs = fs.dirs
                ..dartFiles = _countDartFiles(workspace);
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
          final touched = _changedFiles(workspace, st);
          var syms = 0;
          for (final f in touched) {
            final rel = f.path.startsWith('${workspace.path}/')
                ? f.path.substring(workspace.path.length + 1)
                : f.path;
            final scan = scanDartFile(f, rel);
            syms += _rescanFile(world, scan);
          }
          // Fs tier: same tick — new nodes added, stale nodes dropped.
          final fs = refreshFsTier(world, workspace, cutoff: st.lastScan);
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
          final scans = <String, List<CodeFileScan>>{
            'workspace': [
              for (final f in fsScan.dartFiles)
                scanDartFile(
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

List<File> _changedFiles(Directory workspace, RepoEtlState st) {
  final all = dartFiles(workspace);
  if (all.length != st.dartFiles) return all; // structural change — full pass
  final cutoff = st.lastScan!;
  return [
    for (final f in all)
      if (f.statSync().modified.isAfter(cutoff)) f,
  ];
}

int _countDartFiles(Directory workspace) => dartFiles(workspace).length;

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
