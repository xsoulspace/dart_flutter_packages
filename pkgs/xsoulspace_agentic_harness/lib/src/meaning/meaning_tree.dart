// ignore_for_file: lines_longer_than_80_chars

/// The meaning tree as ECS world state (PLAN Stage F / decision D1).
///
/// Meaning nodes are **entities**; edges and props are **components**. The
/// tree is never loaded whole: [meaningCut] projects only the frontier the
/// current decision needs (focus neighborhood + keyword ray-cast hits),
/// under a token budget — the same law as memory beats. Beats reference the
/// tree through their indexed content; the tree itself is world truth, never
/// actor memory.
///
/// Invariants:
/// - The model never sees [MeaningNode]/[MeaningProps]/[MeaningEdge]
///   directly; it reads the budgeted cut returned by `list` / after each
///   move.
/// - [MeaningIndex] is a *derived* index (like [FacetIndex]): rebuilt from
///   components on snapshot restore, never source-of-truth.
/// - No deletions in V1 — stable ids (`kind_N`) are append-only, which keeps
///   the index simple and ids monotonic.
library;

import 'package:ecsly/ecsly.dart';

import '../narrative/facet_index.dart' show FacetIndex;
import '../systems/projection/relevance.dart' show keywordsOf;

// ---------------------------------------------------------------------------
// Components — the tree's truth lives in the world, not in a closure
// ---------------------------------------------------------------------------

/// A meaning node: the stable, model-facing handle is [id] (`kind_N`).
class MeaningNode implements Component {
  const MeaningNode({
    required this.id,
    required this.kind,
    required this.label,
  });
  final String id;
  final String kind;
  final String label;
}

/// Properties of a meaning node (mutable map component).
class MeaningProps implements Component {
  const MeaningProps([Map<String, dynamic>? props]) : props = props ?? const {};
  final Map<String, dynamic> props;
}

/// A directed, labelled edge between two meaning nodes (entity refs).
class MeaningEdge implements Component {
  const MeaningEdge({
    required this.from,
    required this.relation,
    required this.to,
  });
  final Entity from;
  final String relation;
  final Entity to;
}

// ---------------------------------------------------------------------------
// MeaningIndex — derived, rebuildable, like FacetIndex
// ---------------------------------------------------------------------------

class _EdgeRef {
  const _EdgeRef(this.relation, this.otherId, this.outgoing);
  final String relation;
  final String otherId;
  final bool outgoing;
}

/// Derived index over meaning components: stable-id ↔ entity resolution and
/// adjacency for O(degree) neighborhood cuts. Per-world instance state; never
/// serialized.
class MeaningIndex extends Resource {
  final Map<String, Entity> byId = {};

  /// Per-kind monotonic counters for stable-id assignment (`kind_N`).
  final Map<String, int> kindCounts = {};

  /// Entity → stable id (reverse bookkeeping for edge registration).
  final Map<Entity, String> idsByEntity = {};

  /// Adjacency per stable id (both directions), in write order.
  final Map<String, List<_EdgeRef>> adjacency = {};

  /// All edge triples in write order: (fromId, relation, toId).
  final List<(String, String, String)> triples = [];

  int get nodeCount => byId.length;
  int get edgeCount => triples.length;

  void registerNode(String id, Entity entity) {
    byId[id] = entity;
    idsByEntity[entity] = id;
  }

  void registerEdge(Entity fromEntity, String relation, Entity toEntity) {
    final fromId = idsByEntity[fromEntity];
    final toId = idsByEntity[toEntity];
    if (fromId == null || toId == null) return;
    triples.add((fromId, relation, toId));
    (adjacency[fromId] ??= []).add(_EdgeRef(relation, toId, true));
    (adjacency[toId] ??= []).add(_EdgeRef(relation, fromId, false));
  }

  Entity? entityOf(String id) => byId[id];

  /// Neighbors of [id] as stable ids (both directions), in write order.
  Iterable<String> neighborsOf(String id) =>
      (adjacency[id] ?? const []).map((e) => e.otherId);

