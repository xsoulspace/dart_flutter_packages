import 'package:universal_storage_interface/universal_storage_interface.dart';

import 'live_apply_exceptions.dart';
import 'live_apply_journal.dart';
import 'live_apply_models.dart';
import 'live_apply_transaction.dart';

/// A [StorageProvider] decorator that makes every mutation undoable: each
/// create/update/delete runs through a [LiveApplyTransaction] whose journal
/// survives on local disk, giving the caller a rollback window that closes
/// only on [commitLast].
///
/// Two ways to drive it:
/// - **per-operation (default):** every provider mutation is one run; call
///   [rollbackLast] to undo the most recent mutation, [commitLast] to
///   accept it.
/// - **batch:** [beginTransaction] returns a transaction the caller drives
///   directly — several operations, one journal, all-or-nothing rollback.
///
/// Reads, listing, sync, and authentication delegate untouched. This layer
/// is NOT replication: converging runs across devices is the mesh layer's
/// job (a committed run's journal is the natural proof-carrying delta for
/// that transport).
class LiveApplyStorageProvider implements StorageProvider {
  /// {@macro live_apply_storage_provider}
  LiveApplyStorageProvider({
    required this.inner,
    required this.journalStorePath,
    this.maxSnapshotFileBytes,
  });

  /// The wrapped provider receiving every operation.
  final StorageProvider inner;

  /// Local directory for undo journals.
  final String journalStorePath;

  /// Refusal threshold for journaling a path's prior content.
  final int? maxSnapshotFileBytes;

  LiveApplyJournalStore? _store;
  String? _lastRunId;

  /// The journal store, available after [initWithConfig].
  LiveApplyJournalStore get store =>
      _store ??= LiveApplyJournalStore(storePath: journalStorePath);

  @override
  Future<void> initWithConfig(final StorageConfig config) =>
      inner.initWithConfig(config);

  @override
  Future<bool> isAuthenticated() => inner.isAuthenticated();

  @override
  StorageCapabilities get declaredCapabilities => StorageCapabilities(
        supportsDiff: inner.declaredCapabilities.supportsDiff,
        supportsHistory: true,
        supportsRevisionMetadata:
            inner.declaredCapabilities.supportsRevisionMetadata,
        supportsManualConflictResolution:
            inner.declaredCapabilities.supportsManualConflictResolution,
        supportsBackgroundSync:
            inner.declaredCapabilities.supportsBackgroundSync,
        supportsMigrationEndpoint:
            inner.declaredCapabilities.supportsMigrationEndpoint,
        syncAvailability: inner.declaredCapabilities.syncAvailability,
      );

  @override
  bool get supportsSync => inner.supportsSync;

  @override
  Future<void> sync({
    final String? pullMergeStrategy,
    final String? pushConflictStrategy,
  }) =>
      inner.sync(
        pullMergeStrategy: pullMergeStrategy,
        pushConflictStrategy: pushConflictStrategy,
      );

  @override
  Future<String?> getFile(final String path) => inner.getFile(path);

  @override
  Future<List<FileEntry>> listDirectory(final String directoryPath) =>
      inner.listDirectory(directoryPath);

  @override
  Future<FileOperationResult> createFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) =>
      _journaled((final tx) async {
        // The inner call runs directly (not through writeFile) so the
        // contract's FileAlreadyExistsException semantics survive.
        await tx.snapshot(path);
        final result = await inner.createFile(path, content);
        await tx.recordPost(path, content);
        return result;
      });

  @override
  Future<FileOperationResult> updateFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) =>
      _journaled((final tx) async {
        // Direct inner update: FileNotFoundException on a missing path is
        // the interface contract, not something live apply may blur.
        await tx.snapshot(path);
        final result = await inner.updateFile(path, content);
        await tx.recordPost(path, content);
        return result;
      });

  @override
  Future<FileOperationResult> deleteFile(
    final String path, {
    final String? commitMessage,
  }) =>
      _journaled((final tx) async {
        await tx.snapshot(path);
        final result = await inner.deleteFile(path);
        await tx.recordPost(path, null);
        return result;
      });

  /// Restores [path]. A [versionId] naming a retained run rolls that run
  /// back (the only undo this layer owns); anything else delegates to the
  /// inner provider.
  @override
  Future<void> restore(
    final String path, {
    final String? versionId,
  }) async {
    if (versionId != null) {
      final journal = await store.read(versionId);
      if (journal != null &&
          journal.entries.any((final e) => e.path == path)) {
        final tx = await LiveApplyTransaction.reopen(
          inner,
          store,
          versionId,
          maxSnapshotFileBytes: maxSnapshotFileBytes,
        );
        await tx.rollback();
        return;
      }
    }
    await inner.restore(path, versionId: versionId);
  }

  /// Runs one journaled operation as its own run, retaining it in the
  /// rollback window. An inner failure discards the (mutation-free) run
  /// and rethrows.
  Future<FileOperationResult> _journaled(
    final Future<FileOperationResult> Function(LiveApplyTransaction tx) op,
  ) async {
    final tx = await beginTransaction();
    try {
      final result = await op(tx);
      await tx.markApplied();
      _lastRunId = tx.runId;
      return result;
    } catch (_) {
      if (tx.status == LiveApplyRunStatus.open) {
        // Nothing mutated — the run never left `open`, so discard it.
        await store.prune(tx.runId);
      }
      rethrow;
    }
  }

  /// Opens a batch transaction: many operations, one journal. The caller
  /// decides between `commit()` and `rollback()`.
  Future<LiveApplyTransaction> beginTransaction() async {
    await store.ensureRoot();
    return LiveApplyTransaction.begin(
      inner,
      store,
      maxSnapshotFileBytes: maxSnapshotFileBytes,
    );
  }

  /// The run id of the most recent per-operation mutation, if any.
  String? get lastRunId => _lastRunId;

  /// Undoes the most recent retained run (or an explicit [runId]).
  Future<void> rollbackLast({final String? runId}) async {
    final id = runId ?? _lastRunId;
    if (id == null) {
      throw const LiveApplyRefusalException('no live-apply run to roll back');
    }
    final tx = await LiveApplyTransaction.reopen(
      inner,
      store,
      id,
      maxSnapshotFileBytes: maxSnapshotFileBytes,
    );
    await tx.rollback();
  }

  /// Accepts the most recent retained run (or an explicit [runId]): prunes
  /// its journal; the state is frozen.
  Future<void> commitLast({final String? runId}) async {
    final id = runId ?? _lastRunId;
    if (id == null) {
      throw const LiveApplyRefusalException('no live-apply run to commit');
    }
    final tx = await LiveApplyTransaction.reopen(
      inner,
      store,
      id,
      maxSnapshotFileBytes: maxSnapshotFileBytes,
    );
    await tx.commit();
  }

  /// Every retained run, newest first — including `open` runs left behind
  /// by a crash (their journals alone are enough to roll back).
  Future<List<LiveApplyJournal>> listRuns() => store.list();

  @override
  Future<void> dispose() => inner.dispose();
}
