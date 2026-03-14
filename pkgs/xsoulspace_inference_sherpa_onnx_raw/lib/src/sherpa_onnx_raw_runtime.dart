import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'sherpa_onnx_raw_exception.dart';
import 'sherpa_onnx_raw_library_loader.dart';
import 'sherpa_onnx_raw_models.dart';

final class _Recognizer extends Opaque {}

final class _Stream extends Opaque {}

final class _OnlineTransducerConfig extends Struct {
  external Pointer<Utf8> encoder;
  external Pointer<Utf8> decoder;
  external Pointer<Utf8> joiner;
}

final class _OnlineParaformerConfig extends Struct {
  external Pointer<Utf8> encoder;
  external Pointer<Utf8> decoder;
}

final class _OnlineZipformerCtcConfig extends Struct {
  external Pointer<Utf8> model;
}

final class _OnlineNemoCtcConfig extends Struct {
  external Pointer<Utf8> model;
}

final class _OnlineToneCtcConfig extends Struct {
  external Pointer<Utf8> model;
}

final class _OnlineModelConfig extends Struct {
  external _OnlineTransducerConfig transducer;
  external _OnlineParaformerConfig paraformer;
  external _OnlineZipformerCtcConfig zipformer2_ctc;
  external Pointer<Utf8> tokens;

  @Int32()
  external int num_threads;

  external Pointer<Utf8> provider;

  @Int32()
  external int debug;

  external Pointer<Utf8> model_type;
  external Pointer<Utf8> modeling_unit;
  external Pointer<Utf8> bpe_vocab;
  external Pointer<Utf8> tokens_buf;

  @Int32()
  external int tokens_buf_size;

  external _OnlineNemoCtcConfig nemo_ctc;
  external _OnlineToneCtcConfig t_one_ctc;
}

final class _FeatureConfig extends Struct {
  @Int32()
  external int sample_rate;

  @Int32()
  external int feature_dim;
}

final class _OnlineCtcFstDecoderConfig extends Struct {
  external Pointer<Utf8> graph;

  @Int32()
  external int max_active;
}

final class _HomophoneReplacerConfig extends Struct {
  external Pointer<Utf8> dict_dir;
  external Pointer<Utf8> lexicon;
  external Pointer<Utf8> rule_fsts;
}

final class _OnlineRecognizerConfig extends Struct {
  external _FeatureConfig feat_config;
  external _OnlineModelConfig model_config;
  external Pointer<Utf8> decoding_method;

  @Int32()
  external int max_active_paths;

  @Int32()
  external int enable_endpoint;

  @Float()
  external double rule1_min_trailing_silence;

  @Float()
  external double rule2_min_trailing_silence;

  @Float()
  external double rule3_min_utterance_length;

  external Pointer<Utf8> hotwords_file;

  @Float()
  external double hotwords_score;

  external _OnlineCtcFstDecoderConfig ctc_fst_decoder_config;
  external Pointer<Utf8> rule_fsts;
  external Pointer<Utf8> rule_fars;

  @Float()
  external double blank_penalty;

  external Pointer<Utf8> hotwords_buf;

  @Int32()
  external int hotwords_buf_size;

  external _HomophoneReplacerConfig hr;
}

typedef _CreateRecognizerNative =
    Pointer<_Recognizer> Function(Pointer<_OnlineRecognizerConfig>);
typedef _CreateRecognizerDart =
    Pointer<_Recognizer> Function(Pointer<_OnlineRecognizerConfig>);
typedef _DestroyRecognizerNative = Void Function(Pointer<_Recognizer>);
typedef _DestroyRecognizerDart = void Function(Pointer<_Recognizer>);
typedef _CreateStreamNative = Pointer<_Stream> Function(Pointer<_Recognizer>);
typedef _CreateStreamDart = Pointer<_Stream> Function(Pointer<_Recognizer>);
typedef _DestroyStreamNative = Void Function(Pointer<_Stream>);
typedef _DestroyStreamDart = void Function(Pointer<_Stream>);
typedef _AcceptWaveformNative =
    Void Function(Pointer<_Stream>, Int32, Pointer<Float>, Int32);
typedef _AcceptWaveformDart =
    void Function(Pointer<_Stream>, int, Pointer<Float>, int);
