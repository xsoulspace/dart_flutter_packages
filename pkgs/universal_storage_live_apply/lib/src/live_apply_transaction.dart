import 'dart:convert';

import 'package:universal_storage_interface/universal_storage_interface.dart';

import 'live_apply_exceptions.dart';
import 'live_apply_journal.dart';
import 'live_apply_models.dart';

/// One footprint journal with write-ahead intent and restartable inverse
/// replay.
/// Cooperating operations use the store lock. The host must exclude writers
/// bypassing that store; hash checks are not provider compare-and-swap.
class LiveApplyTransaction {
  LiveApplyTransaction._({
    required this.inner,
    required this.store,
    required this.journal,
    this.maxSnapshotFileBytes,
  });

  /// Provider receiving declared effects.
  final StorageProvider inner;

  /// Local recovery journal and cooperating writer exclusion.
  final LiveApplyJournalStore store;

  /// Latest durable run state, reloaded before each operation.
  LiveApplyJournal journal;

  /// UTF-8 byte limit on retained prior content.
  final int? maxSnapshotFileBytes;

  /// Persist a new run before any effect.
  static Future<LiveApplyTransaction> begin(
    final StorageProvider inner,
    final LiveApplyJournalStore store, {
    final int? maxSnapshotFileBytes,
  }) => store.withExclusive(() async {
    final runId = 'run-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    if (await store.read(runId) != null) {
      throw const LiveApplyRefusalException('run id collision');
    }
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
  });

  /// Reopen a retained run without dispatching effects.
  static Future<LiveApplyTransaction> reopen(
    final StorageProvider inner,
    final LiveApplyJournalStore store,
    final String runId, {
    final int? maxSnapshotFileBytes,
  }) => store.withExclusive(() async {
    final journal = await store.read(runId);
    if (journal == null) {
      throw LiveApplyRefusalException('no live-apply run $runId in the store');
    }
    if (journal.status == LiveApplyRunStatus.committed ||
        journal.status == LiveApplyRunStatus.rolledBack) {
      throw LiveApplyRefusalException('run $runId is ${journal.status.name}');
    }
    return LiveApplyTransaction._(
      inner: inner,
      store: store,
      journal: journal,
      maxSnapshotFileBytes: maxSnapshotFileBytes,
    );
  });

  /// Durable identifier of this run.
  String get runId => journal.runId;

  /// Last loaded lifecycle state.
  LiveApplyRunStatus get status => journal.status;

  Future<T> _exclusive<T>(final Future<T> Function() action) =>
      store.withExclusive(() async {
        final saved = await store.read(runId);
        if (saved == null) {
          throw LiveApplyRefusalException('run $runId is no longer retained');
        }
        journal = saved;
        return action();
      });

  void _requireMutable() {
    if (status != LiveApplyRunStatus.open) {
      throw LiveApplyRefusalException(
        'run $runId is ${status.name}; cannot mutate',
      );
    }
    if (journal.entries.any((final e) => e.pending)) {
      throw const LiveApplyRefusalException(
        'unfinished mutation; roll back before further mutation',
      );
    }
  }

  bool _matches(final String? actual, final String? hash) => actual == null
      ? hash == null
      : hash != null && liveApplySha256(actual) == hash;
  String? _post(final LiveApplyEntry e) => e.postAbsent ? null : e.postSha256;
  String? _prior(final LiveApplyEntry e) => e.prior?.sha256;

  Future<LiveApplyEntry> _snapshot(final String path) async {
    final existing = journal.entries.where((final e) => e.path == path);
    if (existing.isNotEmpty) return existing.first;
    final prior = await inner.getFile(path);
    final bytes = prior == null ? 0 : utf8.encode(prior).length;
    if (maxSnapshotFileBytes != null && bytes > maxSnapshotFileBytes!) {
      throw LiveApplyRefusalException(
        'path $path holds $bytes bytes, above maxSnapshotFileBytes',
      );
    }
    final entry = LiveApplyEntry(
      path: path,
      prior: prior == null
          ? null
          : LiveApplyPrior(sha256: liveApplySha256(prior), content: prior),
      postSha256: prior == null
          ? liveApplyDeletedSha256
          : liveApplySha256(prior),
      postAbsent: prior == null,
    );
    journal.entries.add(entry);
    await store.write(journal);
    return entry;
  }

  /// Snapshot-only callers must use [mutate] to declare an effect before it
  /// runs.
  Future<void> snapshot(final String path) => _exclusive(() async {
    _requireMutable();
    await _snapshot(path);
  });

  /// A post-only recording cannot make an earlier unjournaled write
  /// recoverable.
  /// Retained for source compatibility; callers migrate to [mutate].
  @Deprecated('Use mutate to persist intended state before the provider effect')
  Future<void> recordPost(final String path, final String? content) =>
      Future<void>.error(
        const LiveApplyRefusalException(
          'post-only journaling is unsafe; use mutate with declared content',
        ),
      );

  /// Execute one declared single-path effect, preserving provider semantics.
  /// Intended presence/hash and the pre-operation hash persist BEFORE dispatch.
  /// A thrown/unfinished operation retains both possible states for recovery.
  Future<FileOperationResult> mutate(
    final String path,
    final String? content,
    final Future<FileOperationResult> Function() effect,
  ) => _exclusive(() => _mutate(path, content, effect));

  Future<FileOperationResult> _mutate(
    final String path,
    final String? content,
    final Future<FileOperationResult> Function() effect,
  ) async {
    _requireMutable();
    final entry = await _snapshot(path);
    final before = await inner.getFile(path);
    if (!_matches(before, _post(entry))) {
      throw LiveApplyDriftException('path changed before mutation', [path]);
    }
    entry
      ..pendingPreSha256 = _post(entry)
      ..postSha256 = content == null
          ? liveApplyDeletedSha256
          : liveApplySha256(content)
      ..postAbsent = content == null
      ..pending = true;
    await store.write(journal);
    final result = await effect();
    final actual = await inner.getFile(path);
    if (!_matches(actual, _post(entry))) {
      throw LiveApplyDriftException('provider did not realize declared state', [
        path,
      ]);
    }
    entry
      ..pending = false
      ..pendingPreSha256 = null;
    await store.write(journal);
    return result;
  }

  /// Create or update one path under write-ahead intent.
  Future<FileOperationResult> writeFile(
    final String path,
    final String content,
  ) => mutate(path, content, () => _putFile(path, content));

  /// Delete one path under write-ahead intent.
  Future<FileOperationResult> deleteFile(final String path) =>
      mutate(path, null, () => inner.deleteFile(path));

  /// Append is lowered from one current read while holding the same lock.
  /// The provider still owns its append implementation and exception contract.
  Future<FileOperationResult> appendFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) => _exclusive(() async {
    _requireMutable();
    final before = await inner.getFile(path);
    return _mutate(
      path,
      '${before ?? ''}$content',
      () => inner.appendFile(path, content, commitMessage: commitMessage),
    );
  });

  Future<FileOperationResult> _putFile(
    final String path,
    final String content,
  ) async {
    final existing = await inner.getFile(path);
    return existing == null
        ? inner.createFile(path, content)
        : inner.updateFile(path, content);
  }

  /// Seal forward work while retaining the inverse window.
  Future<void> markApplied() => _exclusive(() async {
    _requireMutable();
    await _verifyPost();
    journal.status = LiveApplyRunStatus.applied;
    await store.write(journal);
  });

  /// Finalize only completed work and close the undo window.
  Future<void> commit() => _exclusive(() async {
    if ((status != LiveApplyRunStatus.open &&
            status != LiveApplyRunStatus.applied) ||
        journal.entries.any((final e) => e.pending)) {
      throw const LiveApplyRefusalException(
        'unfinished/closed run cannot finalize',
      );
    }
    await _verifyPost();
    // Persist the closed state before pruning, so a crash cannot regrant undo.
    journal.status = LiveApplyRunStatus.committed;
    await store.write(journal);
    await store.prune(runId);
  });

  Future<void> _verifyPost() async {
    final drift = <String>[];
    for (final e in journal.entries) {
      if (!_matches(await inner.getFile(e.path), _post(e))) drift.add(e.path);
    }
    if (drift.isNotEmpty) {
      throw LiveApplyDriftException('footprint drift before settlement', drift);
    }
  }

  /// Only discard a failed run after reading every footprint back unchanged.
  Future<bool> discardIfUnchanged() => _exclusive(() async {
    if (status != LiveApplyRunStatus.open) return false;
    for (final e in journal.entries) {
      if (!_matches(await inner.getFile(e.path), _prior(e))) return false;
    }
    await store.prune(runId);
    return true;
  });

  bool _recoverable(final LiveApplyEntry e, final String? actual) {
    if (e.restored) return _matches(actual, _prior(e));
    if (e.inverseStarted && _matches(actual, _prior(e))) return true;
    return _matches(actual, _post(e)) ||
        (e.pending && _matches(actual, e.pendingPreSha256));
  }

  /// Resume verified inverse replay; refuse unexplained footprint drift.
  Future<void> rollback() => _exclusive(() async {
    if (status != LiveApplyRunStatus.open &&
        status != LiveApplyRunStatus.applied &&
        status != LiveApplyRunStatus.rollingBack) {
      throw LiveApplyRefusalException(
        'run $runId is ${status.name}; cannot rollback',
      );
    }
    final drift = <String>[];
    for (final e in journal.entries) {
      if (!_recoverable(e, await inner.getFile(e.path))) drift.add(e.path);
    }
    if (drift.isNotEmpty) {
      throw LiveApplyDriftException('footprint drift; rollback refused', drift);
    }
    journal.status = LiveApplyRunStatus.rollingBack;
    await store.write(journal);
    for (final e in journal.entries.reversed) {
      if (e.restored) continue;
      // Persist authorization for either side of this inverse before dispatch.
      e.inverseStarted = true;
      await store.write(journal);
      final actual = await inner.getFile(e.path);
      if (!_recoverable(e, actual)) {
        throw LiveApplyDriftException('path changed during inverse', [e.path]);
      }
      if (!_matches(actual, _prior(e))) {
        if (e.prior == null) {
          await inner.deleteFile(e.path);
        } else {
          await _putFile(e.path, e.prior!.content);
        }
      }
      if (!_matches(await inner.getFile(e.path), _prior(e))) {
        throw LiveApplyDriftException(
          'inverse did not restore recorded state',
          [e.path],
        );
      }
      e
        ..restored = true
        ..pending = false;
      await store.write(journal);
    }
    journal.status = LiveApplyRunStatus.rolledBack;
    await store.write(journal);
  });
}
