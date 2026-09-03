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

/// `meaning_zoom`: a budgeted cut of the tree — the actor's READ verb at
/// scale (replaces file reads in the meaning profile; ADR 0023 §1).
///
/// Params: `query` (facet ray-cast), `focusId` (start node), `zoom`
/// (point/local/region/summary), `budget` (token cap, default 2048),
/// `maxNodes`. Every response carries the green-screen fact (`total`,
/// `truncated`) — what the actor does NOT see is explicit.
ToolDef meaningZoomTool(World world) => ToolDef.encode(
      name: const ToolName('meaning_zoom'),
      description:
          'Cut a bounded view of the meaning tree (the code/requirement '
          'graph of this world). zoom=point (focus node + its edges), '
          'local (1-hop), region (2-hop), summary (structure counts). '
          'This is how you READ structure at any scale — no file reads.',
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
        final cut = meaningCut(
          world,
          query: query,
          focusIds: [?focus],
          zoom: map['zoom'] is String ? map['zoom'] as String : 'local',
          maxNodes: map['maxNodes'] is int ? map['maxNodes'] as int : 48,
          tokenBudget:
              map['budget'] is int ? map['budget'] as int : 2048,
        );
        return {
          'ok': true,
          'cut': cut,
          'tree_nodes': index.nodeCount,
          'tree_edges': index.edgeCount,
        };
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
