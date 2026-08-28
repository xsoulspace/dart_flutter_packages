// ignore_for_file: lines_longer_than_80_chars

/// Structured-edit seam (the "model picks a tiny move over the MEANING, not
/// the AST" surface).
///
/// The AST is an *internal mechanism*, hidden and replaceable (Dart DTD, the
/// analyzer, AE CanonicalMatrix, a boolean-circuit, whatever). The model
/// talks to a tiny, stable, **project-shaped** protocol:
///
///    list         — what nodes/links exist today
///    add          — add a node of a kind you name (e.g. a cell, a move)
///    link         — connect two existing nodes (board -> cell)
///    set_prop     — set a property on a node (e.g. cell marker = X)
///    materialize  — a host program turns this model into runnable source
///
/// `Agent = G ∘ F` holds: the model ONLY emits a small enum selection; the
/// harness maps selection -> (pure materialize) -> bytes -> (run oracle) ->
/// evidence. Deterministic, LLM-free testable.
library;

import 'dart:convert';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show FM, SchemaBundle, ToolDef, ToolName;

// ---------------------------------------------------------------------------
// The project model (internal) — nodes + edges + props. The model never sees
// this shape directly; it only ever reads `list`'s output.
// ---------------------------------------------------------------------------

class ModelNode {
  ModelNode({
    required this.id,
    required this.kind,
    required this.label,
    Map<String, dynamic> props = const {},
  }) : props = Map<String, dynamic>.of(props);
  final String id;
  final String kind;
  final String label;
  Map<String, dynamic> props;

  Map<String, dynamic> toJson() =>
    {'id': id, 'kind': kind, 'label': label, 'props': props};
}

class StructuredDoc {
  final nodes = <String, ModelNode>{};
  final edges = <(String, String, String)>[]; // (from, relation, to)

  ModelNode add({required String kind, required String label}) {
    final id = '${kind}_${nodes.length + 1}';
    final n = ModelNode(id: id, kind: kind, label: label);
    nodes[id] = n;
    return n;
  }

  void link(String from, String relation, String to) {
    edges.add((from, relation, to));
  }

  String listJson() => jsonEncode({
    'nodes': [for (final n in nodes.values) n.toJson()],
    'edges': [
      for (final (f, r, t) in edges) {'from': f, 'relation': r, 'to': t},
    ],
  });
}

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
ToolDef actWithProjectTool({
  required StructuredDoc Function() doc,
  required Future<Map<String, dynamic>> Function() materialize,
}) => ToolDef.encode(
  name: const ToolName('act_with_project'),
  description:
      'Act on the project as a small graph of concepts (nodes + links). '
      'Sub-actions (pick one): '
      'list (see current nodes/edges); '
      'add (add a node: give kind + label); '
      'link (connect two nodes: from/relation/to); '
      'set_prop (set a node property: id/key/value); '
      'materialize (a host program turns this into runnable source). '
      'You never write text/code or see an AST.',
  argsSchema: SchemaBundle(root: FM.object('act', properties: () => [
    FM.prop('action', FM.enum_('action', actActionCases)),
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
    final d = doc();
    switch (action) {
      case 'list':
        // decode list back to a map so ToolDef.encode can re-encode uniformly
        return jsonDecode(d.listJson()) as Map<String, dynamic>;
      case 'add':
        final kind = map['kind'];
        final label = map['label'];
        if (kind is! String || label is! String) {
          return {'error': 'add requires kind + label'};
        }
        final n = d.add(kind: kind, label: label);
        return {
          'ok': true,
          'id': n.id,
          'added': kind,
          'doc': jsonDecode(d.listJson()),
        };
      case 'link':
        final f = map['from'];
        final r = map['relation'];
        final t = map['to'];
        if (f is String && r is String && t is String) d.link(f, r, t);
        return {'ok': true, 'doc': jsonDecode(d.listJson())};
      case 'set_prop':
        final id = map['id'];
        final k = map['key'];
        final v = map['value'];
        final node = id is String ? d.nodes[id] : null;
        if (node != null && k is String && v != null) node.props[k] = v;
        return {'ok': node != null, 'doc': jsonDecode(d.listJson())};
      case 'materialize':
        return await materialize();
      default:
        return {'error': 'unknown action: $action'};
    }
  },
);

/// The closed sub-action list, exported for surface measurement/benchmarking.
const actWithProjectSubActions = actActionCases;