import 'dart:typed_data';

enum SherpaOnnxRawPreset { streamingZipformerEn20230626 }

final class SherpaOnnxRawModelConfig {
  const SherpaOnnxRawModelConfig({
    required this.preset,
    required this.encoderPath,
    required this.decoderPath,
    required this.joinerPath,
    required this.tokensPath,
    this.providerExtras = const <String, dynamic>{},
  });

  final SherpaOnnxRawPreset preset;
  final String encoderPath;
  final String decoderPath;
  final String joinerPath;
  final String tokensPath;
  final Map<String, dynamic> providerExtras;
}

final class SherpaOnnxRawRealtimeConfig {
  const SherpaOnnxRawRealtimeConfig({
    this.sampleRate = 16000,
    this.featureChunkSize = 1600,
    this.enableEndpointing = true,
    this.minSilenceDurationMs = 500,
    this.minSpeechDurationMs = 200,
    this.providerExtras = const <String, dynamic>{},
  });

  final int sampleRate;
  final int featureChunkSize;
  final bool enableEndpointing;
  final int minSilenceDurationMs;
  final int minSpeechDurationMs;
  final Map<String, dynamic> providerExtras;
}

final class SherpaOnnxRawSegment {
  const SherpaOnnxRawSegment({
    required this.text,
    required this.startMs,
    required this.endMs,
  });

  final String text;
  final int startMs;
  final int endMs;
}

final class SherpaOnnxRawRecognitionResult {
  const SherpaOnnxRawRecognitionResult({
    required this.transcript,
    this.isFinal = false,
    this.segments = const <SherpaOnnxRawSegment>[],
    this.rawJson,
  });

  final String transcript;
  final bool isFinal;
  final List<SherpaOnnxRawSegment> segments;
  final String? rawJson;
}

final class SherpaOnnxRawAudioInput {
  const SherpaOnnxRawAudioInput._({
    required this.bytes,
    required this.sampleRateHz,
    required this.isWavContainer,
  });

  const SherpaOnnxRawAudioInput.wav({
    required final Uint8List bytes,
    required final int sampleRateHz,
  }) : this._(bytes: bytes, sampleRateHz: sampleRateHz, isWavContainer: true);

  const SherpaOnnxRawAudioInput.pcm16le({
    required final Uint8List bytes,
    required final int sampleRateHz,
  }) : this._(bytes: bytes, sampleRateHz: sampleRateHz, isWavContainer: false);

  final Uint8List bytes;
  final int sampleRateHz;
  final bool isWavContainer;
}
