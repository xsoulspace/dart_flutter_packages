import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_whisper_cpp_flutter/xsoulspace_inference_whisper_cpp_flutter.dart';

class _FakeWhisperCppBackend implements WhisperCppRealtimeBackend {
  late void Function(InferenceTranscriptEvent event) emit;

  @override
  Future<void> start({
    required final WhisperCppModelConfig modelConfig,
    required final WhisperCppRuntimeConfig runtimeConfig,
    required final WhisperCppRealtimeConfig realtimeConfig,
    required final void Function(InferenceTranscriptEvent event) emit,
  }) async {
    this.emit = emit;
  }

  @override
  Future<void> sendAudioChunk(final List<int> audioBytes) async {
    emit(
      InferenceTranscriptEvent(
        type: InferenceTranscriptEventType.partialTranscript,
        timestamp: DateTime.now().toUtc(),
        transcript: 'tiny whisper',
      ),
    );
  }

  @override
  Future<void> commit() async {
    emit(
      InferenceTranscriptEvent(
        type: InferenceTranscriptEventType.finalTranscript,
        timestamp: DateTime.now().toUtc(),
        transcript: 'tiny whisper final',
        isFinal: true,
      ),
    );
  }

  @override
  Future<void> stop() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('WhisperCppInferenceClient delegates batch transcription', () async {
    final client = WhisperCppInferenceClient(
      transcribe:
          ({
            required final request,
            required final modelConfig,
            required final runtimeConfig,
          }) async {
            expect(modelConfig.preset, WhisperCppModelPreset.tinyEn);
            return InferenceResult<InferenceResponse>.ok(
              InferenceResponse(
                task: InferenceTask.speechToText,
                output: const <String, dynamic>{},
                transcript: 'low latency incremental',
                normalizedTranscript: 'low latency incremental',
              ),
            );
          },
    );

    final result = await client.infer(
      InferenceRequest.speechToText(
        audioInput: const InferenceAudioInput.filePath(
          filePath: '/tmp/clip.wav',
          mimeType: 'audio/wav',
        ),
      ),
    );

    expect(result.success, isTrue);
    expect(result.data?.transcript, 'low latency incremental');
  });

  test('WhisperCppRealtimeSttSession emits incremental transcripts', () async {
    final backend = _FakeWhisperCppBackend();
    final session = WhisperCppRealtimeSttSession(backend: backend);
    final events = <InferenceTranscriptEvent>[];
    final sub = session.events.listen(events.add);
    addTearDown(sub.cancel);
    addTearDown(session.dispose);

    expect((await session.connect()).success, isTrue);
    expect((await session.sendAudioChunk(<int>[1, 2, 3, 4])).success, isTrue);
    expect((await session.commit()).success, isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(
      events.any(
        (final event) =>
            event.type == InferenceTranscriptEventType.partialTranscript &&
            event.transcript == 'tiny whisper',
      ),
      isTrue,
    );
    expect(
      events.any(
        (final event) =>
            event.type == InferenceTranscriptEventType.finalTranscript &&
            event.transcript == 'tiny whisper final',
      ),
      isTrue,
    );
  });

  test('WhisperCppAvailabilityProbe returns readiness snapshot', () async {
    final probe = WhisperCppAvailabilityProbe(
      runtimeConfig: const WhisperCppRuntimeConfig(),
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
