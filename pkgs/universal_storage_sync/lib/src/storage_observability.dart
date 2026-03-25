import 'dart:math';

import 'package:meta/meta.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

import 'storage_release_gate.dart';

/// Structured log representation for storage observations.
@immutable
final class StorageStructuredLogEntry {
  const StorageStructuredLogEntry({
    required this.correlationId,
    required this.timestampUtc,
    required this.type,
    required this.namespace,
    required this.path,
    required this.origin,
    required this.success,
    required this.message,
    this.metadata = const <String, dynamic>{},
  });

  final String correlationId;
  final DateTime timestampUtc;
  final StorageObservationType type;
  final StorageNamespace namespace;
  final String path;
  final StorageOperationOrigin origin;
  final bool success;
  final String message;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'correlation_id': correlationId,
    'timestamp_utc': timestampUtc.toIso8601String(),
    'type': type.name,
    'namespace': namespace.value,
    'path': path,
    'origin': origin.name,
    'success': success,
    'message': message,
    'metadata': metadata,
  };
}

/// Collects storage observations into a debug bundle and observability summary.
final class StorageDebugBundleCollector {
  StorageDebugBundleCollector({this.maxLogEntries = 2000})
    : assert(maxLogEntries > 0, 'maxLogEntries must be positive');

  static const String redactedValue = '***redacted***';

  final int maxLogEntries;

  final List<StorageStructuredLogEntry> _entries =
      <StorageStructuredLogEntry>[];
  final List<Duration> _writeLatencies = <Duration>[];
  final List<Duration> _readLatencies = <Duration>[];
  final List<Duration> _recoveryReplayDurations = <Duration>[];

  var _generatedCorrelationCounter = 0;
  var _syncEvents = 0;
  var _conflictEvents = 0;
  var _autoResolvedDecisions = 0;
  var _userDecisionRequiredCount = 0;
  var _safeDegradeCount = 0;
  var _migrationSuccessCount = 0;
  var _migrationFailureCount = 0;
  var _lastQueueDepth = 0;

  /// Ingests one kernel observation event and updates counters.
  void ingest(final StorageObservationEvent event) {
    final sanitized = _sanitizeMap(event.metadata);
    final correlationId = _resolveCorrelationId(
      event: event,
      metadata: sanitized,
    );

    final result = event.result;
    final entry = StorageStructuredLogEntry(
      correlationId: correlationId,
      timestampUtc: event.timestamp.toUtc(),
      type: event.type,
      namespace: event.namespace,
      path: event.path,
      origin: event.origin,
      success: result?.success ?? true,
      message: result?.message ?? '',
      metadata: sanitized,
    );
    _entries.add(entry);
    if (_entries.length > maxLogEntries) {
      _entries.removeRange(0, _entries.length - maxLogEntries);
    }

    _updateCounters(entry);
  }

  /// Records local write latency sample.
  void recordWriteLatency(final Duration latency) {
    if (latency.isNegative) {
      return;
    }
    _writeLatencies.add(latency);
  }

  /// Records local read latency sample.
  void recordReadLatency(final Duration latency) {
    if (latency.isNegative) {
      return;
    }
    _readLatencies.add(latency);
  }

  /// Records recovery replay duration sample.
  void recordRecoveryReplayDuration(final Duration duration) {
    if (duration.isNegative) {
      return;
    }
    _recoveryReplayDurations.add(duration);
  }

  /// Builds observability evidence required by Gate G6.
  StorageObservabilityEvidence buildEvidence() {
    final availableMetrics = <String>{};
    if (_writeLatencies.isNotEmpty) {
      availableMetrics.add(StorageObservabilityEvidence.writeLatencyMetric);
    }
    if (_readLatencies.isNotEmpty) {
      availableMetrics.add(StorageObservabilityEvidence.readLatencyMetric);
    }
    if (_syncEvents > 0) {
      availableMetrics
        ..add(StorageObservabilityEvidence.queueDepthMetric)
        ..add(StorageObservabilityEvidence.conflictRateMetric)
        ..add(StorageObservabilityEvidence.safeDegradeCountMetric);
    }
    if (_autoResolvedDecisions > 0 || _userDecisionRequiredCount > 0) {
      availableMetrics.add(StorageObservabilityEvidence.autoResolveRatioMetric);
    }
    if (_recoveryReplayDurations.isNotEmpty) {
      availableMetrics.add(
        StorageObservabilityEvidence.recoveryReplayDurationMetric,
      );
    }
    if (_migrationSuccessCount > 0 || _migrationFailureCount > 0) {
      availableMetrics.add(StorageObservabilityEvidence.migrationOutcomeMetric);
    }

    return StorageObservabilityEvidence(
      hasStructuredLogs: _entries.isNotEmpty,
      hasCorrelationIds:
          _entries.isNotEmpty &&
          _entries.every(
            (final entry) => entry.correlationId.trim().isNotEmpty,
          ),
      hasDebugExportBundle: true,
      availableMetrics: Set<String>.unmodifiable(availableMetrics),
    );
  }