typedef _IsReadyNative = Int32 Function(Pointer<_Recognizer>, Pointer<_Stream>);
typedef _IsReadyDart = int Function(Pointer<_Recognizer>, Pointer<_Stream>);
typedef _DecodeNative = Void Function(Pointer<_Recognizer>, Pointer<_Stream>);
typedef _DecodeDart = void Function(Pointer<_Recognizer>, Pointer<_Stream>);
typedef _GetResultJsonNative =
    Pointer<Utf8> Function(Pointer<_Recognizer>, Pointer<_Stream>);
typedef _GetResultJsonDart =
    Pointer<Utf8> Function(Pointer<_Recognizer>, Pointer<_Stream>);
typedef _DestroyResultJsonNative = Void Function(Pointer<Utf8>);
typedef _DestroyResultJsonDart = void Function(Pointer<Utf8>);
typedef _InputFinishedNative = Void Function(Pointer<_Stream>);
typedef _InputFinishedDart = void Function(Pointer<_Stream>);

final class SherpaOnnxRawBindings {
  SherpaOnnxRawBindings._(this.library)
    : createRecognizer = library
          .lookupFunction<_CreateRecognizerNative, _CreateRecognizerDart>(
            'SherpaOnnxCreateOnlineRecognizer',
          ),
      destroyRecognizer = library
          .lookupFunction<_DestroyRecognizerNative, _DestroyRecognizerDart>(
            'SherpaOnnxDestroyOnlineRecognizer',
          ),
      createStream = library
          .lookupFunction<_CreateStreamNative, _CreateStreamDart>(
            'SherpaOnnxCreateOnlineStream',
          ),
      destroyStream = library
          .lookupFunction<_DestroyStreamNative, _DestroyStreamDart>(
            'SherpaOnnxDestroyOnlineStream',
          ),
      acceptWaveform = library
          .lookupFunction<_AcceptWaveformNative, _AcceptWaveformDart>(
            'SherpaOnnxOnlineStreamAcceptWaveform',
          ),
      isReady = library.lookupFunction<_IsReadyNative, _IsReadyDart>(
        'SherpaOnnxIsOnlineStreamReady',
      ),
      decode = library.lookupFunction<_DecodeNative, _DecodeDart>(
        'SherpaOnnxDecodeOnlineStream',
      ),
      getResultJson = library
          .lookupFunction<_GetResultJsonNative, _GetResultJsonDart>(
            'SherpaOnnxGetOnlineStreamResultAsJson',
          ),
      destroyResultJson = library
          .lookupFunction<_DestroyResultJsonNative, _DestroyResultJsonDart>(
            'SherpaOnnxDestroyOnlineStreamResultJson',
          ),
      inputFinished = library
          .lookupFunction<_InputFinishedNative, _InputFinishedDart>(
            'SherpaOnnxOnlineStreamInputFinished',
          );

  final DynamicLibrary library;
  final _CreateRecognizerDart createRecognizer;
  final _DestroyRecognizerDart destroyRecognizer;
  final _CreateStreamDart createStream;
  final _DestroyStreamDart destroyStream;
  final _AcceptWaveformDart acceptWaveform;
  final _IsReadyDart isReady;
  final _DecodeDart decode;
  final _GetResultJsonDart getResultJson;
  final _DestroyResultJsonDart destroyResultJson;
  final _InputFinishedDart inputFinished;

  static SherpaOnnxRawBindings load(final SherpaOnnxRawRuntimeConfig config) =>
      SherpaOnnxRawBindings._(
        SherpaOnnxRawLibraryLoader(runtimeConfig: config).load(),
      );
}

String? resolveSherpaOnnxRawModelRoot({
  required final SherpaOnnxRawModelConfig modelConfig,
  required final SherpaOnnxRawRuntimeConfig runtimeConfig,
}) {
  final root = (runtimeConfig.modelsDirectory ?? '').trim();
  final requiredFiles = <String>[
    modelConfig.encoderPath,
    modelConfig.decoderPath,
    modelConfig.joinerPath,
    modelConfig.tokensPath,
  ];
  final checked = <String>[];
  for (final relative in requiredFiles) {
    final resolved = resolveSherpaOnnxRawPath(
      relative,
      runtimeConfig.modelsDirectory,
    );
    checked.add(resolved);
    if (!File(resolved).existsSync()) {
      return null;
    }
  }
  return root.isNotEmpty ? root : p.dirname(checked.first);
}

