// ignore_for_file: lines_longer_than_80_chars

/// R7a — ETL as a harness seam (ADR 0023 §2): `repo_etl` is the actor-facing
/// "touch world" tool that scans the workspace and builds/refreshes the
/// meaning tree as WORLD state.
///
/// Before this tool, repo-scale ETL was an outer-agent script — the harness
/// loop could not do it. With it, the actor's loop is: `repo_etl` (scan) →
/// the read program (locate/zoom/impact/read) → edit
/// moves (R7b, the span materializer). No file reads; the tree is the code
/// interface.
///
/// The tree is a RE-DERIVABLE projection (North Star): it is never
/// snapshotted. `scan` rebuilds (repo-scale: ~0.5s); `refresh` re-scans
/// files whose mtime changed (incremental, mechanical persist tick — R7c
/// wires it to the daemon loop).
library;

import 'dart:io';

import 'package:xsoulspace_agentic_harness/src/meaning/capability_nodes.dart'
    show CapabilityEntry, reconcileCapabilityNodes;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart' show FM;

import 'code_etl.dart'
    show CodeFileScan, buildMeaningTreeFromCode, dartFiles;
import 'edit_pack_capture.dart' show EditPackCapture;
import 'file_class_spec.dart' show fileClassSpecs, specForRel;
import 'fs_etl.dart'
    show
        FsScan,
        buildFsTier,
        reconcileFsTier,
        refreshFsTier,
        registerFsCapabilities,
        registerMeaningNodeRefresher,
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
  // Capability ops (effects-as-data): fs_stat is registered on the world
  // so intents can compose jailed fs capabilities (interpreter tier).
  registerFsCapabilities(world, workspace);
  // Zoom staleness refresher (PLAN §NOW): world data the harness
  // the program's read cut discovers — every read serves post-edit
  // spans without waiting for a tick.
  registerMeaningNodeRefresher(world, workspace);
  return ToolDef.encode(
    name: const ToolName('repo_etl'),
    description:
        'Scan the workspace into the meaning tree — the ONE map-graph you '
        'work through (code symbols + dir/file nodes for EVERY file; md/'
        'yaml/json carry section/keypath anchors). Actions: scan (once '
        'before zooming), status, refresh (mtime tick). Then '
        'the meaning_program read ops — never file reads.',
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
              // VCS registration seam (PLAN §NOW P3): the restored world
              // also re-projects the VCS state — the tick never breaks
              // over VCS (named status, zero nodes on degradation).
              final vcs = await _projectVcs(world, workspace);
              // P2 — pack inventory reconcile rides EVERY refresh tick
              // (idempotent: updates in place, removals prune).
              final capabilities = registerPackInventory(world, workspace);
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
                'capabilities': capabilities,
                'vcs': vcs,
                'note': 'persistent tree refreshed (world carried it)',
              };
            }
            return {
              'ok': false,
              'error': 'nothing scanned yet — action scan',
            };
          }
          // TREE-DRIVEN tick (ADR 0027 warm-tick floor): stat the stored
          // file nodes, listSync only dirs whose mtime moved past the
          // cutoff — the full-fs-walk-per-prompt is gone (measured ~1.4 s
          // no-op ticks on this monorepo; the reconcile is syscall-per-node).
          final tick = reconcileFsTier(
            world,
            workspace,
            cutoff: st.lastScan!,
          );
          // Code tier: parseable entries of the SAME reconcile result —
          // changed AND new parseable files re-parse (the ambiguity and
          // refs fences only work when every symbol is in the tree).
          var syms = 0;
          var touched = 0;
          for (final f in tick.changed) {
            if (specForRel(f.rel).parse == null) continue;
            touched++;
            syms += _rescanParse(
              world,
              File('${workspace.path}/${f.rel}'),
              f.rel,
            );
          }
          st
            ..lastScan = DateTime.now()
            ..files = tick.files
            ..dirs = tick.dirs;
          // P2 — pack inventory reconcile rides EVERY refresh tick.
          final capabilities = registerPackInventory(world, workspace);
          // VCS registration seam (PLAN §NOW P3): the daemon's mechanical
          // tick carries branch/head/change into the live world — zero
          // model tokens, named skip on degradation, never a tick breaker.
          final vcs = await _projectVcs(world, workspace);
          return {
            'ok': true,
            'refreshed_files': touched,
            'symbols_touched': syms,
            'files': tick.files,
            'fs_added': tick.added,
            'fs_dropped': tick.dropped,
            'capabilities': capabilities,
            'vcs': vcs,
            if (tick.staleDirs > 0) 'fs_stale_dirs': tick.staleDirs,
          };
        case 'scan':
        default:
          // TINY-MODEL TEACHING FIX (measured on-device, afm_wave row 2):
          // a small model's natural first move is `scan` — bouncing it as an
          // ERROR on an already-built tree looped the real AFM run 4× until
          // the budget died. Scan is now an IDEMPOTENT ENSURE: same
          // mechanical reconcile as refresh (zero model tokens), ok:true +
          // `already_built` so the actor learns the tree is current and
          // moves on. The restored-persistent-world path below is unchanged.
          if (st.lastScan != null) {
            final tick = reconcileFsTier(
              world,
              workspace,
              cutoff: st.lastScan!,
            );
            var syms = 0;
            var touched = 0;
            for (final f in tick.changed) {
              if (specForRel(f.rel).parse == null) continue;
              touched++;
              syms += _rescanParse(
                world,
                File('${workspace.path}/${f.rel}'),
                f.rel,
              );
            }
            st
              ..lastScan = DateTime.now()
              ..files = tick.files
              ..dirs = tick.dirs;
            final capabilities = registerPackInventory(world, workspace);
            final vcs = await _projectVcs(world, workspace);
            return {
              'ok': true,
              'already_built': true,
              'refreshed_files': touched,
              'symbols_touched': syms,
              'files': tick.files,
              'fs_added': tick.added,
              'fs_dropped': tick.dropped,
              'capabilities': capabilities,
              'vcs': vcs,
              'note': 'the tree was already built — reconciled to current '
                  '(zero model tokens); zoom/locate away or run the ready '
                  'move',
            };
          }
          // R7c persistent world: the restored world may already carry the
          // tree — never double-build (ids would collide). The daemon's
          // mechanical tick refreshes mtimes before the prompt.
          final preexisting = world.maybeGetResource<MeaningIndex>();
          if (preexisting != null && preexisting.nodeCount > 0) {
            // P2 — the restored persistent tree still reconciles the pack
            // (the tool instance is fresh; the inventory must not drift).
            final capabilities = registerPackInventory(world, workspace);
            // VCS registration seam: a scan that found a restored tree
            // still projects the VCS state (the world may never have
            // carried it).
            final vcs = await _projectVcs(world, workspace);
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
              'capabilities': capabilities,
              'vcs': vcs,
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
          // P2 — pack inventory as MEANING nodes: the pack executables
          // join the tree in the SAME scan pass (zero model tokens) — the
          // agent LOCATEs and ZOOMs its own capabilities.
          final capabilities = registerPackInventory(world, workspace);
          // VCS registration seam (PLAN §NOW P3): vcs.repo/branch/head/
          // change nodes enter the tree in the SAME pass (zero model
          // tokens) — the daemon world carries VCS state without any test
          // bootstrap. Not-a-repo → zero nodes; adapter error → named
          // skip; the scan pass NEVER breaks over VCS.
          final vcs = await _projectVcs(world, workspace);
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
            'capabilities': capabilities,
            'vcs': vcs,
            'note': 'tree is world state (code graph + fs tier) — use '
                'the meaning_program read ops to read it; it is '
                're-derivable and never snapshotted',
          };
      }
    },
  );
}

