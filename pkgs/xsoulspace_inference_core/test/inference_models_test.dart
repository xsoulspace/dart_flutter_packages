import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  test('InferenceRequest STT serialization round-trips', () {
    final request = InferenceRequest.speechToText(
      audioInput: const InferenceAudioInput.bytes(
        bytes: <int>[1, 2, 3, 4],
        mimeType: 'audio/wav',
        sampleRateHz: 16000,
        channelCount: 1,
      ),
      workingDirectory: '/tmp',
      metadata: const <String, dynamic>{'source': 'unit_test'},
    );

    final decoded = InferenceRequest.fromJson(request.toJson());

    expect(decoded.task, InferenceTask.speechToText);
    expect(decoded.audioInput, isNotNull);
    expect(decoded.audioInput!.source, InferenceAudioSource.bytes);
    expect(decoded.audioInput!.bytes, <int>[1, 2, 3, 4]);
    expect(decoded.audioInput!.mimeType, 'audio/wav');
    expect(decoded.metadata['source'], 'unit_test');
  });

  test('InferenceAudioInput microphone serialization round-trips', () {
    const input = InferenceAudioInput.microphone(
      mimeType: 'audio/webm',
      sampleRateHz: 48000,
      channelCount: 1,
    );

    final decoded = InferenceAudioInput.fromJson(input.toJson());

    expect(decoded.source, InferenceAudioSource.microphone);
    expect(decoded.filePath, isNull);
    expect(decoded.bytes, isNull);
    expect(decoded.mimeType, 'audio/webm');
    expect(decoded.sampleRateHz, 48000);
    expect(decoded.channelCount, 1);
  });

  test(
    'InferenceAudioInput infers source when source discriminant is absent',
    () {
      final decoded = InferenceAudioInput.fromJson(const <String, dynamic>{
        'file_path': 'https://example.com/audio.wav',
        'mime_type': 'audio/wav',
      });

      expect(decoded.source, isNull);
      expect(decoded.resolvedSource, InferenceAudioSource.filePath);
      expect(decoded.filePath, 'https://example.com/audio.wav');
    },
  );

  test('InferenceRequest TTS serialization round-trips', () {
    final request = InferenceRequest.textToSpeech(
      text: 'Hello there',
      workingDirectory: '/tmp',
      voiceOptions: const InferenceVoiceOptions(
        voiceId: 'voice-a',
        locale: 'en-US',
        speechRate: 0.9,
        pitch: 1.1,
        providerExtras: <String, dynamic>{'engine': 'system'},
      ),
    );

    final decoded = InferenceRequest.fromJson(request.toJson());

    expect(decoded.task, InferenceTask.textToSpeech);
    expect(decoded.prompt, 'Hello there');
    expect(decoded.voiceOptions, isNotNull);
    expect(decoded.voiceOptions!.voiceId, 'voice-a');
    expect(decoded.voiceOptions!.providerExtras['engine'], 'system');
  });

  test('InferenceResponse speech payload serialization round-trips', () {
    final response = InferenceResponse(
      task: InferenceTask.speechToText,
      output: const <String, dynamic>{},
      transcript: 'Hello, world.',
      normalizedTranscript: 'Hello world',
      segments: const <InferenceSpeechSegment>[
        InferenceSpeechSegment(text: 'Hello', startMs: 0, endMs: 300),
        InferenceSpeechSegment(text: 'world', startMs: 300, endMs: 700),
      ],
      meta: const <String, dynamic>{'provider': 'whisper'},
    );

    final decoded = InferenceResponse.fromJson(response.toJson());

    expect(decoded.task, InferenceTask.speechToText);
    expect(decoded.transcript, 'Hello, world.');
    expect(decoded.normalizedTranscript, 'Hello world');
    expect(decoded.segments.length, 2);
    expect(decoded.segments.first.startMs, 0);
  });

  test('InferenceClient lifecycle methods are callable', () async {
    final client = _FakeInferenceClient();
    expect(client.isAvailable, isFalse);

    final refreshed = await client.refreshAvailability();
    expect(refreshed, isTrue);
    expect(client.isAvailable, isTrue);

    client.resetAvailabilityCache();
    expect(client.isAvailable, isFalse);
  });

  test('InferenceTranscriptEvent serialization round-trips', () {
    final event = InferenceTranscriptEvent(
      type: InferenceTranscriptEventType.partialTranscript,
      timestamp: DateTime.utc(2026, 3, 13, 12),
      transcript: 'hello wor',
      sessionState: InferenceRealtimeSessionState.streaming,
      metrics: const <String, num>{'latency_ms': 42},
      metadata: const <String, dynamic>{'provider': 'test'},
    );

    final decoded = InferenceTranscriptEvent.fromJson(event.toJson());

    expect(decoded.type, InferenceTranscriptEventType.partialTranscript);
    expect(decoded.transcript, 'hello wor');
    expect(decoded.sessionState, InferenceRealtimeSessionState.streaming);
    expect(decoded.metrics['latency_ms'], 42);
    expect(decoded.metadata['provider'], 'test');
  });

  test('InferenceRealtimeSession lifecycle methods are callable', () async {
    final session = _FakeRealtimeSession();
    expect(session.isConnected, isFalse);

    final result = await session.connect();
    expect(result.success, isTrue);
    expect(session.isConnected, isTrue);

    await session.close();
    expect(session.isConnected, isFalse);
    await session.dispose();
  });

  test('structured text stream event serialization round-trips', () {
    final event = InferenceStructuredTextStreamEvent(
      type: InferenceStructuredTextStreamEventType.completion,
      timestamp: DateTime.utc(2026, 3, 13, 15),
      lifecycleState: InferenceStructuredTextLifecycleState.completed,
      message: 'completed',
      rawChannel: InferenceStructuredTextRawChannel.stdout,
      rawText: '{"ok":true}',
      textDelta: '{"ok":true}',
      attempt: 2,
      completion: InferenceStructuredTextCompletion(
        result: InferenceResult<InferenceResponse>.ok(
          const InferenceResponse(
            output: <String, dynamic>{'ok': true},
            rawOutput: '{"ok":true}',
          ),
          meta: const <String, dynamic>{'attempt_count': 2},
        ),
        attemptCount: 2,
      ),
      metadata: const <String, dynamic>{'provider': 'codex_exec'},
    );

    final decoded = InferenceStructuredTextStreamEvent.fromJson(event.toJson());

    expect(decoded.type, InferenceStructuredTextStreamEventType.completion);
    expect(
      decoded.lifecycleState,
      InferenceStructuredTextLifecycleState.completed,
    );
    expect(decoded.rawChannel, InferenceStructuredTextRawChannel.stdout);
    expect(decoded.attempt, 2);
    expect(decoded.completion?.result.success, isTrue);
    expect(decoded.metadata['provider'], 'codex_exec');
  });

  test('streaming support is discoverable via client extension', () async {
    final client = _FakeStructuredTextStreamingClient();

    expect(client.supportsStructuredTextStreaming, isTrue);

    final session = await client.streamStructuredText(
      const InferenceRequest(
        prompt: 'return json',
        outputSchema: <String, dynamic>{'type': 'object'},
        workingDirectory: '/tmp',
      ),
    );

    final result = await session.result;
    expect(result.success, isTrue);
    await session.dispose();
  });
}

