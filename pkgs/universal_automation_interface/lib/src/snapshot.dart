import 'package:meta/meta.dart';

/// Bounding box of a semantic node in logical pixels.
@immutable
class AxBounds {
  /// Creates bounds.
  const AxBounds({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// Restores bounds from [toJson] output.
  factory AxBounds.fromJson(Map<String, Object?> json) => AxBounds(
    left: (json['left']! as num).toDouble(),
    top: (json['top']! as num).toDouble(),
    width: (json['width']! as num).toDouble(),
    height: (json['height']! as num).toDouble(),
  );

  /// Distance from the left edge of the surface.
  final double left;

  /// Distance from the top edge of the surface.
  final double top;

  /// Horizontal extent.
  final double width;

  /// Vertical extent.
  final double height;

  /// Center point, the default target for input synthesis.
  (double, double) get center => (left + width / 2, top + height / 2);

  /// Serializes the bounds.
  Map<String, Object?> toJson() => {
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  };

  @override
  String toString() => 'AxBounds($left, $top, $width x $height)';
}

/// One node of a semantic/accessibility tree.
///
/// Roles are protocol-agnostic lowercase strings (`button`, `textbox`,
/// `heading`, `image`, `generic`); drivers map protocol-specific roles onto
/// them. `frames != semantics`: a snapshot is the rich observation, a frame
/// is only pixels.
@immutable
class AxNode {
  /// Creates a node.
  const AxNode({
    required this.role,
    this.name,
    this.value,
    this.bounds,
    this.attributes = const {},
    this.children = const [],
  });

  /// Restores a node (and its subtree) from [toJson] output.
  factory AxNode.fromJson(Map<String, Object?> json) => AxNode(
    role: json['role']! as String,
    name: json['name'] as String?,
    value: json['value'] as String?,
    bounds: json['bounds'] == null
        ? null
        : AxBounds.fromJson(json['bounds']! as Map<String, Object?>),
    attributes: (json['attributes'] as Map<Object?, Object?>? ?? const {}).map(
      (key, value) => MapEntry(key! as String, value! as String),
    ),
    children: (json['children'] as List<Object?>? ?? const [])
        .whereType<Map<String, Object?>>()
        .map(AxNode.fromJson)
        .toList(growable: false),
  );

  /// Lowercase semantic role.
  final String role;

  /// Accessible name, when the platform exposes one.
  final String? name;

  /// Current value (for `textbox`, `slider`, …).
  final String? value;

  /// Bounding box, when the driver can resolve one.
  final AxBounds? bounds;

  /// Additional protocol-provided attributes.
  final Map<String, String> attributes;

  /// Child nodes in document order.
  final List<AxNode> children;

  /// Depth-first walk of this subtree, starting at this node.
  Iterable<AxNode> walk() sync* {
    yield this;
    for (final child in children) {
      yield* child.walk();
    }
  }

  /// First node in depth-first order matching [test], or `null`.
  AxNode? firstWhere(bool Function(AxNode node) test) {
    for (final node in walk()) {
      if (test(node)) return node;
    }
    return null;
  }

  /// First node with accessible name [name], or `null`.
  AxNode? byName(String name) => firstWhere((node) => node.name == name);

  /// First node with role [role] and, when given, name [name], or `null`.
  AxNode? byRole(String role, {String? name}) => firstWhere(
    (node) => node.role == role && (name == null || node.name == name),
  );

  /// Serializes the node and its subtree.
  Map<String, Object?> toJson() => {
    'role': role,
    if (name != null) 'name': name,
    if (value != null) 'value': value,
    if (bounds != null) 'bounds': bounds!.toJson(),
    if (attributes.isNotEmpty) 'attributes': attributes,
    if (children.isNotEmpty)
      'children': children.map((child) => child.toJson()).toList(),
  };

  @override
  String toString() => name == null ? 'AxNode($role)' : 'AxNode($role $name)';
}

/// A semantic snapshot of the automated surface at a point in time.
@immutable
class Snapshot {
  /// Creates a snapshot.
  const Snapshot({
    required this.roots,
    required this.capturedAt,
    required this.revision,
  });

  /// Restores a snapshot from [toJson] output.
  factory Snapshot.fromJson(Map<String, Object?> json) => Snapshot(
    roots: (json['roots'] as List<Object?>? ?? const [])
        .whereType<Map<String, Object?>>()
        .map(AxNode.fromJson)
        .toList(growable: false),
    capturedAt: DateTime.parse(json['capturedAt']! as String),
    revision: json['revision'] as int? ?? 0,
  );

  /// Root nodes of the forest (typically one).
  final List<AxNode> roots;

  /// When the driver captured it.
  final DateTime capturedAt;

  /// Monotonic target revision; bumps when the underlying surface changes
  /// in a way that invalidates earlier nodes (e.g. a navigation).
  final int revision;

  /// All nodes across all roots, depth-first.
  Iterable<AxNode> get nodes => roots.expand((root) => root.walk());

  /// Serializes the snapshot.
  Map<String, Object?> toJson() => {
    'roots': roots.map((root) => root.toJson()).toList(),
    'capturedAt': capturedAt.toIso8601String(),
    'revision': revision,
  };
}
