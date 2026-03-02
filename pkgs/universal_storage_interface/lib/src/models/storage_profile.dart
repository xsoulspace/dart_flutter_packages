import 'package:meta/meta.dart';

import 'conflict_resolution_strategy.dart';

/// Logical namespace used to separate storage domains.
@immutable
final class StorageNamespace {
  const StorageNamespace(this.value) : assert(value != '');

  factory StorageNamespace.fromJson(final Object? json) =>
      StorageNamespace((json ?? '').toString());

  final String value;

  static const settings = StorageNamespace('settings');
  static const projects = StorageNamespace('projects');
  static const saves = StorageNamespace('saves');
  static const cache = StorageNamespace('cache');

  Map<String, dynamic> toJson() => {'value': value};

  @override
  String toString() => value;

  @override
  bool operator ==(final Object other) =>
      identical(this, other) ||
      (other is StorageNamespace && other.value == value);

  @override
  int get hashCode => value.hashCode;
}

/// Stable logical object id independent from backend-specific paths.
@immutable
final class StorageObjectId {
  const StorageObjectId(this.value) : assert(value != '');

  factory StorageObjectId.fromJson(final Object? json) =>
      StorageObjectId((json ?? '').toString());

  final String value;

  Map<String, dynamic> toJson() => {'value': value};

  @override
  String toString() => value;

  @override
  bool operator ==(final Object other) =>
      identical(this, other) ||
      (other is StorageObjectId && other.value == value);

  @override
  int get hashCode => value.hashCode;
}

/// Namespace sync/write behavior policy.
enum StoragePolicy { localOnly, optimisticSync, remoteFirst, remoteOnly }

/// Interaction layer for sync and migration decisions.
enum SyncInteractionLevel {
  /// Silent operation, automatic decisions, notifications when action needed.
  minimal,

  /// User-visible diffs and explicit decision workflow.
  complex,
}

/// Retry/backoff policy for namespace outbox replay.
@immutable
final class SyncQueuePolicy {
  const SyncQueuePolicy({
    this.maxRetries = 3,
    this.initialBackoffMs = 1000,
    this.maxBackoffMs = 30000,
    this.maxEntryAgeMs = 86400000,
  });

  factory SyncQueuePolicy.fromJson(final Map<String, dynamic> json) =>
      SyncQueuePolicy(
        maxRetries: _parsePositiveInt(json['max_retries'], fallback: 3),
        initialBackoffMs: _parsePositiveInt(
          json['initial_backoff_ms'],
          fallback: 1000,
        ),
        maxBackoffMs: _parsePositiveInt(
          json['max_backoff_ms'],
          fallback: 30000,
        ),
        maxEntryAgeMs: _parsePositiveInt(
          json['max_entry_age_ms'],
          fallback: 86400000,
        ),
      );

  final int maxRetries;
  final int initialBackoffMs;
  final int maxBackoffMs;
  final int maxEntryAgeMs;

  Duration backoffForAttempt(final int attempt) {
    final normalizedAttempt = attempt < 1 ? 1 : attempt;
    var delayMs = initialBackoffMs;
    for (var i = 1; i < normalizedAttempt; i++) {
      delayMs = delayMs * 2;
      if (delayMs >= maxBackoffMs) {
        delayMs = maxBackoffMs;
        break;
      }
    }
    return Duration(milliseconds: delayMs);
  }

  bool exceedsMaxAge({
    required final DateTime createdAtUtc,
    required final DateTime nowUtc,
  }) => nowUtc.difference(createdAtUtc).inMilliseconds > maxEntryAgeMs;

  Map<String, dynamic> toJson() => {
    'max_retries': maxRetries,
    'initial_backoff_ms': initialBackoffMs,
    'max_backoff_ms': maxBackoffMs,
    'max_entry_age_ms': maxEntryAgeMs,
  };

