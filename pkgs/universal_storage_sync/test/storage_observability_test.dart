import 'package:test/test.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

void main() {
  group('StorageDebugBundleCollector', () {
    test('redacts sensitive metadata values in exported bundle', () {
      final collector = StorageDebugBundleCollector();
      collector.ingest(
        StorageObservationEvent(
          type: StorageObservationType.created,
          namespace: StorageNamespace.settings,
          path: 'settings/profile.json',
          timestamp: DateTime.utc(2026, 3, 2),
          metadata: const <String, dynamic>{
            'correlation_id': 'c-1',
            'auth_token': 'secret-token-value',
            'nested': <String, dynamic>{'password': 'p@ssword'},
          },
        ),
      );

      final bundle = collector.exportDebugBundle();
      final logs = bundle['logs'] as List<dynamic>;
      final firstLog = Map<String, dynamic>.from(
        logs.first as Map<dynamic, dynamic>,
      );
      final metadata = Map<String, dynamic>.from(
        firstLog['metadata'] as Map<dynamic, dynamic>,
      );
      final nested = metadata['nested'] as Map<String, dynamic>;

      expect(metadata['auth_token'], StorageDebugBundleCollector.redactedValue);
      expect(nested['password'], StorageDebugBundleCollector.redactedValue);
    });

    test('builds complete observability evidence from logs and metrics', () {
      final collector = StorageDebugBundleCollector();
      collector.recordWriteLatency(const Duration(milliseconds: 10));
      collector.recordReadLatency(const Duration(milliseconds: 8));
      collector.recordRecoveryReplayDuration(const Duration(milliseconds: 30));

      collector.ingest(
        StorageObservationEvent(
          type: StorageObservationType.synced,
          namespace: StorageNamespace.projects,
          path: '',
          timestamp: DateTime.utc(2026, 3, 2),
          metadata: const <String, dynamic>{
            'outbox_pending': 3,
            'interaction_downgrade_reason': 'Complex mode not supported.',
          },
        ),
      );
      collector.ingest(
        StorageObservationEvent(
          type: StorageObservationType.conflictStaged,
          namespace: StorageNamespace.projects,
          path: 'todos/1.json',
          timestamp: DateTime.utc(2026, 3, 2),
        ),
      );
      collector.ingest(
        StorageObservationEvent(
          type: StorageObservationType.decisionResolved,
          namespace: StorageNamespace.projects,
          path: 'todos/1.json',
          timestamp: DateTime.utc(2026, 3, 2),
          metadata: const <String, dynamic>{'target_state': 'autoResolved'},
        ),
      );
      collector.ingest(
        StorageObservationEvent(
          type: StorageObservationType.migrationExecuted,
          namespace: StorageNamespace.settings,
          path: '',
          timestamp: DateTime.utc(2026, 3, 2),
          result: StorageOperationResult.success(message: 'ok'),
        ),
      );

      final evidence = collector.buildEvidence();
      expect(evidence.hasStructuredLogs, isTrue);
      expect(evidence.hasCorrelationIds, isTrue);
      expect(
        evidence.availableMetrics,
        containsAll(StorageObservabilityEvidence.requiredMetrics),
      );
    });

    test('generates correlation ids when events do not provide them', () {
      final collector = StorageDebugBundleCollector();
      collector.ingest(
        StorageObservationEvent(
          type: StorageObservationType.updated,
          namespace: StorageNamespace.settings,
          path: 'settings.json',
          timestamp: DateTime.utc(2026, 3, 2),
          metadata: const <String, dynamic>{},
        ),
      );

      final bundle = collector.exportDebugBundle();
      final logs = bundle['logs'] as List<dynamic>;
      final firstLog = Map<String, dynamic>.from(
        logs.first as Map<dynamic, dynamic>,
      );
      final correlationId = firstLog['correlation_id']?.toString();
      expect(correlationId, isNotNull);
      expect(correlationId, isNotEmpty);
    });
  });
}
