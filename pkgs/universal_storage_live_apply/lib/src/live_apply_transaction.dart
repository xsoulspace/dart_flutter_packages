import 'package:universal_storage_interface/universal_storage_interface.dart';

import 'live_apply_exceptions.dart';
import 'live_apply_journal.dart';
import 'live_apply_models.dart';

/// One live-apply run: mutations apply IN PLACE against [inner] while every
/// touched path's prior content is journaled, so [rollback] can replay a
/// verified inverse until [commit] freezes the state.
///
/// Refusal discipline (ADR 0014, applied to storage):
/// - a prior state larger than `maxSnapshotFileBytes` refuses BEFORE the
///   mutation happens (the big-file strategy is explicit, never a silently
///   unrestorable write);
/// - a rollback whose drift check fails refuses with
///   [LiveApplyDriftException] listing the paths — external edits are never
///   clobbered by the inverse.
class LiveApplyTransaction {
  LiveApplyTransaction._({
    required this.inner,
    required this.store,
    required this.journal,
    this.maxSnapshotFileBytes,
  });

  /// The provider the run mutates.
  final StorageProvider inner;

  /// Where the journal is persisted.
  final LiveApplyJournalStore store;

  /// The journal document (entries appended in first-touch order).
  final LiveApplyJournal journal;

  /// Refusal threshold for snapshotting a path's prior content.
  final int? maxSnapshotFileBytes;

  LiveApplyEntry _entryFor(final String path) => journal.entries
      .firstWhere((final e) => e.path == path, orElse: () {
        throw StateError('path $path was not snapshotted before mutation');
      });

