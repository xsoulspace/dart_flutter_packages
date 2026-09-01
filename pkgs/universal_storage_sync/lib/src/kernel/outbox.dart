import 'dart:convert';

import 'package:universal_storage_interface/universal_storage_interface.dart';

import '../decision_store.dart';
import '../storage_kernel.dart';
import '../storage_profile_resolver.dart';
import '../sync_queue_store.dart';
import 'observation_hub.dart';

/// Enqueues durable, deduplicated outbox entries for local operations.
final class OutboxManager {
  OutboxManager({
    required this._queueStore,
    required this._observations,
  });

  final SyncQueueStore _queueStore;
  final ObservationHub _observations;

  /// Stages a write/delete operation in the namespace outbox.
  ///
  /// Entry ids are deterministic per (namespace, operation, path, seed) so
  /// repeated writes of identical content collapse into one entry.
  Future<String> enqueue({
    required final StorageNamespaceProfile namespaceProfile,
    required final StorageService service,
    required final SyncQueueOperationType operation,
    required final String path,
    required final String content,
    required final String? message,
    required final FileOperationResult result,
  }) async {
    final now = DateTime.now().toUtc();
    final contentDigest = operation == SyncQueueOperationType.write
        ? hashString(content)
        : '';
    final operationSeed = operation == SyncQueueOperationType.write
        ? (result.revisionId.isNotEmpty ? result.revisionId : contentDigest)
        : path;
    final entryId = deterministicEntryId(
      namespace: namespaceProfile.namespace,
      operation: operation,
      path: path,
      seed: operationSeed,
    );

    final metadata = <String, dynamic>{
      if (result.revisionId.isNotEmpty) 'revision_id': result.revisionId,
      if (result.metadata.isNotEmpty) ...result.metadata,
    };

    final newEntry = SyncOutboxEntry(
      id: entryId,
      namespace: namespaceProfile.namespace,
      operation: operation,
      path: path,
      createdAtUtc: now,
      updatedAtUtc: now,
      message: message ?? '',
      contentDigest: contentDigest,
      localRevisionId: result.revisionId,
      metadata: metadata,
    );

    var nextOutboxLength = 0;
    // Serialize load-modify-save so concurrent enqueues never lose entries.
    await _queueStore.mutateState(
      namespace: namespaceProfile.namespace,
      service: service,
      update: (final queueState) async {
        final nextOutbox = <SyncOutboxEntry>[
          for (final entry in queueState.outbox)
            if (entry.id != newEntry.id &&
                !(entry.path == newEntry.path && entry.operation == operation))
              entry,
          newEntry,
        ]..sort((final a, final b) => a.createdAtUtc.compareTo(b.createdAtUtc));
        nextOutboxLength = nextOutbox.length;
        return queueState.copyWith(outbox: nextOutbox);
      },
    );

    _observations.emit(
      type: StorageObservationType.outboxQueued,
      namespace: namespaceProfile.namespace,
      path: path,
      origin: StorageOperationOrigin.local,
      metadata: <String, dynamic>{
        'outbox_entry_id': entryId,
        'operation': operation.name,
        'outbox_pending': nextOutboxLength,
      },
    );

    return entryId;
  }

  /// Returns outbox snapshot for [namespace].
  Future<List<SyncOutboxEntry>> snapshot(
    final StorageNamespace namespace, {
    required final StorageService service,
  }) async {
    final state = await _queueStore.loadState(
      namespace: namespace,
      service: service,
    );
    return List<SyncOutboxEntry>.unmodifiable(state.outbox);
  }

  /// Returns dead-letter snapshot for [namespace].
  Future<List<SyncOutboxEntry>> deadLetterSnapshot(
    final StorageNamespace namespace, {
    required final StorageService service,
  }) async {
    final state = await _queueStore.loadState(
      namespace: namespace,
      service: service,
    );
    return List<SyncOutboxEntry>.unmodifiable(state.deadLetter);
  }
}

/// FNV-1a 64-bit hash used for stable content digests and entry ids.
String hashString(final String value) {
  final mask64 = BigInt.parse('ffffffffffffffff', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);

  for (final byte in utf8.encode(value)) {
    hash = ((hash ^ BigInt.from(byte)) * prime) & mask64;
  }

  return hash.toRadixString(16).padLeft(16, '0');
}

/// Deterministic outbox entry id; identical inputs collapse to one entry.
String deterministicEntryId({
  required final StorageNamespace namespace,
  required final SyncQueueOperationType operation,
  required final String path,
  required final String seed,
}) => hashString('${namespace.value}|${operation.name}|$path|$seed');

