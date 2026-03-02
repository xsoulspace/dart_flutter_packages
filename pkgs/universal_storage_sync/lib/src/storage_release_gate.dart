import 'dart:math';

import 'package:meta/meta.dart';

/// Final status for Gate G6 hardening/release checks.
enum StorageReleaseGateStatus { passed, failed }

/// Severity for gate findings.
enum StorageReleaseGateSeverity { blocking, warning }

/// Structured gate finding for CI and release pipelines.
@immutable
final class StorageReleaseGateFinding {
  const StorageReleaseGateFinding({
    required this.id,
    required this.severity,
    required this.message,
    this.metadata = const <String, dynamic>{},
  });

  final String id;
  final StorageReleaseGateSeverity severity;
  final String message;
  final Map<String, dynamic> metadata;

  bool get isBlocking => severity == StorageReleaseGateSeverity.blocking;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'severity': severity.name,
    'message': message,
    'metadata': metadata,
  };
}

/// Performance thresholds enforced by Gate G6.
@immutable
final class StoragePerformanceBudgets {
  const StoragePerformanceBudgets({
    required this.writeLatencyP50Max,
    required this.writeLatencyP95Max,
    required this.readLatencyP50Max,
    required this.readLatencyP95Max,
    required this.minSyncQueueThroughputPerMinute,
    required this.maxMemoryOverheadBytes,
    required this.diffDecisionLatencyP95Max,
    this.minSamplesPerMetric = 30,
  });

  final Duration writeLatencyP50Max;
  final Duration writeLatencyP95Max;
  final Duration readLatencyP50Max;
  final Duration readLatencyP95Max;
  final int minSyncQueueThroughputPerMinute;
  final int maxMemoryOverheadBytes;
  final Duration diffDecisionLatencyP95Max;
  final int minSamplesPerMetric;
}

/// Collected benchmark evidence for release candidate validation.
@immutable
final class StoragePerformanceEvidence {
  const StoragePerformanceEvidence({
    this.writeLatencies = const <Duration>[],
    this.readLatencies = const <Duration>[],
    this.syncQueueThroughputPerMinute = const <int>[],
    this.memoryOverheadBytes = const <int>[],
    this.diffDecisionLatencies = const <Duration>[],
  });

  final List<Duration> writeLatencies;
  final List<Duration> readLatencies;
  final List<int> syncQueueThroughputPerMinute;
  final List<int> memoryOverheadBytes;
  final List<Duration> diffDecisionLatencies;
}

/// Reliability thresholds for soak and recovery validation.
@immutable
final class StorageReliabilityCriteria {
  const StorageReliabilityCriteria({
    required this.minSoakDuration,
    required this.minFaultInjectionScenarios,
    required this.maxStartupRecoveryP95,
    required this.minMigrationStressOperations,
    required this.minOutboxStressOperations,
    this.maxFailureRate = 0.005,
  });

  final Duration minSoakDuration;
  final int minFaultInjectionScenarios;
  final Duration maxStartupRecoveryP95;
  final int minMigrationStressOperations;
  final int minOutboxStressOperations;
  final double maxFailureRate;
}

/// Measured reliability evidence from hardening runs.
@immutable
final class StorageReliabilityEvidence {
  const StorageReliabilityEvidence({
    required this.soakDuration,
    required this.faultInjectionScenarios,
    this.startupRecoveryDurations = const <Duration>[],
    this.migrationStressOperations = 0,
    this.outboxStressOperations = 0,
    this.totalOperations = 0,
    this.failedOperations = 0,
  });

  final Duration soakDuration;
  final int faultInjectionScenarios;
  final List<Duration> startupRecoveryDurations;
  final int migrationStressOperations;
  final int outboxStressOperations;
  final int totalOperations;
  final int failedOperations;

  double get failureRate {
    if (totalOperations <= 0) {
      return 0;
    }
    final boundedFailed = min(max(failedOperations, 0), totalOperations);
    return boundedFailed / totalOperations;
  }
}

/// Status for one security control item.
enum StorageSecurityControlStatus { passed, failed, waived }

/// Security checklist entry required by Gate G6.
@immutable
final class StorageSecurityControl {
  const StorageSecurityControl({
    required this.id,
    required this.description,
    required this.owner,
    required this.status,
    this.required = true,
    this.note = '',
  });

