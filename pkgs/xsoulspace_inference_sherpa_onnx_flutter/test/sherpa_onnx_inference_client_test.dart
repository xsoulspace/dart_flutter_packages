import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_sherpa_onnx_flutter/xsoulspace_inference_sherpa_onnx_flutter.dart';

class _FakeSherpaBackend implements SherpaOnnxRealtimeBackend {
  late void Function(InferenceTranscriptEvent event) emit;
  final List<List<int>> chunks = <List<int>>[];
  bool committed = false;
  bool stopped = false;

  @override
  Future<void> start({
    required final SherpaOnnxModelConfig modelConfig,
    required final SherpaOnnxRuntimeConfig runtimeConfig,
    required final SherpaOnnxRealtimeConfig realtimeConfig,
    required final void Function(InferenceTranscriptEvent event) emit,
  }) async {
    this.emit = emit;
  }

  @override
  Future<void> sendAudioChunk(final List<int> audioBytes) async {
    chunks.add(audioBytes);
    emit(
      InferenceTranscriptEvent(
        type: InferenceTranscriptEventType.partialTranscript,
        timestamp: DateTime.now().toUtc(),
        transcript: 'hello',
        sessionState: InferenceRealtimeSessionState.streaming,
      ),
    );
  }

  @override
  Future<void> commit() async {
    committed = true;
    emit(
      InferenceTranscriptEvent(
        type: InferenceTranscriptEventType.finalTranscript,
        timestamp: DateTime.now().toUtc(),
        transcript: 'hello world',
        isFinal: true,
        sessionState: InferenceRealtimeSessionState.finalizing,
      ),
    );
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SherpaOnnxInferenceClient delegates batch transcription', () async {
    final client = SherpaOnnxInferenceClient(
      transcribe:
          ({
            required final request,
            required final modelConfig,
            required final runtimeConfig,
          }) async {
            expect(
              modelConfig.preset,
              SherpaOnnxStreamingModelPreset.streamingZipformerEn20230626,
            );
            return InferenceResult<InferenceResponse>.ok(
              InferenceResponse(
                task: InferenceTask.speechToText,
                output: const <String, dynamic>{},
                transcript: 'arena voice',
                normalizedTranscript: 'arena voice',
                meta: const <String, dynamic>{'provider': 'sherpa_onnx'},
              ),
            );
          },
    );

    final result = await client.infer(
      InferenceRequest.speechToText(
        audioInput: const InferenceAudioInput.filePath(
          filePath: '/tmp/input.wav',
          mimeType: 'audio/wav',
        ),
      ),
    );

    expect(result.success, isTrue);
    expect(result.data?.transcript, 'arena voice');
  });

  test('SherpaOnnxInferenceClient rejects microphone batch requests', () async {
    final client = SherpaOnnxInferenceClient();

    final result = await client.infer(
      InferenceRequest.speechToText(
        audioInput: const InferenceAudioInput.microphone(mimeType: 'audio/pcm'),
      ),
    );

    expect(result.success, isFalse);
    expect(result.error?.code, errorCodeTaskUnsupported);
  });

  test(
    'SherpaOnnxRealtimeSttSession streams partial and final events',
    () async {
      final backend = _FakeSherpaBackend();
      final session = SherpaOnnxRealtimeSttSession(backend: backend);
      final seen = <InferenceTranscriptEvent>[];
      final sub = session.events.listen(seen.add);
      addTearDown(sub.cancel);
      addTearDown(session.dispose);

      final connectResult = await session.connect();
      expect(connectResult.success, isTrue);

      final sendResult = await session.sendAudioChunk(<int>[1, 2, 3]);
      expect(sendResult.success, isTrue);

      final commitResult = await session.commit();
      expect(commitResult.success, isTrue);

      await session.close();
      await Future<void>.delayed(Duration.zero);

      expect(backend.chunks, hasLength(1));
      expect(backend.committed, isTrue);
      expect(
        seen.any(
          (final event) =>
              event.type == InferenceTranscriptEventType.partialTranscript &&
              event.transcript == 'hello',
        ),
        isTrue,
      );
      expect(
        seen.any(
          (final event) =>
              event.type == InferenceTranscriptEventType.finalTranscript &&
              event.transcript == 'hello world',
        ),
        isTrue,
      );
    },
  );

  test('SherpaOnnxAvailabilityProbe returns readiness snapshot', () async {
    final probe = SherpaOnnxAvailabilityProbe(
      runtimeConfig: const SherpaOnnxRuntimeConfig(),
      modelPathResolver: () => null,
      platformProbe: () => true,
      loadProbe: (final _) => false,
    );

    final snapshot = await probe.probe();
    expect(snapshot.isReady, isFalse);
    expect(
      snapshot.issues.any((final issue) => issue.code == 'runtime_missing'),
      isTrue,
    );
    expect(
      snapshot.issues.any((final issue) => issue.code == 'model_missing'),
      isTrue,
    );
  });
}
