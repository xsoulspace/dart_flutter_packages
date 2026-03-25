import 'dart:async';

import 'inference_result.dart';

enum InferenceReadinessState { ready, degraded, unavailable }

final class InferenceReadinessIssue {
  const InferenceReadinessIssue({
    required this.code,
    required this.message,
    this.isBlocking = true,
    this.details,
    this.remediation,
  });

  final String code;
  final String message;
  final bool isBlocking;
  final Object? details;
  final String? remediation;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'code': code,
    'message': message,
    'is_blocking': isBlocking,
    if (details != null) 'details': details,
    if (remediation != null) 'remediation': remediation,
  };

  factory InferenceReadinessIssue.fromJson(final Map<String, dynamic> json) =>
      InferenceReadinessIssue(
        code: (json['code'] as String?) ?? 'readiness_issue',
        message: (json['message'] as String?) ?? 'Readiness issue',
        isBlocking: json['is_blocking'] as bool? ?? true,
        details: json['details'],
        remediation: json['remediation'] as String?,
      );
}

final class InferenceReadinessSnapshot {
  const InferenceReadinessSnapshot({
    required this.state,
    this.summary = '',
    this.issues = const <InferenceReadinessIssue>[],
    this.metadata = const <String, dynamic>{},
  });

  final InferenceReadinessState state;
  final String summary;
  final List<InferenceReadinessIssue> issues;
  final Map<String, dynamic> metadata;

  bool get isReady => state == InferenceReadinessState.ready;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'state': state.name,
    'summary': summary,
    'issues': issues.map((final issue) => issue.toJson()).toList(),
    'metadata': metadata,
  };

  factory InferenceReadinessSnapshot.fromJson(final Map<String, dynamic> json) {
    final stateName = json['state'] as String?;
    return InferenceReadinessSnapshot(
      state: InferenceReadinessState.values.firstWhere(
        (final value) => value.name == stateName,
        orElse: () => InferenceReadinessState.unavailable,
      ),
      summary: (json['summary'] as String?) ?? '',
      issues:
          (json['issues'] as List?)
              ?.map(
                (final issue) => InferenceReadinessIssue.fromJson(
                  (issue as Map).cast<String, dynamic>(),
                ),
              )
              .toList(growable: false) ??
          const <InferenceReadinessIssue>[],
      metadata:
          (json['metadata'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
    );
  }
}

abstract interface class InferenceReadinessProbe {
  FutureOr<InferenceReadinessSnapshot> probe();
}

String formatInferenceReadinessSummary(
  final InferenceReadinessSnapshot snapshot,
) {
  if (snapshot.summary.trim().isNotEmpty) {
    return snapshot.summary.trim();
  }
  if (snapshot.issues.isEmpty) {
    return switch (snapshot.state) {
      InferenceReadinessState.ready => 'Ready',
      InferenceReadinessState.degraded => 'Ready with limitations',
      InferenceReadinessState.unavailable => 'Unavailable',
    };
  }
  return snapshot.issues.first.message;
}

List<String> formatInferenceReadinessIssues(
  final InferenceReadinessSnapshot snapshot,
) {
  return snapshot.issues
      .map((final issue) {
        final remediation = issue.remediation?.trim();
        return remediation == null || remediation.isEmpty
            ? issue.message
            : '${issue.message} ${remediation.trim()}';
      })
      .toList(growable: false);
}

InferenceResult<void> toInferenceReadinessResult(
  final InferenceReadinessSnapshot snapshot,
) {
  if (snapshot.isReady) {
    return InferenceResult<void>.ok(null);
  }

  final issue = snapshot.issues.firstWhere(
    (final value) => value.isBlocking,
    orElse: () => snapshot.issues.isEmpty
        ? const InferenceReadinessIssue(
            code: 'engine_unavailable',
            message: 'Provider is unavailable',
          )
        : snapshot.issues.first,
  );
  return InferenceResult<void>.fail(
    code: issue.code,
    message: issue.message,
    details: issue.details ?? snapshot.metadata,
  );
}