String resolveSherpaOnnxRawPath(final String value, final String? root) {
  if (File(value).existsSync()) {
    return value;
  }
  if ((root ?? '').trim().isNotEmpty) {
    final joined = p.join(root!, value);
    if (File(joined).existsSync()) {
      return joined;
    }
  }
  return value;
}

void validateSherpaOnnxRawModelConfig({
  required final SherpaOnnxRawModelConfig modelConfig,
  required final SherpaOnnxRawRuntimeConfig runtimeConfig,
}) {
  final failures = <String, String>{
    'encoder': resolveSherpaOnnxRawPath(
      modelConfig.encoderPath,
      runtimeConfig.modelsDirectory,
    ),
    'decoder': resolveSherpaOnnxRawPath(
      modelConfig.decoderPath,
      runtimeConfig.modelsDirectory,
    ),
    'joiner': resolveSherpaOnnxRawPath(
      modelConfig.joinerPath,
      runtimeConfig.modelsDirectory,
    ),
    'tokens': resolveSherpaOnnxRawPath(
      modelConfig.tokensPath,
      runtimeConfig.modelsDirectory,
    ),
  };
  final missing = failures.entries
      .where((final entry) => !File(entry.value).existsSync())
      .map((final entry) => MapEntry(entry.key, entry.value))
      .toList(growable: false);
  if (missing.isNotEmpty) {
    throw SherpaOnnxRawException(
      code: 'engine_unavailable',
      message: 'Sherpa-ONNX model files are missing',
      details: Map<String, String>.fromEntries(missing),
    );
  }
}

final class SherpaOnnxRawBatchRuntime {
  SherpaOnnxRawBatchRuntime({
    required this.runtimeConfig,
    required this.modelConfig,
  });

  final SherpaOnnxRawRuntimeConfig runtimeConfig;
  final SherpaOnnxRawModelConfig modelConfig;

  Future<SherpaOnnxRawRecognitionResult> transcribe(
    final SherpaOnnxRawAudioInput input,
  ) async {
    validateSherpaOnnxRawModelConfig(
      modelConfig: modelConfig,
      runtimeConfig: runtimeConfig,
    );
    final samples = input.isWavContainer
        ? extractSherpaOnnxRawFloatSamplesFromWav(input.bytes)
        : pcm16leToSherpaOnnxRawFloatSamples(input.bytes);
    final runtime = _SherpaRuntime(
      bindings: SherpaOnnxRawBindings.load(runtimeConfig),
      runtimeConfig: runtimeConfig,
      modelConfig: modelConfig,
    );
    try {
      runtime.start();
      runtime.acceptSamples(samples, input.sampleRateHz);
      runtime.finishInput();
      runtime.decodeUntilStable();
      return runtime.currentResult(isFinal: true);
    } finally {
      runtime.dispose();
    }
  }
}

final class SherpaOnnxRawRealtimeRuntime {
  SherpaOnnxRawRealtimeRuntime({
    required this.modelConfig,
    required this.runtimeConfig,
    required this.realtimeConfig,
  });

  final SherpaOnnxRawModelConfig modelConfig;
  final SherpaOnnxRawRuntimeConfig runtimeConfig;
  final SherpaOnnxRawRealtimeConfig realtimeConfig;

  _SherpaRuntime? _runtime;

  Future<void> start() async {
    validateSherpaOnnxRawModelConfig(
      modelConfig: modelConfig,
      runtimeConfig: runtimeConfig,
    );
    final runtime = _SherpaRuntime(
      bindings: SherpaOnnxRawBindings.load(runtimeConfig),
      runtimeConfig: runtimeConfig,
      modelConfig: modelConfig,
      realtimeConfig: realtimeConfig,
    );
    runtime.start();
    _runtime = runtime;
  }

