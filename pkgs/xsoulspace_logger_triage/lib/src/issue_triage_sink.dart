
import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:xsoulspace_logger/xsoulspace_logger.dart';

import 'fingerprint_generator.dart';
import 'issue_group.dart';
import 'issue_status.dart';
import 'triage_config.dart';

/// Log sink that builds issue groups with scoring and escalation.
final class IssueTriageSink implements LogSink {
  IssueTriageSink({
    this.config = const TriageConfig(),
    final FingerprintGenerator? fingerprintGenerator,
  }) : _fingerprintGenerator =
           fingerprintGenerator ?? const FingerprintGenerator();

  final TriageConfig config;
  final FingerprintGenerator _fingerprintGenerator;

  final Map<String, _IssueState> _states = <String, _IssueState>{};
  final StreamController<List<IssueGroup>> _groupsController =
      StreamController<List<IssueGroup>>.broadcast();

  bool _initialized = false;
  bool _disposed = false;
  DateTime? _latestObservedAtUtc;

  @override
  Future<void> init() async {
    _initialized = true;
  }

  @override
  void enqueue(final LogRecord record) {
    if (_disposed) {
      return;
    }

    final nowUtc = record.timestampUtc.toUtc();
    if (_latestObservedAtUtc == null || nowUtc.isAfter(_latestObservedAtUtc!)) {
      _latestObservedAtUtc = nowUtc;
    }
    final fingerprint =
        record.fingerprint ??
        _fingerprintGenerator.fingerprint(
          record,
          topFrames: config.topAppFrames,
        );

    final existing = _states[fingerprint];
    if (existing == null) {
      final state = _IssueState(
        fingerprint: fingerprint,
        firstSeen: nowUtc,
        lastSeen: nowUtc,
        highestLevel: record.level,
        status: IssueStatus.open,
      );
      state.addOccurrence(nowUtc);
      _states[fingerprint] = state;
    } else {
      existing.addOccurrence(nowUtc);
      if (nowUtc.difference(existing.lastSeen) <= config.dedupWindow &&
          !nowUtc.isBefore(existing.lastSeen)) {
        existing.lastDuplicateAt = nowUtc;
      }
      existing.lastSeen = nowUtc;
      if (record.level.index > existing.highestLevel.index) {
        existing.highestLevel = record.level;
      }
      if (existing.status == IssueStatus.resolved) {
        existing.status = IssueStatus.regressing;
      }
    }

    _emit();
  }

  /// Streams sorted issue groups (highest score first).
  Stream<List<IssueGroup>> watchTopIssues({final int limit = 50}) async* {
    yield currentTopIssues(limit: limit);
    yield* _groupsController.stream.map(
      (final groups) =>
          List<IssueGroup>.unmodifiable(groups.take(limit < 0 ? 0 : limit)),
    );
  }

  /// Snapshot of current top issues.
  List<IssueGroup> currentTopIssues({final int limit = 50}) {
    final sorted = _buildSortedGroups();
    if (limit >= 0 && sorted.length > limit) {
      return List<IssueGroup>.unmodifiable(sorted.take(limit));
    }
    return List<IssueGroup>.unmodifiable(sorted);
  }

  /// Marks a fingerprint as resolved.
  Future<void> markResolved(final String fingerprint) async {
    final state = _states[fingerprint];
    if (state == null) {
      return;
    }

    state.status = IssueStatus.resolved;
    _emit();
  }

  @override
  Future<void> flush() async {
    // In-memory aggregation only.
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    if (!_groupsController.isClosed) {
      await _groupsController.close();
    }
  }

  void _emit() {
    if (_disposed || !_initialized || _groupsController.isClosed) {
      return;
    }

    _groupsController.add(_buildSortedGroups());
  }

  List<IssueGroup> _buildSortedGroups() {
    final nowUtc = _latestObservedAtUtc ?? DateTime.now().toUtc();
    final groups = <IssueGroup>[];

    for (final state in _states.values) {
      state.pruneOlderThan(nowUtc.subtract(config.occurrenceWindow));
      final occurrences24h = state.occurrences.length;
      final score = _priorityScore(
        highestLevel: state.highestLevel,
        occurrences24h: occurrences24h,
        lastSeen: state.lastSeen,
        nowUtc: nowUtc,
      );
      final escalated =
          state.highestLevel == LogLevel.critical ||
          score >= config.escalationScoreThreshold;

      groups.add(
        IssueGroup(
          fingerprint: state.fingerprint,
          firstSeen: state.firstSeen,
          lastSeen: state.lastSeen,
          occurrences24h: occurrences24h,
          highestLevel: state.highestLevel,
          status: state.status,
          priorityScore: score,
          escalated: escalated,
        ),
      );
    }

    groups.sort((final a, final b) {
      final scoreCompare = b.priorityScore.compareTo(a.priorityScore);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return b.lastSeen.compareTo(a.lastSeen);
    });

    return groups;
  }

  double _priorityScore({
    required final LogLevel highestLevel,
    required final int occurrences24h,
    required final DateTime lastSeen,
    required final DateTime nowUtc,
  }) {
    final severityWeight = config.severityWeight(highestLevel).toDouble();
    final frequencyWeight = log(occurrences24h + 1) / ln10 * 15;
    final recencyWeight = _recencyBoost(lastSeen: lastSeen, nowUtc: nowUtc);

    return severityWeight + frequencyWeight + recencyWeight;
  }

  double _recencyBoost({
    required final DateTime lastSeen,
    required final DateTime nowUtc,
  }) {
    if (lastSeen.isAfter(nowUtc)) {
      return 25;
    }

    final elapsedMs = nowUtc.difference(lastSeen).inMilliseconds;
    final windowMs = config.occurrenceWindow.inMilliseconds;
    if (windowMs <= 0 || elapsedMs >= windowMs) {
      return 0;
    }

    final ratio = 1 - (elapsedMs / windowMs);
    return ratio * 25;
  }
}

final class _IssueState {
  _IssueState({
    required this.fingerprint,
    required this.firstSeen,
    required this.lastSeen,
    required this.highestLevel,
    required this.status,
  });

  final String fingerprint;
  final DateTime firstSeen;
  DateTime lastSeen;
  LogLevel highestLevel;
  IssueStatus status;
  DateTime? lastDuplicateAt;

  final ListQueue<DateTime> occurrences = ListQueue<DateTime>();

  void addOccurrence(final DateTime timestampUtc) {
    occurrences.addLast(timestampUtc);
  }

  void pruneOlderThan(final DateTime thresholdUtc) {
    while (occurrences.isNotEmpty && occurrences.first.isBefore(thresholdUtc)) {
      occurrences.removeFirst();
    }
  }
}
