import 'package:test/test.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

void main() {
  group('StorageReleaseGateEvaluator', () {
    test('fails gate when write latency p95 exceeds budget', () {
      final evaluator = const StorageReleaseGateEvaluator();
      final report = evaluator.evaluate(
        input: _baseInput(
          performanceEvidence: const StoragePerformanceEvidence(
            writeLatencies: <Duration>[
              Duration(milliseconds: 10),
              Duration(milliseconds: 11),
              Duration(milliseconds: 12),
              Duration(milliseconds: 13),
              Duration(milliseconds: 900),
            ],
            readLatencies: <Duration>[
              Duration(milliseconds: 8),
              Duration(milliseconds: 9),
              Duration(milliseconds: 10),
              Duration(milliseconds: 10),
              Duration(milliseconds: 11),
            ],
            syncQueueThroughputPerMinute: <int>[180, 190, 200, 210, 205],
            memoryOverheadBytes: <int>[
              1200000,
              1300000,
              1250000,
              1400000,
              1350000,
            ],
            diffDecisionLatencies: <Duration>[
              Duration(milliseconds: 40),
              Duration(milliseconds: 41),
              Duration(milliseconds: 39),
              Duration(milliseconds: 42),
              Duration(milliseconds: 40),
            ],
          ),
        ),
      );

      expect(report.passed, isFalse);
      expect(
        report.findings.map((final finding) => finding.id),
        contains('performance.write_latency_p95'),
      );
    });

    test('passes gate when all G6 criteria are satisfied', () {
      final evaluator = const StorageReleaseGateEvaluator();
      final report = evaluator.evaluate(input: _baseInput());

      expect(report.passed, isTrue);
      expect(
        report.findings.where((final finding) => finding.isBlocking),
        isEmpty,
      );
    });

    test('fails gate when deprecation item is overdue and unfinished', () {
      final evaluator = const StorageReleaseGateEvaluator();
      final report = evaluator.evaluate(
        input: _baseInput(
          deprecationSchedule: <StorageDeprecationItem>[
            StorageDeprecationItem(
              id: 'legacy_storage_path',
              description: 'Remove old local db path compatibility layer.',
              owner: 'storage-team',
              targetDateUtc: DateTime.utc(2025, 12, 31),
              stage: StorageDeprecationStage.announced,
            ),
          ],
        ),
      );

      expect(report.passed, isFalse);
      expect(
        report.findings.map((final finding) => finding.id),
        contains('deprecation.overdue.legacy_storage_path'),
      );
    });
  });
}

