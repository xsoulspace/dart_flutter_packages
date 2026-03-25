import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

/// Type of migration between profile intents.
enum StorageMigrationTransitionKind {
  /// Both source and target require only local engines.
  localToLocal,

  /// Source uses remote-enabled policies and target uses only local policies.
  remoteToLocal,

  /// Source uses only local policies and target uses remote-enabled policies.
  localToRemote,

  /// Both source and target rely on remote-enabled policies.
  remoteToRemote,

  /// Mixed local/remote policy sets exist in source or target.
  mixed,
}

/// Canonical first-party migration recipe identifiers.
enum StorageFirstPartyMigrationRecipe {
  sharedPreferencesToFiles,
  filesToOfflineGit,
  offlineGitToFiles,
  mixedLocalToDocumentFile,
  serverpodToGraphql,
  graphqlToServerpod,
  githubApiToGenericGitRemote,
  genericGitRemoteToProviderSpecific,
  lastAnswerEnableGit,
  lastAnswerDisableGit,
  dripLocalOnlyToOptimisticSync,
  dripOptimisticSyncToLocalOnly,
  minimalToComplex,
  complexToMinimal,
}

/// Detailed per-namespace change description for migration planning.
@immutable
final class StorageMigrationNamespaceChange {
  /// Creates a namespace change description.
  const StorageMigrationNamespaceChange({
    required this.namespace,
    this.sourceProfile,
    this.targetProfile,
    this.mappedTo,
    this.notes = '',
  });

  /// Namespace involved in migration mapping.
  final StorageNamespace namespace;

  /// Source namespace profile, if available.
  final StorageNamespaceProfile? sourceProfile;

  /// Target namespace profile, if available.
  final StorageNamespaceProfile? targetProfile;

  /// Target namespace this source namespace is mapped to.
  final StorageNamespace? mappedTo;

  /// Human-readable note about this namespace change.
  final String notes;

  /// Whether this namespace exists only in source profile.
  bool get isRemoved => targetProfile == null;

  /// Whether this namespace exists only in target profile.
  bool get isAdded => sourceProfile == null;

  /// Whether namespace exists in both profiles.
  bool get isMapped => sourceProfile != null && targetProfile != null;
}

/// Migration blueprint output of validation and mapping phase.
@immutable
final class StorageMigrationBlueprint {
  /// Creates a blueprint instance.
  const StorageMigrationBlueprint({
    required this.id,
    required this.sourceProfile,
    required this.targetProfile,
    required this.kind,
    required this.namespaceMappings,
    required this.namespaceChanges,
    required this.sourceProfileHash,
    required this.targetProfileHash,
    required this.issues,
    required this.warnings,
    this.reversible = true,
    this.metadata = const <String, dynamic>{},
    this.plannedAt,
  });

  /// Blueprint identifier.
  final String id;

  /// Source profile used for planning.
  final StorageProfile sourceProfile;

  /// Target profile used for planning.
  final StorageProfile targetProfile;

  /// Transition classification for planning.
  final StorageMigrationTransitionKind kind;

  /// Mapping from source namespace -> target namespace.
  final Map<StorageNamespace, StorageNamespace> namespaceMappings;

  /// Per-namespace migration differences.
  final List<StorageMigrationNamespaceChange> namespaceChanges;

  /// Deterministic source hash.
  final String sourceProfileHash;

  /// Deterministic target hash.
  final String targetProfileHash;

  /// Validation issues preventing migration execution.
  final List<String> issues;

  /// Validation warnings that may degrade behavior.
  final List<String> warnings;

  /// Whether migration can be rolled back with inverse direction.
  final bool reversible;

  /// Arbitrary metadata for tools, UI and diagnostics.
  final Map<String, dynamic> metadata;

  /// Timestamp when this plan was generated.
  final DateTime? plannedAt;

  /// Whether there are blocking issues.
  bool get hasIssues => issues.isNotEmpty;

  /// Whether execution can proceed (no blocking issues).
  bool get canExecute => !hasIssues;

  /// Converts blueprint to a kernel migration plan.
  MigrationPlan toMigrationPlan({final DateTime? createdAt}) => MigrationPlan(
    id: id,
    sourceProfileHash: sourceProfileHash,
    targetProfileHash: targetProfileHash,
    createdAt: createdAt ?? DateTime.now().toUtc(),
    namespaceMappings: namespaceMappings.map(
      (final source, final target) => MapEntry(source.value, target.value),
    ),
    metadata: <String, dynamic>{
      'transition_kind': kind.name,
      'reversible': reversible,
      if (metadata.isNotEmpty) ...metadata,
    },
  );

