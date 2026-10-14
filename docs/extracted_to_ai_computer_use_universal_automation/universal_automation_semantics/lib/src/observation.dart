import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'semantic_view.dart';

/// One node as an observation shows it: the family node plus the ref
/// this observation issued for it and its pane membership.
final class ObservedNode {
  const ObservedNode._(this.ref, this.node, this.pane, this.offsetDepth);

  /// The observation-scoped ref (`s_N`, or `<pane>.s_N` inside a pane).
  final String ref;

  /// The family node.
  final AxNode node;

  /// The pane that showed this node; `null` for the main view.
  final String? pane;

  /// Render indent depth (0 at the deepest shown root of its section).
  final int offsetDepth;
}

/// A view resolved against one live snapshot — the managed instance
/// layer (the [SemanticView] is the declaration; this is what the
/// renderer manages, the way elements manage widgets).
///
/// Construction assigns refs over the **full** walk in document order
/// (`s_N`; each pane renumbers its own subtree as `<pane>.s_N`), then
/// applies the view to decide what is shown. Trimming hides rows and
/// says so in the header; it never renumbers. A ref stays resolvable
/// for the lifetime of this observation; against a NEWER observation
/// stale refs fail closed with [SemanticRefUnavailableException] —
/// reobserve, never guess.
final class Observation {
  Observation._(
    this.snapshot,
    this.view,
    this._nodes,
    this._byRef,
    this.walkedCount,
    this.trimmed,
  );

  /// Resolves [view] against [snapshot].
  factory Observation.of(Snapshot snapshot, SemanticView view) {
    // One full walk, document order; index i IS main-walk ref `s_i`.
    final walk = <AxNode>[];
    final depthOf = <int>[];
    void visit(AxNode node, int depth) {
      walk.add(node);
      depthOf.add(depth);
      for (final child in node.children) {
        visit(child, depth + 1);
      }
    }

    for (final root in snapshot.roots) {
      visit(root, 0);
    }

    final nodes = <ObservedNode>[];
    final byRef = <String, ObservedNode>{};
    var walkedCount = walk.length;
    var trimmed = false;

    void showSection(
      SemanticView section,
      int start,
      int end, // exclusive; over `walk` for the main view.
      String? pane,
    ) {
      final prefix = section.identifierPrefix;
      final matched = [
        for (var i = start; i < end; i++)
          if (prefix == null ||
              (walk[i].attributes['identifier'] ?? '').startsWith(prefix))
            i,
      ];
      if (section.maxNodes != null && matched.length > section.maxNodes!) {
        trimmed = true;
      }
      // Refs are ISSUED for every walked node of the section (trimming
      // and field filters are display concerns); only the capped prefix
      // is SHOWN.
      for (var local = 0; local < matched.length; local++) {
        final i = matched[local];
        final ref = pane == null ? 's_$i' : '$pane.s_${i - start}';
        byRef[ref] ??= ObservedNode._(ref, walk[i], pane, 0);
      }
      final shown = section.maxNodes == null
          ? matched
          : matched.take(section.maxNodes!).toList(growable: false);
      final offset = shown.isEmpty ? 0 : depthOf[shown.first];
      for (var local = 0; local < shown.length; local++) {
        final i = shown[local];
        final ref = pane == null ? 's_$i' : '$pane.s_${i - start}';
        nodes.add(ObservedNode._(ref, walk[i], pane, depthOf[i] - offset));
      }
    }

    // Main view. Its own subtreeOf resolves against the full walk; an
    // unresolvable selector shows an empty section (loud), while the
    // numbering base stays the full walk.
    final mainRoot = _selectorIndex(walk, view.subtreeOf);
    if (mainRoot != null) {
      showSection(view, mainRoot, _subtreeEnd(walk, depthOf, mainRoot), null);
    } else if (view.subtreeOf == null) {
      showSection(view, 0, walk.length, null);
    }
    // Refs are positional identities of the full walk: issue `s_N` for
    // EVERY node, including ones the view's subtreeOf excludes —
    // showing is a render concern, resolution is not.
    for (var i = 0; i < walk.length; i++) {
      byRef['s_$i'] ??= ObservedNode._('s_$i', walk[i], null, 0);
    }

    // Panes: named sub-views over the same snapshot, each numbering its
    // own walk (`<pane>.s_N` over the pane's range). A pane selector
    // naming an absent node renders an empty section — loud, not a
    // silent fallback to the whole surface.
    for (final entry in view.panes.entries) {
      final paneView = entry.value;
      final rootIndex = _selectorIndex(walk, paneView.subtreeOf);
      if (rootIndex != null) {
        final end = _subtreeEnd(walk, depthOf, rootIndex);
        showSection(paneView, rootIndex, end, entry.key);
        walkedCount += end - rootIndex;
      } else if (paneView.subtreeOf == null) {
        showSection(paneView, 0, walk.length, entry.key);
        walkedCount += walk.length;
      }
    }

    return Observation._(snapshot, view, nodes, byRef, walkedCount, trimmed);
  }

