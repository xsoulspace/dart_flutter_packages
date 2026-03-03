import 'package:test/test.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_sync_utils/universal_storage_sync_utils.dart';

void main() {
  group('StorageMigrationRecipe', () {
    test('builds a local-to-local blueprint with stable namespace mapping', () {
      const source = StorageProfile(
        name: 'source',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.settings,
            policy: StoragePolicy.localOnly,
            localEngineId: 'files',
          ),
          StorageNamespaceProfile(
            namespace: StorageNamespace.projects,
            policy: StoragePolicy.localOnly,
            localEngineId: 'git',
          ),
        ],
      );

      const target = StorageProfile(
        name: 'target',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.settings,
            policy: StoragePolicy.localOnly,
            localEngineId: 'files',
          ),
          StorageNamespaceProfile(
            namespace: StorageNamespace.projects,
            policy: StoragePolicy.localOnly,
            localEngineId: 'files',
          ),
        ],
      );

      final blueprint = StorageMigrationRecipe.build(
        id: 'local_to_local',
        sourceProfile: source,
        targetProfile: target,
      );

      expect(blueprint.kind, StorageMigrationTransitionKind.localToLocal);
      expect(blueprint.canExecute, isTrue);
      expect(blueprint.issues, isEmpty);
      expect(
        blueprint.namespaceMappings[StorageNamespace.settings],
        StorageNamespace.settings,
      );
      expect(
        blueprint.namespaceMappings[StorageNamespace.projects],
        StorageNamespace.projects,
      );
      expect(blueprint.toMigrationPlan().namespaceMappings.isNotEmpty, isTrue);
    });

    test('builds migration plan metadata with default execution strategy', () {
      const source = StorageProfile(
        name: 'source',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.settings,
            policy: StoragePolicy.localOnly,
            localEngineId: 'files',
            syncInteractionLevel: SyncInteractionLevel.minimal,
          ),
        ],
      );

      const target = StorageProfile(
        name: 'target',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.settings,
            policy: StoragePolicy.localOnly,
            localEngineId: 'files',
            syncInteractionLevel: SyncInteractionLevel.minimal,
          ),
        ],
      );

      final blueprint = StorageMigrationRecipe.build(
        id: 'metadata_defaults',
        sourceProfile: source,
        targetProfile: target,
      );
      final plan = blueprint.toMigrationPlan();

      expect(blueprint.metadata['migration_interaction_level'], 'minimal');
      expect(plan.metadata['migration_interaction_level'], 'minimal');
      expect(plan.metadata['collect_diffs'], isFalse);
      expect(plan.metadata['overwrite'], isTrue);
      expect(plan.metadata['dry_run'], isFalse);
    });

    test('detects local-to-remote transition and records policy changes', () {
      const source = StorageProfile(
        name: 'source',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.projects,
            policy: StoragePolicy.localOnly,
            localEngineId: 'files',
            syncInteractionLevel: SyncInteractionLevel.minimal,
          ),
        ],
      );

      const target = StorageProfile(
        name: 'target',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.projects,
            policy: StoragePolicy.optimisticSync,
            localEngineId: 'files',
            remoteEngineId: 'github',
            syncInteractionLevel: SyncInteractionLevel.complex,
            requiredCapabilities: StorageCapabilities(
              supportsDiff: true,
              supportsHistory: true,
              supportsRevisionMetadata: true,
              supportsManualConflictResolution: true,
            ),
          ),
        ],
      );

      final blueprint = StorageMigrationRecipe.build(
        id: 'local_to_remote',
        sourceProfile: source,
        targetProfile: target,
      );

      expect(blueprint.kind, StorageMigrationTransitionKind.localToRemote);
      expect(blueprint.canExecute, isTrue);
      expect(blueprint.warnings, isNotEmpty);
      expect(
        blueprint.namespaceChanges.single.notes,
        contains('policy changed from localOnly to optimisticSync'),
      );
    });

    test(
      'sets complex interaction and default diff collection for complex plans',
      () {
        const source = StorageProfile(
          name: 'source',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.projects,
              policy: StoragePolicy.optimisticSync,
              localEngineId: 'files',
              remoteEngineId: 'github',
              syncInteractionLevel: SyncInteractionLevel.complex,
              requiredCapabilities: StorageCapabilities(
                supportsDiff: true,
                supportsHistory: true,
                supportsRevisionMetadata: true,
                supportsManualConflictResolution: true,
              ),
            ),
          ],
        );

        const target = StorageProfile(
          name: 'target',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.projects,
              policy: StoragePolicy.optimisticSync,
              localEngineId: 'files',
              remoteEngineId: 'serverpod',
              syncInteractionLevel: SyncInteractionLevel.minimal,
            ),
          ],
        );

        final blueprint = StorageMigrationRecipe.build(
          id: 'metadata_complex',
          sourceProfile: source,
          targetProfile: target,
        );

        expect(blueprint.metadata['migration_interaction_level'], 'complex');
        expect(blueprint.metadata['collect_diffs'], isTrue);
      },
    );

    test('lets callers override migration execution metadata', () {
      const source = StorageProfile(
        name: 'source',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.projects,
            policy: StoragePolicy.localOnly,
            localEngineId: 'files',
            syncInteractionLevel: SyncInteractionLevel.complex,
          ),
        ],
      );

      const target = StorageProfile(
        name: 'target',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.projects,
            policy: StoragePolicy.localOnly,
            localEngineId: 'files',
            syncInteractionLevel: SyncInteractionLevel.complex,
          ),
        ],
      );

      final blueprint = StorageMigrationRecipe.build(
        id: 'metadata_override',
        sourceProfile: source,
        targetProfile: target,
        metadata: <String, dynamic>{
          'migration_interaction_level': SyncInteractionLevel.minimal.name,
          'collect_diffs': false,
          'dry_run': true,
          'overwrite': false,
        },
      );
      final plan = blueprint.toMigrationPlan();

      expect(plan.metadata['migration_interaction_level'], 'minimal');
      expect(plan.metadata['collect_diffs'], isFalse);
      expect(plan.metadata['dry_run'], isTrue);
      expect(plan.metadata['overwrite'], isFalse);
    });

    test('classifies remote-to-remote transition', () {
      const source = StorageProfile(
        name: 'source',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.projects,
            policy: StoragePolicy.remoteOnly,
            localEngineId: 'files',
            remoteEngineId: 'github',
          ),
        ],
      );

      const target = StorageProfile(
        name: 'target',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.projects,
            policy: StoragePolicy.optimisticSync,
            localEngineId: 'git',
            remoteEngineId: 'serverpod',
          ),
        ],
      );

      final blueprint = StorageMigrationRecipe.build(
        id: 'remote_to_remote',
        sourceProfile: source,
        targetProfile: target,
      );

      expect(blueprint.kind, StorageMigrationTransitionKind.remoteToRemote);
      expect(blueprint.canExecute, isTrue);
    });

    test('adds warnings for unmapped namespaces and missing mappings', () {
      const source = StorageProfile(
        name: 'source',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.projects,
            policy: StoragePolicy.localOnly,
            localEngineId: 'files',
          ),
          StorageNamespaceProfile(
            namespace: StorageNamespace.settings,
            policy: StoragePolicy.localOnly,
            localEngineId: 'files',
          ),
        ],
      );

      const target = StorageProfile(
        name: 'target',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.settings,
            policy: StoragePolicy.localOnly,
            localEngineId: 'files',
          ),
        ],
      );

      final blueprint = StorageMigrationRecipe.build(
        id: 'missing_namespace',
        sourceProfile: source,
        targetProfile: target,
        namespaceMappings: <StorageNamespace, StorageNamespace>{
          StorageNamespace.settings: StorageNamespace.settings,
        },
      );

      expect(blueprint.canExecute, isFalse);
      expect(
        blueprint.issues,
        contains('No target mapping for source namespace "projects".'),
      );
      expect(
        blueprint.namespaceChanges.any(
          (final change) =>
              change.isRemoved && change.namespace == StorageNamespace.projects,
        ),
        isTrue,
      );
    });

    test('builds last_answer enable git first-party recipe', () {
      final blueprint = StorageMigrationRecipe.lastAnswerEnableGitRecipe(
        id: 'last_answer_git_on',
      );
      final plan = blueprint.toMigrationPlan();
      final sourceProjects = blueprint.sourceProfile.namespaceProfile(
        StorageNamespace.projects,
      );
      final targetProjects = blueprint.targetProfile.namespaceProfile(
        StorageNamespace.projects,
      );

      expect(blueprint.canExecute, isTrue);
      expect(sourceProjects.localEngineId, 'files');
      expect(targetProjects.localEngineId, 'offline_git');
      expect(plan.metadata['first_party_recipe'], 'lastAnswerEnableGit');
      expect(plan.metadata['app'], 'last_answer');
      expect(
        blueprint.targetProfile.namespaces.any(
          (final namespace) =>
              namespace.namespace == const StorageNamespace('tags'),
        ),
        isTrue,
      );
      expect(
        blueprint.targetProfile.namespaces.any(
          (final namespace) =>
              namespace.namespace == const StorageNamespace('drafts'),
        ),
        isTrue,
      );
    });

    test('builds last_answer disable git first-party recipe', () {
      final blueprint = StorageMigrationRecipe.lastAnswerDisableGitRecipe(
        id: 'last_answer_git_off',
      );
      final sourceProjects = blueprint.sourceProfile.namespaceProfile(
        StorageNamespace.projects,
      );
      final targetProjects = blueprint.targetProfile.namespaceProfile(
        StorageNamespace.projects,
      );

      expect(sourceProjects.localEngineId, 'offline_git');
      expect(targetProjects.localEngineId, 'files');
      expect(blueprint.metadata['first_party_recipe'], 'lastAnswerDisableGit');
    });

    test(
      'interaction-level transition recipe preserves decision history policy',
      () {
        const source = StorageProfile(
          name: 'drip_profile',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.projects,
              policy: StoragePolicy.optimisticSync,
              localEngineId: 'files',
              remoteEngineId: 'serverpod',
              syncInteractionLevel: SyncInteractionLevel.minimal,
            ),
            StorageNamespaceProfile(
              namespace: StorageNamespace.settings,
              policy: StoragePolicy.localOnly,
              localEngineId: 'files',
              syncInteractionLevel: SyncInteractionLevel.minimal,
            ),
          ],
        );

        final blueprint = StorageMigrationRecipe.buildFirstPartyRecipe(
          recipe: StorageFirstPartyMigrationRecipe.minimalToComplex,
          id: 'minimal_to_complex',
          sourceProfile: source,
        );

        expect(blueprint.canExecute, isTrue);
        expect(blueprint.metadata['first_party_recipe'], 'minimalToComplex');
        expect(blueprint.metadata['preserve_decision_history'], isTrue);
        expect(
          blueprint.targetProfile.namespaces.every(
            (final namespace) =>
                namespace.syncInteractionLevel == SyncInteractionLevel.complex,
          ),
          isTrue,
        );
      },
    );
  });
}
