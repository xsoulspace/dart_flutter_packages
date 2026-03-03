import 'package:test/test.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_sync_utils/universal_storage_sync_utils.dart';

void main() {
  group('StorageProfileCapabilityGuard', () {
    const guard = StorageProfileCapabilityGuard();

    test('blocks remote policy without remote engine id', () {
      const namespace = StorageNamespaceProfile(
        namespace: StorageNamespace.projects,
        policy: StoragePolicy.optimisticSync,
        localEngineId: 'files',
      );

      final result = guard.evaluateNamespace(
        profile: namespace,
        availableCapabilities: const StorageCapabilities(
          supportsBackgroundSync: true,
        ),
      );

      expect(result.decision, CapabilityDecision.blocked);
      expect(result.reason, contains('remote_engine_id'));
    });

    test(
      'degrades complex mode to minimal when capabilities are insufficient',
      () {
        const namespace = StorageNamespaceProfile(
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
        );

        final result = guard.evaluateNamespace(
          profile: namespace,
          availableCapabilities: const StorageCapabilities(supportsDiff: true),
        );

        expect(result.decision, CapabilityDecision.degraded);
        expect(result.resolvedInteractionLevel, SyncInteractionLevel.minimal);
      },
    );

    test(
      'profile decision reports allowed/degraded/blocked aggregate state',
      () {
        const profile = StorageProfile(
          name: 'aggregate_profile',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.settings,
              policy: StoragePolicy.localOnly,
              localEngineId: 'files',
            ),
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
            StorageNamespaceProfile(
              namespace: StorageNamespace.saves,
              policy: StoragePolicy.remoteOnly,
              localEngineId: 'files',
            ),
          ],
        );

        final result = guard.evaluateProfile(
          profile: profile,
          capabilitiesByNamespace: <StorageNamespace, StorageCapabilities>{
            StorageNamespace.settings: StorageCapabilities.none,
            StorageNamespace.projects: const StorageCapabilities(
              supportsDiff: true,
            ),
          },
        );

        expect(result.hasBlocked, isTrue);
        expect(result.hasDegraded, isTrue);
        expect(result.allAllowed, isFalse);
      },
    );
  });
}