/// Result of one namespace sync replay pass.
final class NamespaceSyncReport {
  const NamespaceSyncReport({
    required this.queueState,
    required this.result,
    required this.replayedEntries,
    required this.deadLetteredEntries,
    required this.stagedConflicts,
    required this.metadata,
  });

  final SyncQueueState queueState;
  final StorageOperationResult result;
  final int replayedEntries;
  final int deadLetteredEntries;
  final int stagedConflicts;
  final Map<String, dynamic> metadata;
}

/// Replays due outbox entries against the remote with retry/backoff,
/// dead-lettering exhausted entries and staging conflicts on conflict errors.
final class OutboxReplayer {
  OutboxReplayer({
    required this._decisionStore,
    required this._observations,
    required this._conflictDecisionHook,
  });

  final DecisionStore _decisionStore;
  final ObservationHub _observations;
  final ConflictDecisionHook? _conflictDecisionHook;

  final Map<StorageNamespace, String> interactionDowngradeReasons =
      <StorageNamespace, String>{};

  /// Runs one replay pass over [queueState] for [namespaceProfile].
  Future<NamespaceSyncReport> run({
    required final StorageNamespaceProfile namespaceProfile,
    required final SyncInteractionLevel interactionLevel,
    required final StorageService service,
    required final SyncQueueState queueState,
    required final Future<StorageOperationResult> Function() performSync,
  }) async {
    final now = DateTime.now().toUtc();
    final queuePolicy = namespaceProfile.queuePolicy;

    var outbox = <SyncOutboxEntry>[];
    final deadLetter = List<SyncOutboxEntry>.from(queueState.deadLetter);
    var conflicts = List<SyncConflictEntry>.from(queueState.conflicts);
    final appliedEntryIds = uniqueStrings(queueState.appliedEntryIds);

    var deadLetteredEntries = 0;
    for (final entry in queueState.outbox) {
      if (appliedEntryIds.contains(entry.id)) {
        continue;
      }
      if (queuePolicy.exceedsMaxAge(
        createdAtUtc: entry.createdAtUtc,
        nowUtc: now,
      )) {
        final deadEntry = entry.copyWith(
          updatedAtUtc: now,
          lastError: entry.lastError.isEmpty
              ? 'Entry exceeded max age policy.'
              : entry.lastError,
        );
        deadLetter.add(deadEntry);
        deadLetteredEntries++;
        _observations.emit(
          type: StorageObservationType.outboxDeadLettered,
          namespace: namespaceProfile.namespace,
          path: entry.path,
          metadata: <String, dynamic>{
            'outbox_entry_id': entry.id,
            'reason': 'max_age_exceeded',
          },
        );
        continue;
      }
      outbox.add(entry);
    }

    outbox.sort((final a, final b) => a.createdAtUtc.compareTo(b.createdAtUtc));

    final dueEntries = outbox
        .where(
          (final entry) =>
              entry.nextAttemptAtUtc == null ||
              !entry.nextAttemptAtUtc!.isAfter(now),
        )
        .toList(growable: false);

    StorageOperationResult syncResult;
    var replayedEntries = 0;
    var stagedConflicts = 0;
    var metadata = const <String, dynamic>{};

    try {
      final providerSyncResult = await performSync();
      syncResult = providerSyncResult;
      metadata = providerSyncResult.metadata;

      final syncWasSkipped = metadata['sync_skipped'] != null;
      if (dueEntries.isNotEmpty && !syncWasSkipped) {
        final replayedIds = dueEntries.map((final item) => item.id).toSet();
        outbox = outbox
            .where((final entry) => !replayedIds.contains(entry.id))
            .toList(growable: false);

        for (final replayed in dueEntries) {
          if (!appliedEntryIds.contains(replayed.id)) {
            appliedEntryIds.add(replayed.id);
          }
          replayedEntries++;
          _observations.emit(
            type: StorageObservationType.outboxReplayed,
            namespace: namespaceProfile.namespace,
            path: replayed.path,
            origin: StorageOperationOrigin.remote,
            metadata: <String, dynamic>{
              'outbox_entry_id': replayed.id,
              'operation': replayed.operation.name,
            },
          );
        }
      } else if (dueEntries.isNotEmpty && syncWasSkipped) {
        // Sync was skipped (e.g. no remote configured): keep entries queued.
        metadata = <String, dynamic>{
          ...metadata,
          'outbox_retained': dueEntries.length,
        };
      }
    } on Object catch (error) {
      final message = errorMessage(error);
      final isConflict = isConflictError(error);
      final dueIds = dueEntries.map((final entry) => entry.id).toSet();
      final nextOutbox = <SyncOutboxEntry>[];

      for (final entry in outbox) {
        if (!dueIds.contains(entry.id)) {
          nextOutbox.add(entry);
          continue;
        }

        final updatedAttempts = entry.attempts + 1;
        final updatedEntry = entry.copyWith(
          updatedAtUtc: now,
          attempts: updatedAttempts,
          nextAttemptAtUtc: now.add(
            queuePolicy.backoffForAttempt(updatedAttempts),
          ),
          lastError: message,
        );

        var shouldDeadLetter = updatedAttempts >= queuePolicy.maxRetries;
        if (queuePolicy.exceedsMaxAge(
          createdAtUtc: updatedEntry.createdAtUtc,
          nowUtc: now,
        )) {
          shouldDeadLetter = true;
        }

        if (isConflict) {
          final conflictState = await stageConflict(
            namespaceProfile: namespaceProfile,
            interactionLevel: interactionLevel,
            outboxEntry: updatedEntry,
            reason: message,
            existingConflicts: conflicts,
          );
          conflicts = conflictState.conflicts;
          stagedConflicts += conflictState.stagedCount;

          if (conflictState.decisionState == DecisionState.blocked) {
            shouldDeadLetter = true;
          }
        }

        if (shouldDeadLetter) {
          deadLetter.add(updatedEntry);
          deadLetteredEntries++;
          _observations.emit(
            type: StorageObservationType.outboxDeadLettered,
            namespace: namespaceProfile.namespace,
            path: updatedEntry.path,
            metadata: <String, dynamic>{
              'outbox_entry_id': updatedEntry.id,
              'reason': isConflict ? 'conflict_or_retry_limit' : 'retry_limit',
              'attempts': updatedEntry.attempts,
            },
          );
        } else {
          nextOutbox.add(updatedEntry);
        }
      }

      outbox = nextOutbox;

      syncResult = StorageOperationResult.failure(
        message: message,
        decisionState: isConflict
            ? DecisionState.needsUserDecision
            : DecisionState.blocked,
        metadata: <String, dynamic>{
          'error_type': error.runtimeType.toString(),
          if (isConflict) 'conflict': true,
        },
      );
      metadata = syncResult.metadata;
    }

    return NamespaceSyncReport(
      queueState: SyncQueueState(
        outbox: List<SyncOutboxEntry>.unmodifiable(outbox),
        deadLetter: List<SyncOutboxEntry>.unmodifiable(deadLetter),
        conflicts: List<SyncConflictEntry>.unmodifiable(conflicts),
        appliedEntryIds: List<String>.unmodifiable(appliedEntryIds),
      ),
      result: syncResult,
      replayedEntries: replayedEntries,
      deadLetteredEntries: deadLetteredEntries,
      stagedConflicts: stagedConflicts,
      metadata: metadata,
    );
  }