  /// Exports sanitized structured logs and key metrics for support bundles.
  Map<String, dynamic> exportDebugBundle({final int logLimit = 200}) {
    final normalizedLogLimit = logLimit < 1 ? 1 : logLimit;
    final fromIndex = max(_entries.length - normalizedLogLimit, 0);
    final logs = _entries
        .sublist(fromIndex)
        .map((final entry) => entry.toJson())
        .toList(growable: false);

    final totalDecisionEvents =
        _autoResolvedDecisions + _userDecisionRequiredCount;
    final autoResolveRatio = totalDecisionEvents == 0
        ? 0
        : _autoResolvedDecisions / totalDecisionEvents;

    final conflictRate = _syncEvents == 0 ? 0 : _conflictEvents / _syncEvents;

    return <String, dynamic>{
      'generated_at_utc': DateTime.now().toUtc().toIso8601String(),
      'metrics': <String, dynamic>{
        'write_latency_p50_ms': _percentileDurationMs(_writeLatencies, 0.50),
        'write_latency_p95_ms': _percentileDurationMs(_writeLatencies, 0.95),
        'read_latency_p50_ms': _percentileDurationMs(_readLatencies, 0.50),
        'read_latency_p95_ms': _percentileDurationMs(_readLatencies, 0.95),
        'queue_depth': _lastQueueDepth,
        'conflict_rate': conflictRate,
        'auto_resolve_ratio': autoResolveRatio,
        'safe_degrade_count': _safeDegradeCount,
        'recovery_replay_duration_p95_ms': _percentileDurationMs(
          _recoveryReplayDurations,
          0.95,
        ),
        'migration_success_count': _migrationSuccessCount,
        'migration_failure_count': _migrationFailureCount,
      },
      'logs': logs,
    };
  }

  String _resolveCorrelationId({
    required final StorageObservationEvent event,
    required final Map<String, dynamic> metadata,
  }) {
    final raw = metadata['correlation_id']?.toString().trim() ?? '';
    if (raw.isNotEmpty) {
      return raw;
    }
    _generatedCorrelationCounter++;
    final generated =
        'generated_${event.type.name}_${event.namespace.value}_'
        '${event.timestamp.toUtc().microsecondsSinceEpoch}_'
        '$_generatedCorrelationCounter';
    metadata['correlation_id'] = generated;
    return generated;
  }

  void _updateCounters(final StorageStructuredLogEntry entry) {
    final metadata = entry.metadata;
    final degradeReason = metadata['interaction_downgrade_reason']
        ?.toString()
        .trim();
    if (degradeReason != null && degradeReason.isNotEmpty) {
      _safeDegradeCount++;
    }

    final queueDepth = _asInt(metadata['outbox_pending']);
    if (queueDepth != null) {
      _lastQueueDepth = max(queueDepth, 0);
    }

    final writeLatencyMs = _asInt(metadata['write_latency_ms']);
    if (writeLatencyMs != null && writeLatencyMs >= 0) {
      _writeLatencies.add(Duration(milliseconds: writeLatencyMs));
    }

    final readLatencyMs = _asInt(metadata['read_latency_ms']);
    if (readLatencyMs != null && readLatencyMs >= 0) {
      _readLatencies.add(Duration(milliseconds: readLatencyMs));
    }

    final recoveryReplayMs = _asInt(metadata['recovery_replay_ms']);
    if (recoveryReplayMs != null && recoveryReplayMs >= 0) {
      _recoveryReplayDurations.add(Duration(milliseconds: recoveryReplayMs));
    }

    switch (entry.type) {
      case StorageObservationType.synced:
        _syncEvents++;
      case StorageObservationType.conflictStaged:
        _conflictEvents++;
        _userDecisionRequiredCount++;
      case StorageObservationType.decisionResolved:
        final targetState = metadata['target_state']?.toString().trim();
        if (targetState == DecisionState.autoResolved.name) {
          _autoResolvedDecisions++;
        }
      case StorageObservationType.migrationExecuted:
        if (entry.success) {
          _migrationSuccessCount++;
        } else {
          _migrationFailureCount++;
        }
      case StorageObservationType.created:
      case StorageObservationType.updated:
      case StorageObservationType.deleted:
      case StorageObservationType.syncSkipped:
      case StorageObservationType.outboxQueued:
      case StorageObservationType.outboxReplayed:
      case StorageObservationType.outboxDeadLettered:
      case StorageObservationType.migrationPrepared:
    }
  }

  int? _asInt(final Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  int? _percentileDurationMs(
    final List<Duration> values,
    final double percentile,
  ) {
    if (values.isEmpty) {
      return null;
    }
    final sorted = values.toList()..sort();
    final index = _percentileIndex(sorted.length, percentile);
    return sorted[index].inMilliseconds;
  }

  int _percentileIndex(final int length, final double percentile) {
    if (length <= 1) {
      return 0;
    }
    final position = ((length - 1) * percentile).ceil();
    return position.clamp(0, length - 1);
  }

  Map<String, dynamic> _sanitizeMap(final Map<String, dynamic> source) {
    final sanitized = <String, dynamic>{};
    source.forEach((final rawKey, final rawValue) {
      final key = rawKey.toString();
      sanitized[key] = _sanitizeValue(key: key, value: rawValue);
    });
    return sanitized;
  }

  Object? _sanitizeValue({
    required final String key,
    required final Object? value,
  }) {
    if (value is Map) {
      return _sanitizeMap(Map<String, dynamic>.from(value));
    }
    if (value is List) {
      return value
          .map(
            (final item) =>
                _sanitizeValue(key: key, value: item) ?? redactedValue,
          )
          .toList(growable: false);
    }
    if (_isSensitiveKey(key) || _looksSensitiveValue(value)) {
      return redactedValue;
    }
    return value;
  }

  bool _isSensitiveKey(final String key) {
    final normalized = key.toLowerCase();
    const sensitiveParts = <String>[
      'token',
      'secret',
      'password',
      'authorization',
      'api_key',
      'access_key',
      'refresh_key',
      'cookie',
      'credential',
    ];
    return sensitiveParts.any(normalized.contains);
  }

  bool _looksSensitiveValue(final Object? value) {
    if (value is! String) {
      return false;
    }
    final normalized = value.toLowerCase().trim();
    if (normalized.isEmpty) {
      return false;
    }
    return normalized.startsWith('bearer ') ||
        normalized.contains('ghp_') ||
        normalized.contains('github_pat_');
  }
}
