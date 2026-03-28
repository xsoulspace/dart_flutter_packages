import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

/// Local operation type staged in namespace outbox.
enum SyncQueueOperationType { write, delete }

/// Durable outbox entry used for optimistic replay.
@immutable
final class SyncOutboxEntry {
  const SyncOutboxEntry({
    required this.id,
    required this.namespace,
    required this.operation,
    required this.path,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.message = '',
    this.contentDigest = '',
    this.localRevisionId = '',
    this.attempts = 0,
    this.nextAttemptAtUtc,
    this.lastError = '',
    this.metadata = const <String, dynamic>{},
  });

  factory SyncOutboxEntry.fromJson(final Map<String, dynamic> json) {
    final operationName = (json['operation'] ?? 'write').toString();
    final operation = SyncQueueOperationType.values.firstWhere(
      (final item) => item.name == operationName,
      orElse: () => SyncQueueOperationType.write,
    );

    final createdAtUtc =
        DateTime.tryParse((json['created_at'] ?? '').toString())?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final updatedAtUtc =
        DateTime.tryParse((json['updated_at'] ?? '').toString())?.toUtc() ??
        createdAtUtc;

    return SyncOutboxEntry(
      id: (json['id'] ?? '').toString(),
      namespace: StorageNamespace.fromJson(json['namespace']),
      operation: operation,
      path: (json['path'] ?? '').toString(),
      createdAtUtc: createdAtUtc,
      updatedAtUtc: updatedAtUtc,
      message: (json['message'] ?? '').toString(),
      contentDigest: (json['content_digest'] ?? '').toString(),
      localRevisionId: (json['local_revision_id'] ?? '').toString(),
      attempts: _parseNonNegativeInt(json['attempts']),
      nextAttemptAtUtc: DateTime.tryParse(
        (json['next_attempt_at'] ?? '').toString(),
      )?.toUtc(),
      lastError: (json['last_error'] ?? '').toString(),
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map<dynamic, dynamic>)
          : const <String, dynamic>{},
    );
  }

  final String id;
  final StorageNamespace namespace;
  final SyncQueueOperationType operation;
  final String path;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final String message;
  final String contentDigest;
  final String localRevisionId;
  final int attempts;
  final DateTime? nextAttemptAtUtc;
  final String lastError;
  final Map<String, dynamic> metadata;

  SyncOutboxEntry copyWith({
    final DateTime? updatedAtUtc,
    final int? attempts,
    final DateTime? nextAttemptAtUtc,
    final String? lastError,
    final Map<String, dynamic>? metadata,
  }) => SyncOutboxEntry(
    id: id,
    namespace: namespace,
    operation: operation,
    path: path,
    createdAtUtc: createdAtUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    message: message,
    contentDigest: contentDigest,
    localRevisionId: localRevisionId,
    attempts: attempts ?? this.attempts,
    nextAttemptAtUtc: nextAttemptAtUtc ?? this.nextAttemptAtUtc,
    lastError: lastError ?? this.lastError,
    metadata: metadata ?? this.metadata,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'namespace': namespace.value,
    'operation': operation.name,
    'path': path,
    'created_at': createdAtUtc.toIso8601String(),
    'updated_at': updatedAtUtc.toIso8601String(),
    'message': message,
    'content_digest': contentDigest,
    'local_revision_id': localRevisionId,
    'attempts': attempts,
    if (nextAttemptAtUtc != null)
      'next_attempt_at': nextAttemptAtUtc!.toIso8601String(),
    'last_error': lastError,
    'metadata': metadata,
  };

  static int _parseNonNegativeInt(final Object? raw) {
    if (raw is int) {
      return raw < 0 ? 0 : raw;
    }
    if (raw is num) {
      final value = raw.toInt();
      return value < 0 ? 0 : value;
    }
    if (raw is String) {
      final value = int.tryParse(raw.trim());
      if (value != null) {
        return value < 0 ? 0 : value;
      }
    }
    return 0;
  }
}

/// Staged conflict item bound to one outbox entry.
@immutable
final class SyncConflictEntry {
  const SyncConflictEntry({
    required this.id,
    required this.namespace,
    required this.outboxEntryId,
    required this.path,
    required this.reason,
    required this.decisionState,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.metadata = const <String, dynamic>{},
  });

