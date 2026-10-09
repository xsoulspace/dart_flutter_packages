/// Projects a producer's snapshot node maps into the automation family's
/// [Snapshot]/[Observation] shape (ADR 0052, the vmService rung of the
/// unification ladder).
///
/// Any tier whose native walk emits Flutter-shaped node maps — `type`,
/// `label`, `value`, `bounds` as left/top/right/bottom, children as ref
/// lists — feeds [familySnapshotFromNodes] unchanged. The projection is
/// lossless on the shared axis — role (from `type`), name (from
/// `label`), value, bounds — and carries the producer-specific
/// vocabulary (`identifier`, `hint`, `enabled`, `actions`, `id`) in
/// [AxNode.attributes], where family consumers can read it without this
/// package depending on them. Refs agree by construction: family refs
/// are positional over the same emitted walk ([snapshotRef]), so `s_N`
/// here is the producer's `s_N` everywhere.
library;

import 'package:universal_automation_interface/universal_automation_interface.dart';

/// The family's ref format over an emitted walk: `s_N`, document order.
///
/// One dialect for every face that prints or parses a ref — producers
/// issue them with this, the observation grammar resolves them, agents
/// read them off either.
String snapshotRef(final int index) => 's_$index';

/// Builds a family [Snapshot] from one snapshot's node maps (the
/// `nodes` list of a semantic snapshot envelope, in walk order, parents
/// before children).
Snapshot familySnapshotFromNodes(
  final List<Map<String, Object?>> nodes, {
  required final int snapshotId,
  required final DateTime capturedAt,
}) {
  final byRef = <String, Map<String, Object?>>{
    for (final node in nodes) node['ref']! as String: node,
  };
  final built = <String, AxNode>{};

  AxNode build(final Map<String, Object?> node) {
    final ref = node['ref']! as String;
    final existing = built[ref];
    if (existing != null) return existing;
    final axNode = AxNode(
      role: (node['type'] as String? ?? 'generic').toLowerCase(),
      name: node['label'] as String?,
      value: node['value'] as String?,
      bounds: _boundsOf(node['bounds']),
      attributes: _attributesOf(node),
      children: [
        for (final child in node['children'] as List<String>? ?? const <String>[])
          if (byRef.containsKey(child)) build(byRef[child]!),
      ],
    );
    built[ref] = axNode;
    return axNode;
  }

  final roots = <AxNode>[];
  final referenced = <String>{
    for (final node in nodes)
      ...(node['children'] as List<String>? ?? const <String>[]),
  };
  for (final node in nodes) {
    if (!referenced.contains(node['ref'])) roots.add(build(node));
  }
  return Snapshot(
    roots: roots,
    capturedAt: capturedAt,
    revision: snapshotId,
  );
}

AxBounds? _boundsOf(final Object? raw) {
  if (raw is! Map<Object?, Object?>) return null;
  final left = (raw['left'] as num?)?.toDouble();
  final top = (raw['top'] as num?)?.toDouble();
  final right = (raw['right'] as num?)?.toDouble();
  final bottom = (raw['bottom'] as num?)?.toDouble();
  if (left == null || top == null || right == null || bottom == null) {
    return null;
  }
  return AxBounds(
    left: left,
    top: top,
    width: right - left,
    height: bottom - top,
  );
}

Map<String, String> _attributesOf(final Map<String, Object?> node) => {
  for (final entry in node.entries)
    if (entry.value != null &&
        entry.key != 'ref' &&
        entry.key != 'children' &&
        entry.key != 'bounds' &&
        entry.key != 'type' &&
        entry.key != 'label' &&
        entry.key != 'value')
      entry.key: '${entry.value}',
};
