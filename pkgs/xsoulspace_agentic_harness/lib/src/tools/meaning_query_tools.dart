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

/// Host-supplied SINGLE-NODE refresher (PLAN §NOW "Zoom staleness"): on a
/// `point` zoom of a file-bearing node (a non-empty `path` prop — file /
/// section / key), the tool calls this BEFORE serving the cut, so a
/// just-edited file never serves pre-edit text while the tree lags. The
/// host stats the underlying file (mtime + size) and, only when the
/// node's recorded props differ, re-derives that ONE node from disk — one
/// stat plus at most one small re-read, never a tree-wide rebuild. The
/// core stays fs-blind (ADR 0015): the same host-closes-over-the-jail
/// shape as [MeaningSpanReader]. Returns named data when a refresh fired
/// (e.g. `{'refreshed': true, 'file_node': …}`) or null when the node was
/// already current — the common case costs exactly one stat.
typedef MeaningNodeRefresher = Map<String, Object?>? Function(
  String focusId,
  Map<String, dynamic> nodeProps,
);

/// The refresher as WORLD data: the workspace registers it once (in the
/// same registration pass that wires the fs capabilities), and EVERY
/// [meaningZoomTool] built over the world — harness, daemon, host — picks
/// it up with no constructor change.
class MeaningNodeRefresh extends Resource {
  MeaningNodeRefresh(this.refresh);

  final MeaningNodeRefresher refresh;
}

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
        var zoomLevel = map['zoom'] is String ? map['zoom'] as String : 'local';
        final budget = map['budget'] is int ? map['budget'] as int : 2048;
        // Tiny-model guard (measured: a keyword ray-cast sent as zoom=point
        // silently returned an EMPTY cut — point admits focus ids only and
        // ignores the query, so the actor looped on nothing). A query-only
        // point zoom is auto-served as the ray-cast it obviously is:
        // zoom=local, with the degradation named in the result.
        String? degradedNote;
        if (zoomLevel == 'point' && focus == null && query != null) {
          zoomLevel = 'local';
          degradedNote =
              'point zoom requires a valid focusId — the query ray-cast '
              'was served as zoom=local (pick an id from the cut, then '
              'point-zoom it for the span)';
        }
        // Zoom staleness (PLAN §NOW): a POINT zoom of a file-bearing node
        // re-stats the underlying file through the host refresher BEFORE
        // the cut — a just-edited file must never serve pre-edit text.
        // Bounded: one stat + at most one small re-read, ONE node, never a
        // tree-wide rebuild. Failures are named, never fatal (the span
        // reader bounces on its own); a missing refresher (no workspace
        // wired) costs nothing.
        var effectiveFocus = focus;
        String? refreshedPath;
        String? refreshError;
        if (zoomLevel == 'point' && effectiveFocus != null) {
          final refresher = world.maybeGetResource<MeaningNodeRefresh>();
          if (refresher != null) {
            final entity = index.entityOf(effectiveFocus);
            final props = entity == null
                ? null
                : meaningComponentOf<MeaningProps>(world, entity)?.props;
            final path = props?['path'];
            if (props != null && path is String && path.isNotEmpty) {
              Map<String, Object?>? refresh;
              try {
                refresh = refresher.refresh(effectiveFocus, props);
              } on Object catch (e) {
                refreshError = '$e';
              }
              if (refresh != null) {
                refreshedPath = path;
                if (refresh['error'] is String) {
                  refreshError = refresh['error'] as String;
                } else if (!index.byId.containsKey(effectiveFocus)) {
                  // The anchor was re-derived (an ordinal/keypath shifted
                  // under the edit): fall back to its file node — the cut
                  // stays navigable, never dead.
                  final fileNode = refresh['file_node'];
                  if (fileNode is String && index.byId.containsKey(fileNode)) {
                    degradedNote = 'focus anchor was re-derived after the '
                        'staleness refresh — the cut serves the file node '
                        '($fileNode)';
                    effectiveFocus = fileNode;
                  }
                }
              }
            }
          }
        }
        final cut = meaningCut(
          world,
          query: query,
          focusIds: [?effectiveFocus],
          zoom: zoomLevel,
          maxNodes: map['maxNodes'] is int ? map['maxNodes'] as int : 48,
          tokenBudget: budget,
        );
        final result = <String, Object?>{
          'ok': true,
          'cut': cut,
          // Echo the cut's inputs so an empty cut is ATTRIBUTABLE (the
          // operator — and the model — see what was actually searched).
          'query': ?query,
          'focusId': ?focus,
          'tree_nodes': index.nodeCount,
          'tree_edges': index.edgeCount,
          'note': ?degradedNote,
          // The staleness fact: WHICH file was re-derived to serve this
          // cut (the green-screen law — what the host did is explicit).
          if (refreshedPath != null) 'refreshed': true,
          if (refreshedPath != null) 'refreshed_path': refreshedPath,
          if (refreshError != null) 'refresh_error': refreshError,
        };
        // Empty ray-cast → navigable, never a dead end: suggest ids whose
        // path/kind text contains any query token (the same repair-hint
        // pattern as the unknown-focusId bounce).
        final nodes = cut['nodes'];
        if (nodes is List && nodes.isEmpty && query != null) {
          final tokens = query
              .toLowerCase()
              .split(RegExp(r'[^a-z0-9_]+'))
              .where((t) => t.length > 2)
              .toSet();
          final hints = [
            for (final id in index.byId.keys)
              if (tokens.any(id.toLowerCase().contains)) id,
          ].take(8).toList();
          result['empty_ray_cast'] = true;
          result['hints'] = hints;
          result['hint'] =
              'the query matched no nodes — try tokens from these ids, or '
              'zoom=summary for the shape of the tree';
        }
        // Span cut (fs tier): a POINT zoom on a span-bearing node serves
        // that anchor's text as a budgeted projection — text as meaning,
        // never a whole file (ADR 0024, as amended).
        if (zoomLevel == 'point' && effectiveFocus != null) {
          // Props are read AFTER the staleness refresh — the span served
          // is the POST-edit span by construction.
          final entity = index.entityOf(effectiveFocus);
          final props = entity == null
              ? null
              : meaningComponentOf<MeaningProps>(world, entity)?.props;
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
