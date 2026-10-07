import 'package:universal_storage_interface/universal_storage_interface.dart';

/// One attachable participant in the sync cycle (ADR 0047 §3): the
/// flush/absorb/compact seam wrapped around anti-entropy.
///
/// Doc-replica stores, actor rosters, task boards, game-world boards —
/// anything durable that wants its state shipped BY the mesh exchange and
/// remote state folded back IN — implements this seam and attaches to a
/// [MeshWorldSession]. The session owns the ORDER (flush → exchange →
/// absorb → compact) and never learns what a participant's content is;
/// convergence rests on the kernel (VV dedupe + order-independent fold),
/// never on file ordering.
abstract interface class MeshSyncParticipant {
  /// Writes this participant's durable state into [storage] (before the
  /// exchange) so anti-entropy ships the latest state.
  Future<void> flush(final StorageService storage);

  /// Folds durable state the exchange delivered (after the exchange).
  /// Snapshot-first when the participant carries compacted peers' state:
  /// the kernel adopts only snapshots its version vector does not already
  /// cover (the DocReplicaStore.absorbRemote ordering insight).
  Future<void> absorb(final StorageService storage);

  /// Post-absorb compaction. Fire only above the participant's own policy
  /// thresholds (cheap no-op below them).
  Future<void> compact(final StorageService storage);
}
