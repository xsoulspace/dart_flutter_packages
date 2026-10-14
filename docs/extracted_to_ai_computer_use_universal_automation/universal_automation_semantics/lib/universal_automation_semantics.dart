/// The semantic view grammar for the universal automation family
/// (ADR 0052).
///
/// Every automation tier projects its native tree into the family
/// `Snapshot` (`universal_automation_interface`); this package owns
/// everything after the tree exists:
///
/// - [SemanticView] — the declarative view value: what an observation
///   keeps (fields, subtree, prefix, cap, named panes). Immutable,
///   const-able, builder-refinable, and wire-compatible with
///   mcp_flutter's `semantic_snapshot` filter keys.
/// - [Observation] — the view resolved against one live snapshot:
///   ref-stable numbering over the full walk, compact numbered text
///   ([Observation.render]), ref resolution ([Observation.resolve]),
///   and the act loop's closing read ([Observation.diff]).
/// - [snapshotRef] / [familySnapshotFromNodes] — the ref dialect and
///   the projection from a producer's Flutter-shaped node maps into
///   the family [Snapshot].
/// - [projectSnapshotNodes] — the envelope-side selection policy over
///   those node maps (fields projection, children pruning).
///
/// Pure Dart, no Flutter, no protocol clients — producers stay native
/// (Flutter semantics walks, macOS AX, AT-SPI, UIA, CDP a11y).
library;

export 'src/family_projection.dart';
export 'src/observation.dart';
export 'src/semantic_view.dart';
export 'src/snapshot_projection.dart';
