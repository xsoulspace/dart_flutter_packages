import 'dart:convert';
import 'dart:io';

import 'package:universal_storage_sync/universal_storage_sync.dart';

Future<void> main(final List<String> args) async {
  var outputPath = '../../../tool/artifacts/storage_release_gate_g6.json';
  var scenario = 'pass';

  for (var index = 0; index < args.length; index++) {
    final arg = args[index];
    switch (arg) {
      case '--output':
        index++;
        if (index >= args.length) {
          stderr.writeln('Missing value for --output');
          exit(2);
        }
        outputPath = args[index];
      case '--scenario':
        index++;
        if (index >= args.length) {
          stderr.writeln('Missing value for --scenario');
          exit(2);
        }
        scenario = args[index];
      default:
        stderr.writeln('Unknown argument: $arg');
        stderr.writeln(
          'Usage: dart run tool/storage_release_gate_ci.dart '
          '--output <path> [--scenario pass|fail]',
        );
        exit(2);
    }
  }

  if (scenario != 'pass' && scenario != 'fail') {
    stderr.writeln('Invalid scenario: $scenario (expected pass|fail)');
    exit(2);
  }

  const evaluator = StorageReleaseGateEvaluator();
  final report = evaluator.evaluate(
    input: _buildInput(failingEvidence: scenario == 'fail'),
  );

  final artifact = <String, dynamic>{
    'status': report.status.name,
    'passed': report.passed,
    'scenario': scenario,
    'evaluated_at_utc': report.evaluatedAtUtc.toIso8601String(),
    'blocking_findings': report.findings
        .where((final finding) => finding.isBlocking)
        .map((final finding) => finding.toJson())
        .toList(growable: false),
    'report': report.toJson(),
  };

  final outputFile = File(outputPath);
  await outputFile.parent.create(recursive: true);
  await outputFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(artifact),
  );

  final blockingFindings = artifact['blocking_findings'] as List<Object?>;
  if (!report.passed) {
    stderr.writeln(
      'Storage release gate G6 failed with '
      '${blockingFindings.length} blocking finding(s). '
      'Artifact: ${outputFile.path}',
    );
    exit(1);
  }

  stdout.writeln(
    'Storage release gate G6 passed. Artifact: ${outputFile.path}',
  );
}

StorageReleaseGateInput _buildInput({required final bool failingEvidence}) {
  final performanceEvidence = failingEvidence
      ? const StoragePerformanceEvidence(
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
            Duration(milliseconds: 11),
            Duration(milliseconds: 12),
          ],
          syncQueueThroughputPerMinute: <int>[180, 190, 200, 210, 220],
          memoryOverheadBytes: <int>[
            1000000,
            1100000,
            1150000,
            1200000,
            1250000,
          ],
          diffDecisionLatencies: <Duration>[
            Duration(milliseconds: 40),
            Duration(milliseconds: 42),
            Duration(milliseconds: 43),
            Duration(milliseconds: 41),
            Duration(milliseconds: 44),
          ],
        )
      : const StoragePerformanceEvidence(
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
          memoryOverheadBytes: <int>[
            1000000,
            1100000,
            1150000,
            1200000,
            1250000,
          ],
          diffDecisionLatencies: <Duration>[
            Duration(milliseconds: 40),
            Duration(milliseconds: 42),
            Duration(milliseconds: 43),
            Duration(milliseconds: 41),
            Duration(milliseconds: 44),
          ],
        );

  return StorageReleaseGateInput(
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
    observabilityEvidence: const StorageObservabilityEvidence(
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
        completedAtUtc: DateTime.utc(2026, 3),
      ),
      StorageReleaseChecklistItem(
        id: 'rollback_playbook',
        description: 'Rollback playbook rehearsal complete.',
        owner: 'release-manager',
        done: true,
        completedAtUtc: DateTime.utc(2026, 3),
      ),
    ],
    rollbackDrills: <StorageRollbackDrillRecord>[
      StorageRollbackDrillRecord(
        executedAtUtc: DateTime.utc(2026, 2, 25),
        success: true,
        note: 'Rollback rehearsal completed in staging.',
      ),
    ],
    deprecationSchedule: <StorageDeprecationItem>[
      StorageDeprecationItem(
        id: 'legacy_storage_service_facade',
        description: 'Deprecate legacy facade path in favor of kernel.',
        owner: 'storage-team',
        targetDateUtc: DateTime.utc(2026, 6),
        stage: StorageDeprecationStage.announced,
      ),
    ],
    evaluationTimeUtc: DateTime.utc(2026, 3, 3),
  );
}
