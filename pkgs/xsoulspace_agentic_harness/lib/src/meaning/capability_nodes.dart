// ignore_for_file: lines_longer_as_80_chars

/// P2 — pack inventory as MEANING nodes (PLAN §NOW, decision amortization).
///
/// The project pack (`EditPackCapture`, ADR 0021/0023) is host data the
/// model never sees — so far the model could only CONSUME an executable id
/// it was told about. This module lifts the inventory INTO the meaning
/// tree: every executable becomes a node the agent can LOCATE and ZOOM —
/// "the agent zooms its own capabilities".
///
/// Node shape (rides MeaningNode/MeaningProps/MeaningEdge as DATA — never a
/// new ECS Component class):
/// - kind `'executable'`, label = the executable id (exactly what
///   `apply_executable` takes), stable id `exec_<sanitized id>`.
/// - props: `{executableId, kind, params, verification, description, pack}`.
/// - `impl` edge executable → the pack anchor node (where the realizing
///   data — the op-chain / consented body — lives).
/// - `capability_of` edge executable → `dir_root` (a capability OF this
///   workspace; best-effort — linked once the fs tier has scanned).
///
/// Idempotence is the contract: a re-scan re-reconciles from the CURRENT
/// pack — entries re-register in place (stable ids, no duplicates), props
/// refresh, and entries REMOVED from the pack are dropped from the tree
/// (never resurrected by a later refresh).
library;

import 'package:ecsly/ecsly.dart';

import 'meaning_tree.dart';

/// The stable anchor node every executable's `impl` edge points at.
const packAnchorId = 'pack_edit_capture';

/// One executable to register, as generic data (the workspace maps its
/// [EditExecutableWire] rows onto this — the harness core stays
/// domain-generic, ADR 0015).
class CapabilityEntry {
  const CapabilityEntry({
    required this.executableId,
    required this.kind,
    this.params = const [],
    this.verification = const [],
    this.description = '',
  });

  /// The model-facing handle — the exact id `apply_executable` takes.
  final String executableId;

  /// The repair class, e.g. `replace_member_body`, `rename_symbol`.
  final String kind;

  /// Bounded parameter slots the executable declares.
  final List<String> params;

  /// The mechanical verify tier that must run after expansion.
  final List<String> verification;

  final String description;
}

/// The stable tree id of an executable node (derived from the executable
/// id — never model-authored, never re-derived differently between scans).
String capabilityNodeId(String executableId) =>
    'exec_${executableId.replaceAll(RegExp('[^A-Za-z0-9_.]'), '_')}';

bool _hasEdge(MeaningIndex index, String from, String relation, String to) {
  for (final t in index.triples) {
    if (t.$1 == from && t.$2 == relation && t.$3 == to) return true;
  }
  return false;
}

bool _isPackExecutable(World world, String id, String anchorId) {
  final entity = _entityOf(world, id);
  if (entity == null) return false;
  final node = meaningComponentOf<MeaningNode>(world, entity);
  if (node == null || node.kind != 'executable') return false;
  final props = meaningComponentOf<MeaningProps>(world, entity);
  return props?.props['pack'] == anchorId;
}

Entity? _entityOf(World world, String id) =>
    world.maybeGetResource<MeaningIndex>()?.entityOf(id);

/// Reconciles the pack inventory INTO the tree — the ONE registration path
/// (after the workspace ETL scan, and on every tick/refresh). Idempotent
/// across refreshes: re-registration updates in place, removals prune.
/// Returns named counts (registered / updated / removed / total).
Map<String, int> reconcileCapabilityNodes(
  World world,
  List<CapabilityEntry> entries, {
  String anchorId = packAnchorId,
  String anchorLabel = 'edit_pack',
}) {
  // The stable anchor: ONE node per pack, created once, never re-created.
  if (!hasMeaningNode(world, anchorId)) {
    addMeaningNode(
      world,
      kind: 'capability_pack',
      label: anchorLabel,
      props: {'packId': 'edit_capture', 'anchor': anchorId},
      id: anchorId,
    );
  }
  final index = world.getResource<MeaningIndex>();
  final liveIds = {for (final e in entries) capabilityNodeId(e.executableId)};

  var registered = 0;
  var updated = 0;
  for (final e in entries) {
    final id = capabilityNodeId(e.executableId);
    final props = {
      'executableId': e.executableId,
      'kind': e.kind,
      'params': List<String>.of(e.params),
      'verification': List<String>.of(e.verification),
      'description': e.description,
      'pack': anchorId,
    };
    if (hasMeaningNode(world, id)) {
      // Refresh in place — a changed repair class must not leave a stale
      // capability zoomable.
      for (final entry in props.entries) {
        setMeaningProp(world, id: id, key: entry.key, value: entry.value);
      }
      updated++;
    } else {
      addMeaningNode(
        world,
        kind: 'executable',
        label: e.executableId,
        props: props,
        id: id,
      );
      registered++;
    }
    // impl edge → the pack anchor (the realizing data lives there).
    if (!_hasEdge(index, id, 'impl', anchorId)) {
      linkMeaning(world, from: id, relation: 'impl', to: anchorId);
    }
    // capability_of → dir_root (a capability OF this workspace; the fs
    // tier creates dir_root on scan — linked once it exists).
    if (hasMeaningNode(world, 'dir_root') &&
        !_hasEdge(index, id, 'capability_of', 'dir_root')) {
      linkMeaning(world, from: id, relation: 'capability_of', to: 'dir_root');
    }
  }

  // Removals: executable nodes of THIS pack that the current pack no
  // longer carries are dropped (a re-scan never resurrects a removed
  // entry). Executable nodes of other packs (no matching anchor prop) are
  // never touched.
  var removed = 0;
  final stale = [
    for (final entry in index.byId.entries)
      if (!liveIds.contains(entry.key) &&
          _isPackExecutable(world, entry.key, anchorId))
        entry.key,
  ];
  for (final id in stale) {
    if (dropMeaningNode(world, id)) removed++;
  }
  return {
    'registered': registered,
    'updated': updated,
    'removed': removed,
    'total': entries.length,
  };
}
