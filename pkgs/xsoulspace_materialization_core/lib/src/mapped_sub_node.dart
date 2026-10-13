/// One mapped sub-node the fs tier should stamp (ADR 0035 §2 — pure
/// DATA): the binding's map parser parses; the ENGINE stamps ids, edges
/// and budget green-screen facts. [idTail] is unique within the owning
/// file (the node id is `<prefix><fileNodeId>_<idTail>`, prefix
/// binding-declared).
class MappedSubNode {
  const MappedSubNode({
    required this.kind,
    required this.label,
    required this.idTail,
    required this.props,
  });

  /// The node kind (`section`, `key`).
  final String kind;

  /// The zoom label (the human/mechanical handle).
  final String label;

  /// The id tail unique within the file.
  final String idTail;

  /// Structural props (spans, level/keypath/line — never file text).
  final Map<String, dynamic> props;
}

/// The binding's map-half parser type (parse → data; the engine stamps).
typedef MapParser = List<MappedSubNode> Function(String content);
