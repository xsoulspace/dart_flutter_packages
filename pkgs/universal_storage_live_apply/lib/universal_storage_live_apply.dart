/// Live-apply transaction layer for universal_storage (ADR 0014 semantics).
///
/// Every mutation applies in place against the underlying provider but is
/// first recorded in a footprint journal: the prior content of each touched
/// path, the post-content hash, and the operation order. While a run is
/// uncommitted, `rollback` replays a VERIFIED inverse — external edits to a
/// journaled path refuse the rollback instead of being clobbered. `commit`
/// prunes the journal and freezes the state.
///
/// The layer is provider-agnostic: wrap any [StorageProvider] with
/// [LiveApplyStorageProvider], or drive [LiveApplyTransaction] directly for
/// multi-operation batches. It is deliberately NOT a replication protocol:
/// convergence across devices belongs to the sync/mesh layer; this package
/// guarantees that one device's writes are provably invertible.
library;

export 'src/live_apply_exceptions.dart';
export 'src/live_apply_journal.dart';
export 'src/live_apply_models.dart';
export 'src/live_apply_storage_provider.dart';
export 'src/live_apply_transaction.dart';
