import 'dart:typed_data';

enum WhisperCppRawModelPreset { tinyEn }

final class WhisperCppRawModelConfig {
  const WhisperCppRawModelConfig({
    this.preset = WhisperCppRawModelPreset.tinyEn,
    required this.modelPath,
    this.providerExtras = const <String, dynamic>{},
  });

  final WhisperCppRawModelPreset preset;
  final String modelPath;
  final Map<String, dynamic> providerExtras;
}

final class WhisperCppRawRealtimeConfig {
  const WhisperCppRawRealtimeConfig({
    this.sampleRate = 16000,
    this.stepMs = 500,
    this.lengthMs = 5000,
    this.keepMs = 200,
    this.threads = 4,
    this.language = 'en',
    this.translate = false,
    this.providerExtras = const <String, dynamic>{},
  });

  final int sampleRate;
  final int stepMs;
  final int lengthMs;
  final int keepMs;
  final int threads;
  final String language;
  final bool translate;
  final Map<String, dynamic> providerExtras;
}

final class WhisperCppRawSegment {
  const WhisperCppRawSegment({
    required this.text,
    required this.startMs,
    required this.endMs,
  });

  final String text;
  final int startMs;
  final int endMs;
}

final class WhisperCppRawRecognitionResult {
  const WhisperCppRawRecognitionResult({
    required this.transcript,
    this.isFinal = false,
    this.segments = const <WhisperCppRawSegment>[],
  });

  final String transcript;
  final bool isFinal;
  final List<WhisperCppRawSegment> segments;
}

final class WhisperCppRawAudioInput {
  const WhisperCppRawAudioInput._({
    required this.bytes,
    required this.sampleRateHz,
    required this.isWavContainer,
  });

  const WhisperCppRawAudioInput.wav({
    required final Uint8List bytes,
    required final int sampleRateHz,
  }) : this._(bytes: bytes, sampleRateHz: sampleRateHz, isWavContainer: true);

  const WhisperCppRawAudioInput.pcm16le({
    required final Uint8List bytes,
    required final int sampleRateHz,
  }) : this._(bytes: bytes, sampleRateHz: sampleRateHz, isWavContainer: false);

  final Uint8List bytes;
  final int sampleRateHz;
  final bool isWavContainer;
}