  final String id;
  final String description;
  final String owner;
  final StorageSecurityControlStatus status;
  final bool required;
  final String note;
}

/// Observability readiness evidence.
@immutable
final class StorageObservabilityEvidence {
  const StorageObservabilityEvidence({
    required this.hasStructuredLogs,
    required this.hasCorrelationIds,
    required this.hasDebugExportBundle,
    this.availableMetrics = const <String>{},
  });

  static const String writeLatencyMetric = 'write_latency';
  static const String readLatencyMetric = 'read_latency';
  static const String queueDepthMetric = 'queue_depth';
  static const String conflictRateMetric = 'conflict_rate';
  static const String autoResolveRatioMetric = 'auto_resolve_ratio';
  static const String safeDegradeCountMetric = 'safe_degrade_count';
  static const String recoveryReplayDurationMetric = 'recovery_replay_duration';
  static const String migrationOutcomeMetric = 'migration_outcome';

  static const Set<String> requiredMetrics = <String>{
    writeLatencyMetric,
    readLatencyMetric,
    queueDepthMetric,
    conflictRateMetric,
    autoResolveRatioMetric,
    safeDegradeCountMetric,
    recoveryReplayDurationMetric,
    migrationOutcomeMetric,
  };

  final bool hasStructuredLogs;
  final bool hasCorrelationIds;
  final bool hasDebugExportBundle;
  final Set<String> availableMetrics;
}

/// Compatibility policy for profile and migration schemas.
@immutable
final class StorageCompatibilityPolicy {
  const StorageCompatibilityPolicy({
    required this.supportedProfileSchemaVersions,
    required this.supportedMigrationManifestSchemaVersions,
    required this.targetProfileSchemaVersion,
    required this.targetMigrationManifestSchemaVersion,
  });

  final Set<int> supportedProfileSchemaVersions;
  final Set<int> supportedMigrationManifestSchemaVersions;
  final int targetProfileSchemaVersion;
  final int targetMigrationManifestSchemaVersion;
}

/// Compatibility evidence from versioned tests.
@immutable
final class StorageCompatibilityEvidence {
  const StorageCompatibilityEvidence({
    this.profileSchemaVersionsValidated = const <int>{},
    this.migrationManifestVersionsValidated = const <int>{},
  });

  final Set<int> profileSchemaVersionsValidated;
  final Set<int> migrationManifestVersionsValidated;
}

/// Release checklist item with owner accountability.
@immutable
final class StorageReleaseChecklistItem {
  const StorageReleaseChecklistItem({
    required this.id,
    required this.description,
    required this.owner,
    required this.done,
    this.completedAtUtc,
  });

  final String id;
  final String description;
  final String owner;
  final bool done;
  final DateTime? completedAtUtc;
}

/// Rollback rehearsal record.
@immutable
final class StorageRollbackDrillRecord {
  const StorageRollbackDrillRecord({
    required this.executedAtUtc,
    required this.success,
    this.note = '',
  });

  final DateTime executedAtUtc;
  final bool success;
  final String note;
}

/// Deprecation stage for a legacy API/path.
enum StorageDeprecationStage {
  planned,
  announced,
  dualWrite,
  readSwitched,
  writeRemoved,
  completed,
}

/// Deprecation schedule item with owner/date.
@immutable
final class StorageDeprecationItem {
  const StorageDeprecationItem({
    required this.id,
    required this.description,
    required this.owner,
    required this.targetDateUtc,
    required this.stage,
  });

  final String id;
  final String description;
  final String owner;
  final DateTime targetDateUtc;
  final StorageDeprecationStage stage;
}

/// All inputs required to evaluate Gate G6.
@immutable
final class StorageReleaseGateInput {
  const StorageReleaseGateInput({
    required this.performanceBudgets,
    required this.performanceEvidence,
    required this.reliabilityCriteria,
    required this.reliabilityEvidence,
    required this.securityControls,
    required this.observabilityEvidence,
    required this.compatibilityPolicy,
    required this.compatibilityEvidence,
    required this.releaseChecklist,
    required this.rollbackDrills,
    required this.deprecationSchedule,
    this.maxRollbackDrillAge = const Duration(days: 30),
    this.evaluationTimeUtc,
  });

