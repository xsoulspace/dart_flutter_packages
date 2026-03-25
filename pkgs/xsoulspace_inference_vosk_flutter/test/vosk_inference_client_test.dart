import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_vosk_flutter/xsoulspace_inference_vosk_flutter.dart';

class _FakeVoskBackend implements VoskRealtimeBackend {
  late void Function(InferenceTranscriptEvent event) emit;
  bool committed = false;

  @override
  Future<void> start({
    required final VoskModelConfig modelConfig,
    required final VoskRuntimeConfig runtimeConfig,
    required final VoskRealtimeConfig realtimeConfig,
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
        transcript: 'tiny model',
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
        transcript: 'tiny model final',
        isFinal: true,
      ),
    );
  }

  @override
  Future<void> stop() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('VoskInferenceClient delegates batch transcription', () async {
    final client = VoskInferenceClient(
      transcribe:
          ({
            required final request,
            required final modelConfig,
            required final runtimeConfig,
          }) async {
            expect(modelConfig.preset, VoskModelPreset.smallEnUs015);
            return InferenceResult<InferenceResponse>.ok(
              InferenceResponse(
                task: InferenceTask.speechToText,
                output: const <String, dynamic>{},
                transcript: 'small footprint',
                normalizedTranscript: 'small footprint',
              ),
            );
          },
    );

    final result = await client.infer(
      InferenceRequest.speechToText(
        audioInput: const InferenceAudioInput.bytes(
          bytes: <int>[1, 2, 3],
          mimeType: 'audio/wav',
        ),
      ),
    );

    expect(result.success, isTrue);
    expect(result.data?.transcript, 'small footprint');
  });

  test(
    'VoskRealtimeSttSession emits partial and final transcript events',
    () async {
      final backend = _FakeVoskBackend();
      final session = VoskRealtimeSttSession(backend: backend);
      final events = <InferenceTranscriptEvent>[];
      final sub = session.events.listen(events.add);
      addTearDown(sub.cancel);
      addTearDown(session.dispose);

      expect((await session.connect()).success, isTrue);
      expect((await session.sendAudioChunk(<int>[9, 8, 7])).success, isTrue);
      expect((await session.commit()).success, isTrue);
      await Future<void>.delayed(Duration.zero);

      expect(
        events.any(
          (final event) =>
              event.type == InferenceTranscriptEventType.partialTranscript &&
              event.transcript == 'tiny model',
        ),
        isTrue,
      );
      expect(
        events.any(
          (final event) =>
              event.type == InferenceTranscriptEventType.finalTranscript &&
              event.transcript == 'tiny model final',
        ),
        isTrue,
      );
    },
  );

  test('VoskAvailabilityProbe returns readiness snapshot', () async {
    final probe = VoskAvailabilityProbe(
      runtimeConfig: const VoskRuntimeConfig(),
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