  /// Stages a conflict bound to [outboxEntry], honoring hook or minimal mode.
  Future<ConflictStageResult> stageConflict({
    required final StorageNamespaceProfile namespaceProfile,
    required final SyncInteractionLevel interactionLevel,
    required final SyncOutboxEntry outboxEntry,
    required final String reason,
    required final List<SyncConflictEntry> existingConflicts,
  }) async {
    final now = DateTime.now().toUtc();
    final conflictId = 'conflict_${outboxEntry.id}';

    var decisionState = DecisionState.needsUserDecision;
    var stagedCount = 0;

    SyncConflictEntry conflict = SyncConflictEntry(
      id: conflictId,
      namespace: namespaceProfile.namespace,
      outboxEntryId: outboxEntry.id,
      path: outboxEntry.path,
      reason: reason,
      decisionState: decisionState,
      createdAtUtc: now,
      updatedAtUtc: now,
      metadata: <String, dynamic>{
        'operation': outboxEntry.operation.name,
        'attempts': outboxEntry.attempts,
      },
    );

    final hook = _conflictDecisionHook;
    if (hook != null) {
      decisionState = await hook(conflict);
      conflict = conflict.copyWith(decisionState: decisionState);
    } else if (interactionLevel == SyncInteractionLevel.minimal) {
      decisionState = DecisionState.needsUserDecision;
      conflict = conflict.copyWith(decisionState: decisionState);
    }

    final decisionId = 'decision_$conflictId';
    await _decisionStore.saveState(
      decisionId: decisionId,
      state: decisionState,
      note: reason,
    );

    final conflictIndex = existingConflicts.indexWhere(
      (final item) => item.id == conflict.id,
    );
    final nextConflicts = List<SyncConflictEntry>.from(existingConflicts);
    if (conflictIndex >= 0) {
      final existing = nextConflicts[conflictIndex];
      nextConflicts[conflictIndex] = existing.copyWith(
        reason: reason,
        decisionState: decisionState,
        updatedAtUtc: now,
        metadata: <String, dynamic>{
          ...existing.metadata,
          ...conflict.metadata,
          'attempts': outboxEntry.attempts,
        },
      );
    } else {
      nextConflicts.add(conflict);
      stagedCount = 1;
      _observations.emit(
        type: StorageObservationType.conflictStaged,
        namespace: namespaceProfile.namespace,
        path: outboxEntry.path,
        metadata: <String, dynamic>{
          'conflict_entry_id': conflict.id,
          'outbox_entry_id': outboxEntry.id,
          'decision_id': decisionId,
          'decision_state': decisionState.name,
        },
      );
    }

    return ConflictStageResult(
      conflicts: nextConflicts,
      stagedCount: stagedCount,
      decisionState: decisionState,
    );
  }
}