  SherpaOnnxRawRecognitionResult? sendAudioChunk(final List<int> audioBytes) {
    if (audioBytes.isEmpty || audioBytes.length.isOdd) {
      throw const SherpaOnnxRawException(
        code: 'audio_input_invalid',
        message: 'Sherpa-ONNX expects non-empty PCM16LE audio chunks',
      );
    }
    final runtime = _requireRuntime();
    runtime.acceptSamples(
      pcm16leToSherpaOnnxRawFloatSamples(Uint8List.fromList(audioBytes)),
      realtimeConfig.sampleRate,
    );
    runtime.decodeUntilStable();
    final result = runtime.currentResult(isFinal: false);
    return result.transcript.isEmpty ? null : result;
  }

  SherpaOnnxRawRecognitionResult? commit() {
    final runtime = _requireRuntime();
    runtime.finishInput();
    runtime.decodeUntilStable();
    final result = runtime.currentResult(isFinal: true);
    return result.transcript.isEmpty ? null : result;
  }

  Future<void> stop() async {
    _runtime?.dispose();
    _runtime = null;
  }

  _SherpaRuntime _requireRuntime() {
    final runtime = _runtime;
    if (runtime == null) {
      throw const SherpaOnnxRawException(
        code: 'engine_unavailable',
        message: 'Sherpa-ONNX runtime is not initialized',
      );
    }
    return runtime;
  }
}

final class _SherpaRuntime {
  _SherpaRuntime({
    required this.bindings,
    required this.runtimeConfig,
    required this.modelConfig,
    this.realtimeConfig,
  });

  final SherpaOnnxRawBindings bindings;
  final SherpaOnnxRawRuntimeConfig runtimeConfig;
  final SherpaOnnxRawModelConfig modelConfig;
  final SherpaOnnxRawRealtimeConfig? realtimeConfig;

  Pointer<_Recognizer> recognizer = nullptr;
  Pointer<_Stream> stream = nullptr;
  final List<Pointer<Utf8>> _allocatedStrings = <Pointer<Utf8>>[];

  void start() {
    final config = calloc<_OnlineRecognizerConfig>();
    try {
      _fillConfig(config.ref);
      recognizer = bindings.createRecognizer(config);
    } finally {
      calloc.free(config);
    }
    if (recognizer == nullptr) {
      _freeStrings();
      throw const SherpaOnnxRawException(
        code: 'engine_unavailable',
        message: 'Failed to create Sherpa-ONNX recognizer',
      );
    }
    stream = bindings.createStream(recognizer);
    if (stream == nullptr) {
      dispose();
      throw const SherpaOnnxRawException(
        code: 'engine_unavailable',
        message: 'Failed to create Sherpa-ONNX stream',
      );
    }
  }

  void acceptSamples(final Float32List samples, final int sampleRate) {
    final ptr = calloc<Float>(samples.length);
    ptr.asTypedList(samples.length).setAll(0, samples);
    try {
      bindings.acceptWaveform(stream, sampleRate, ptr, samples.length);
    } finally {
      calloc.free(ptr);
    }
  }

  void decodeUntilStable() {
    while (bindings.isReady(recognizer, stream) != 0) {
      bindings.decode(recognizer, stream);
    }
  }

  void finishInput() {
    bindings.inputFinished(stream);
  }

  SherpaOnnxRawRecognitionResult currentResult({required final bool isFinal}) {
    final ptr = bindings.getResultJson(recognizer, stream);
    if (ptr == nullptr) {
      return SherpaOnnxRawRecognitionResult(transcript: '', isFinal: isFinal);
    }
    try {
      return parseSherpaOnnxRawRecognitionResult(
        ptr.toDartString(),
        isFinal: isFinal,
      );
    } finally {
      bindings.destroyResultJson(ptr);
    }
  }

  void dispose() {
    if (stream != nullptr) {
      bindings.destroyStream(stream);
      stream = nullptr;
    }
    if (recognizer != nullptr) {
      bindings.destroyRecognizer(recognizer);
      recognizer = nullptr;
    }
    _freeStrings();
  }

