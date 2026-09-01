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

import '../meaning/meaning_program.dart' show validateMeaningProgram;
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
  // Macro sub-actions (D3 gate fired, ADR 0018): composite moves implemented
  // as host programs. The model picks ONE selection with structured params;
  // the host does the heavy lifting. Intent-level repair lives on
  // intent_define (action `redefine_chain`) — one verb per domain, no
  // near-tool collisions (ADR 0016).
  'add_chain',
  'link_chain',
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
      'Sub-actions: list (zoom: point/local/region/summary); add (kind + '
      'label, optional stable id); link (from/relation/to); set_prop '
      '(id/key/value); materialize (host turns the tree into runnable '
      'source); add_chain (whole op chain: specs=[{label, a?, b?, next?, '
      '\'b\': "#row" for jumps}]); link_chain (edges=[{from, relation, '
      'to}]). Answers carry just what changed. Intent-level definition + '
      'repair lives on intent_define (action define, requires specs).',
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
    // Macro params: structured, host-interpreted.
    FM.prop('specs', FM.array(FM.object('spec', properties: () => [
      FM.prop('label', FM.string()),
      FM.prop('a', FM.string(), optional: true),
      FM.prop('b', FM.string(), optional: true),
    ])), optional: true),
    FM.prop('edges', FM.array(FM.object('edge', properties: () => [
      FM.prop('from', FM.string()),
      FM.prop('relation', FM.string()),
      FM.prop('to', FM.string()),
    ])), optional: true),
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
          focusIds: [?focus],
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
          // Optional stable id (B1): pins a node id (e.g. an intent node
          // whose id MUST be the intent name so intent_call resolves it).
          // Duplicate ids fail loudly (ArgumentError) — never a silent
          // overwrite.
          id: map['id'] is String && (map['id'] as String).isNotEmpty
              ? map['id'] as String
              : null,
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
        return materialize();

      // ---- Macros (J1): one selection, host does the heavy lifting ----
      case 'add_chain':
        final specs = map['specs'];
        if (specs is! List || specs.isEmpty) {
          return {'error': 'add_chain requires specs: [{label, a?, b?}]'};
        }
        final ids = _addChain(world, specs);
        if (ids == null) {
          return {'error': 'add_chain spec requires label (string)'};
        }
        return {
          'ok': true,
          'ids': ids,
          'added': ids.length,
          'view': cut(focus: ids.first, zoom: 'point'),
          'problems': validateMeaningProgram(world),
        };
      case 'link_chain':
        final edges = map['edges'];
        if (edges is! List || edges.isEmpty) {
          return {'error': 'link_chain requires edges: [{from, relation, to}]'};
        }
        final results = <Map<String, dynamic>>[];
        String? lastFrom;
        for (final e in edges) {
          if (e is! Map) {
            results.add({'error': 'edge must be an object'});
            continue;
          }
          final em = e;
          final f = em['from'];
          final r = em['relation'];
          final t = em['to'];
          if (f is! String || r is! String || t is! String) {
            results.add({'error': 'edge requires from + relation + to'});
            continue;
          }
          final ok = mt.linkMeaning(world, from: f, relation: r, to: t);
          results.add({'from': f, 'relation': r, 'to': t, 'ok': ok});
          if (ok) lastFrom = f;
        }
        return {
          'ok': results.every((r) => r['ok'] == true),
          'results': results,
          if (lastFrom != null) 'view': cut(focus: lastFrom, zoom: 'point'),
        };
      default:
        return {'error': 'unknown action: $action'};
    }
  },
);

/// Macro helper: two-pass build. Pass 1 spawns the op nodes for [specs];
/// pass 2 wires `then` edges — spec[i] → spec[spec[i].next ?? i+1] — and
/// resolves jump targets of the form `b: '#<index>'` to the spawned stable
/// id of spec[<index>]. Declarative by design: the model emits a TABLE of
/// rows with row-relative references; the host tracks every id. Returns
/// the assigned ids in spec order, or null if any spec is malformed
/// (nothing spawned when [dryRun]).
List<String>? _addChain(World world, List specs, {bool dryRun = false}) {
  final parsed = <({String label, String? a, String? b, int? next})>[];
  for (final s in specs) {
    if (s is! Map) return null;
    final label = s['label'];
    if (label is! String || label.isEmpty) return null;
    final next = s['next'] is int ? s['next'] as int : null;
    parsed.add((
      label: label,
      a: s['a'] is String ? s['a'] as String : null,
      b: s['b'] is String ? s['b'] as String : null,
      next: next == null || (next >= 0 && next < specs.length) ? next : null,
    ));
  }
  if (dryRun) return const ['ok'];

  // Pass 1: spawn (b kept raw — jump targets resolve after all ids exist).
  final ids = <String>[];
  final rawB = <String?>[];
  for (final spec in parsed) {
    final entity = mt.addMeaningNode(
      world,
      kind: 'op',
      label: spec.label,
      props: {
        if (spec.a != null) 'a': spec.a,
      },
    );
    final node = mt.meaningComponentOf<mt.MeaningNode>(world, entity)!;
    ids.add(node.id);
    rawB.add(spec.b);
  }

  // Pass 2: write `b` props (resolving `#<index>` jump targets to the
  // spawned stable id), then wire `then` edges.
  for (var i = 0; i < parsed.length; i++) {
    final b = rawB[i];
    if (b != null) {
      var resolved = b;
      if (b.startsWith('#')) {
        final ref = int.tryParse(b.substring(1));
        resolved = (ref != null && ref >= 0 && ref < ids.length) ? ids[ref] : b;
      }
      mt.setMeaningProp(world, id: ids[i], key: 'b', value: resolved);
    }
    final target = parsed[i].next ?? i + 1;
    if (target < ids.length) {
      mt.linkMeaning(world, from: ids[i], relation: 'then', to: ids[target]);
    }
  }
  return ids;
}

/// The closed sub-action list, exported for surface measurement/benchmarking.
const actWithProjectSubActions = actActionCases;
