/// The envelope-side selection policy over a producer's snapshot node
/// maps (ADR 0052's full-cutover rung).
///
/// A producer's walk stays native (Flutter semantics, AX, AT-SPI, CDP
/// a11y); what this package owns is the *shape* policy every consumer
/// of the walk shares: which of the kept node maps survive projection,
/// and what happens to their `children`. Node-map keys stay the
/// producer's (`label`, `hint`, …) — the same vocabulary
/// [familySnapshotFromNodes] projects into the family shape.
library;

/// Projects [nodes] (walk order) through a selection.
///
/// [keep] is the producer-side predicate (identity containment, prefix
/// matching — anything the walk itself can see). [fields] names the
/// keys a filtered node keeps; `ref` always survives. Shared shape
/// rules, applied here so every producer stays dialect-free:
///
/// - kept nodes project to [fields] (`ref` always kept);
/// - `children` lists prune to refs that survived [keep];
/// - a `children` key whose pruning emptied it is dropped.
List<Map<String, Object?>> projectSnapshotNodes(
  final Iterable<Map<String, Object?>> nodes, {
  final bool Function(Map<String, Object?> node)? keep,
  final List<String>? fields,
}) {
  final kept = <Map<String, Object?>>[
    for (final node in nodes) if (keep == null || keep(node)) node,
  ];
  final keptRefs = <Object?>{for (final node in kept) node['ref']};
  final fieldSet = fields?.toSet();
  return <Map<String, Object?>>[
    for (final node in kept)
      <String, Object?>{
        for (final MapEntry(:key, :value) in node.entries)
          if (fieldSet == null || key == 'ref' || fieldSet.contains(key))
            if (key == 'children')
              key: <String>[
                for (final child in value! as List<String>)
                  if (keptRefs.contains(child)) child,
              ]
            else
              key: value,
      }..removeWhere(
        (final key, final value) =>
            key == 'children' && (value! as List<String>).isEmpty,
      ),
  ];
}
