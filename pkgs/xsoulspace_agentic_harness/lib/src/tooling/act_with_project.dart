// ignore_for_file: lines_longer_than_80_chars

/// `act_with_project` — the structured-edit seam (the "model picks a tiny
/// move over the MEANING, not the AST" surface).
///
/// The meaning tree lives as **ECS world state** (`meaning/meaning_tree.dart`):
/// nodes are entities, edges/props are components. This tool is a thin view
/// over it — the model's whole skill is picking one sub-action from a closed
/// enum; every move returns a *budgeted cut* of the tree (projection law),
/// never the whole graph. The AST / code is an internal materialization
/// detail owned by the host's [materialize] program.
///
/// `Agent = G ∘ F` holds: the model ONLY emits a small enum selection; the
/// harness maps selection → (pure materialize) → bytes → (run oracle) →
/// evidence. Deterministic, LLM-free testable.
library;

import 'package:ecsly/ecsly.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show FM, SchemaBundle, ToolDef, ToolName;

import '../meaning/meaning_tree.dart' as mt;

// ---------------------------------------------------------------------------
// Sub-actions (closed enum). The model's whole skill is picking one.
// ---------------------------------------------------------------------------

const actActionCases = <String>[
  'list',
  'add',
  'link',
  'set_prop',
  'materialize',
];

/// ONE tool whose sub-action is an [FM.enum_] — countable + benchmarkable.
///
/// [world] carries the meaning tree (Stage F: nodes are entities). The
/// `list` sub-action (and every move's `view`) is a **budgeted cut** of the
/// tree — `total` reports the true size and `truncated` the green-screen
/// fact — so a 100k-node tree never floods a 2–4k context.
ToolDef actWithProjectTool({
  required World world,
  required Future<Map<String, dynamic>> Function() materialize,
  int cutMaxNodes = 64,
  int cutTokenBudget = 2048,
}) => ToolDef.encode(
  name: const ToolName('act_with_project'),
  description:
      'Act on the project as a small graph of concepts (nodes + links). '
      'Sub-actions (pick one): '
      'list (see the project — zoom: point = one node, local = neighborhood, '
      'region = wide, summary = the whole picture without details); '
      'add (add a node: give kind + label); '
      'link (connect two nodes: from/relation/to); '
      'set_prop (set a node property: id/key/value); '
      'materialize (a host program turns this into runnable source). '
      'Every move answers with just what changed; use list to zoom out. '
      'You never write text/code or see an AST.',
  argsSchema: SchemaBundle(root: FM.object('act', properties: () => [
    FM.prop('action', FM.enum_('action', actActionCases)),
    FM.prop('zoom', FM.enum_('zoom', mt.meaningZoomLevels), optional: true),
    FM.prop('query', FM.string(), optional: true),
    FM.prop('kind', FM.string(), optional: true),
    FM.prop('label', FM.string(), optional: true),
    FM.prop('from', FM.string(), optional: true),
    FM.prop('relation', FM.string(), optional: true),
    FM.prop('to', FM.string(), optional: true),
    FM.prop('id', FM.string(), optional: true),
    FM.prop('key', FM.string(), optional: true),
    FM.prop('value', FM.string(), optional: true),
  ])),
  execute: (args) async {
    final map = args is Map ? args : const {};
    final action = map['action'];
    // Per-decision projection strategy: a zoomable `list`, while every
    // move ack is a POINT zoom (only what changed) so feedback stays O(1)
    // in the tree size no matter how long the build runs.
    Map<String, dynamic> cut({
      String? focus,
      String? query,
      String zoom = 'local',
    }) => mt.meaningCut(
          world,
          query: query,
          focusIds: [if (focus != null) focus],
          maxNodes: cutMaxNodes,
          tokenBudget: cutTokenBudget,
          zoom: zoom,
        );
    switch (action) {
      case 'list':
        final requested = map['zoom'] is String ? map['zoom'] as String : null;
        final zoom = requested != null &&
                mt.meaningZoomLevels.contains(requested)
            ? requested
            : 'local';
        return cut(
          query: map['query'] is String ? map['query'] as String : null,
          zoom: zoom,
        );
      case 'add':
        final kind = map['kind'];
        final label = map['label'];
        if (kind is! String || label is! String) {
          return {'error': 'add requires kind + label'};
        }
        final entity = mt.addMeaningNode(
          world,
          kind: kind,
          label: label,
          props: map['props'] is Map
              ? (map['props'] as Map).cast<String, dynamic>()
              : const {},
        );
        final node = mt.meaningComponentOf<mt.MeaningNode>(world, entity)!;
        return {
          'ok': true,
          'id': node.id,
          'added': kind,
          'view': cut(focus: node.id, zoom: 'point'),
        };
      case 'link':
        final f = map['from'];
        final r = map['relation'];
        final t = map['to'];
        if (f is! String || r is! String || t is! String) {
          return {'error': 'link requires from + relation + to'};
        }
        final okLink = mt.linkMeaning(world, from: f, relation: r, to: t);
        return okLink
            ? {'ok': true, 'view': cut(focus: f, zoom: 'point')}
            : {'ok': false, 'error': 'unknown node: $f or $t'};
      case 'set_prop':
        final id = map['id'];
        final k = map['key'];
        final v = map['value'];
        if (id is! String || k is! String) {
          return {'error': 'set_prop requires id + key'};
        }
        final okProp = mt.setMeaningProp(world, id: id, key: k, value: v);
        return okProp
            ? {'ok': true, 'view': cut(focus: id, zoom: 'point')}
            : {'ok': false, 'error': 'unknown node: $id'};
      case 'materialize':
        return await materialize();
      default:
        return {'error': 'unknown action: $action'};
    }
  },
);

/// The closed sub-action list, exported for surface measurement/benchmarking.
const actWithProjectSubActions = actActionCases;