  factory SyncConflictEntry.fromJson(final Map<String, dynamic> json) {
    final decisionStateName = (json['decision_state'] ?? 'needsUserDecision')
        .toString();
    final decisionState = DecisionState.values.firstWhere(
      (final value) => value.name == decisionStateName,
      orElse: () => DecisionState.needsUserDecision,
    );

    final createdAtUtc =
        DateTime.tryParse((json['created_at'] ?? '').toString())?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    return SyncConflictEntry(
      id: (json['id'] ?? '').toString(),
      namespace: StorageNamespace.fromJson(json['namespace']),
      outboxEntryId: (json['outbox_entry_id'] ?? '').toString(),
      path: (json['path'] ?? '').toString(),
      reason: (json['reason'] ?? '').toString(),
      decisionState: decisionState,
      createdAtUtc: createdAtUtc,
      updatedAtUtc:
          DateTime.tryParse((json['updated_at'] ?? '').toString())?.toUtc() ??
          createdAtUtc,
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map<dynamic, dynamic>)
          : const <String, dynamic>{},
    );
  }

  final String id;
  final StorageNamespace namespace;
  final String outboxEntryId;
  final String path;
  final String reason;
  final DecisionState decisionState;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final Map<String, dynamic> metadata;

  SyncConflictEntry copyWith({
    final String? reason,
    final DecisionState? decisionState,
    final DateTime? updatedAtUtc,
    final Map<String, dynamic>? metadata,
  }) => SyncConflictEntry(
    id: id,
    namespace: namespace,
    outboxEntryId: outboxEntryId,
    path: path,
    reason: reason ?? this.reason,
    decisionState: decisionState ?? this.decisionState,
    createdAtUtc: createdAtUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    metadata: metadata ?? this.metadata,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'namespace': namespace.value,
    'outbox_entry_id': outboxEntryId,
    'path': path,
    'reason': reason,
    'decision_state': decisionState.name,
    'created_at': createdAtUtc.toIso8601String(),
    'updated_at': updatedAtUtc.toIso8601String(),
    'metadata': metadata,
  };
}

/// Queue state persisted per namespace.
@immutable
final class SyncQueueState {
  const SyncQueueState({
    this.outbox = const <SyncOutboxEntry>[],
    this.deadLetter = const <SyncOutboxEntry>[],
    this.conflicts = const <SyncConflictEntry>[],
    this.appliedEntryIds = const <String>[],
  });

  final List<SyncOutboxEntry> outbox;
  final List<SyncOutboxEntry> deadLetter;
  final List<SyncConflictEntry> conflicts;
  final List<String> appliedEntryIds;

  SyncQueueState copyWith({
    final List<SyncOutboxEntry>? outbox,
    final List<SyncOutboxEntry>? deadLetter,
    final List<SyncConflictEntry>? conflicts,
    final List<String>? appliedEntryIds,
  }) => SyncQueueState(
    outbox: outbox ?? this.outbox,
    deadLetter: deadLetter ?? this.deadLetter,
    conflicts: conflicts ?? this.conflicts,
    appliedEntryIds: appliedEntryIds ?? this.appliedEntryIds,
  );
}

/// Durable persistence API for namespace sync queues.
abstract interface class SyncQueueStore {
  Future<SyncQueueState> loadState({
    required final StorageNamespace namespace,
    required final StorageService service,
  });

  Future<void> saveState({
    required final StorageNamespace namespace,
    required final StorageService service,
    required final SyncQueueState state,
  });
}

/// In-memory queue persistence.
final class InMemorySyncQueueStore implements SyncQueueStore {
  final Map<StorageNamespace, SyncQueueState> _states =
      <StorageNamespace, SyncQueueState>{};

  @override
  Future<SyncQueueState> loadState({
    required final StorageNamespace namespace,
    required final StorageService service,
  }) async {
    final state = _states[namespace] ?? const SyncQueueState();
    return SyncQueueState(
      outbox: List<SyncOutboxEntry>.unmodifiable(state.outbox),
      deadLetter: List<SyncOutboxEntry>.unmodifiable(state.deadLetter),
      conflicts: List<SyncConflictEntry>.unmodifiable(state.conflicts),
      appliedEntryIds: List<String>.unmodifiable(state.appliedEntryIds),
    );
  }

