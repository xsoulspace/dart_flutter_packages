class VoskRuntimeConfig {
  const VoskRuntimeConfig({
    this.libraryPath,
    this.librarySearchPaths = const <String>[],
    this.modelDirectory,
    this.ownsRuntimeResolution = true,
  });

  final String? libraryPath;
  final List<String> librarySearchPaths;
  final String? modelDirectory;
  final bool ownsRuntimeResolution;
}

enum VoskModelPreset { smallEnUs015 }

class VoskModelConfig {
  const VoskModelConfig({
    this.preset = VoskModelPreset.smallEnUs015,
    this.modelPath = 'vosk-model-small-en-us-0.15',
    this.providerExtras = const <String, dynamic>{},
  });

  final VoskModelPreset preset;
  final String modelPath;
  final Map<String, dynamic> providerExtras;
}

class VoskRealtimeConfig {
  const VoskRealtimeConfig({
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