  void _fillConfig(final _OnlineRecognizerConfig config) {
    final extras = modelConfig.providerExtras;
    config.feat_config.sample_rate = realtimeConfig?.sampleRate ?? 16000;
    config.feat_config.feature_dim = _intExtra(extras, 'feature_dim', 80);
    config.model_config.transducer.encoder = _alloc(
      resolveSherpaOnnxRawPath(
        modelConfig.encoderPath,
        runtimeConfig.modelsDirectory,
      ),
    );
    config.model_config.transducer.decoder = _alloc(
      resolveSherpaOnnxRawPath(
        modelConfig.decoderPath,
        runtimeConfig.modelsDirectory,
      ),
    );
    config.model_config.transducer.joiner = _alloc(
      resolveSherpaOnnxRawPath(
        modelConfig.joinerPath,
        runtimeConfig.modelsDirectory,
      ),
    );
    config.model_config.paraformer.encoder = nullptr;
    config.model_config.paraformer.decoder = nullptr;
    config.model_config.zipformer2_ctc.model = nullptr;
    config.model_config.tokens = _alloc(
      resolveSherpaOnnxRawPath(
        modelConfig.tokensPath,
        runtimeConfig.modelsDirectory,
      ),
    );
    config.model_config.num_threads = _intExtra(extras, 'num_threads', 1);
    config.model_config.provider = _alloc(
      _stringExtra(extras, 'provider', 'cpu'),
    );
    config.model_config.debug = _boolExtra(extras, 'debug', false) ? 1 : 0;
    config.model_config.model_type = _alloc(
      _stringExtra(extras, 'model_type', 'zipformer'),
    );
    config.model_config.modeling_unit = _alloc(
      _stringExtra(extras, 'modeling_unit', 'bpe'),
    );
    config.model_config.bpe_vocab = _alloc(
      _stringExtra(extras, 'bpe_vocab', ''),
    );
    config.model_config.tokens_buf = nullptr;
    config.model_config.tokens_buf_size = 0;
    config.model_config.nemo_ctc.model = nullptr;
    config.model_config.t_one_ctc.model = nullptr;
    config.decoding_method = _alloc(
      _stringExtra(extras, 'decoding_method', 'greedy_search'),
    );
    config.max_active_paths = _intExtra(extras, 'max_active_paths', 4);
    config.enable_endpoint =
        realtimeConfig == null || realtimeConfig!.enableEndpointing ? 1 : 0;
    config.rule1_min_trailing_silence =
        (realtimeConfig?.minSilenceDurationMs ?? 500) / 1000.0;
    config.rule2_min_trailing_silence =
        (realtimeConfig?.minSilenceDurationMs ?? 500) / 1000.0;
    config.rule3_min_utterance_length =
        (realtimeConfig?.minSpeechDurationMs ?? 200) / 1000.0;
    config.hotwords_file = nullptr;
    config.hotwords_score = 1.5;
    config.ctc_fst_decoder_config.graph = nullptr;
    config.ctc_fst_decoder_config.max_active = 0;
    config.rule_fsts = nullptr;
    config.rule_fars = nullptr;
    config.blank_penalty = 0;
    config.hotwords_buf = nullptr;
    config.hotwords_buf_size = 0;
    config.hr.dict_dir = nullptr;
    config.hr.lexicon = nullptr;
    config.hr.rule_fsts = nullptr;
  }

  Pointer<Utf8> _alloc(final String value) {
    final ptr = value.toNativeUtf8();
    _allocatedStrings.add(ptr);
    return ptr;
  }

  void _freeStrings() {
    for (final value in _allocatedStrings) {
      calloc.free(value);
    }
    _allocatedStrings.clear();
  }
}

Float32List pcm16leToSherpaOnnxRawFloatSamples(final Uint8List pcmBytes) {
  final data = ByteData.sublistView(pcmBytes);
  final samples = Float32List(pcmBytes.length ~/ 2);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return samples;
}

