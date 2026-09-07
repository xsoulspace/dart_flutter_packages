// ignore_for_file: lines_longer_than_80_chars

/// ADR 0034 — the ONE edit verb's class router: edits address MEANING
/// NODES; the node's class routes the materializer.
///
/// The model supplies `{action, symbolId, body?}` to `edit_symbol` —
/// never a path, never a format. The router resolves the node in the
/// meaning tree, reads its class, checks the action against the class's
/// registered `MaterializerSpec.actions`, and dispatches to the class
/// materializer (splice + named oracle + locks + auto-revert — all
/// existing machinery, class-routed). A wrong action for a class is a
/// NAMED bounce listing that node's legal actions — legality is taught
/// by the bounce and the cut, never by knowing formats.
///
/// Non-dart classes only: `sym_*` nodes stay on the span editor's dart
/// path (compiled op-chains, packs, coverage fence). The router handles
/// the classes that registered a materializer spec: `section` (md) and
/// `key` (yaml/json) today. A class with NO spec (or no oracle) has NO
/// edit actions — its writes route through the review gate (ADR 0024 §6,
/// named never silent).
library;

import 'dart:io';

import 'package:ecsly/ecsly.dart';
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show FileLockTable, FsToolsRoot;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart'
    show MeaningIndex, MeaningNode, MeaningProps, meaningComponentOf;

import 'file_class_spec.dart' show materializerSpecFor;
import 'md_materializer.dart' show MdMaterializer;
import 'yaml_json_materializer.dart' show KeypathMaterializer;

/// A named edit bounce (mirrors [SpanEditBounce]'s contract: reason +
/// repair hint, navigable, never silent).
class NodeEditBounce implements Exception {
  NodeEditBounce(this.reason, this.hint);
  final String reason;
  final String hint;

  Map<String, dynamic> toJson() => {
    'ok': false,
    'bounce': true,
    'error': reason,
    'hint': hint,
  };
}

/// The resolved meaning node — id, kind, and the props the router needs.
class ResolvedNode {
  const ResolvedNode({
    required this.id,
    required this.kind,
    required this.props,
  });
  final String id;
  final String kind;
  final Map<String, dynamic> props;

  /// The node's file class prop (`md`, `yaml`, `json`, `dart`).
  String get fileClass => '${props['class'] ?? ''}';

  /// The node's file path (the model never names it — ADR 0034 §3).
  String get path => '${props['path'] ?? ''}';
}

/// Resolves [symbolId] in the meaning tree. Null → the id is unknown.
ResolvedNode? resolveMeaningNode(World world, String symbolId) {
  final index = world.getResource<MeaningIndex>();
  final entity = index.byId[symbolId];
  if (entity == null) return null;
  final node = meaningComponentOf<MeaningNode>(world, entity);
  if (node == null) return null;
  final props =
      meaningComponentOf<MeaningProps>(world, entity)?.props ??
      const <String, dynamic>{};
  return ResolvedNode(id: node.id, kind: node.kind, props: props);
}

/// Routes ONE non-dart node edit: `{action, symbolId, body}` through the
/// node class's registered materializer.
///
/// - `section` (md) → [MdMaterializer.perform] (anchor = the node id —
///   the md materializer accepts section node ids natively).
/// - `key` (yaml/json) → [KeypathMaterializer.perform] (anchor = the
///   node id — the keypath materializer accepts key node ids natively).
///
/// Throws [NodeEditBounce] for: unknown id, class without registered
/// actions, or an action outside the class's legal set. Bytes only move
/// through the materializer's own splice + oracle + auto-revert.
Future<Map<String, dynamic>> routeNodeEdit({
  required World world,
  required Directory workspace,
  required FsToolsRoot fsRoot,
  required String symbolId,
  required String action,
  String? body,
  FileLockTable? locks,
  Object owner = 'edit_node_router',
}) async {
  final node = resolveMeaningNode(world, symbolId);
  if (node == null) {
    throw NodeEditBounce(
      'unknown node id: $symbolId',
      'locate/zoom to find the node, then re-send with a valid symbolId '
          '(ids look like sym_lib_main.dart_main, sec_…, key_…)',
    );
  }
  final fileClass = node.fileClass;
  final spec = materializerSpecFor(fileClass);
  if (spec == null || spec.actions.isEmpty) {
    throw NodeEditBounce(
      'class "$fileClass" has no registered edit actions',
      'writes to this class route through write_review (the human '
          'consents the diff) — register a MaterializerSpec with a named '
          'oracle to give it edit actions (ADR 0024 §6, ADR 0034 §5)',
    );
  }
  if (!spec.actions.contains(action)) {
    throw NodeEditBounce(
      'action "$action" is not legal for a $fileClass node',
      'legal actions for THIS node (${node.id}): '
          "${spec.actions.join(", ")} — the node's class teaches the "
          'vocabulary; never the format',
    );
  }
  final path = node.path;
  if (path.isEmpty) {
    throw NodeEditBounce(
      'node ${node.id} carries no path prop',
      're-scan the workspace (repo_etl scan) — the tree is stale',
    );
  }
  return switch (node.kind) {
    'section' => MdMaterializer(root: fsRoot, locks: locks, owner: owner)
        .perform(path: path, op: action, anchor: symbolId, body: body)
        .toJson(),
    'key' => KeypathMaterializer(root: fsRoot, locks: locks, owner: owner)
        // The anchor is the node's KEYPATH (the semantic-diff oracle's
        // change-at accounting names changes by keypath — the node id is
        // only the model's handle; the props carry the truth).
        .perform(
          path: path,
          op: action,
          anchor: '${node.props['keypath'] ?? symbolId}',
          body: body,
        )
        .toJson(),
    _ => throw NodeEditBounce(
      'node kind "${node.kind}" is not routed for edits',
      'dart symbols edit through the span path (replace_member_body / '
          'insert_member / apply_executable); other kinds need a '
          'registered materializer spec',
    ),
  };
}