  /// The snapshot this observation resolved.
  final Snapshot snapshot;

  /// The view this observation resolved through.
  final SemanticView view;

  final List<ObservedNode> _nodes;
  final Map<String, ObservedNode> _byRef;

  /// Nodes the full walks visited (main + panes) — the numbering base.
  final int walkedCount;

  /// Whether any section's view asked for more than its `maxNodes`.
  final bool trimmed;

  /// Shown nodes in render order (main view first, then panes).
  List<ObservedNode> get nodes => List.unmodifiable(_nodes);

  /// Resolves [ref] against this observation; stale or unknown refs
  /// fail closed with [SemanticRefUnavailableException].
  ObservedNode resolve(String ref) {
    final observed = _byRef[ref];
    if (observed == null) {
      throw SemanticRefUnavailableException(ref, snapshot.revision);
    }
    return observed;
  }

  /// Grounds a surface point back to a ref: the walked node whose
  /// bounds contain ([x], [y]), smallest area first — the innermost
  /// answer wins (the observe-at-point grounding aid, ADR 0053).
  ///
  /// This is *bounds* grounding, not pixel grounding: it reads the
  /// tree's own geometry, so it needs no screenshots. A point no walked
  /// node covers — or a tier that publishes no bounds — fails closed
  /// with [SemanticRefUnavailableException] (reobserve, never guess).
  ObservedNode nodeAt(double x, double y) {
    ObservedNode? best;
    var bestArea = double.infinity;
    for (final observed in _byRef.values) {
      final bounds = observed.node.bounds;
      if (bounds == null) continue;
      final contains =
          x >= bounds.left &&
          x <= bounds.left + bounds.width &&
          y >= bounds.top &&
          y <= bounds.top + bounds.height;
      if (!contains) continue;
      final area = bounds.width * bounds.height;
      if (area < bestArea) {
        best = observed;
        bestArea = area;
      }
    }
    if (best == null) {
      throw SemanticRefUnavailableException('point($x, $y)', snapshot.revision);
    }
    return best;
  }

  /// The compact numbered text a model reads: one line per shown node
  /// (`<ref> <role> "name" value=…`), two-space indent per depth, a
  /// header that admits trimming, and one `# pane <name>` section per
  /// declared pane (main first; empty panes render as empty sections —
  /// loud, not silent).
  String render() {
    final buffer = StringBuffer()
      ..write(
        '# observation rev=${snapshot.revision} walked=$walkedCount '
        'shown=${_nodes.length}${trimmed ? ' TRIMMED' : ''}',
      );
    var currentPane = '';
    void section(String name) {
      buffer.write('\n# pane $name');
      currentPane = name;
    }

    for (final observed in _nodes) {
      final paneName = observed.pane ?? 'main';
      if (paneName != currentPane) section(paneName);
      buffer.write('\n${'  ' * observed.offsetDepth}${_line(observed)}');
    }
    // Announce declared panes that showed nothing.
    final shownPanes = _nodes.map((observed) => observed.pane).toSet();
    for (final pane in view.panes.keys) {
      if (!shownPanes.contains(pane)) section(pane);
    }
    return buffer.toString();
  }

  /// Diffs this observation against [previous] — the act loop's closing
  /// read. Nodes carrying a non-empty `identifier` attribute match by
  /// that key (so reordering identified siblings reports no change);
  /// everything else matches by structural signature (pane + positional
  /// ancestor chain + role/name). Duplicate identifiers: last one wins.
  ObservationDelta diff(Observation previous) {
    final now = _signatureMap(this);
    final before = _signatureMap(previous);
    final added = <ObservedNode>[];
    final removed = <ObservedNode>[];
    final changed = <ChangedNode>[];
    for (final entry in now.entries) {
      final was = before[entry.key];
      if (was == null) {
        added.add(entry.value);
      } else if (_projection(was.node) != _projection(entry.value.node)) {
        changed.add(ChangedNode(entry.value, was.node, entry.value.node));
      }
    }
    for (final entry in before.entries) {
      if (!now.containsKey(entry.key)) removed.add(entry.value);
    }
    return ObservationDelta._(added, removed, changed);
  }

  /// Report/wire shape: rendered text plus the ref index.
  Map<String, Object?> toJson() => {
    'render': render(),
    'shown': _nodes.length,
    'walked': walkedCount,
    'trimmed': trimmed,
    'revision': snapshot.revision,
    'refs': {
      for (final observed in _nodes)
        observed.ref: {
          'role': observed.node.role,
          if (observed.node.name != null) 'name': observed.node.name,
          if (observed.node.value != null) 'value': observed.node.value,
          if (observed.pane != null) 'pane': observed.pane,
        },
    },
  };

  static int? _selectorIndex(List<AxNode> walk, String? selector) {
    if (selector == null) return null;
    // Main refs are walk indices (`s_N` → index N); an identifier is
    // tried second.
    if (selector.startsWith('s_')) {
      final index = int.tryParse(selector.substring(2));
      if (index != null && index < walk.length) return index;
    }
    for (var i = 0; i < walk.length; i++) {
      if (walk[i].attributes['identifier'] == selector) return i;
    }
    return null;
  }