  static int _parsePositiveInt(
    final Object? raw, {
    required final int fallback,
  }) {
    if (raw is int) {
      return raw > 0 ? raw : fallback;
    }
    if (raw is num) {
      final value = raw.toInt();
      return value > 0 ? value : fallback;
    }
    if (raw is String) {
      final value = int.tryParse(raw.trim());
      if (value != null && value > 0) {
        return value;
      }
    }
    return fallback;
  }
}

/// Provider capability set used for profile negotiation.
@immutable
final class StorageCapabilities {
  const StorageCapabilities({
    this.supportsDiff = false,
    this.supportsHistory = false,
    this.supportsRevisionMetadata = false,
    this.supportsManualConflictResolution = false,
    this.supportsBackgroundSync = false,
    this.supportsMigrationEndpoint = false,
  });

  factory StorageCapabilities.fromJson(final Map<String, dynamic> json) =>
      StorageCapabilities(
        supportsDiff: json['supports_diff'] == true,
        supportsHistory: json['supports_history'] == true,
        supportsRevisionMetadata: json['supports_revision_metadata'] == true,
        supportsManualConflictResolution:
            json['supports_manual_conflict_resolution'] == true,
        supportsBackgroundSync: json['supports_background_sync'] == true,
        supportsMigrationEndpoint: json['supports_migration_endpoint'] == true,
      );

  static const none = StorageCapabilities();

  final bool supportsDiff;
  final bool supportsHistory;
  final bool supportsRevisionMetadata;
  final bool supportsManualConflictResolution;
  final bool supportsBackgroundSync;
  final bool supportsMigrationEndpoint;

  bool get supportsComplexInteraction =>
      supportsDiff &&
      supportsHistory &&
      supportsRevisionMetadata &&
      supportsManualConflictResolution;

  bool satisfies(final StorageCapabilities required) =>
      (!required.supportsDiff || supportsDiff) &&
      (!required.supportsHistory || supportsHistory) &&
      (!required.supportsRevisionMetadata || supportsRevisionMetadata) &&
      (!required.supportsManualConflictResolution ||
          supportsManualConflictResolution) &&
      (!required.supportsBackgroundSync || supportsBackgroundSync) &&
      (!required.supportsMigrationEndpoint || supportsMigrationEndpoint);

  Map<String, dynamic> toJson() => {
    'supports_diff': supportsDiff,
    'supports_history': supportsHistory,
    'supports_revision_metadata': supportsRevisionMetadata,
    'supports_manual_conflict_resolution': supportsManualConflictResolution,
    'supports_background_sync': supportsBackgroundSync,
    'supports_migration_endpoint': supportsMigrationEndpoint,
  };
}

/// Per-namespace profile binding for local/remote engines and policies.
@immutable
final class StorageNamespaceProfile {
  const StorageNamespaceProfile({
    required this.namespace,
    required this.policy,
    this.localEngineId = 'default',
    this.remoteEngineId,
    this.pathPrefix = '',
    this.defaultFileExtension = '.json',
    this.conflictResolution = ConflictResolutionStrategy.clientAlwaysRight,
    this.syncInteractionLevel = SyncInteractionLevel.minimal,
    this.requiredCapabilities = StorageCapabilities.none,
    this.queuePolicy = const SyncQueuePolicy(),
  });