  void clear() {
    byId.clear();
    kindCounts.clear();
    idsByEntity.clear();
    adjacency.clear();
    triples.clear();
  }

  /// Removes one edge triple (after its entity is despawned).
  void removeEdge(String from, String relation, String to) {
    triples.remove((from, relation, to));
    adjacency[from]?.removeWhere(
      (r) => r.relation == relation && r.otherId == to && r.outgoing,
    );
    adjacency[to]?.removeWhere(
      (r) => r.relation == relation && r.otherId == from && !r.outgoing,
    );
  }

  /// Removes one node (after its entity is despawned). Edge cleanup is the
  /// caller's job — a node whose edges still reference it has dangling
  /// adjacency entries.
  void removeNode(String id) {
    final entity = byId.remove(id);
    if (entity != null) idsByEntity.remove(entity);
    for (final ref in (adjacency.remove(id) ?? const <_EdgeRef>[])) {
      adjacency[ref.otherId]?.removeWhere(
        (r) => r.relation == ref.relation && r.otherId == id,
      );
    }
    triples.removeWhere((t) => t.$1 == id || t.$3 == id);
  }
}

// ---------------------------------------------------------------------------
// Accessor helpers
// ---------------------------------------------------------------------------

/// Read a component from a plain [Entity] handle (validity-checked).
T? meaningComponentOf<T extends Component>(World world, Entity entity) {
  final (facade, valid) = world.getEntity(entity);
  return valid ? facade.get<T>() : null;
}

MeaningIndex _indexOf(World world) {
  try {
    return world.getResource<MeaningIndex>();
  } on StateError {
    final index = MeaningIndex();
    world.upsertResource(index);
    world.flush();
    return index;
  }
}

/// The facet keywords of one meaning node: kind + label + bounded props
/// text. Shared by the write path and snapshot rebuild so ray-casts are
/// identical in both worlds.
List<String> meaningKeywords(
  String kind,
  String label,
  Map<String, dynamic> props,
) {
  final propsText = props.values.take(4).map((v) => '$v').join(' ');
  final bounded = propsText.length > 300 ? propsText.substring(0, 300) : propsText;
  return keywordsOf('$kind $label $bounded');
}

// ---------------------------------------------------------------------------
// Write API — used by the act_with_project tool and host builders
// ---------------------------------------------------------------------------

/// Adds a meaning node to [world] (entity + props + derived index updates).
///
/// Stable id scheme: `kind_N` with a per-kind monotonic N — `cell_1` is the
/// first cell, always predictable for the model. Hosts importing EXTERNAL
/// structure (e.g. AE canonical feature ids via [planFromSpec]) pass [id]
/// to preserve canonical truth — external ids must not collide with the
/// `kind_N` space (canonical ids contain dots, so they don't).
Entity addMeaningNode(
  World world, {
  required String kind,
  required String label,
  Map<String, dynamic> props = const {},
  String? id,
}) {
  final index = _indexOf(world);
  final n = (index.kindCounts[kind] ?? 0) + 1;
  final stableId = id ?? '${kind}_$n';
  if (index.byId.containsKey(stableId)) {
    throw ArgumentError('meaning node id already exists: $stableId');
  }
  final entity = world.spawnComponents([
    MeaningNode(id: stableId, kind: kind, label: label),
    MeaningProps(Map<String, dynamic>.of(props)),
  ]);
  if (id == null) index.kindCounts[kind] = n;
  index.registerNode(stableId, entity);
  // Facet ray-cast: index kind + label + bounded prop text so `list
  // {query: …}` and projection can find nodes without scanning the tree.
  world.getResource<FacetIndex>().indexBeat(
    entity,
    meaningKeywords(kind, label, props),
  );
  world.flush();
  return entity;
}

/// Links two existing meaning nodes. Returns false (and writes nothing)
/// when either endpoint is unknown.
bool linkMeaning(
  World world, {
  required String from,
  required String relation,
  required String to,
}) {
  final index = _indexOf(world);
  final f = index.entityOf(from);
  final t = index.entityOf(to);
  if (f == null || t == null) return false;
  world.spawnComponents([MeaningEdge(from: f, relation: relation, to: t)]);
  index.registerEdge(f, relation, t);
  world.flush();
  return true;
}