final class _FakeInferenceClient implements InferenceClient {
  bool _available = false;

  @override
  String get id => 'fake';

  @override
  bool get isAvailable => _available;

  @override
  Set<InferenceTask> get supportedTasks => const <InferenceTask>{
    InferenceTask.structuredText,
  };

  @override
  Future<bool> refreshAvailability() async {
    _available = true;
    return _available;
  }

  @override
  void resetAvailabilityCache() {
    _available = false;
  }

  @override
  Future<InferenceResult<InferenceResponse>> infer(
    final InferenceRequest request,
  ) async {
    return InferenceResult<InferenceResponse>.fail(
      code: 'unsupported',
      message: 'Not implemented in fake',
    );
  }
}

final class _FakeRealtimeSession
    implements InferenceRealtimeSession<InferenceTranscriptEvent> {
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Stream<InferenceTranscriptEvent> get events =>
      const Stream<InferenceTranscriptEvent>.empty();

  @override
  Future<InferenceResult<void>> connect() async {
    _connected = true;
    return InferenceResult<void>.ok(null);
  }

  @override
  Future<void> close() async {
    _connected = false;
  }

  @override
  Future<void> dispose() => close();
}

final class _FakeStructuredTextStreamingClient
    implements StructuredTextStreamingInferenceClient {
  @override
  String get id => 'fake_stream';

  @override
  bool get isAvailable => true;

  @override
  Set<InferenceTask> get supportedTasks => const <InferenceTask>{
    InferenceTask.structuredText,
  };

  @override
  Future<InferenceResult<InferenceResponse>> infer(
    final InferenceRequest request,
  ) async => InferenceResult<InferenceResponse>.ok(
    const InferenceResponse(output: <String, dynamic>{'ok': true}),
  );

  @override
  void resetAvailabilityCache() {}

  @override
  Future<bool> refreshAvailability() async => true;

  @override
  Future<InferenceStructuredTextStreamSession> streamStructuredText(
    final InferenceRequest request,
  ) async => _FakeStructuredTextStreamSession();
}

final class _FakeStructuredTextStreamSession
    implements InferenceStructuredTextStreamSession {
  @override
  Stream<InferenceStructuredTextStreamEvent> get events =>
      Stream<InferenceStructuredTextStreamEvent>.fromIterable(
        <InferenceStructuredTextStreamEvent>[
          InferenceStructuredTextStreamEvent(
            type: InferenceStructuredTextStreamEventType.lifecycle,
            timestamp: DateTime.utc(2026, 3, 13),
            lifecycleState: InferenceStructuredTextLifecycleState.started,
            message: 'started',
            attempt: 1,
          ),
        ],
      );

  @override
  Future<InferenceResult<InferenceResponse>> get result async =>
      InferenceResult<InferenceResponse>.ok(
        const InferenceResponse(output: <String, dynamic>{'ok': true}),
      );

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}
