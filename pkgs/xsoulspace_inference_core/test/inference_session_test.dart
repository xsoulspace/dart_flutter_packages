import 'dart:convert';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  test('composes declarations without prompt edits', () {
    final original = InferenceRequest(
      prompt: 'exact 😀\n',
      systemPrompt: 'stable',
    );
    final request = InferenceSessionSpec(
      id: 'actor-thread',
      affinityKey: 'shared-route',
      cache: InferenceCachePolicy(
        group: 'authorized-prefix',
        boundaries: ContextCacheIntent(writeAfterSegmentIds: ['context[0]']),
      ),
    ).attach(original, turn: InferenceTurnSpec(id: 'turn-1'));
    final restored = InferenceRequest.fromJson(
      jsonDecode(jsonEncode(request.value)) as Map<String, dynamic>,
    );
    final context = InferenceSessionContext.fromRequest(restored)!;
    expect(context.session.id, 'actor-thread');
    expect(context.session.effectiveAffinityKey, 'shared-route');
    expect(context.session.effectiveCacheGroup, 'authorized-prefix');
    expect(context.turn!.id, 'turn-1');
    expect(request.prompt, original.prompt);
    expect(request.systemPrompt, original.systemPrompt);
    expect(request.metadata[contextCacheIntentMetadataKey], {
      'writeAfterSegmentIds': ['context[0]'],
      'lookupAfterSegmentIds': [],
    });
    expect(original.metadata, isEmpty);
  });
  test('defaults are stable and declarations refuse invalid identities', () {
    final session = InferenceSessionSpec(id: 'thread-1');
    expect(session.effectiveAffinityKey, 'thread-1');
    expect(session.effectiveCacheGroup, 'thread-1');
    for (final id in ['', 'a\r\nb', 'x' * 257]) {
      expect(() => InferenceSessionSpec(id: id), throwsFormatException);
      expect(() => InferenceTurnSpec(id: id), throwsFormatException);
      expect(() => InferenceCachePolicy(group: id), throwsFormatException);
    }
    expect(
      InferenceSessionContext.fromRequest(InferenceRequest(prompt: 'x')),
      isNull,
    );
    expect(
      () => InferenceSessionContext.fromRequest(
        InferenceRequest(
          prompt: 'x',
          metadata: {inferenceSessionMetadataKey: {}},
        ),
      ),
      throwsFormatException,
    );
  });
  test('ambiguous boundary declarations refuse instead of overriding', () {
    expect(
      () =>
          InferenceSessionSpec(
            id: 'x',
            cache: InferenceCachePolicy(
              group: 'g',
              boundaries: ContextCacheIntent(),
            ),
          ).attach(
            InferenceRequest(
              prompt: 'x',
              metadata: {contextCacheIntentMetadataKey: {}},
            ),
          ),
      throwsFormatException,
    );
  });
  test(
    'transport diagnostics capture exact routing names without raw values',
    () {
      final value = captureContextTransportMetadata(
        endpoint: Uri.parse('https://example.com/v1'),
        method: 'POST',
        requestHeaders: {
          'Session-ID': 'private-session',
          'Thread-ID': 'private-thread',
          'X-Codex-Turn-State': 'private-token',
          'authorization': 'Bearer never',
        },
        requestBody: {'session_id': 'private-session'},
        clientCohort: 'test',
        followRedirects: false,
        responseHeaders: {'X-Codex-Turn-State': 'private-token'},
      );
      final controls = value['requestControls']! as Map;
      for (final name in [
        'header.session-id',
        'header.thread-id',
        'header.x-codex-turn-state',
        'body.session_id',
      ]) {
        expect((controls[name] as Map)['state'], 'present');
      }
      expect(
        ((value['responseHeaderFingerprints']! as Map)['x-codex-turn-state']
            as Map)['state'],
        'present',
      );
      expect(jsonEncode(value), isNot(contains('private-')));
      expect(jsonEncode(value), isNot(contains('Bearer never')));
    },
  );
}