/// Sets a property on a meaning node. Returns false when the node is
/// unknown; the value may be any JSON-encodable scalar/map.
bool setMeaningProp(
  World world, {
  required String id,
  required String key,
  required Object? value,
}) {
  final index = _indexOf(world);
  final entity = index.entityOf(id);
  if (entity == null) return false;
  final props = meaningComponentOf<MeaningProps>(world, entity)?.props;
  if (props == null) return false;
  props[key] = value;
  world.upsertComponent(entity, MeaningProps(props));
  world.flush();
  return true;
}

/// Whether [id] exists in the tree.
bool hasMeaningNode(World world, String id) =>
    _indexOf(world).entityOf(id) != null;

/// HOST PROGRAM (macro support): drops the intent's `impl` chain — the impl
/// edge and every op node reachable through `then` edges — and despawns
/// them. The intent NODE itself is kept (re-define overwrites its props).
/// Returns the number of dropped op nodes. Scoped by design: this is the
/// only deletion in the tree, so a repair macro can rebuild one intent's
/// logic without ever letting the model destroy unrelated structure.
int dropMeaningChain(World world, String intentName) {
  final index = _indexOf(world);
  final intentEntity = index.entityOf(intentName);
  if (intentEntity == null) return 0;

  // Collect the impl entry + everything reachable through `then`.
  String? entry;
  final toDrop = <String>{};
  final toDropEdges = <(String, String, String)>{};
  for (final (f, r, t) in index.triples) {
    if (f == intentName && r == 'impl') entry = t;
  }
  if (entry == null) return 0;
  final queue = <String>[entry];
  while (queue.isNotEmpty) {
    final id = queue.removeLast();
    if (!toDrop.add(id)) continue;
    for (final (f, r, t) in index.triples) {
      if (f == id && r == 'then') {
        toDropEdges.add((f, r, t));
        queue.add(t);
      }
    }
  }

  // Every edge touching a dropped node (impl/then/foreign) goes too.
  for (final (f, r, t) in index.triples) {
    if (toDrop.contains(f) || toDrop.contains(t)) toDropEdges.add((f, r, t));
  }

  // Despawn the edge ENTITIES whose triples touch the chain, then the op
  // entities, then update the derived index. One query pass collects edge
  // entities (they store entity refs; match them back to triples).
  final edgeEntities = <Entity>[];
  for (final (facade, edge) in world.query<MeaningEdge>().toList()) {
    final fid = index.idsByEntity[edge.from];
    final tid = index.idsByEntity[edge.to];
    if (fid == null || tid == null) continue;
    if (toDropEdges.contains((fid, edge.relation, tid))) {
      edgeEntities.add(facade.entity);
    }
  }
  for (final e in edgeEntities) {
    world.commands.despawn(e);
  }
  for (final id in toDrop) {
    final entity = index.entityOf(id);
    if (entity == null) continue;
    world.commands.despawn(entity);
    index.removeNode(id);
  }
  for (final (f, r, t) in toDropEdges) {
    index.removeEdge(f, r, t);
  }
  world.flush();
  return toDrop.length;
}

// ---------------------------------------------------------------------------
// Read API — budgeted cut (projection law) + full view (host materializers)
// ---------------------------------------------------------------------------

/// One node as the model sees it: id / kind / label / props only.
Map<String, dynamic> _nodeJson(MeaningNode node, MeaningProps props) => {
  'id': node.id,
  'kind': node.kind,
  'label': node.label,
  'props': props.props,
};

/// A full, uncut view of the tree for host materializers (pure programs that
/// turn meaning into code). Never handed to the model.
class MeaningView {
  MeaningView(this.nodes, this.edges);
  final List<Map<String, dynamic>> nodes; // id/kind/label/props
  final List<Map<String, dynamic>> edges; // from/relation/to
  int get nodeCount => nodes.length;
  int get edgeCount => edges.length;
}

