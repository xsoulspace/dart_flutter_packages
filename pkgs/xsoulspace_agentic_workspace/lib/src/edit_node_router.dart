// ignore_for_file: lines_longer_than_80_chars

/// ADR 0035 §1 — the ONE edit verb's registry router: edits address
/// MEANING NODES; the node's STAMPED `class` prop routes the materializer
/// through the binding registry. There is NO `switch (node.kind)` and no
/// kind-based special case — a new format lands as a binding
/// registration (materializer_binding.dart), never a router edit.
///
/// The model supplies `{action, symbolId, body?, anchor?}` — never a
/// path, never a format. The router resolves the node in the meaning
/// tree, reads its class, dispatches through the registry: the binding's
/// materializer plans, splices, oracles and auto-reverts (all existing
/// machinery, class-routed). A wrong action for a class is a NAMED
/// bounce listing that node's legal actions — legality is taught by the
/// bounce and the cut, never by knowing formats.
///
/// ADR 0035 §5 — the bounces are MECHANISM-FIRST and bounded for every
/// future class: the repair names the move (the read program locates the
/// node; zoom rows stamp the id) and points at the node's own props
/// (`edit_actions` names the legal actions AND the anchor currency).
/// ZERO per-class recipe prose; no format name appears in any bounce.
///
/// Non-dart classes only: `sym_*` nodes stay on the span editor's dart
/// path (compiled op-chains, packs, coverage fence). A class with NO
/// binding has NO edit actions — its writes route through the review
/// gate (ADR 0024 §6, named never silent). Absence of registration IS
/// the enforcement.
library;

import 'dart:io';

import 'package:ecsly/ecsly.dart';
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show FileLockTable, FsToolsRoot;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart'
    show MeaningIndex, MeaningNode, MeaningProps, meaningComponentOf;

import 'materializer_binding.dart'
    show NodeEditRequest, materializerRegistry;

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

  /// The node's stamped `class` prop — THE routing key (ADR 0035 §1).
  String get fileClass => '${props['class'] ?? ''}';

  /// The node's file path (the model never names it — ADR 0034 §3).
  String get path => '${props['path'] ?? ''}';

  /// The file node's declared legal actions (stamped by the tick from
  /// the registry) — the bounce points here, never at a format.
  String get editActions => '${props['edit_actions'] ?? ''}';
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

/// Routes ONE node edit — `{action, symbolId, body?, anchor?}` — through
/// the class binding's registered materializer.
///
/// Dispatch is REGISTRY DISPATCH keyed on the node's stamped `class`
/// prop (ADR 0035 §1): the binding resolves the anchor into its declared
/// currency and performs (plan → splice → oracle → auto-revert). Throws
/// [NodeEditBounce] for: unknown id, class without registered actions,
/// or an action outside the class's legal set — all mechanism-first
/// bounces (ADR 0035 §5), bounded for every future class.
Future<Map<String, dynamic>> routeNodeEdit({
  required World world,
  required Directory workspace,
  required FsToolsRoot fsRoot,
  required String symbolId,
  required String action,
  String? body,

  /// CREATION anchor (ADR 0034 — parent-addressed creation): the literal
  /// anchor in the class's DECLARED currency (the binding's
  /// `anchors`/`resolveAnchor`), scoped to the file of [symbolId].
  /// Absent → the node itself is the anchor (the node-id form).
  String? anchor,
  FileLockTable? locks,
  Object owner = 'edit_node_router',
}) async {
  final node = resolveMeaningNode(world, symbolId);
  if (node == null) {
    // ADR 0035 §5 — the UNKNOWN-ID bounce is MECHANISM-FIRST, bounded for
    // every future class: name the repair move (the read program; zoom
    // rows stamp the id) and the creation rule (an EXISTING node of the
    // target file scopes it; the file node's edit_actions prop names the
    // legal actions and the anchor currency). ZERO per-class recipe
    // prose; no format name appears here — the registry teaches
    // vocabulary through the node's own props, never through prose.
    throw NodeEditBounce(
      'unknown node id: $symbolId',
      'the id resolved to no node in the tree. REPAIR: run the read '
          'program (locate, then zoom the target) — zoom rows stamp the '
          'id; re-send with a stamped symbolId. CREATING something that '
          'has no node yet? symbolId must be an EXISTING node of the '
          "target file (it scopes the file) — that file node's "
          'edit_actions prop names the legal actions AND the anchor '
          'currency for the creation anchor.',
    );
  }
  final fileClass = node.fileClass;
  final binding = materializerRegistry.bindingFor(fileClass);
  if (binding == null || binding.actions.isEmpty) {
    // Mechanism-first (§5): the class's write power is REGISTRY FACT —
    // unregistered = review gate. The repair names the registration
    // move, never a format.
    throw NodeEditBounce(
      'class "$fileClass" has no registered edit actions',
      'writes to this class route through write_review (the human '
          'consents the diff) — give the class edit power by registering '
          'a binding with a named oracle in the materializer registry '
          '(ADR 0024 §6, ADR 0035 §1/§3)',
    );
  }
  if (!binding.actions.contains(action)) {
    // Mechanism-first (§5): legality is the binding's declared union,
    // taught by THIS node's own props (the file node's edit_actions —
    // the same registry data, stamped by the tick).
    throw NodeEditBounce(
      'action "$action" is not legal for a $fileClass node',
      'legal actions for THIS node (${node.id}): '
          "${binding.actions.join(", ")} — the node's edit_actions prop "
          'carries the same list AND the anchor currency; the registry '
          'teaches the vocabulary, never the format',
    );
  }
  final path = node.path;
  if (path.isEmpty) {
    throw NodeEditBounce(
      'node ${node.id} carries no path prop',
      're-scan the workspace (repo_etl scan) — the tree is stale',
    );
  }
  // The binding resolves the anchor into its DECLARED currency (§3d) —
  // a registry field, not a kind-based special case.
  final anchorValue = binding.resolveAnchor(node.id, node.props, anchor);
  return binding.materializer(
    NodeEditRequest(
      root: fsRoot,
      locks: locks,
      owner: owner,
      path: path,
      action: action,
      anchor: anchorValue,
      body: body,
    ),
  );
}