  factory StorageNamespaceProfile.fromJson(final Map<String, dynamic> json) {
    final namespace = StorageNamespace.fromJson(json['namespace']);
    final policyName = (json['policy'] ?? '').toString();
    final interactionName = (json['sync_interaction_level'] ?? 'minimal')
        .toString();
    final conflictName = (json['conflict_resolution'] ?? 'clientAlwaysRight')
        .toString();

    final policy = StoragePolicy.values.firstWhere(
      (final e) => e.name == policyName,
      orElse: () => StoragePolicy.localOnly,
    );
    final interaction = SyncInteractionLevel.values.firstWhere(
      (final e) => e.name == interactionName,
      orElse: () => SyncInteractionLevel.minimal,
    );
    final conflict = ConflictResolutionStrategy.values.firstWhere(
      (final e) => e.name == conflictName,
      orElse: () => ConflictResolutionStrategy.clientAlwaysRight,
    );

    return StorageNamespaceProfile(
      namespace: namespace,
      policy: policy,
      localEngineId: (json['local_engine_id'] ?? 'default').toString(),
      remoteEngineId: json['remote_engine_id']?.toString(),
      pathPrefix: (json['path_prefix'] ?? '').toString(),
      defaultFileExtension: (json['default_file_extension'] ?? '.json')
          .toString(),
      conflictResolution: conflict,
      syncInteractionLevel: interaction,
      requiredCapabilities: json['required_capabilities'] is Map
          ? StorageCapabilities.fromJson(
              Map<String, dynamic>.from(
                json['required_capabilities'] as Map<dynamic, dynamic>,
              ),
            )
          : StorageCapabilities.none,
      queuePolicy: json['queue_policy'] is Map
          ? SyncQueuePolicy.fromJson(
              Map<String, dynamic>.from(
                json['queue_policy'] as Map<dynamic, dynamic>,
              ),
            )
          : const SyncQueuePolicy(),
    );
  }

  final StorageNamespace namespace;
  final StoragePolicy policy;
  final String localEngineId;
  final String? remoteEngineId;
  final String pathPrefix;
  final String defaultFileExtension;
  final ConflictResolutionStrategy conflictResolution;
  final SyncInteractionLevel syncInteractionLevel;
  final StorageCapabilities requiredCapabilities;
  final SyncQueuePolicy queuePolicy;

  bool get requiresRemote => policy != StoragePolicy.localOnly;

  SyncInteractionLevel resolveInteractionLevel(
    final StorageCapabilities availableCapabilities,
  ) {
    if (syncInteractionLevel == SyncInteractionLevel.minimal) {
      return SyncInteractionLevel.minimal;
    }
    final supportsComplex =
        availableCapabilities.supportsComplexInteraction &&
        availableCapabilities.satisfies(requiredCapabilities);
    return supportsComplex
        ? SyncInteractionLevel.complex
        : SyncInteractionLevel.minimal;
  }

  Map<String, dynamic> toJson() => {
    'namespace': namespace.value,
    'policy': policy.name,
    'local_engine_id': localEngineId,
    if (remoteEngineId != null) 'remote_engine_id': remoteEngineId,
    'path_prefix': pathPrefix,
    'default_file_extension': defaultFileExtension,
    'conflict_resolution': conflictResolution.name,
    'sync_interaction_level': syncInteractionLevel.name,
    'required_capabilities': requiredCapabilities.toJson(),
    'queue_policy': queuePolicy.toJson(),
  };
}

/// Profile describing namespace routing and policy for one application/workspace.
@immutable
final class StorageProfile {
  const StorageProfile({
    required this.name,
    required this.namespaces,
    this.version = 1,
    this.metadata = const <String, dynamic>{},
  }) : assert(name != '');

  factory StorageProfile.fromJson(
    final Map<String, dynamic> json,
  ) => StorageProfile(
    name: (json['name'] ?? '').toString(),
    version: json['version'] is int ? json['version'] as int : 1,
    namespaces: (json['namespaces'] as List<dynamic>? ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (final e) =>
              StorageNamespaceProfile.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList(),
    metadata: json['metadata'] is Map
        ? Map<String, dynamic>.from(json['metadata'] as Map<dynamic, dynamic>)
        : const <String, dynamic>{},
  );

  final String name;
  final int version;
  final List<StorageNamespaceProfile> namespaces;
  final Map<String, dynamic> metadata;

  StorageNamespaceProfile namespaceProfile(final StorageNamespace namespace) =>
      namespaces.firstWhere(
        (final e) => e.namespace == namespace,
        orElse: () => throw ArgumentError.value(
          namespace,
          'namespace',
          'Namespace is not configured in profile: $name',
        ),
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'version': version,
    'namespaces': namespaces.map((final e) => e.toJson()).toList(),
    'metadata': metadata,
  };
}