  static int _subtreeEnd(List<AxNode> walk, List<int> depthOf, int rootIndex) {
    final rootDepth = depthOf[rootIndex];
    var end = walk.length;
    for (var i = rootIndex + 1; i < walk.length; i++) {
      if (depthOf[i] <= rootDepth) {
        end = i;
        break;
      }
    }
    return end;
  }

  static Map<String, ObservedNode> _signatureMap(Observation observation) {
    final result = <String, ObservedNode>{};

    // Main section: ref s_i is walk index i.
    var i = 0;
    void walkMain(AxNode node, String parentSignature, int childIndex) {
      final index = i++;
      // Identifier-keyed nodes match across reflows and reorders; the
      // positional chain covers everything else.
      final identifier = node.attributes['identifier'];
      final signature = identifier != null && identifier.isNotEmpty
          ? '@id=$identifier'
          : '$parentSignature/${node.role}:${node.name ?? ''}@$childIndex';
      final observed = observation._byRef['s_$index'];
      if (observed != null) result[signature] = observed;
      var c = 0;
      for (final child in node.children) {
        walkMain(child, signature, c++);
      }
    }

    var rootIndex = 0;
    for (final root in observation.snapshot.roots) {
      walkMain(root, '@r${rootIndex++}', 0);
    }

    // Pane sections: pane-local indices follow the same walk order.
    for (final pane in observation.view.panes.keys) {
      var paneIndex = 0;
      void walkPane(AxNode node, String parentSignature, int childIndex) {
        final index = paneIndex++;
        final identifier = node.attributes['identifier'];
        final signature = identifier != null && identifier.isNotEmpty
            ? '$pane@id=$identifier'
            : '$pane$parentSignature/${node.role}:${node.name ?? ''}@$childIndex';
        final observed = observation._byRef['$pane.s_$index'];
        if (observed != null) result[signature] = observed;
        var c = 0;
        for (final child in node.children) {
          walkPane(child, signature, c++);
        }
      }

      var paneRootIndex = 0;
      for (final root in observation.snapshot.roots) {
        walkPane(root, '@r${paneRootIndex++}', 0);
      }
    }
    return result;
  }

  /// The diffable projection: what can change without changing identity
  /// (value and origin; role/name live in the signature).
  static String _projection(AxNode node) =>
      'v=${node.value ?? ''}'
      '@${node.bounds == null ? '' : '${node.bounds!.left},${node.bounds!.top}'}';
}

/// The act loop's closing read: what appeared, what vanished, what
/// changed. Added/changed rows carry the new observation's refs;
/// removed rows carry the previous observation's.
final class ObservationDelta {
  const ObservationDelta._(this.added, this.removed, this.changed);

  /// Nodes present now that were not before.
  final List<ObservedNode> added;

  /// Nodes present before that are not now.
  final List<ObservedNode> removed;

  /// Nodes whose value/bounds changed in place.
  final List<ChangedNode> changed;

  /// Whether nothing moved.
  bool get isEmpty => added.isEmpty && removed.isEmpty && changed.isEmpty;

  /// Compact delta text; `# no change` when nothing moved.
  String render() {
    if (isEmpty) return '# no change';
    final buffer = StringBuffer();
    for (final observed in added) {
      buffer.writeln('+ ${_line(observed)}');
    }
    for (final observed in removed) {
      buffer.writeln('- ${_line(observed)}');
    }
    for (final change in changed) {
      buffer.writeln(
        '~ ${_line(change.current)} '
        '"${change.beforeNode.value ?? ''}" → '
        '"${change.current.node.value ?? ''}"',
      );
    }
    return buffer.toString().trimRight();
  }
}

/// One changed node: the current observation's row plus both carriers.
final class ChangedNode {
  const ChangedNode(this.current, this.beforeNode, this.currentNode);

  /// The current observation's row.
  final ObservedNode current;

  /// The previous node value carrier.
  final AxNode beforeNode;

  /// The current node value carrier.
  final AxNode currentNode;
}

String _line(ObservedNode observed) {
  final node = observed.node;
  return [
    observed.ref,
    node.role,
    if (node.name != null) '"${node.name}"',
    if (node.value != null) 'value="${node.value}"',
  ].join(' ');
}

/// A ref an interaction wants is not resolvable against the current
/// observation — the surface moved on. Fail closed: reobserve, never
/// guess (the family's stale-handle posture, made agent-visible).
class SemanticRefUnavailableException implements Exception {
  /// Creates the exception for [ref] at observation [revision].
  const SemanticRefUnavailableException(this.ref, this.revision);

  /// The unresolvable ref.
  final String ref;

  /// The revision the resolving observation was taken at.
  final int revision;

  /// Agent-facing hint.
  String get message =>
      'semantic ref "$ref" is unavailable at observation rev=$revision '
      '(stale or trimmed away): reobserve, never guess';

  @override
  String toString() => message;
}