  final StoragePerformanceBudgets performanceBudgets;
  final StoragePerformanceEvidence performanceEvidence;
  final StorageReliabilityCriteria reliabilityCriteria;
  final StorageReliabilityEvidence reliabilityEvidence;
  final List<StorageSecurityControl> securityControls;
  final StorageObservabilityEvidence observabilityEvidence;
  final StorageCompatibilityPolicy compatibilityPolicy;
  final StorageCompatibilityEvidence compatibilityEvidence;
  final List<StorageReleaseChecklistItem> releaseChecklist;
  final List<StorageRollbackDrillRecord> rollbackDrills;
  final List<StorageDeprecationItem> deprecationSchedule;
  final Duration maxRollbackDrillAge;
  final DateTime? evaluationTimeUtc;
}

/// Gate G6 evaluation output.
@immutable
final class StorageReleaseGateReport {
  const StorageReleaseGateReport({
    required this.status,
    required this.evaluatedAtUtc,
    required this.findings,
    required this.summary,
  });

  final StorageReleaseGateStatus status;
  final DateTime evaluatedAtUtc;
  final List<StorageReleaseGateFinding> findings;
  final Map<String, dynamic> summary;

  bool get passed => status == StorageReleaseGateStatus.passed;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'status': status.name,
    'evaluated_at_utc': evaluatedAtUtc.toIso8601String(),
    'findings': findings.map((final finding) => finding.toJson()).toList(),
    'summary': summary,
  };
}

/// Evaluates hardening evidence and returns Gate G6 pass/fail status.
final class StorageReleaseGateEvaluator {
  const StorageReleaseGateEvaluator();

  StorageReleaseGateReport evaluate({
    required final StorageReleaseGateInput input,
  }) {
    final findings = <StorageReleaseGateFinding>[];
    final now = (input.evaluationTimeUtc ?? DateTime.now().toUtc()).toUtc();
    final summary = <String, dynamic>{
      'performance': _evaluatePerformance(input, findings),
      'reliability': _evaluateReliability(input, findings),
      'security': _evaluateSecurity(input, findings),
      'observability': _evaluateObservability(input, findings),
      'compatibility': _evaluateCompatibility(input, findings),
      'release': _evaluateReleaseAndRollback(input, findings, now),
      'deprecation': _evaluateDeprecation(input, findings, now),
    };

    final status = findings.any((final finding) => finding.isBlocking)
        ? StorageReleaseGateStatus.failed
        : StorageReleaseGateStatus.passed;

    return StorageReleaseGateReport(
      status: status,
      evaluatedAtUtc: now,
      findings: List<StorageReleaseGateFinding>.unmodifiable(findings),
      summary: Map<String, dynamic>.unmodifiable(summary),
    );
  }

