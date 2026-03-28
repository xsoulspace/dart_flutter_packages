
import 'package:xsoulspace_logger/xsoulspace_logger.dart';

import 'issue_status.dart';

/// Aggregated issue state for one fingerprint.
final class IssueGroup {
  const IssueGroup({
    required this.fingerprint,
    required this.firstSeen,
    required this.lastSeen,
    required this.occurrences24h,
    required this.highestLevel,
    required this.status,
    required this.priorityScore,
    required this.escalated,
  });

  final String fingerprint;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final int occurrences24h;
  final LogLevel highestLevel;
  final IssueStatus status;
  final double priorityScore;
  final bool escalated;

  IssueGroup copyWith({
    final DateTime? firstSeen,
    final DateTime? lastSeen,
    final int? occurrences24h,
    final LogLevel? highestLevel,
    final IssueStatus? status,
    final double? priorityScore,
    final bool? escalated,
  }) => IssueGroup(
    fingerprint: fingerprint,
    firstSeen: firstSeen ?? this.firstSeen,
    lastSeen: lastSeen ?? this.lastSeen,
    occurrences24h: occurrences24h ?? this.occurrences24h,
    highestLevel: highestLevel ?? this.highestLevel,
    status: status ?? this.status,
    priorityScore: priorityScore ?? this.priorityScore,
    escalated: escalated ?? this.escalated,
  );
}
