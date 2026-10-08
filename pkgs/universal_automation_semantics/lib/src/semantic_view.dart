/// Which [AxNode](universal_automation_interface) fields a view renders.
///
/// Token economy is the design constraint: an observation is read by a
/// model every loop iteration, so the default set is the minimum that
/// locates a control — role, name, value.
enum SemanticField {
  /// Lowercase semantic role (`window`, `button`, `textbox`, …).
  role,

  /// Accessible name, when the platform exposes one.
  name,

  /// Current value (`textbox`, `slider`, …).
  value,

  /// Bounding box (left/top/width/height in surface coordinates).
  bounds;

  /// The canonical wire name (the AxNode JSON key).
  String get wireName => switch (this) {
    SemanticField.role => 'role',
    SemanticField.name => 'name',
    SemanticField.value => 'value',
    SemanticField.bounds => 'bounds',
  };

  /// Parses a wire name; unknown names fail closed.
  static SemanticField parse(Object? value) {
    final name = '$value';
    for (final field in SemanticField.values) {
      if (field.wireName == name) return field;
    }
    throw FormatException(
      'unknown semantic field "$name" '
      '(known: ${SemanticField.values.map((f) => f.wireName).join(', ')})',
    );
  }
}

/// A declarative view over one semantic snapshot — WHAT an observation
/// keeps, never WHERE the tree comes from.
///
/// Views are immutable values and compose both ways: build one whole in
/// a single const expression (the Flutter widget manner) or refine one
/// step by step through the builder methods — every method returns a
/// new view, never mutates. The wire form deliberately matches
/// mcp_flutter's `semantic_snapshot` filter keys
/// (`identifierPrefix`/`subtreeOf`/`fields`), which are the family's
/// de facto interchange for view selection (ADR 0047).
///
/// Numbering contract (the invariant everything else builds on): refs
/// number the **full** walk of the observed snapshot in document order;
/// the view only decides which of the numbered nodes are **shown**.
/// Trimming hides rows and never renumbers, so a ref read off a
/// filtered or trimmed observation stays valid for the whole
/// observation, and for interaction tools that resolve against it.
final class SemanticView {
  /// Creates a view.
  const SemanticView({
    this.fields = defaultFields,
    this.subtreeOf,
    this.identifierPrefix,
    this.maxNodes,
    this.panes = const {},
  });

  /// The default rendered fields: the minimum that locates a control.
  static const defaultFields = {
    SemanticField.role,
    SemanticField.name,
    SemanticField.value,
  };

  /// Fields rendered for each shown node; `ref` is always rendered.
  final Set<SemanticField> fields;

  /// Show one node and its descendants: the node's ref from the
  /// observation this view resolves against (tried first), or the
  /// node's `identifier` attribute when the tier exposes one.
  final String? subtreeOf;

  /// Show nodes whose `identifier` attribute starts with this prefix.
  final String? identifierPrefix;

  /// Cap on shown nodes. Trimming hides the tail (document order,
  /// ancestors kept) and the render says so; refs stay full-walk.
  final int? maxNodes;

  /// Named sub-views — nested composition beyond the linear filter.
  /// Each pane resolves against the same snapshot with its own walk and
  /// its own ref space (`<pane>.s_N`), rendered as a named section.
  final Map<String, SemanticView> panes;

  /// Whether the view asks for nothing beyond the defaults — no
  /// subtree, no prefix, no cap, no panes.
  bool get isEmpty =>
      subtreeOf == null &&
      identifierPrefix == null &&
      maxNodes == null &&
      panes.isEmpty;

  /// Returns a view scoped to one subtree (see [subtreeOf]).
  SemanticView scoped(String selector) => SemanticView(
    fields: fields,
    subtreeOf: selector,
    identifierPrefix: identifierPrefix,
    maxNodes: maxNodes,
    panes: panes,
  );

  /// Returns a view rendering [fields].
  SemanticView withFields(Set<SemanticField> fields) => SemanticView(
    fields: fields,
    subtreeOf: subtreeOf,
    identifierPrefix: identifierPrefix,
    maxNodes: maxNodes,
    panes: panes,
  );

  /// Returns a view capped at [maxNodes] shown nodes.
  SemanticView trimmed(int maxNodes) => SemanticView(
    fields: fields,
    subtreeOf: subtreeOf,
    identifierPrefix: identifierPrefix,
    maxNodes: maxNodes,
    panes: panes,
  );

  /// Returns a view with [name] → [subView] added to [panes].
  SemanticView withPane(String name, SemanticView subView) => SemanticView(
    fields: fields,
    subtreeOf: subtreeOf,
    identifierPrefix: identifierPrefix,
    maxNodes: maxNodes,
    panes: {...panes, name: subView},
  );

  /// The wire form. Keys match mcp_flutter's filter schema; `panes`
  /// and `maxNodes` are family extensions.
  Map<String, Object?> toJson() => {
    'fields': [for (final field in fields) field.wireName],
    if (subtreeOf != null) 'subtreeOf': subtreeOf,
    if (identifierPrefix != null) 'identifierPrefix': identifierPrefix,
    if (maxNodes != null) 'maxNodes': maxNodes,
    if (panes.isNotEmpty)
      'panes': {
        for (final entry in panes.entries) entry.key: entry.value.toJson(),
      },
  };

  /// Restores a view from its wire form (or from a bare argument map
  /// carrying the same keys). Unknown keys and unknown field names fail
  /// closed; a blank selector counts as unasked, as in mcp_flutter.
  factory SemanticView.fromJson(Object? json) {
    if (json == null) return const SemanticView();
    if (json is! Map<Object?, Object?>) {
      throw const FormatException('a semantic view must be a map');
    }
    final fieldsValue = json['fields'];
    final fields = fieldsValue is List<Object?>
        ? {for (final name in fieldsValue) SemanticField.parse(name)}
        : SemanticView.defaultFields;
    final maxNodesValue = json['maxNodes'];
    if (maxNodesValue != null && maxNodesValue is! int) {
      throw const FormatException('view.maxNodes must be an integer');
    }
    final panesValue = json['panes'];
    final panes = panesValue is Map<Object?, Object?>
        ? {
            for (final entry in panesValue.entries)
              '${entry.key}': SemanticView.fromJson(entry.value),
          }
        : const <String, SemanticView>{};
    return SemanticView(
      fields: fields,
      subtreeOf: _selector(json['subtreeOf']),
      identifierPrefix: _selector(json['identifierPrefix']),
      maxNodes: maxNodesValue as int?,
      panes: panes,
    );
  }

  static String? _selector(Object? raw) {
    final text = raw == null ? '' : '$raw';
    return text.trim().isEmpty ? null : text;
  }
}