  Map<String, dynamic> _evaluatePerformance(
    final StorageReleaseGateInput input,
    final List<StorageReleaseGateFinding> findings,
  ) {
    final budgets = input.performanceBudgets;
    final evidence = input.performanceEvidence;

    final writeP50 = _percentileDuration(evidence.writeLatencies, 0.50);
    final writeP95 = _percentileDuration(evidence.writeLatencies, 0.95);
    final readP50 = _percentileDuration(evidence.readLatencies, 0.50);
    final readP95 = _percentileDuration(evidence.readLatencies, 0.95);
    final syncP50 = _percentileInt(evidence.syncQueueThroughputPerMinute, 0.50);
    final memoryP95 = _percentileInt(evidence.memoryOverheadBytes, 0.95);
    final diffP95 = _percentileDuration(evidence.diffDecisionLatencies, 0.95);

    _requireSamples(
      findings: findings,
      metricId: 'performance.write_samples',
      actualSamples: evidence.writeLatencies.length,
      minSamples: budgets.minSamplesPerMetric,
      message: 'Insufficient write latency samples for budget evaluation.',
    );
    _requireSamples(
      findings: findings,
      metricId: 'performance.read_samples',
      actualSamples: evidence.readLatencies.length,
      minSamples: budgets.minSamplesPerMetric,
      message: 'Insufficient read latency samples for budget evaluation.',
    );
    _requireSamples(
      findings: findings,
      metricId: 'performance.sync_throughput_samples',
      actualSamples: evidence.syncQueueThroughputPerMinute.length,
      minSamples: budgets.minSamplesPerMetric,
      message: 'Insufficient sync throughput samples for budget evaluation.',
    );
    _requireSamples(
      findings: findings,
      metricId: 'performance.memory_samples',
      actualSamples: evidence.memoryOverheadBytes.length,
      minSamples: budgets.minSamplesPerMetric,
      message: 'Insufficient memory overhead samples for budget evaluation.',
    );
    _requireSamples(
      findings: findings,
      metricId: 'performance.diff_latency_samples',
      actualSamples: evidence.diffDecisionLatencies.length,
      minSamples: budgets.minSamplesPerMetric,
      message:
          'Insufficient diff decision latency samples for budget evaluation.',
    );

    if (writeP50 != null && writeP50 > budgets.writeLatencyP50Max) {
      findings.add(
        StorageReleaseGateFinding(
          id: 'performance.write_latency_p50',
          severity: StorageReleaseGateSeverity.blocking,
          message:
              'Write latency p50 ${writeP50.inMilliseconds}ms exceeds '
              'budget ${budgets.writeLatencyP50Max.inMilliseconds}ms.',
        ),
      );
    }
    if (writeP95 != null && writeP95 > budgets.writeLatencyP95Max) {
      findings.add(
        StorageReleaseGateFinding(
          id: 'performance.write_latency_p95',
          severity: StorageReleaseGateSeverity.blocking,
          message:
              'Write latency p95 ${writeP95.inMilliseconds}ms exceeds '
              'budget ${budgets.writeLatencyP95Max.inMilliseconds}ms.',
        ),
      );
    }
    if (readP50 != null && readP50 > budgets.readLatencyP50Max) {
      findings.add(
        StorageReleaseGateFinding(
          id: 'performance.read_latency_p50',
          severity: StorageReleaseGateSeverity.blocking,
          message:
              'Read latency p50 ${readP50.inMilliseconds}ms exceeds '
              'budget ${budgets.readLatencyP50Max.inMilliseconds}ms.',
        ),
      );
    }
    if (readP95 != null && readP95 > budgets.readLatencyP95Max) {
      findings.add(
        StorageReleaseGateFinding(
          id: 'performance.read_latency_p95',
          severity: StorageReleaseGateSeverity.blocking,
          message:
              'Read latency p95 ${readP95.inMilliseconds}ms exceeds '
              'budget ${budgets.readLatencyP95Max.inMilliseconds}ms.',
        ),
      );
    }
    if (syncP50 != null && syncP50 < budgets.minSyncQueueThroughputPerMinute) {
      findings.add(
        StorageReleaseGateFinding(
          id: 'performance.sync_throughput',
          severity: StorageReleaseGateSeverity.blocking,
          message:
              'Sync throughput p50 $syncP50 ops/min is below '
              'budget ${budgets.minSyncQueueThroughputPerMinute} ops/min.',
        ),
      );
    }
    if (memoryP95 != null && memoryP95 > budgets.maxMemoryOverheadBytes) {
      findings.add(
        StorageReleaseGateFinding(
          id: 'performance.memory_overhead',
          severity: StorageReleaseGateSeverity.blocking,
          message:
              'Memory overhead p95 $memoryP95 bytes exceeds '
              'budget ${budgets.maxMemoryOverheadBytes} bytes.',
        ),
      );
    }
    if (diffP95 != null && diffP95 > budgets.diffDecisionLatencyP95Max) {
      findings.add(
        StorageReleaseGateFinding(
          id: 'performance.diff_decision_latency',
          severity: StorageReleaseGateSeverity.blocking,
          message:
              'Diff decision latency p95 ${diffP95.inMilliseconds}ms exceeds '
              'budget ${budgets.diffDecisionLatencyP95Max.inMilliseconds}ms.',
        ),
      );
    }

    return <String, dynamic>{
      'write_latency_p50_ms': writeP50?.inMilliseconds,
      'write_latency_p95_ms': writeP95?.inMilliseconds,
      'read_latency_p50_ms': readP50?.inMilliseconds,
      'read_latency_p95_ms': readP95?.inMilliseconds,
      'sync_throughput_p50_ops_per_min': syncP50,
      'memory_overhead_p95_bytes': memoryP95,
      'diff_decision_latency_p95_ms': diffP95?.inMilliseconds,
    };
  }