  @override
  Future<void> saveState({
    required final StorageNamespace namespace,
    required final StorageService service,
    required final SyncQueueState state,
  }) async {
    _states[namespace] = SyncQueueState(
      outbox: List<SyncOutboxEntry>.unmodifiable(state.outbox),
      deadLetter: List<SyncOutboxEntry>.unmodifiable(state.deadLetter),
      conflicts: List<SyncConflictEntry>.unmodifiable(state.conflicts),
      appliedEntryIds: List<String>.unmodifiable(state.appliedEntryIds),
    );
  }
}

/// Storage-backed queue store that survives process restarts.
final class StorageServiceSyncQueueStore implements SyncQueueStore {
  StorageServiceSyncQueueStore({
    this.path = '.us/sync_queue_v1.json',
    this.maxAppliedEntryIds = 512,
  });

  final String path;
  final int maxAppliedEntryIds;

  @override
  Future<SyncQueueState> loadState({
    required final StorageNamespace namespace,
    required final StorageService service,
  }) async {
    final content = await service.readFile(path);
    if (content == null || content.trim().isEmpty) {
      return const SyncQueueState();
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException {
      return const SyncQueueState();
    }

    if (decoded is! Map) {
      return const SyncQueueState();
    }

    final raw = Map<String, dynamic>.from(decoded);

    List<SyncOutboxEntry> parseOutbox(final String key) {
      final rawList = raw[key];
      if (rawList is! List) {
        return const <SyncOutboxEntry>[];
      }
      return rawList
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (final item) =>
                SyncOutboxEntry.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((final entry) => entry.namespace == namespace)
          .toList(growable: false);
    }

    final rawConflicts = raw['conflicts'];
    final conflicts = rawConflicts is List
        ? rawConflicts
              .whereType<Map<dynamic, dynamic>>()
              .map(
                (final item) =>
                    SyncConflictEntry.fromJson(Map<String, dynamic>.from(item)),
              )
              .where((final entry) => entry.namespace == namespace)
              .toList(growable: false)
        : const <SyncConflictEntry>[];

    final rawAppliedIds = raw['applied_entry_ids'];
    final appliedIds = rawAppliedIds is List
        ? rawAppliedIds
              .map((final item) => item.toString())
              .where((final item) => item.isNotEmpty)
              .toSet()
              .toList(growable: false)
        : const <String>[];

    return SyncQueueState(
      outbox: parseOutbox('outbox'),
      deadLetter: parseOutbox('dead_letter'),
      conflicts: conflicts,
      appliedEntryIds: _boundedAppliedIds(appliedIds),
    );
  }

  @override
  Future<void> saveState({
    required final StorageNamespace namespace,
    required final StorageService service,
    required final SyncQueueState state,
  }) async {
    final payload = <String, dynamic>{
      'schema_version': 1,
      'namespace': namespace.value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'outbox': state.outbox.map((final entry) => entry.toJson()).toList(),
      'dead_letter': state.deadLetter
          .map((final entry) => entry.toJson())
          .toList(),
      'conflicts': state.conflicts
          .map((final entry) => entry.toJson())
          .toList(),
      'applied_entry_ids': _boundedAppliedIds(state.appliedEntryIds),
    };

    await service.saveFile(
      path,
      jsonEncode(payload),
      message: 'Persist sync queue state for ${namespace.value}',
    );
  }

  List<String> _boundedAppliedIds(final List<String> ids) {
    final unique = <String>[];
    final seen = <String>{};

    for (final id in ids) {
      if (id.isEmpty || !seen.add(id)) {
        continue;
      }
      unique.add(id);
    }

    if (unique.length <= maxAppliedEntryIds) {
      return List<String>.unmodifiable(unique);
    }

    final startIndex = unique.length - maxAppliedEntryIds;
    return List<String>.unmodifiable(unique.sublist(startIndex));
  }
}
