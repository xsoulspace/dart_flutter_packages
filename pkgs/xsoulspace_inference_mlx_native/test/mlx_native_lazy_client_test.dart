import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

/// ADR 0059 — the lazy native client: the weight load rides the
/// readiness contract (`load()`), unavailability is a typed retryable
/// failure (never a crash or a hang), `messages` render as a real
/// conversation, and a request-level `thinking` overrides the cast
/// default (or warns where the cast has no switch).
void main() {
  test('lazy lfm2: unavailable before load; missing snapshot fails typed',
      () async {
    final client = MlxNativeTextClient.lazyLfm2(
      snapshotDir: '/nonexistent/lfm2/snapshot',
    );
    expect(client.isAvailable, isFalse, reason: 'lazy = not loaded yet');
    expect(client.refreshAvailability(), completion(isFalse));

    final beforeLoad = await client.infer(
      InferenceRequest(prompt: 'x', maxTokens: 2),
    );
    expect(beforeLoad.success, isFalse);
    expect(beforeLoad.error!.code, 'unavailable');
    expect(
      (beforeLoad.error!.toJson()['details'] as Map)['retryable'],
      isTrue,
      reason: 'weights may still arrive; the refusal stays retryable',
    );

    await client.load();
    expect(client.isAvailable, isFalse);
    expect(client.loadError, isNotNull, reason: 'the failure is recorded');

    final afterFailedLoad = await client.infer(
      InferenceRequest(prompt: 'x', maxTokens: 2),
    );
    expect(afterFailedLoad.success, isFalse);
    expect(afterFailedLoad.error!.code, 'unavailable');
    expect(
      '${afterFailedLoad.error!.toJson()}',
      contains('nonexistent'),
      reason: 'the refusal names the recorded load failure',
    );
    expect(
      (afterFailedLoad.error!.toJson()['details'] as Map)['retryable'],
      isTrue,
    );
  });

  test('lazy lfm2: load once, then the full infer path', () async {
    final client = MlxNativeTextClient.lazyLfm2();
    try {
      await client.load();
      // On a machine without the cached snapshot this lane is honestly
      // absent — record and skip the live half.
      if (!client.isAvailable) {
        return markTestSkipped('lfm2 snapshot not cached: $client.loadError');
      }
      expect(client.loadError, isNull);
      await client.load();
      expect(client.isAvailable, isTrue, reason: 'load is memoized');

      final result = await client.infer(
        InferenceRequest(
          prompt: 'Reply with exactly one word: the sky color by day?',
          maxTokens: 24,
        ),
      );
      expect(result.success, isTrue, reason: '${result.error?.toJson()}');
      expect(result.data!.rawOutput, isNotEmpty);
    } finally {
      client.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('messages render as a real conversation (qwen lazy)', () async {
    final client = MlxNativeTextClient.lazyQwen();
    try {
      await client.load();
      if (!client.isAvailable) {
        return markTestSkipped('qwen snapshot not cached: $client.loadError');
      }
      final result = await client.infer(
        InferenceRequest(
          prompt: '',
          messages: [
            const ChatMessage.system('Answer in exactly one word.'),
            const ChatMessage.user('Say the word "blue".'),
            const ChatMessage.assistant('blue'),
            const ChatMessage.user('Repeat your previous word exactly.'),
          ],
          maxTokens: 24,
        ),
      );
      expect(result.success, isTrue, reason: '${result.error?.toJson()}');
      expect(
        (result.data!.rawOutput ?? '').toLowerCase(),
        contains('blue'),
        reason: 'multi-turn context must reach the render',
      );
    } finally {
      client.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('request-level thinking: qwen honors, lfm2 warns', () async {
    final qwen = MlxNativeTextClient.lazyQwen();
    try {
      await qwen.load();
      if (qwen.isAvailable) {
        final thinking = await qwen.infer(
          InferenceRequest(prompt: 'What is 2+2?', maxTokens: 128, thinking: true),
        );
        expect(thinking.success, isTrue, reason: '${thinking.error?.toJson()}');
        expect(
          thinking.warnings,
          isEmpty,
          reason: 'the qwen cast HAS a thinking switch — nothing to warn',
        );
      }
    } finally {
      qwen.dispose();
    }

    final engine = MlxNativeTextClient.lazyLfm2();
    try {
      await engine.load();
      if (!engine.isAvailable) {
        return markTestSkipped('lfm2 snapshot not cached');
      }
      final thinking = await engine.infer(
        InferenceRequest(prompt: 'What is 2+2?', maxTokens: 24, thinking: true),
      );
      expect(thinking.success, isTrue);
      expect(
        thinking.warnings.join(' '),
        contains('no thinking switch'),
        reason: 'the lfm2 cast must warn, never silently pretend',
      );
    } finally {
      engine.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
