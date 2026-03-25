class SherpaOnnxRuntimeConfig {
  const SherpaOnnxRuntimeConfig({
    this.libraryPath,
    this.librarySearchPaths = const <String>[],
    this.modelsDirectory,
    this.ownsRuntimeResolution = true,
  });

  final String? libraryPath;
  final List<String> librarySearchPaths;
  final String? modelsDirectory;
  final bool ownsRuntimeResolution;
}

enum SherpaOnnxStreamingModelPreset { streamingZipformerEn20230626 }

class SherpaOnnxModelConfig {
  const SherpaOnnxModelConfig({
    required this.preset,
    required this.encoderPath,
    required this.decoderPath,
    required this.joinerPath,
    required this.tokensPath,
    this.providerExtras = const <String, dynamic>{},
  });

  const SherpaOnnxModelConfig.streamingZipformerEn20230626({
    this.encoderPath = 'encoder-epoch-99-avg-1.onnx',
    this.decoderPath = 'decoder-epoch-99-avg-1.onnx',
    this.joinerPath = 'joiner-epoch-99-avg-1.onnx',
    this.tokensPath = 'tokens.txt',
    this.providerExtras = const <String, dynamic>{},
  }) : preset = SherpaOnnxStreamingModelPreset.streamingZipformerEn20230626;

  final SherpaOnnxStreamingModelPreset preset;
  final String encoderPath;
  final String decoderPath;
  final String joinerPath;
  final String tokensPath;
  final Map<String, dynamic> providerExtras;
}

class SherpaOnnxRealtimeConfig {
  const SherpaOnnxRealtimeConfig({
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