/// Result of staging one conflict against existing queue state.
final class ConflictStageResult {
  const ConflictStageResult({
    required this.conflicts,
    required this.stagedCount,
    required this.decisionState,
  });

  final List<SyncConflictEntry> conflicts;
  final int stagedCount;
  final DecisionState decisionState;
}

/// Applies a resolved decision to the persisted conflict/outbox queues.
Future<void> applyDecisionToQueues({
  required final DecisionStore decisionStore,
  required final SyncQueueStore queueStore,
  required final ObservationHub observations,
  required final StorageProfileResolver resolver,
  required final StorageDecision decision,
  required final DecisionState targetState,
  required final String note,
}) async {
  final conflictEntryId = decision.metadata['conflict_entry_id']?.toString();
  final outboxEntryId = decision.metadata['outbox_entry_id']?.toString();

  if ((conflictEntryId == null || conflictEntryId.isEmpty) &&
      (outboxEntryId == null || outboxEntryId.isEmpty)) {
    return;
  }

  final service = await resolver.resolveService(decision.namespace);

  // Serialize load-modify-save so concurrent queue writers never lose updates.
  await queueStore.mutateState(
    namespace: decision.namespace,
    service: service,
    update: (final currentState) async {
      var conflicts = List<SyncConflictEntry>.from(currentState.conflicts);
      final outbox = List<SyncOutboxEntry>.from(currentState.outbox);
      final deadLetter = List<SyncOutboxEntry>.from(currentState.deadLetter);

      if (conflictEntryId != null && conflictEntryId.isNotEmpty) {
        conflicts = conflicts
            .map(
              (final entry) => entry.id == conflictEntryId
                  ? entry.copyWith(
                      decisionState: targetState,
                      updatedAtUtc: DateTime.now().toUtc(),
                      metadata: <String, dynamic>{
                        ...entry.metadata,
                        if (note.isNotEmpty) 'decision_note': note,
                      },
                    )
                  : entry,
            )
            .toList(growable: false);

        if (targetState != DecisionState.needsUserDecision) {
          conflicts = conflicts
              .where((final entry) => entry.id != conflictEntryId)
              .toList(growable: false);
        }
      }

      if (outboxEntryId != null && outboxEntryId.isNotEmpty) {
        final entryIndex = outbox.indexWhere(
          (final entry) => entry.id == outboxEntryId,
        );
        if (entryIndex >= 0) {
          final entry = outbox[entryIndex];
          if (targetState == DecisionState.blocked) {
            outbox.removeAt(entryIndex);
            deadLetter.add(
              entry.copyWith(
                updatedAtUtc: DateTime.now().toUtc(),
                lastError: note.isEmpty ? 'Blocked by user decision.' : note,
              ),
            );
            observations.emit(
              type: StorageObservationType.outboxDeadLettered,
              namespace: decision.namespace,
              path: entry.path,
              metadata: <String, dynamic>{
                'outbox_entry_id': entry.id,
                'reason': 'decision_blocked',
              },
            );
          } else if (targetState == DecisionState.autoResolved) {
            outbox[entryIndex] = entry.copyWith(
              updatedAtUtc: DateTime.now().toUtc(),
              nextAttemptAtUtc: DateTime.now().toUtc(),
              lastError: '',
            );
          }
        }
      }

      return currentState.copyWith(
        outbox: outbox,
        deadLetter: deadLetter,
        conflicts: conflicts,
      );
    },
  );
}

/// Deduplicates non-empty strings preserving order.
List<String> uniqueStrings(final List<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    if (value.isEmpty || !seen.add(value)) {
      continue;
    }
    result.add(value);
  }
  return result;
}

/// True when [error] represents a sync/merge conflict requiring a decision.
bool isConflictError(final Object error) =>
    error is SyncConflictException ||
    error is GitConflictException ||
    error is MergeConflictException ||
    error is DecisionRequiredException;

/// Extracts a human-readable message from storage errors.
String errorMessage(final Object error) {
  if (error is StorageException) {
    return error.message;
  }
  return error.toString();
}