  Map<String, dynamic> _evaluateReliability(
    final StorageReleaseGateInput input,
    final List<StorageReleaseGateFinding> findings,
  ) {
    final criteria = input.reliabilityCriteria;
    final evidence = input.reliabilityEvidence;
    final startupRecoveryP95 = _percentileDuration(
      evidence.startupRecoveryDurations,
      0.95,
    );

    if (evidence.soakDuration < criteria.minSoakDuration) {
      findings.add(
        StorageReleaseGateFinding(
          id: 'reliability.soak_duration',
          severity: StorageReleaseGateSeverity.blocking,
          message:
              'Soak duration ${evidence.soakDuration.inHours}h is below '
              'required ${criteria.minSoakDuration.inHours}h.',
        ),
      );
    }
    if (evidence.faultInjectionScenarios <
        criteria.minFaultInjectionScenarios) {
      findings.add(
        StorageReleaseGateFinding(
          id: 'reliability.fault_injection',
          severity: StorageReleaseGateSeverity.blocking,
          message:
              'Fault injection scenarios ${evidence.faultInjectionScenarios} '
              'is below required ${criteria.minFaultInjectionScenarios}.',
        ),
      );
    }
    if (startupRecoveryP95 == null) {
      findings.add(
        const StorageReleaseGateFinding(
          id: 'reliability.startup_recovery_samples',
          severity: StorageReleaseGateSeverity.blocking,
          message: 'Startup recovery durations were not provided.',
        ),
      );
    } else if (startupRecoveryP95 > criteria.maxStartupRecoveryP95) {
      findings.add(
        StorageReleaseGateFinding(
          id: 'reliability.startup_recovery_p95',
          severity: StorageReleaseGateSeverity.blocking,
          message:
              'Startup recovery p95 ${startupRecoveryP95.inMilliseconds}ms '
              'exceeds budget ${criteria.maxStartupRecoveryP95.inMilliseconds}ms.',
        ),
      );
    }
    if (evidence.migrationStressOperations <
        criteria.minMigrationStressOperations) {
      findings.add(
        StorageReleaseGateFinding(
          id: 'reliability.migration_stress',
          severity: StorageReleaseGateSeverity.blocking,
          message:
              'Migration stress coverage ${evidence.migrationStressOperations} '
              'ops is below required ${criteria.minMigrationStressOperations} ops.',
        ),
      );
    }
    if (evidence.outboxStressOperations < criteria.minOutboxStressOperations) {
      findings.add(
        StorageReleaseGateFinding(
          id: 'reliability.outbox_stress',
          severity: StorageReleaseGateSeverity.blocking,
          message:
              'Outbox stress coverage ${evidence.outboxStressOperations} ops '
              'is below required ${criteria.minOutboxStressOperations} ops.',
        ),
      );
    }

    final failureRate = evidence.failureRate;
    if (failureRate > criteria.maxFailureRate) {
      findings.add(
        StorageReleaseGateFinding(
          id: 'reliability.failure_rate',
          severity: StorageReleaseGateSeverity.blocking,
          message:
              'Failure rate ${(failureRate * 100).toStringAsFixed(2)}% exceeds '
              'budget ${(criteria.maxFailureRate * 100).toStringAsFixed(2)}%.',
        ),
      );
    }

    return <String, dynamic>{
      'soak_duration_hours': evidence.soakDuration.inHours,
      'fault_injection_scenarios': evidence.faultInjectionScenarios,
      'startup_recovery_p95_ms': startupRecoveryP95?.inMilliseconds,
      'migration_stress_operations': evidence.migrationStressOperations,
      'outbox_stress_operations': evidence.outboxStressOperations,
      'failure_rate': failureRate,
    };
  }