Float32List extractSherpaOnnxRawFloatSamplesFromWav(final Uint8List wavBytes) {
  if (wavBytes.length < 44) {
    throw const SherpaOnnxRawException(
      code: 'audio_input_invalid',
      message: 'WAV payload is too small',
    );
  }
  final bytes = ByteData.sublistView(wavBytes);
  final riff = ascii.decode(wavBytes.sublist(0, 4), allowInvalid: true);
  final wave = ascii.decode(wavBytes.sublist(8, 12), allowInvalid: true);
  if (riff != 'RIFF' || wave != 'WAVE') {
    throw const SherpaOnnxRawException(
      code: 'audio_input_invalid',
      message: 'Only RIFF/WAVE PCM input is supported',
    );
  }
  var offset = 12;
  var audioFormat = 0;
  var bitsPerSample = 0;
  var dataOffset = -1;
  var dataLength = 0;
  while (offset + 8 <= wavBytes.length) {
    final chunkId = ascii.decode(
      wavBytes.sublist(offset, offset + 4),
      allowInvalid: true,
    );
    final chunkSize = bytes.getUint32(offset + 4, Endian.little);
    final chunkDataOffset = offset + 8;
    if (chunkId == 'fmt ' && chunkSize >= 16) {
      audioFormat = bytes.getUint16(chunkDataOffset, Endian.little);
      bitsPerSample = bytes.getUint16(chunkDataOffset + 14, Endian.little);
    } else if (chunkId == 'data') {
      dataOffset = chunkDataOffset;
      dataLength = chunkSize;
      break;
    }
    offset = chunkDataOffset + chunkSize + (chunkSize.isOdd ? 1 : 0);
  }
  if (audioFormat != 1 || bitsPerSample != 16 || dataOffset < 0) {
    throw const SherpaOnnxRawException(
      code: 'audio_input_invalid',
      message: 'Only PCM16 WAV input is supported',
    );
  }
  final end = dataOffset + dataLength;
  if (end > wavBytes.length) {
    throw const SherpaOnnxRawException(
      code: 'audio_input_invalid',
      message: 'WAV data chunk exceeds payload size',
    );
  }
  return pcm16leToSherpaOnnxRawFloatSamples(
    Uint8List.sublistView(wavBytes, dataOffset, end),
  );
}

SherpaOnnxRawRecognitionResult parseSherpaOnnxRawRecognitionResult(
  final String jsonPayload, {
  required final bool isFinal,
}) {
  if (jsonPayload.trim().isEmpty) {
    return SherpaOnnxRawRecognitionResult(transcript: '', isFinal: isFinal);
  }
  final decoded = jsonDecode(jsonPayload);
  if (decoded is! Map<String, dynamic>) {
    return SherpaOnnxRawRecognitionResult(
      transcript: '',
      isFinal: isFinal,
      rawJson: jsonPayload,
    );
  }
  final transcript = (decoded['text'] as String? ?? '').trim();
  final dynamicSegments = switch (decoded['segments'] ??
      decoded['timestamps'] ??
      decoded['tokens'] ??
      decoded['words']) {
    final List values => values.whereType<Map>(),
    _ => const <Map>[],
  };
  final segments = dynamicSegments
      .map((final value) {
        final text =
            ((value['text'] ??
                            value['token'] ??
                            value['word'] ??
                            value['piece'])
                        as String? ??
                    '')
                .trim();
        final startMs = _numToMs(
          value['start_ms'] ?? value['start'] ?? value['begin'],
        );
        final endMs = _numToMs(
          value['end_ms'] ?? value['end'] ?? value['stop'],
        );
        return SherpaOnnxRawSegment(
          text: text,
          startMs: startMs,
          endMs: endMs < startMs ? startMs : endMs,
        );
      })
      .where((final value) => value.text.isNotEmpty)
      .toList(growable: false);
  return SherpaOnnxRawRecognitionResult(
    transcript: transcript,
    isFinal: isFinal,
    segments: segments,
    rawJson: jsonPayload,
  );
}

int _numToMs(final Object? value) {
  if (value is int) {
    return value > 1000 ? value : value * 10;
  }
  if (value is double) {
    if (value > 1000) {
      return value.round();
    }
    if (value > 60) {
      return (value * 10).round();
    }
    return (value * 1000).round();
  }
  if (value is num) {
    return _numToMs(value.toDouble());
  }
  return 0;
}

String _stringExtra(
  final Map<String, dynamic> extras,
  final String key,
  final String fallback,
) {
  final value = extras[key];
  return value is String && value.trim().isNotEmpty ? value.trim() : fallback;
}

int _intExtra(
  final Map<String, dynamic> extras,
  final String key,
  final int fallback,
) {
  final value = extras[key];
  return value is num ? value.round() : fallback;
}

bool _boolExtra(
  final Map<String, dynamic> extras,
  final String key,
  final bool fallback,
) {
  final value = extras[key];
  return value is bool ? value : fallback;
}