  /// Summary useful for logs and diagnostics.
  String summary() {
    final buffer = StringBuffer('Migration blueprint [$id]');
    buffer
      ..writeln(': $kind')
      ..writeln(
        '  Source: ${sourceProfile.name} (${sourceProfile.namespaces.length} namespaces)',
      )
      ..writeln(
        '  Target: ${targetProfile.name} (${targetProfile.namespaces.length} namespaces)',
      )
      ..writeln('  Mapped namespaces: ${namespaceMappings.length}');
    if (issues.isNotEmpty) {
      buffer.writeln('  Issues:');
      for (final issue in issues) {
        buffer.writeln('    - $issue');
      }
    }
    if (warnings.isNotEmpty) {
      buffer.writeln('  Warnings:');
      for (final warning in warnings) {
        buffer.writeln('    - $warning');
      }
    }
    return buffer.toString();
  }
}

/// Builder for deterministic migration planning and cross-backend transitions.
final class StorageMigrationRecipe {
  StorageMigrationRecipe._();

  static const _defaultTransitionMetadata = <String, dynamic>{
    'overwrite': true,
    'dry_run': false,
    'collect_diffs': false,
  };

  /// Builds a migration blueprint from source and target profiles.
  static StorageMigrationBlueprint build({
    required final String id,
    required final StorageProfile sourceProfile,
    required final StorageProfile targetProfile,
    final Map<StorageNamespace, StorageNamespace>? namespaceMappings,
    final Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    final effectiveMappings =
        namespaceMappings ??
        _buildDefaultMappings(sourceProfile, targetProfile);
    final sourceMap = {
      for (final ns in sourceProfile.namespaces) ns.namespace: ns,
    };
    final targetMap = {
      for (final ns in targetProfile.namespaces) ns.namespace: ns,
    };

    final issues = <String>[];
    final warnings = <String>[];
    final changes = <StorageMigrationNamespaceChange>[];

    for (final sourceNs in sourceMap.values) {
      final mappedTo = effectiveMappings[sourceNs.namespace];
      if (mappedTo == null) {
        final issue =
            'No target mapping for source namespace "${sourceNs.namespace.value}".';
        issues.add(issue);
        changes.add(
          StorageMigrationNamespaceChange(
            namespace: sourceNs.namespace,
            sourceProfile: sourceNs,
            notes: issue,
          ),
        );
        continue;
      }
      final targetNs = targetMap[mappedTo];
      if (targetNs == null) {
        issues.add(
          'Mapped target namespace "${mappedTo.value}" does not exist '
          'in target profile.',
        );
        continue;
      }

      final notes = <String>[];
      if (sourceNs.policy != targetNs.policy) {
        warnings.add(
          'Namespace "${sourceNs.namespace.value}" policy changed from '
          '${sourceNs.policy.name} to ${targetNs.policy.name}.',
        );
        notes.add(
          'policy changed from ${sourceNs.policy.name} to ${targetNs.policy.name}',
        );
      }
      if (sourceNs.pathPrefix != targetNs.pathPrefix) {
        notes.add(
          'path_prefix changed from "${sourceNs.pathPrefix}" '
          'to "${targetNs.pathPrefix}"',
        );
      }
      if (sourceNs.defaultFileExtension != targetNs.defaultFileExtension) {
        notes.add(
          'default_file_extension changed from '
          '"${sourceNs.defaultFileExtension}" to "${targetNs.defaultFileExtension}"',
        );
      }
      if (sourceNs.syncInteractionLevel == SyncInteractionLevel.complex &&
          targetNs.syncInteractionLevel == SyncInteractionLevel.minimal) {
        warnings.add(
          'Namespace "${sourceNs.namespace.value}" migrates from complex '
          'to minimal interaction level.',
        );
      }
      if (sourceNs.syncInteractionLevel != targetNs.syncInteractionLevel) {
        notes.add(
          'sync interaction level changed from '
          '${sourceNs.syncInteractionLevel.name} to ${targetNs.syncInteractionLevel.name}',
        );
      }

      final transition = StorageMigrationNamespaceChange(
        namespace: sourceNs.namespace,
        sourceProfile: sourceNs,
        targetProfile: targetNs,
        mappedTo: mappedTo,
        notes: notes.join('; '),
      );
      changes.add(transition);
    }

    for (final targetNs in targetMap.values) {
      final mappedFrom = effectiveMappings.entries
          .where((final entry) => entry.value == targetNs.namespace)
          .map((final entry) => entry.key)
          .firstOrNull;
      if (mappedFrom == null) {
        changes.add(
          StorageMigrationNamespaceChange(
            namespace: targetNs.namespace,
            targetProfile: targetNs,
            notes: 'Added namespace in target profile.',
          ),
        );
      }
    }

    final sourceHash = profileHash(sourceProfile);
    final targetHash = profileHash(targetProfile);
    final kind = _classifyTransition(sourceProfile, targetProfile);
    final interactionLevel = _resolveMigrationInteractionLevel(
      sourceProfile: sourceProfile,
      targetProfile: targetProfile,
      effectiveMappings: effectiveMappings,
      explicitLevel: metadata['migration_interaction_level'],
    );
    final shouldCollectDiffs = metadata.containsKey('collect_diffs')
        ? metadata['collect_diffs']
        : interactionLevel == SyncInteractionLevel.complex.name;
    final planMetadata = <String, dynamic>{
      ..._defaultTransitionMetadata,
      'migration_interaction_level': interactionLevel,
      'transition_kind': kind.name,
      'reversible': true,
      'source_profile_hash': sourceHash,
      'target_profile_hash': targetHash,
      ...metadata,
      'collect_diffs': shouldCollectDiffs,
    };

    return StorageMigrationBlueprint(
      id: id,
      sourceProfile: sourceProfile,
      targetProfile: targetProfile,
      kind: kind,
      namespaceMappings: effectiveMappings,
      namespaceChanges: changes,
      sourceProfileHash: sourceHash,
      targetProfileHash: targetHash,
      issues: issues,
      warnings: warnings,
      plannedAt: DateTime.now().toUtc(),
      metadata: planMetadata,
    );
  }

  /// Builds one of the canonical first-party migration recipes.
  static StorageMigrationBlueprint buildFirstPartyRecipe({
    required final StorageFirstPartyMigrationRecipe recipe,
    required final String id,
    final StorageProfile? sourceProfile,
    final StorageProfile? targetProfile,
    final Map<StorageNamespace, StorageNamespace>? namespaceMappings,
    final Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    switch (recipe) {
      case StorageFirstPartyMigrationRecipe.lastAnswerEnableGit:
        return lastAnswerEnableGitRecipe(id: id, metadata: metadata);
      case StorageFirstPartyMigrationRecipe.lastAnswerDisableGit:
        return lastAnswerDisableGitRecipe(id: id, metadata: metadata);
      case StorageFirstPartyMigrationRecipe.minimalToComplex:
        if (sourceProfile == null) {
          throw ArgumentError.value(
            sourceProfile,
            'sourceProfile',
            'sourceProfile is required for minimal->complex transition.',
          );
        }
        return interactionLevelTransitionRecipe(
          id: id,
          sourceProfile: sourceProfile,
          targetLevel: SyncInteractionLevel.complex,
          metadata: metadata,
        );
      case StorageFirstPartyMigrationRecipe.complexToMinimal:
        if (sourceProfile == null) {
          throw ArgumentError.value(
            sourceProfile,
            'sourceProfile',
            'sourceProfile is required for complex->minimal transition.',
          );
        }
        return interactionLevelTransitionRecipe(
          id: id,
          sourceProfile: sourceProfile,
          targetLevel: SyncInteractionLevel.minimal,
          metadata: metadata,
        );
      default:
        if (sourceProfile == null || targetProfile == null) {
          throw ArgumentError(
            'sourceProfile and targetProfile are required for recipe '
            '${recipe.name}.',
          );
        }
        return build(
          id: id,
          sourceProfile: sourceProfile,
          targetProfile: targetProfile,
          namespaceMappings: namespaceMappings,
          metadata: <String, dynamic>{
            'first_party_recipe': recipe.name,
            'first_party': true,
            ...metadata,
          },
        );
    }
  }

  /// last_answer: enable git-like local structure over existing files.
  static StorageMigrationBlueprint lastAnswerEnableGitRecipe({
    required final String id,
    final SyncInteractionLevel interactionLevel = SyncInteractionLevel.minimal,
    final Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    final source = _lastAnswerProfile(
      gitEnabled: false,
      interactionLevel: interactionLevel,
    );
    final target = _lastAnswerProfile(
      gitEnabled: true,
      interactionLevel: interactionLevel,
    );
    return build(
      id: id,
      sourceProfile: source,
      targetProfile: target,
      metadata: <String, dynamic>{
        'first_party_recipe':
            StorageFirstPartyMigrationRecipe.lastAnswerEnableGit.name,
        'first_party': true,
        'app': 'last_answer',
        'mode_toggle': 'enable_git_like_structure',
        ...metadata,
      },
    );
  }

  /// last_answer: disable git and keep file mode.
  static StorageMigrationBlueprint lastAnswerDisableGitRecipe({
    required final String id,
    final SyncInteractionLevel interactionLevel = SyncInteractionLevel.minimal,
    final Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    final source = _lastAnswerProfile(
      gitEnabled: true,
      interactionLevel: interactionLevel,
    );
    final target = _lastAnswerProfile(
      gitEnabled: false,
      interactionLevel: interactionLevel,
    );
    return build(
      id: id,
      sourceProfile: source,
      targetProfile: target,
      metadata: <String, dynamic>{
        'first_party_recipe':
            StorageFirstPartyMigrationRecipe.lastAnswerDisableGit.name,
        'first_party': true,
        'app': 'last_answer',
        'mode_toggle': 'disable_git_keep_files',
        ...metadata,
      },
    );
  }

  /// Interaction-level transition recipe that preserves decision history.
  static StorageMigrationBlueprint interactionLevelTransitionRecipe({
    required final String id,
    required final StorageProfile sourceProfile,
    required final SyncInteractionLevel targetLevel,
    final Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    final targetNamespaces = sourceProfile.namespaces
        .map(
          (final namespace) => StorageNamespaceProfile(
            namespace: namespace.namespace,
            policy: namespace.policy,
            localEngineId: namespace.localEngineId,
            remoteEngineId: namespace.remoteEngineId,
            pathPrefix: namespace.pathPrefix,
            defaultFileExtension: namespace.defaultFileExtension,
            conflictResolution: namespace.conflictResolution,
            syncInteractionLevel: targetLevel,
            requiredCapabilities: namespace.requiredCapabilities,
          ),
        )
        .toList(growable: false);
    final targetProfile = StorageProfile(
      name: '${sourceProfile.name}_${targetLevel.name}_transition',
      version: sourceProfile.version,
      namespaces: targetNamespaces,
      metadata: sourceProfile.metadata,
    );

    final recipeId = targetLevel == SyncInteractionLevel.complex
        ? StorageFirstPartyMigrationRecipe.minimalToComplex.name
        : StorageFirstPartyMigrationRecipe.complexToMinimal.name;
    return build(
      id: id,
      sourceProfile: sourceProfile,
      targetProfile: targetProfile,
      metadata: <String, dynamic>{
        'first_party_recipe': recipeId,
        'first_party': true,
        'interaction_transition': '${sourceProfile.name}->${targetLevel.name}',
        'preserve_decision_history': true,
        'decision_history_policy': 'preserve',
        ...metadata,
      },
    );
  }

  /// Computes a deterministic profile hash string.
  static String profileHash(final StorageProfile profile) => sha256
      .convert(utf8.encode(jsonEncode(_normalizeProfileJson(profile.toJson()))))
      .toString();

  static Map<StorageNamespace, StorageNamespace> _buildDefaultMappings(
    final StorageProfile sourceProfile,
    final StorageProfile targetProfile,
  ) {
    final targetNamespaces = targetProfile.namespaces
        .map((final ns) => ns.namespace.value)
        .toSet();

    final mappings = <StorageNamespace, StorageNamespace>{};
    for (final sourceNs in sourceProfile.namespaces) {
      if (targetNamespaces.contains(sourceNs.namespace.value)) {
        mappings[sourceNs.namespace] = sourceNs.namespace;
      }
    }

    return mappings;
  }

  static StorageMigrationTransitionKind _classifyTransition(
    final StorageProfile sourceProfile,
    final StorageProfile targetProfile,
  ) {
    final sourceHasRemote = sourceProfile.namespaces.any(
      (final ns) => ns.requiresRemote,
    );
    final sourceHasLocal = sourceProfile.namespaces.any(
      (final ns) => !ns.requiresRemote,
    );
    final targetHasRemote = targetProfile.namespaces.any(
      (final ns) => ns.requiresRemote,
    );
    final targetHasLocal = targetProfile.namespaces.any(
      (final ns) => !ns.requiresRemote,
    );

    if (!sourceHasRemote) {
      if (!targetHasRemote) return StorageMigrationTransitionKind.localToLocal;
      if (!targetHasLocal) return StorageMigrationTransitionKind.localToRemote;
      return StorageMigrationTransitionKind.mixed;
    }

    if (!targetHasRemote) {
      return targetHasLocal
          ? StorageMigrationTransitionKind.mixed
          : StorageMigrationTransitionKind.remoteToLocal;
    }

    if (!sourceHasLocal && !targetHasLocal) {
      return StorageMigrationTransitionKind.remoteToRemote;
    }
    if (!sourceHasLocal) {
      return StorageMigrationTransitionKind.remoteToRemote;
    }
    if (!targetHasLocal) {
      return StorageMigrationTransitionKind.remoteToRemote;
    }

    return StorageMigrationTransitionKind.mixed;
  }

  static String _resolveMigrationInteractionLevel({
    required final StorageProfile sourceProfile,
    required final StorageProfile targetProfile,
    required final Map<StorageNamespace, StorageNamespace> effectiveMappings,
    final Object? explicitLevel,
  }) {
    if (explicitLevel is String && explicitLevel.isNotEmpty) {
      final normalized = explicitLevel.trim().toLowerCase();
      if (normalized == SyncInteractionLevel.complex.name ||
          normalized == SyncInteractionLevel.minimal.name) {
        return normalized;
      }
    }

    final sourceProfileMap = <StorageNamespace, StorageNamespaceProfile>{
      for (final entry in sourceProfile.namespaces) entry.namespace: entry,
    };
    final targetProfileMap = <StorageNamespace, StorageNamespaceProfile>{
      for (final entry in targetProfile.namespaces) entry.namespace: entry,
    };

    var requiresComplex = false;
    for (final mapping in effectiveMappings.entries) {
      final source = sourceProfileMap[mapping.key];
      final target = targetProfileMap[mapping.value];
      if (source == null || target == null) {
        continue;
      }
      if (source.syncInteractionLevel == SyncInteractionLevel.complex ||
          target.syncInteractionLevel == SyncInteractionLevel.complex) {
        requiresComplex = true;
        break;
      }
    }

    if (requiresComplex) {
      return SyncInteractionLevel.complex.name;
    }
    return SyncInteractionLevel.minimal.name;
  }

  static StorageProfile _lastAnswerProfile({
    required final bool gitEnabled,
    required final SyncInteractionLevel interactionLevel,
  }) => StorageProfile(
    name: gitEnabled ? 'last_answer_git_enabled' : 'last_answer_files_only',
    namespaces: <StorageNamespaceProfile>[
      StorageNamespaceProfile(
        namespace: StorageNamespace.projects,
        policy: StoragePolicy.localOnly,
        localEngineId: gitEnabled ? 'offline_git' : 'files',
        pathPrefix: 'projects',
        defaultFileExtension: '.json',
        syncInteractionLevel: interactionLevel,
      ),
      StorageNamespaceProfile(
        namespace: StorageNamespace.settings,
        policy: StoragePolicy.localOnly,
        localEngineId: 'files',
        pathPrefix: 'settings',
        defaultFileExtension: '.json',
        syncInteractionLevel: SyncInteractionLevel.minimal,
      ),
      StorageNamespaceProfile(
        namespace: const StorageNamespace('tags'),
        policy: StoragePolicy.localOnly,
        localEngineId: 'files',
        pathPrefix: 'tags',
        defaultFileExtension: '.json',
        syncInteractionLevel: interactionLevel,
      ),
      StorageNamespaceProfile(
        namespace: const StorageNamespace('drafts'),
        policy: StoragePolicy.localOnly,
        localEngineId: 'files',
        pathPrefix: 'drafts',
        defaultFileExtension: '.json',
        syncInteractionLevel: interactionLevel,
      ),
      StorageNamespaceProfile(
        namespace: StorageNamespace.cache,
        policy: StoragePolicy.localOnly,
        localEngineId: 'files',
        pathPrefix: 'cache',
        defaultFileExtension: '.json',
        syncInteractionLevel: SyncInteractionLevel.minimal,
      ),
    ],
  );
}

Object? _normalizeProfileJson(final Object? node) {
  if (node is Map) {
    final entries = node.entries.toList()
      ..sort(
        (final left, final right) =>
            left.key.toString().compareTo(right.key.toString()),
      );
    return <String, dynamic>{
      for (final entry in entries)
        entry.key.toString(): _normalizeProfileJson(entry.value),
    };
  }
  if (node is List) {
    return node.map(_normalizeProfileJson).toList(growable: false);
  }
  return node;
}