StorageReleaseGateInput _baseInput({
  final StoragePerformanceEvidence performanceEvidence =
      const StoragePerformanceEvidence(
        writeLatencies: <Duration>[
          Duration(milliseconds: 10),
          Duration(milliseconds: 11),
          Duration(milliseconds: 12),
          Duration(milliseconds: 13),
          Duration(milliseconds: 14),
        ],
        readLatencies: <Duration>[
          Duration(milliseconds: 8),
          Duration(milliseconds: 9),
          Duration(milliseconds: 10),
          Duration(milliseconds: 11),
          Duration(milliseconds: 12),
        ],
        syncQueueThroughputPerMinute: <int>[180, 190, 200, 210, 220],
        memoryOverheadBytes: <int>[1000000, 1100000, 1150000, 1200000, 1250000],
        diffDecisionLatencies: <Duration>[
          Duration(milliseconds: 40),
          Duration(milliseconds: 42),
          Duration(milliseconds: 43),
          Duration(milliseconds: 41),
          Duration(milliseconds: 44),
        ],
      ),
  final List<StorageDeprecationItem>? deprecationSchedule,
}) => StorageReleaseGateInput(
  performanceBudgets: const StoragePerformanceBudgets(
    writeLatencyP50Max: Duration(milliseconds: 50),
    writeLatencyP95Max: Duration(milliseconds: 120),
    readLatencyP50Max: Duration(milliseconds: 40),
    readLatencyP95Max: Duration(milliseconds: 90),
    minSyncQueueThroughputPerMinute: 120,
    maxMemoryOverheadBytes: 3000000,
    diffDecisionLatencyP95Max: Duration(milliseconds: 250),
    minSamplesPerMetric: 5,
  ),
  performanceEvidence: performanceEvidence,
  reliabilityCriteria: const StorageReliabilityCriteria(
    minSoakDuration: Duration(hours: 24),
    minFaultInjectionScenarios: 5,
    maxStartupRecoveryP95: Duration(seconds: 2),
    minMigrationStressOperations: 5000,
    minOutboxStressOperations: 3000,
    maxFailureRate: 0.01,
  ),
  reliabilityEvidence: const StorageReliabilityEvidence(
    soakDuration: Duration(hours: 72),
    faultInjectionScenarios: 12,
    startupRecoveryDurations: <Duration>[
      Duration(milliseconds: 300),
      Duration(milliseconds: 350),
      Duration(milliseconds: 380),
      Duration(milliseconds: 420),
      Duration(milliseconds: 450),
    ],
    migrationStressOperations: 12000,
    outboxStressOperations: 7000,
    totalOperations: 50000,
    failedOperations: 100,
  ),
  securityControls: const <StorageSecurityControl>[
    StorageSecurityControl(
      id: 'at_rest_encryption',
      description: 'Encryption at rest for migration backups.',
      owner: 'security-team',
      status: StorageSecurityControlStatus.passed,
    ),
    StorageSecurityControl(
      id: 'transport_tls',
      description: 'Remote adapters require TLS.',
      owner: 'security-team',
      status: StorageSecurityControlStatus.passed,
    ),
    StorageSecurityControl(
      id: 'token_refresh_boundary',
      description: 'Token refresh occurs in dedicated auth boundary.',
      owner: 'security-team',
      status: StorageSecurityControlStatus.passed,
    ),
  ],
  observabilityEvidence: StorageObservabilityEvidence(
    hasStructuredLogs: true,
    hasCorrelationIds: true,
    hasDebugExportBundle: true,
    availableMetrics: StorageObservabilityEvidence.requiredMetrics,
  ),
  compatibilityPolicy: const StorageCompatibilityPolicy(
    supportedProfileSchemaVersions: <int>{1, 2},
    supportedMigrationManifestSchemaVersions: <int>{1, 2},
    targetProfileSchemaVersion: 2,
    targetMigrationManifestSchemaVersion: 2,
  ),
  compatibilityEvidence: const StorageCompatibilityEvidence(
    profileSchemaVersionsValidated: <int>{1, 2},
    migrationManifestVersionsValidated: <int>{1, 2},
  ),
  releaseChecklist: <StorageReleaseChecklistItem>[
    StorageReleaseChecklistItem(
      id: 'release_checklist',
      description: 'Release checklist complete.',
      owner: 'release-manager',
      done: true,
      completedAtUtc: DateTime.utc(2026, 3, 1),
    ),
    StorageReleaseChecklistItem(
      id: 'rollback_playbook',
      description: 'Rollback playbook rehearsal complete.',
      owner: 'release-manager',
      done: true,
      completedAtUtc: DateTime.utc(2026, 3, 1),
    ),
  ],
  rollbackDrills: <StorageRollbackDrillRecord>[
    StorageRollbackDrillRecord(
      executedAtUtc: DateTime.utc(2026, 2, 25),
      success: true,
      note: 'Rollback rehearsal completed in staging.',
    ),
  ],
  deprecationSchedule:
      deprecationSchedule ??
      <StorageDeprecationItem>[
        StorageDeprecationItem(
          id: 'legacy_storage_service_facade',
          description: 'Deprecate legacy facade path in favor of kernel.',
          owner: 'storage-team',
          targetDateUtc: DateTime.utc(2026, 6, 1),
          stage: StorageDeprecationStage.announced,
        ),
      ],
  evaluationTimeUtc: DateTime.utc(2026, 3, 2),
);
