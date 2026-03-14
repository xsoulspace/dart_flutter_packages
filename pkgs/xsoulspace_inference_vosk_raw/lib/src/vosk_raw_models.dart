import 'dart:typed_data';

final class VoskRawModelConfig {
  const VoskRawModelConfig({
    required this.modelPath,
    this.providerExtras = const <String, dynamic>{},
  });

  final String modelPath;
  final Map<String, dynamic> providerExtras;
}

final class VoskRawRealtimeConfig {
  const VoskRawRealtimeConfig({
    this.sampleRate = 16000,
    this.emitPartialWords = true,
    this.minSilenceDurationMs = 500,
    this.providerExtras = const <String, dynamic>{},
  });

  final int sampleRate;
  final bool emitPartialWords;
  final int minSilenceDurationMs;
  final Map<String, dynamic> providerExtras;
}

final class VoskRawWordSegment {
  const VoskRawWordSegment({
    required this.text,
    required this.startMs,
    required this.endMs,
    this.confidence,
  });

  final String text;
  final int startMs;
  final int endMs;
  final double? confidence;
}

final class VoskRawRecognitionResult {
  const VoskRawRecognitionResult({
    required this.transcript,
    this.isFinal = false,
    this.segments = const <VoskRawWordSegment>[],
    this.alternatives = const <String>[],
    this.rawJson,
  });

  final String transcript;
  final bool isFinal;
  final List<VoskRawWordSegment> segments;
  final List<String> alternatives;
  final String? rawJson;
}

final class VoskRawAudioInput {
  const VoskRawAudioInput._({
    required this.bytes,
    required this.sampleRateHz,
    required this.isWavContainer,
  });

  const VoskRawAudioInput.wav({
    required final Uint8List bytes,
    required final int sampleRateHz,
  }) : this._(bytes: bytes, sampleRateHz: sampleRateHz, isWavContainer: true);

  const VoskRawAudioInput.pcm16le({
    required final Uint8List bytes,
    required final int sampleRateHz,
  }) : this._(bytes: bytes, sampleRateHz: sampleRateHz, isWavContainer: false);

  final Uint8List bytes;
  final int sampleRateHz;
  final bool isWavContainer;
}
