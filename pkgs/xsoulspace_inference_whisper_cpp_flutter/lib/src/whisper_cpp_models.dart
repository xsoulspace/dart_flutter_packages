class WhisperCppRuntimeConfig {
  const WhisperCppRuntimeConfig({
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

enum WhisperCppModelPreset { tinyEn }

class WhisperCppModelConfig {
  const WhisperCppModelConfig({
    this.preset = WhisperCppModelPreset.tinyEn,
    this.modelPath = 'ggml-tiny.en.bin',
    this.providerExtras = const <String, dynamic>{},
  });

  final WhisperCppModelPreset preset;
  final String modelPath;
  final Map<String, dynamic> providerExtras;
}

class WhisperCppRealtimeConfig {
  const WhisperCppRealtimeConfig({
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