  Map<String, dynamic> _evaluateSecurity(
    final StorageReleaseGateInput input,
    final List<StorageReleaseGateFinding> findings,
  ) {
    if (input.securityControls.isEmpty) {
      findings.add(
        const StorageReleaseGateFinding(
          id: 'security.controls_missing',
          severity: StorageReleaseGateSeverity.blocking,
          message: 'Security checklist is empty.',
        ),
      );
      return const <String, dynamic>{
        'required_controls': 0,
        'passed': 0,
        'failed': 0,
        'waived': 0,
      };
    }

    var requiredControls = 0;
    var passed = 0;
    var failed = 0;
    var waived = 0;

    for (final control in input.securityControls) {
      if (!control.required) {
        continue;
      }
      requiredControls++;
      if (control.owner.trim().isEmpty) {
        findings.add(
          StorageReleaseGateFinding(
            id: 'security.owner_missing.${control.id}',
            severity: StorageReleaseGateSeverity.blocking,
            message: 'Security control "${control.id}" has no owner.',
          ),
        );
      }

      switch (control.status) {
        case StorageSecurityControlStatus.passed:
          passed++;
        case StorageSecurityControlStatus.failed:
          failed++;
          findings.add(
            StorageReleaseGateFinding(
              id: 'security.control_failed.${control.id}',
              severity: StorageReleaseGateSeverity.blocking,
              message:
                  'Security control "${control.id}" failed: '
                  '${control.description}',
            ),
          );
        case StorageSecurityControlStatus.waived:
          waived++;
          findings.add(
            StorageReleaseGateFinding(
              id: 'security.control_waived.${control.id}',
              severity: StorageReleaseGateSeverity.warning,
              message:
                  'Security control "${control.id}" is waived and requires '
                  'explicit release sign-off.',
            ),
          );
      }
    }

    return <String, dynamic>{
      'required_controls': requiredControls,
      'passed': passed,
      'failed': failed,
      'waived': waived,
    };
  }

  Map<String, dynamic> _evaluateObservability(
    final StorageReleaseGateInput input,
    final List<StorageReleaseGateFinding> findings,
  ) {
    final evidence = input.observabilityEvidence;

    if (!evidence.hasStructuredLogs) {
      findings.add(
        const StorageReleaseGateFinding(
          id: 'observability.structured_logs',
          severity: StorageReleaseGateSeverity.blocking,
          message: 'Structured logs are not enabled.',
        ),
      );
    }
    if (!evidence.hasCorrelationIds) {
      findings.add(
        const StorageReleaseGateFinding(
          id: 'observability.correlation_ids',
          severity: StorageReleaseGateSeverity.blocking,
          message: 'Correlation ids are missing from observability output.',
        ),
      );
    }
    if (!evidence.hasDebugExportBundle) {
      findings.add(
        const StorageReleaseGateFinding(
          id: 'observability.debug_bundle',
          severity: StorageReleaseGateSeverity.blocking,
          message: 'Debug export bundle support is not available.',
        ),
      );
    }

    final missingMetrics = StorageObservabilityEvidence.requiredMetrics
        .difference(evidence.availableMetrics);
    if (missingMetrics.isNotEmpty) {
      findings.add(
        StorageReleaseGateFinding(
          id: 'observability.metrics_missing',
          severity: StorageReleaseGateSeverity.blocking,
          message:
              'Missing required observability metrics: '
              '${missingMetrics.toList()..sort()}.',
        ),
      );
    }

    return <String, dynamic>{
      'has_structured_logs': evidence.hasStructuredLogs,
      'has_correlation_ids': evidence.hasCorrelationIds,
      'has_debug_export_bundle': evidence.hasDebugExportBundle,
      'available_metrics': evidence.availableMetrics.toList()..sort(),
      'missing_metrics': missingMetrics.toList()..sort(),
    };
  }

