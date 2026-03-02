import 'package:meta/meta.dart';

import 'storage_profile.dart';

/// Decision lifecycle for sync/migration operations.
enum DecisionState { autoResolved, needsUserDecision, blocked }

/// Explicit per-operation migration action used by complex conflict workflows.
enum MigrationDecisionAction { overwrite, skip, abort }

MigrationDecisionAction? migrationDecisionActionFromString(
  final Object? value,
) {
  final name = value?.toString();
  if (name == null || name.isEmpty) {
    return null;
  }
  for (final action in MigrationDecisionAction.values) {
    if (action.name == name) {
      return action;
    }
  }
  return null;
}

/// Generic operation result used by kernel workflows.
@immutable
final class StorageOperationResult {
  const StorageOperationResult({
    required this.success,
    this.message = '',
    this.decisionState = DecisionState.autoResolved,
    this.metadata = const <String, dynamic>{},
  });

  factory StorageOperationResult.success({
    final String message = '',
    final Map<String, dynamic> metadata = const <String, dynamic>{},
  }) => StorageOperationResult(
    success: true,
    message: message,
    metadata: metadata,
  );

  factory StorageOperationResult.failure({
    required final String message,
    final DecisionState decisionState = DecisionState.blocked,
    final Map<String, dynamic> metadata = const <String, dynamic>{},
  }) => StorageOperationResult(
    success: false,
    message: message,
    decisionState: decisionState,
    metadata: metadata,
  );

  factory StorageOperationResult.fromJson(final Map<String, dynamic> json) {
    final stateName = (json['decision_state'] ?? 'autoResolved').toString();
    final state = DecisionState.values.firstWhere(
      (final e) => e.name == stateName,
      orElse: () => DecisionState.autoResolved,
    );

    return StorageOperationResult(
      success: json['success'] == true,
      message: (json['message'] ?? '').toString(),
      decisionState: state,
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map<dynamic, dynamic>)
          : const <String, dynamic>{},
    );
  }

  final bool success;
  final String message;
  final DecisionState decisionState;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
    'success': success,
    'message': message,
    'decision_state': decisionState.name,
    'metadata': metadata,
  };
}

/// Event kind emitted by [StorageKernelContract.observe].
enum StorageObservationType {
  created,
  updated,
  deleted,
  synced,
  syncSkipped,
  outboxQueued,
  outboxReplayed,
  outboxDeadLettered,
  conflictStaged,
  migrationPrepared,
  migrationExecuted,
  decisionResolved,
}

/// Event source origin.
enum StorageOperationOrigin { local, remote, system }

/// Observation event emitted by kernel operations.
@immutable
final class StorageObservationEvent {
  const StorageObservationEvent({
    required this.type,
    required this.namespace,
    required this.path,
    required this.timestamp,
    this.origin = StorageOperationOrigin.system,
    this.result,
    this.metadata = const <String, dynamic>{},
  });

  factory StorageObservationEvent.fromJson(final Map<String, dynamic> json) {
    final typeName = (json['type'] ?? 'updated').toString();
    final originName = (json['origin'] ?? 'system').toString();
    final type = StorageObservationType.values.firstWhere(
      (final e) => e.name == typeName,
      orElse: () => StorageObservationType.updated,
    );
    final origin = StorageOperationOrigin.values.firstWhere(
      (final e) => e.name == originName,
      orElse: () => StorageOperationOrigin.system,
    );
    final timestamp =
        DateTime.tryParse((json['timestamp'] ?? '').toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0);

    return StorageObservationEvent(
      type: type,
      namespace: StorageNamespace.fromJson(json['namespace']),
      path: (json['path'] ?? '').toString(),
      timestamp: timestamp,
      origin: origin,
      result: json['result'] is Map
          ? StorageOperationResult.fromJson(
              Map<String, dynamic>.from(
                json['result'] as Map<dynamic, dynamic>,
              ),
            )
          : null,
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map<dynamic, dynamic>)
          : const <String, dynamic>{},
    );
  }

  final StorageObservationType type;
  final StorageNamespace namespace;
  final String path;
  final DateTime timestamp;
  final StorageOperationOrigin origin;
  final StorageOperationResult? result;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'namespace': namespace.value,
    'path': path,
    'timestamp': timestamp.toIso8601String(),
    'origin': origin.name,
    if (result != null) 'result': result!.toJson(),
    'metadata': metadata,
  };
}

/// User-facing decision item for complex mode conflict/migration resolution.
@immutable
final class StorageDecision {
  const StorageDecision({
    required this.id,
    required this.namespace,
    required this.reason,
    this.diffSummary = '',
    this.metadata = const <String, dynamic>{},
  });

  factory StorageDecision.fromJson(final Map<String, dynamic> json) =>
      StorageDecision(
        id: (json['id'] ?? '').toString(),
        namespace: StorageNamespace.fromJson(json['namespace']),
        reason: (json['reason'] ?? '').toString(),
        diffSummary: (json['diff_summary'] ?? '').toString(),
        metadata: json['metadata'] is Map
            ? Map<String, dynamic>.from(
                json['metadata'] as Map<dynamic, dynamic>,
              )
            : const <String, dynamic>{},
      );

  final String id;
  final StorageNamespace namespace;
  final String reason;
  final String diffSummary;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
    'id': id,
    'namespace': namespace.value,
    'reason': reason,
    'diff_summary': diffSummary,
    'metadata': metadata,
  };
}