  /// Starts a new run with a fresh journal on disk.
  static Future<LiveApplyTransaction> begin(
    final StorageProvider inner,
    final LiveApplyJournalStore store, {
    final int? maxSnapshotFileBytes,
  }) async {
    final runId =
        'run-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    final journal = LiveApplyJournal(
      runId: runId,
      createdUtc: DateTime.now().toUtc().toIso8601String(),
    );
    await store.write(journal);
    return LiveApplyTransaction._(
      inner: inner,
      store: store,
      journal: journal,
      maxSnapshotFileBytes: maxSnapshotFileBytes,
    );
  }

  /// Reopens an existing run from its journal — the crash-recovery and
  /// rollback-window path. Refuses runs that are already closed.
  static Future<LiveApplyTransaction> reopen(
    final StorageProvider inner,
    final LiveApplyJournalStore store,
    final String runId, {
    final int? maxSnapshotFileBytes,
  }) async {
    final journal = await store.read(runId);
    if (journal == null) {
      throw LiveApplyRefusalException('no live-apply run $runId in the store');
    }
    if (journal.status != LiveApplyRunStatus.open &&
        journal.status != LiveApplyRunStatus.applied) {
      throw LiveApplyRefusalException(
        'run $runId is ${journal.status.name}; only open or applied runs '
        'can roll back',
      );
    }
    return LiveApplyTransaction._(
      inner: inner,
      store: store,
      journal: journal,
      maxSnapshotFileBytes: maxSnapshotFileBytes,
    );
  }

  String get runId => journal.runId;
  LiveApplyRunStatus get status => journal.status;
  bool get _isClosed =>
      journal.status == LiveApplyRunStatus.committed ||
      journal.status == LiveApplyRunStatus.rolledBack;

  Future<void> _snapshot(final String path) async {
    if (_isClosed) {
      throw LiveApplyRefusalException('run $runId is closed');
    }
    final existing = journal.entries.where((final e) => e.path == path);
    if (existing.isNotEmpty) return; // first touch wins; already journaled
    final prior = await inner.getFile(path);
    if (prior != null &&
        maxSnapshotFileBytes != null &&
        prior.length > maxSnapshotFileBytes!) {
      throw LiveApplyRefusalException(
        'path $path holds ${prior.length} bytes, above the '
        'maxSnapshotFileBytes limit ($maxSnapshotFileBytes) — live apply '
        'refuses rather than journal an unrestorable snapshot',
      );
    }
    journal.entries.add(
      LiveApplyEntry(
        path: path,
        prior: prior == null
            ? null
            : LiveApplyPrior(
                sha256: liveApplySha256(prior),
                content: prior,
              ),
        postSha256: prior == null
            ? liveApplyDeletedSha256
            : liveApplySha256(prior),
      ),
    );
    await store.write(journal);
  }

  /// Journals [path]'s prior state before its first mutation. Callers that
  /// drive the inner provider directly (to preserve create/update
  /// semantics) pair this with [recordPost].
  Future<void> snapshot(final String path) => _snapshot(path);

  /// Records the content hash a run left at a previously snapshotted path
  /// (`null` records a deletion) and persists the journal.
  Future<void> recordPost(final String path, final String? content) async {
    _entryFor(path).postSha256 = content == null
        ? liveApplyDeletedSha256
        : liveApplySha256(content);
    await store.write(journal);
  }

  /// Creates or updates [path] with [content] under the journal.
  Future<FileOperationResult> writeFile(
    final String path,
    final String content,
  ) async {
    await _snapshot(path);
    final result = await _putFile(path, content);
    _entryFor(path).postSha256 = liveApplySha256(content);
    await store.write(journal);
    return result;
  }

  /// Deletes [path] under the journal.
  Future<FileOperationResult> deleteFile(final String path) async {
    await _snapshot(path);
    final result = await inner.deleteFile(path);
    _entryFor(path).postSha256 = liveApplyDeletedSha256;
    await store.write(journal);
    return result;
  }

  /// Create-or-update against the inner provider, tolerating the race where
  /// another writer created the path between the existence check and the
  /// create call (the same discipline [StorageService.saveFile] uses).
  Future<FileOperationResult> _putFile(
    final String path,
    final String content,
  ) async {
    final existing = await inner.getFile(path);
    if (existing != null) {
      return inner.updateFile(path, content);
    }
    try {
      return await inner.createFile(path, content);
    } on FileAlreadyExistsException {
      return inner.updateFile(path, content);
    }
  }

  /// Marks the run applied: it stays in the rollback window until
  /// [commit] prunes it. Mutations have already happened by now.
  Future<void> markApplied() async {
    journal.status = LiveApplyRunStatus.applied;
    await store.write(journal);
  }

  /// Accepts the run: freezes the state and prunes the journal.
  Future<void> commit() async {
    if (_isClosed) {
      throw LiveApplyRefusalException('run $runId is closed');
    }
    journal.status = LiveApplyRunStatus.committed;
    await store.prune(runId);
  }

  /// Verifies the rollback window (current content must match what the run
  /// left behind) and then replays the inverse in reverse first-touch
  /// order. A drift refusal mutates nothing.
  Future<void> rollback() async {
    if (journal.status == LiveApplyRunStatus.rolledBack) {
      throw LiveApplyRefusalException('run $runId was already rolled back');
    }
    if (_isClosed) {
      throw LiveApplyRefusalException('run $runId is closed');
    }
    final drift = <String>[];
    for (final entry in journal.entries) {
      final current = await inner.getFile(entry.path);
      final expectedDeletion = entry.postSha256 == liveApplyDeletedSha256;
      if (expectedDeletion && current == null) continue;
      if (!expectedDeletion && current != null) {
        if (liveApplySha256(current) == entry.postSha256) continue;
      }
      drift.add(entry.path);
    }
    if (drift.isNotEmpty) {
      throw LiveApplyDriftException(
        'footprint changed after the apply — rollback refused, reconcile '
        'manually: ${drift.take(10).join(', ')}',
        drift,
      );
    }
    for (final entry in journal.entries.reversed) {
      final prior = entry.prior;
      if (prior == null) {
        try {
          await inner.deleteFile(entry.path);
        } on FileNotFoundException {
          // Already gone — the goal state is reached either way.
        }
        continue;
      }
      await _putFile(entry.path, prior.content);
      final restored = await inner.getFile(entry.path);
      if (restored == null || liveApplySha256(restored) != prior.sha256) {
        throw LiveApplyDriftException(
          'restored content of ${entry.path} does not verify against the '
          'journal',
          [entry.path],
        );
      }
    }
    journal.status = LiveApplyRunStatus.rolledBack;
    await store.write(journal);
  }
}
