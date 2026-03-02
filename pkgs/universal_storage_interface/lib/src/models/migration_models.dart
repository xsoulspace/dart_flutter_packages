import 'package:meta/meta.dart';

/// Runtime status of a migration plan execution.
enum MigrationStatus {
  draft,
  prepared,
  executing,
  completed,
  failed,
  rolledBack,
}

/// Immutable migration plan descriptor.
@immutable
final class MigrationPlan {
  const MigrationPlan({
    required this.id,
    required this.sourceProfileHash,
    required this.targetProfileHash,
    required this.createdAt,
    this.namespaceMappings = const <String, String>{},
    this.metadata = const <String, dynamic>{},
    this.status = MigrationStatus.draft,
  });

  factory MigrationPlan.fromJson(final Map<String, dynamic> json) {
    final statusName = (json['status'] ?? MigrationStatus.draft.name)
        .toString();
    final status = MigrationStatus.values.firstWhere(
      (final e) => e.name == statusName,
      orElse: () => MigrationStatus.draft,
    );

    return MigrationPlan(
      id: (json['id'] ?? '').toString(),
      sourceProfileHash: (json['source_profile_hash'] ?? '').toString(),
      targetProfileHash: (json['target_profile_hash'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      namespaceMappings: json['namespace_mappings'] is Map
          ? Map<String, String>.from(
              json['namespace_mappings'] as Map<dynamic, dynamic>,
            )
          : const <String, String>{},
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map<dynamic, dynamic>)
          : const <String, dynamic>{},
      status: status,
    );
  }

  final String id;
  final String sourceProfileHash;
  final String targetProfileHash;
  final DateTime createdAt;
  final Map<String, String> namespaceMappings;
  final Map<String, dynamic> metadata;
  final MigrationStatus status;

  MigrationPlan copyWith({
    final MigrationStatus? status,
    final Map<String, dynamic>? metadata,
  }) => MigrationPlan(
    id: id,
    sourceProfileHash: sourceProfileHash,
    targetProfileHash: targetProfileHash,
    createdAt: createdAt,
    namespaceMappings: namespaceMappings,
    metadata: metadata ?? this.metadata,
    status: status ?? this.status,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'source_profile_hash': sourceProfileHash,
    'target_profile_hash': targetProfileHash,
    'created_at': createdAt.toIso8601String(),
    'namespace_mappings': namespaceMappings,
    'metadata': metadata,
    'status': status.name,
  };
}

/// Result of the preflight phase before applying migration.
@immutable
final class MigrationPreparationResult {
  const MigrationPreparationResult({
    required this.ok,
    this.issues = const <String>[],
    this.warnings = const <String>[],
    this.metadata = const <String, dynamic>{},
  });

  final bool ok;
  final List<String> issues;
  final List<String> warnings;
  final Map<String, dynamic> metadata;
}

/// Result of migration execution.
@immutable
final class MigrationExecutionResult {
  const MigrationExecutionResult({
    required this.ok,
    required this.status,
    this.message = '',
    this.metadata = const <String, dynamic>{},
  });

  final bool ok;
  final MigrationStatus status;
  final String message;
  final Map<String, dynamic> metadata;
}
