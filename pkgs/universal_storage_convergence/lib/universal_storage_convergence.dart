/// Convergence kernel shared by Universal Storage mesh sync and ecsly world
/// sync (ADR 0011).
///
/// Dual mode: every replica keeps an incrementally-folded state plus a
/// pending op log. State is a projection; compaction is a deliberate
/// transform.
///
/// Sub-star boundary: this package knows nothing about storage namespaces,
/// worlds, actors, or transports. Consumers choose merge strategies from
/// what is exposed here; they never hand-roll ordering, version vectors, or
/// fold rules.
library;

export 'src/convergence_doc.dart';
export 'src/hlc.dart';
export 'src/lww_map_strategy.dart';
export 'src/op_record.dart';
export 'src/version_vector.dart';