/// VCS registration seam (PLAN §NOW P3) — the ONE helper every scan/
/// refresh/tick result reports: projects the VCS state through the
/// read-only adapter into the live world. Failure-HONEST: not-a-repo →
/// the projection's own named `not_a_repo` (zero nodes); an adapter
/// error → a NAMED skip — the scan pass never breaks over VCS.
Future<Map<String, Object?>> _projectVcs(
  World world,
  Directory workspace,
) async {
  try {
    final r = await projectVcsMeaning(
      world,
      const GitVcsAdapter(),
      workspace.path,
    );
    return {'status': r.status, 'nodes': r.nodeIds.length};
  } on Object catch (e) {
    return {'status': 'vcs_skip', 'nodes': 0, 'error': '$e'};
  }
}

/// ADR 0027 dogfood fix — the restored-tree pass enumerates from the TREE,
/// not from a second walker. The old path re-walked with `dartFiles()`,
/// whose skip rules differ from the fs walk's (`1,071` vs `1,123` on this
/// repo) — the count mismatch forced a FULL re-parse on every no-op tick
/// (measured: 5.8 s per prompt on the monorepo).
/// (The INCREMENTAL tick no longer routes here: `reconcileFsTier` stats
/// stored nodes and walks only mtime-moved dirs. This pass remains the
/// cutoff-null honest pass over a restored persistent tree.)
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

/// P2 — pack inventory as MEANING nodes: loads the project pack and
/// reconciles every executable into the tree (kind 'executable', label =
/// executable id, impl edge to the pack anchor, capability_of → dir_root).
/// Idempotent across refreshes: re-scan updates in place; entries removed
/// from the pack are dropped — never resurrected. Returns the live
/// inventory size. A corrupt/missing pack contributes ZERO entries (the
/// pack loader skips corrupt rows as named data) — registration never
/// throws into the scan path.
int registerPackInventory(World world, Directory workspace) {
  final entries = [
    for (final e in EditPackCapture(workspace).load())
      CapabilityEntry(
        executableId: e.wire.id,
        kind: e.wire.kind.wire,
        params: e.wire.params,
        verification: [for (final v in e.wire.verification) v.wire],
        description: e.wire.description,
      ),
  ];
  reconcileCapabilityNodes(world, entries);
  return entries.length;
}

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