  Map<String, dynamic> _evaluateCompatibility(
    final StorageReleaseGateInput input,
    final List<StorageReleaseGateFinding> findings,
  ) {
    final policy = input.compatibilityPolicy;
    final evidence = input.compatibilityEvidence;

    if (!policy.supportedProfileSchemaVersions.contains(
      policy.targetProfileSchemaVersion,
    )) {
      findings.add(
        StorageReleaseGateFinding(
          id: 'compatibility.profile_target_unsupported',
          severity: StorageReleaseGateSeverity.blocking,
          message:
              'Target profile schema v${policy.targetProfileSchemaVersion} '
              'is not part of supported profile schema versions.',
        ),
      );
    }
    if (!policy.supportedMigrationManifestSchemaVersions.contains(
      policy.targetMigrationManifestSchemaVersion,
    )) {
      findings.add(
        StorageReleaseGateFinding(
          id: 'compatibility.migration_target_unsupported',
          severity: StorageReleaseGateSeverity.blocking,
          message:
              'Target migration manifest schema '
              'v${policy.targetMigrationManifestSchemaVersion} is not part of '
              'supported migration schema versions.',
        ),
      );
    }
    if (!evidence.profileSchemaVersionsValidated.contains(
      policy.targetProfileSchemaVersion,
    )) {
      findings.add(
        StorageReleaseGateFinding(
          id: 'compatibility.profile_target_not_validated',
          severity: StorageReleaseGateSeverity.blocking,
          message:
              'Profile schema v${policy.targetProfileSchemaVersion} was not '
              'validated in compatibility tests.',
        ),
      );
    }
    if (!evidence.migrationManifestVersionsValidated.contains(
      policy.targetMigrationManifestSchemaVersion,
    )) {
      findings.add(
        StorageReleaseGateFinding(
          id: 'compatibility.migration_target_not_validated',
          severity: StorageReleaseGateSeverity.blocking,
          message:
              'Migration schema v${policy.targetMigrationManifestSchemaVersion} '
              'was not validated in compatibility tests.',
        ),
      );
    }

    final unsupportedProfileValidated = evidence.profileSchemaVersionsValidated
        .difference(policy.supportedProfileSchemaVersions);
    if (unsupportedProfileValidated.isNotEmpty) {
      findings.add(
        StorageReleaseGateFinding(
          id: 'compatibility.profile_unsupported_validated_versions',
          severity: StorageReleaseGateSeverity.blocking,
          message:
              'Compatibility suite validated unsupported profile schema '
              'versions: ${unsupportedProfileValidated.toList()..sort()}.',
        ),
      );
    }

    final unsupportedMigrationValidated = evidence
        .migrationManifestVersionsValidated
        .difference(policy.supportedMigrationManifestSchemaVersions);
    if (unsupportedMigrationValidated.isNotEmpty) {
      findings.add(
        StorageReleaseGateFinding(
          id: 'compatibility.migration_unsupported_validated_versions',
          severity: StorageReleaseGateSeverity.blocking,
          message:
              'Compatibility suite validated unsupported migration schema '
              'versions: ${unsupportedMigrationValidated.toList()..sort()}.',
        ),
      );
    }

    if (evidence.profileSchemaVersionsValidated.length < 2 &&
        policy.supportedProfileSchemaVersions.length > 1) {
      findings.add(
        const StorageReleaseGateFinding(
          id: 'compatibility.profile_backward_coverage',
          severity: StorageReleaseGateSeverity.warning,
          message:
              'Profile schema compatibility coverage has fewer than 2 versions.',
        ),
      );
    }
    if (evidence.migrationManifestVersionsValidated.length < 2 &&
        policy.supportedMigrationManifestSchemaVersions.length > 1) {
      findings.add(
        const StorageReleaseGateFinding(
          id: 'compatibility.migration_backward_coverage',
          severity: StorageReleaseGateSeverity.warning,
          message:
              'Migration schema compatibility coverage has fewer than 2 versions.',
        ),
      );
    }

    return <String, dynamic>{
      'supported_profile_schema_versions':
          policy.supportedProfileSchemaVersions.toList()..sort(),
      'supported_migration_schema_versions':
          policy.supportedMigrationManifestSchemaVersions.toList()..sort(),
      'validated_profile_schema_versions':
          evidence.profileSchemaVersionsValidated.toList()..sort(),
      'validated_migration_schema_versions':
          evidence.migrationManifestVersionsValidated.toList()..sort(),
    };
  }

