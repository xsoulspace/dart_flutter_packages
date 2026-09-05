// ignore_for_file: lines_longer_than_80_chars

/// The `see` seam at scale (ADR 0023 §2): zoom + impact as actor-facing
/// tools over ANY meaning tree.
///
/// R6 proved the workspace-oracle generation path; the repo-scale verdict
/// (results_etl_scale.md) proved the containers hold. This module closes
/// the first R7 gap: an actor INSIDE the loop can query a repo-scale tree
/// through the same registry as every other tool — zoom (ray-cast cut,
/// budgeted) and impact (hard-capped reverse-reference frontier) — instead
/// of an outer agent running scripts.
///
/// Domain-generic by design (ADR 0015): the tools know nothing about Dart
/// or code — they operate on meaning nodes/edges. The dart_meaning host
/// wires them to the code scanner via `repo_etl`.
library;

import 'package:ecsly/ecsly.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show FM, SchemaBundle, ToolDef, ToolName;

import '../meaning/meaning_tree.dart';

/// Host-supplied SPAN reader (ADR 0024, as amended: text enters model
/// context ONLY as a budgeted span cut under a meaning anchor — never as a
/// whole file, never as line windows). A node whose props declare a source
/// span (`path` + `span_start`/`span_end`) is a span-bearing node; on a
/// `point` zoom the host reader serves that span's text, budget-clamped,
/// with the green-screen fact. The core stays fs-blind (ADR 0015); the
/// host closes over the jail and returns NAMED bounces, never silent
/// degradation. The model works with MEANING: files are ETL'd into
/// section/keypath nodes (the map half of the materializer spec), and the
/// model reads one anchor's span at a time — at any file size.
typedef MeaningSpanReader = Map<String, Object?>? Function(
  Map<String, dynamic> nodeProps,
  int budgetTokens,
);

/// `meaning_zoom`: a budgeted cut of the tree — the actor's READ verb at
/// scale (replaces file reads in the meaning profile; ADR 0023 §1).
///
/// Params: `query` (facet ray-cast), `focusId` (start node), `zoom`
/// (point/local/region/summary — the CLOSED ADR 0018 vocabulary), `budget`
/// (token cap, default 2048), `maxNodes`. Every response carries the
/// green-screen fact (`total`, `truncated`) — what the actor does NOT see
/// is explicit.
///
/// Span cuts (fs tier, ADR 0024): `zoom=point` on a span-bearing node
/// (`section`/`key` — the ETL'd map of an md/yaml/json file) attaches that
/// span's text to the cut, budget-bounded by the host [spanReader]. Files
/// without a map expose only structural facts — text never enters context
/// outside a meaning anchor.
ToolDef meaningZoomTool(World world, {MeaningSpanReader? spanReader}) => ToolDef.encode(
      name: const ToolName('meaning_zoom'),
      description:
          'Budgeted cut of the meaning tree. zoom=point (focus + edges; '
          'a section/keypath anchor also yields its text span, budgeted), '
          'local (1-hop — a file shows its outline), region, summary. '
          'The map-graph IS the search.',
      argsSchema: SchemaBundle(
        root: FM.object('meaning_zoom', properties: () => [
              FM.prop('query', FM.string(), optional: true),
              FM.prop('focusId', FM.string(), optional: true),
              FM.prop(
                'zoom',
                FM.enum_('zoom', meaningZoomLevels),
                optional: true,
              ),
              FM.prop('budget', FM.integer(), optional: true),
              FM.prop('maxNodes', FM.integer(), optional: true),
            ]),
      ),
      execute: (args) async {
        final map = args is Map ? args : const {};
        final index = world.getResource<MeaningIndex>();
        final focus = map['focusId'] is String ? map['focusId'] as String : null;
        final query = map['query'] is String ? map['query'] as String : null;
        if (focus == null && query == null) {
          return {
            'error': 'meaning_zoom requires focusId or query',
            'total': index.nodeCount,
          };
        }
        if (focus != null && !index.byId.containsKey(focus)) {
          // Fail with navigable data: suggest ids by suffix match.
          final hints = [
            for (final id in index.byId.keys)
              if (focus.length > 3 && id.contains(focus)) id,
          ].take(5).toList();
          return {
            'error': 'unknown focusId: $focus',
            'hints': hints,
            'total': index.nodeCount,
          };
        }
        final zoomLevel = map['zoom'] is String ? map['zoom'] as String : 'local';
        final budget = map['budget'] is int ? map['budget'] as int : 2048;
        final cut = meaningCut(
          world,
          query: query,
          focusIds: [?focus],
          zoom: zoomLevel,
          maxNodes: map['maxNodes'] is int ? map['maxNodes'] as int : 48,
          tokenBudget: budget,
        );
        final result = <String, Object?>{
          'ok': true,
          'cut': cut,
          'tree_nodes': index.nodeCount,
          'tree_edges': index.edgeCount,
        };
        // Span cut (fs tier): a POINT zoom on a span-bearing node serves
        // that anchor's text as a budgeted projection — text as meaning,
        // never a whole file (ADR 0024, as amended).
        if (zoomLevel == 'point' && focus != null) {
          final entity = index.entityOf(focus);
          final props = meaningComponentOf<MeaningProps>(world, entity!)?.props;
          if (props != null &&
              props.containsKey('span_start') &&
              props.containsKey('span_end')) {
            final reader = spanReader;
            if (reader == null) {
              result['span'] = {
                'ok': false,
                'error': 'span_reader_unavailable',
                'hint': 'this session has no span read surface',
              };
            } else {
              result['span'] = reader(props, budget);
            }
          }
        }
        return result;
      },
    );

/// `meaning_impact`: the hard-capped, degree-ranked reverse-reference
/// frontier of a node — the deterministic decomposition input (ADR 0009).
/// The model never receives an unbounded frontier (scale finding: real
/// frontiers reach 1,000+ nodes; the cap is enforced server-side).
ToolDef meaningImpactTool(World world) => ToolDef.encode(
      name: const ToolName('meaning_impact'),
      description:
          'Impact frontier of a node: which symbols/files reference it, '
          'ranked by reference degree, HARD-CAPPED. This is your '
          'decomposition input for any change — plan from it, never guess.',
      argsSchema: SchemaBundle(
        root: FM.object('meaning_impact', properties: () => [
              FM.prop('focusId', FM.string()),
              FM.prop('depth', FM.integer(), optional: true),
              FM.prop('maxNodes', FM.integer(), optional: true),
            ]),
      ),
      execute: (args) async {
        final map = args is Map ? args : const {};
        final focus = map['focusId'];
        if (focus is! String || focus.isEmpty) {
          return {'error': 'meaning_impact requires focusId'};
        }
        final index = world.getResource<MeaningIndex>();
        if (!index.byId.containsKey(focus)) {
          return {'error': 'unknown focusId: $focus'};
        }
        final depth = map['depth'] is int ? map['depth'] as int : 2;
        final maxNodes = map['maxNodes'] is int ? map['maxNodes'] as int : 64;
        final frontier = impactFrontier(world, focus, maxDepth: depth, maxNodes: maxNodes);
        final ranked = [
          for (final id in frontier)
            {
              'id': id,
              'degree': index.adjacency[id]?.length ?? 0,
            },
        ]..sort((a, b) => (b['degree']! as int).compareTo(a['degree']! as int));
        return {
          'ok': true,
          'focus': focus,
          'frontier': ranked,
          'capped': ranked.length >= maxNodes,
        };
      },
    );
