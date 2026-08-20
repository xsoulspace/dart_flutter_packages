import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  test('InferenceReadinessSnapshot serialization round-trips', () {
    const snapshot = InferenceReadinessSnapshot(
      state: InferenceReadinessState.degraded,
      summary: 'Ready with limitations',
      issues: <InferenceReadinessIssue>[
        InferenceReadinessIssue(
          code: 'model_missing',
          message: 'Model is missing',
          remediation: 'Provide model path.',
        ),
      ],
      metadata: <String, dynamic>{'provider': 'test'},
    );

    final decoded = InferenceReadinessSnapshot.fromJson(snapshot.toJson());
    expect(decoded.state, InferenceReadinessState.degraded);
    expect(decoded.issues.single.code, 'model_missing');
    expect(decoded.metadata['provider'], 'test');
  });

  test('formatInferenceReadinessIssues appends remediation', () {
    const snapshot = InferenceReadinessSnapshot(
      state: InferenceReadinessState.unavailable,
      issues: <InferenceReadinessIssue>[
        InferenceReadinessIssue(
          code: 'runtime_missing',
          message: 'Runtime not found.',
          remediation: 'Set libraryPath.',
        ),
      ],
    );

    expect(formatInferenceReadinessIssues(snapshot), const <String>[
      'Runtime not found. Set libraryPath.',
    ]);
  });

  test('toInferenceReadinessResult fails on blocking issue', () {
    const snapshot = InferenceReadinessSnapshot(
      state: InferenceReadinessState.unavailable,
      issues: <InferenceReadinessIssue>[
        InferenceReadinessIssue(
          code: 'runtime_missing',
          message: 'Runtime not found',
        ),
      ],
    );

    final result = toInferenceReadinessResult(snapshot);
    expect(result.success, isFalse);
    expect(result.error?.code, 'runtime_missing');
  });
}