  Map<String, dynamic> _evaluateReleaseAndRollback(
    final StorageReleaseGateInput input,
    final List<StorageReleaseGateFinding> findings,
    final DateTime now,
  ) {
    if (input.releaseChecklist.isEmpty) {
      findings.add(
        const StorageReleaseGateFinding(
          id: 'release.checklist_missing',
          severity: StorageReleaseGateSeverity.blocking,
          message: 'Release checklist is empty.',
        ),
      );
    }

    var completedChecklistItems = 0;
    for (final item in input.releaseChecklist) {
      if (item.owner.trim().isEmpty) {
        findings.add(
          StorageReleaseGateFinding(
            id: 'release.owner_missing.${item.id}',
            severity: StorageReleaseGateSeverity.blocking,
            message: 'Release checklist item "${item.id}" has no owner.',
          ),
        );
      }
      if (!item.done) {
        findings.add(
          StorageReleaseGateFinding(
            id: 'release.pending.${item.id}',
            severity: StorageReleaseGateSeverity.blocking,
            message: 'Release checklist item "${item.id}" is not completed.',
          ),
        );
      } else {
        completedChecklistItems++;
      }
    }

    final successfulDrills = input.rollbackDrills
        .where((final drill) => drill.success)
        .toList(growable: false);
    if (successfulDrills.isEmpty) {
      findings.add(
        const StorageReleaseGateFinding(
          id: 'release.rollback_drill_missing',
          severity: StorageReleaseGateSeverity.blocking,
          message: 'No successful rollback drill found. Rehearsal is required.',
        ),
      );
    } else {
      successfulDrills.sort(
        (final a, final b) => b.executedAtUtc.compareTo(a.executedAtUtc),
      );
      final latestDrill = successfulDrills.first.executedAtUtc.toUtc();
      if (now.difference(latestDrill) > input.maxRollbackDrillAge) {
        findings.add(
          StorageReleaseGateFinding(
            id: 'release.rollback_drill_stale',
            severity: StorageReleaseGateSeverity.blocking,
            message:
                'Latest successful rollback drill is older than '
                '${input.maxRollbackDrillAge.inDays} days.',
            metadata: <String, dynamic>{
              'latest_successful_drill_utc': latestDrill.toIso8601String(),
            },
          ),
        );
      }
    }

    return <String, dynamic>{
      'checklist_items_total': input.releaseChecklist.length,
      'checklist_items_completed': completedChecklistItems,
      'rollback_drills_total': input.rollbackDrills.length,
      'rollback_drills_successful': successfulDrills.length,
    };
  }

  Map<String, dynamic> _evaluateDeprecation(
    final StorageReleaseGateInput input,
    final List<StorageReleaseGateFinding> findings,
    final DateTime now,
  ) {
    if (input.deprecationSchedule.isEmpty) {
      findings.add(
        const StorageReleaseGateFinding(
          id: 'deprecation.schedule_missing',
          severity: StorageReleaseGateSeverity.blocking,
          message: 'Deprecation schedule is empty.',
        ),
      );
      return const <String, dynamic>{'scheduled_items': 0, 'overdue_items': 0};
    }

    var overdueItems = 0;
    for (final item in input.deprecationSchedule) {
      if (item.owner.trim().isEmpty) {
        findings.add(
          StorageReleaseGateFinding(
            id: 'deprecation.owner_missing.${item.id}',
            severity: StorageReleaseGateSeverity.blocking,
            message: 'Deprecation item "${item.id}" has no owner.',
          ),
        );
      }

      final target = item.targetDateUtc.toUtc();
      if (!target.isAfter(now) &&
          item.stage != StorageDeprecationStage.completed) {
        overdueItems++;
        findings.add(
          StorageReleaseGateFinding(
            id: 'deprecation.overdue.${item.id}',
            severity: StorageReleaseGateSeverity.blocking,
            message:
                'Deprecation item "${item.id}" is overdue for '
                '${target.toIso8601String()} and not completed.',
          ),
        );
      }
    }

    return <String, dynamic>{
      'scheduled_items': input.deprecationSchedule.length,
      'overdue_items': overdueItems,
    };
  }

  void _requireSamples({
    required final List<StorageReleaseGateFinding> findings,
    required final String metricId,
    required final int actualSamples,
    required final int minSamples,
    required final String message,
  }) {
    if (actualSamples >= minSamples) {
      return;
    }
    findings.add(
      StorageReleaseGateFinding(
        id: metricId,
        severity: StorageReleaseGateSeverity.blocking,
        message: '$message ($actualSamples/$minSamples).',
      ),
    );
  }

  Duration? _percentileDuration(
    final List<Duration> values,
    final double percentile,
  ) {
    if (values.isEmpty) {
      return null;
    }
    final sorted = values.toList()..sort();
    final index = _percentileIndex(sorted.length, percentile);
    return sorted[index];
  }

  int? _percentileInt(final List<int> values, final double percentile) {
    if (values.isEmpty) {
      return null;
    }
    final sorted = values.toList()..sort();
    final index = _percentileIndex(sorted.length, percentile);
    return sorted[index];
  }

  int _percentileIndex(final int length, final double percentile) {
    if (length <= 1) {
      return 0;
    }
    final position = ((length - 1) * percentile).ceil();
    return position.clamp(0, length - 1);
  }
}