/// Full snapshot of the tree (host-side; the model only ever gets cuts).
MeaningView meaningView(World world) {
  final index = _indexOf(world);
  final nodes = <Map<String, dynamic>>[];
  for (final entry in index.byId.entries) {
    final node = meaningComponentOf<MeaningNode>(world, entry.value);
    if (node == null) continue;
    final props =
        meaningComponentOf<MeaningProps>(world, entry.value) ??
        const MeaningProps();
    nodes.add(_nodeJson(node, props));
  }
  final edges = [
    for (final (f, r, t) in index.triples) {'from': f, 'relation': r, 'to': t},
  ];
  return MeaningView(nodes, edges);
}

/// Projects a **budgeted cut** of the tree for one decision (F2) — the
/// meaning view under the SAME law as beat projection: relevance-ranked
/// selection, token budget, and the green-screen fact (`total` + `truncated`)
/// of what the model does NOT see. [zoom] is the per-decision strategy knob:
///
/// - `point`   — zoom IN: focus nodes only + their edges (what just changed);
///   per-move feedback stays tiny no matter how big the tree grows.
/// - `local`   — focus + 1-hop neighbors + query ray-cast hits (default).
/// - `region`  — zoom OUT: focus + 2-hop neighborhood.
/// - `summary` — zoom OUT fully: structuralize/destructurize. No node
///   details; kind histogram + edges aggregated by (from --rel--> to) kind.
///   The "bigger picture without details" an overseer actor can hold while
///   a mover actor holds a point zoom — strategies can differ per actor.
///
/// Edges at `point` zoom render with full from/to ids even when the other
/// endpoint is not admitted: ids are stable handles, so the agent can zoom
/// out later and find them.
Map<String, dynamic> meaningCut(
  World world, {
  String? query,
  Iterable<String> focusIds = const [],
  int maxNodes = 64,
  int tokenBudget = 2048,
  String zoom = 'local',
}) {
  final index = _indexOf(world);
  final facet = world.getResource<FacetIndex>();
  final selected = <String>{};
  final zoomLevel = meaningZoomLevels.contains(zoom.trim())
      ? zoom.trim()
      : 'local';

  List<Map<String, dynamic>> nodeJsons(Iterable<String> ids) {
    final out = <Map<String, dynamic>>[];
    for (final id in ids) {
      final entity = index.byId[id];
      if (entity == null) continue;
      final node = meaningComponentOf<MeaningNode>(world, entity);
      if (node == null) continue;
      final props =
          meaningComponentOf<MeaningProps>(world, entity) ??
          const MeaningProps();
      out.add(_nodeJson(node, props));
    }
    return out;
  }

  List<Map<String, dynamic>> edgesJsons(
    Set<String> ids, {
    bool dangling = false,
  }) => [
    for (final (f, r, t) in index.triples)
      if (dangling
          ? ids.contains(f) || ids.contains(t)
          : ids.contains(f) && ids.contains(t))
        {'from': f, 'relation': r, 'to': t},
  ];

  int tokensOf(Map<String, dynamic> cut) =>
      ('${cut['nodes']}${cut['edges']}}'.length / 4).ceil();

  // ---- summary: structuralize/destructurize, early return ----
  if (zoomLevel == 'summary') {
    final kinds = <String, int>{};
    for (final id in index.byId.keys) {
      final entity = index.byId[id];
      if (entity == null) continue;
      final node = meaningComponentOf<MeaningNode>(world, entity);
      if (node == null) continue;
      kinds.update(node.kind, (v) => v + 1, ifAbsent: () => 1);
    }
    final edgeCount = <String, int>{};
    for (final (f, r, t) in index.triples) {
      final key = '${_kindOf(index, world, f)} --$r--> ${_kindOf(index, world, t)}';
      edgeCount.update(key, (v) => v + 1, ifAbsent: () => 1);
    }
    return {
      'zoom': zoomLevel,
      'kinds': kinds,
      'edges': [
        for (final e in edgeCount.entries)
          {'edge': e.key, 'count': e.value},
      ],
      'total': index.nodeCount,
      'truncated': false,
    };
  }

  // ---- node-level zooms: point / local / region ----
  void admit(String id) {
    if (selected.length >= maxNodes) return;
    if (index.byId.containsKey(id)) selected.add(id);
  }

  if (zoomLevel == 'point') {
    for (final focus in focusIds) {
      if (index.byId.containsKey(focus)) selected.add(focus);
    }
    // Zoom IN admits NOTHING else — no neighbors, no ray-cast, no fill.
    // Per-move feedback stays O(1) in the tree size.
    final ordered = selected.toList();
    var cut = {
      'nodes': nodeJsons(ordered),
      'edges': edgesJsons(ordered.toSet(), dangling: true),
      'total': index.nodeCount,
      'truncated': ordered.length < index.nodeCount,
      'zoom': zoomLevel,
    };
    while (tokensOf(cut) > tokenBudget && ordered.length > 1) {
      ordered.removeLast();
      cut = {
        'nodes': nodeJsons(ordered),
        'edges': edgesJsons(ordered.toSet(), dangling: true),
        'total': index.nodeCount,
        'truncated': ordered.length < index.nodeCount,
        'zoom': zoomLevel,
      };
    }
    return cut;
  }

  // Seeds: focus ids (per-move targets) + query ray-cast hits (relevance
  // frontier found through the facet index). The ZOOM decides how wide each
  // seed expands: local = 1-hop, region = 2-hop. Hits are seeds, not just
  // admissions — a ray-cast hit should pull its neighborhood with it.
  final seeds = <String>{};
  for (final focus in focusIds) {
    admit(focus);
    seeds.add(focus);
  }
  if (query != null && query.isNotEmpty) {
    for (final hit in facet.beatsFor(keywordsOf(query))) {
      if (selected.length >= maxNodes) break;
      final id = index.idsByEntity[hit];
      if (id == null) continue;
      admit(id);
      seeds.add(id);
    }
  }
  final radius = zoomLevel == 'region' ? 2 : 1;
  var frontier = seeds.toList();
  for (var hop = 0; hop < radius && frontier.isNotEmpty; hop++) {
    final next = <String>[];
    for (final n in frontier) {
      for (final m in index.neighborsOf(n)) {
        admit(m);
        next.add(m);
      }
    }
    frontier = next;
  }
  // Small-tree fill is a LOCAL-zoom affordance only: when the whole tree
  // fits the cap, the default view shows it whole. region keeps its
  // zoomed-out contract (a wide neighborhood, not everything).
  if (zoomLevel == 'local' && selected.length < maxNodes) {
    final all = index.byId.keys.toList(growable: false);
    for (var i = all.length - 1; i >= 0 && selected.length < maxNodes; i--) {
      selected.add(all[i]);
    }
  }

  var ordered = selected.toList();
  var cut = {
    'nodes': nodeJsons(ordered),
    'edges': edgesJsons(ordered.toSet()),
    'total': index.nodeCount,
    'truncated': ordered.length < index.nodeCount,
    'zoom': zoomLevel,
  };
  while (tokensOf(cut) > tokenBudget && ordered.length > 1) {
    ordered.removeLast();
    cut = {
      'nodes': nodeJsons(ordered),
      'edges': edgesJsons(ordered.toSet()),
      'total': index.nodeCount,
      'truncated': ordered.length < index.nodeCount,
      'zoom': zoomLevel,
    };
  }
  return cut;
}

String _kindOf(MeaningIndex index, World world, String id) {
  final entity = index.byId[id];
  if (entity == null) return '?';
  return meaningComponentOf<MeaningNode>(world, entity)?.kind ?? '?';
}

/// The model-facing closed zoom vocabulary (D3: closed enum over meaning
/// surfaces). `point`/`local` zoom in on the frontier; `region` widens;
/// `summary` shows the bigger picture without details.
const meaningZoomLevels = <String>['point', 'local', 'region', 'summary'];
