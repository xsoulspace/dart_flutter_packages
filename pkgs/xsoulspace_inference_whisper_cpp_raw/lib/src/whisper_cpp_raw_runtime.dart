import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'whisper_cpp_raw_exception.dart';
import 'whisper_cpp_raw_library_loader.dart';
import 'whisper_cpp_raw_models.dart';

final class _WhisperContext extends Opaque {}

final class _WhisperGrammarElement extends Struct {
  @Int32()
  external int type;

  @Uint32()
  external int value;
}

final class _WhisperVadParams extends Struct {
  @Float()
  external double threshold;

  @Int32()
  external int min_speech_duration_ms;

  @Int32()
  external int min_silence_duration_ms;

  @Float()
  external double max_speech_duration_s;

  @Int32()
  external int speech_pad_ms;

  @Float()
  external double samples_overlap;
}

final class _WhisperContextParams extends Struct {
  @Bool()
  external bool use_gpu;

  @Bool()
  external bool flash_attn;

  @Int32()
  external int gpu_device;

  @Bool()
  external bool dtw_token_timestamps;

  @Int32()
  external int dtw_aheads_preset;

  @Int32()
  external int dtw_n_top;

  external Pointer<Void> dtw_aheads;

  @IntPtr()
  external int dtw_mem_size;
}

final class _WhisperGreedy extends Struct {
  @Int32()
  external int best_of;
}

final class _WhisperBeamSearch extends Struct {
  @Int32()
  external int beam_size;

  @Float()
  external double patience;
}

final class _WhisperFullParams extends Struct {
  @Int32()
  external int strategy;

  @Int32()
  external int n_threads;

  @Int32()
  external int n_max_text_ctx;

  @Int32()
  external int offset_ms;

  @Int32()
  external int duration_ms;

  @Bool()
  external bool translate;

  @Bool()
  external bool no_context;

  @Bool()
  external bool no_timestamps;

  @Bool()
  external bool single_segment;

  @Bool()
  external bool print_special;

  @Bool()
  external bool print_progress;

  @Bool()
  external bool print_realtime;

  @Bool()
  external bool print_timestamps;

  @Bool()
  external bool token_timestamps;

  @Float()
  external double thold_pt;

  @Float()
  external double thold_ptsum;

  @Int32()
  external int max_len;

  @Bool()
  external bool split_on_word;

  @Int32()
  external int max_tokens;

  @Bool()
  external bool debug_mode;

  @Int32()
  external int audio_ctx;

  @Bool()
  external bool tdrz_enable;

  external Pointer<Utf8> suppress_regex;
  external Pointer<Utf8> initial_prompt;

  @Bool()
  external bool carry_initial_prompt;

  external Pointer<Int32> prompt_tokens;

  @Int32()
  external int prompt_n_tokens;

  external Pointer<Utf8> language;

  @Bool()
  external bool detect_language;

  @Bool()
  external bool suppress_blank;

  @Bool()
  external bool suppress_nst;

  @Float()
  external double temperature;

  @Float()
  external double max_initial_ts;

  @Float()
  external double length_penalty;

  @Float()
  external double temperature_inc;

  @Float()
  external double entropy_thold;

  @Float()
  external double logprob_thold;

  @Float()
  external double no_speech_thold;

  external _WhisperGreedy greedy;
  external _WhisperBeamSearch beam_search;

  external Pointer<NativeFunction<Void Function()>> new_segment_callback;
  external Pointer<Void> new_segment_callback_user_data;
  external Pointer<NativeFunction<Void Function()>> progress_callback;
  external Pointer<Void> progress_callback_user_data;
  external Pointer<NativeFunction<Void Function()>> encoder_begin_callback;
  external Pointer<Void> encoder_begin_callback_user_data;
  external Pointer<NativeFunction<Void Function()>> abort_callback;
  external Pointer<Void> abort_callback_user_data;
  external Pointer<NativeFunction<Void Function()>> logits_filter_callback;
  external Pointer<Void> logits_filter_callback_user_data;
  external Pointer<Pointer<_WhisperGrammarElement>> grammar_rules;

  @IntPtr()
  external int n_grammar_rules;

  @IntPtr()
  external int i_start_rule;

  @Float()
  external double grammar_penalty;

  @Bool()
  external bool vad;

  external Pointer<Utf8> vad_model_path;
  external _WhisperVadParams vad_params;
}

typedef _WhisperVersionNative = Pointer<Utf8> Function();
typedef _WhisperVersionDart = Pointer<Utf8> Function();
typedef _WhisperContextDefaultParamsByRefNative =
    Pointer<_WhisperContextParams> Function();
typedef _WhisperContextDefaultParamsByRefDart =
    Pointer<_WhisperContextParams> Function();
typedef _WhisperFullDefaultParamsByRefNative =
    Pointer<_WhisperFullParams> Function(Int32);
typedef _WhisperFullDefaultParamsByRefDart =
    Pointer<_WhisperFullParams> Function(int);
typedef _WhisperInitFromFileWithParamsNative =
    Pointer<_WhisperContext> Function(Pointer<Utf8>, _WhisperContextParams);
typedef _WhisperInitFromFileWithParamsDart =
    Pointer<_WhisperContext> Function(Pointer<Utf8>, _WhisperContextParams);
typedef _WhisperFreeNative = Void Function(Pointer<_WhisperContext>);
typedef _WhisperFreeDart = void Function(Pointer<_WhisperContext>);
typedef _WhisperFreeParamsNative = Void Function(Pointer<_WhisperFullParams>);
typedef _WhisperFreeParamsDart = void Function(Pointer<_WhisperFullParams>);
typedef _WhisperFreeContextParamsNative =
    Void Function(Pointer<_WhisperContextParams>);
typedef _WhisperFreeContextParamsDart =
    void Function(Pointer<_WhisperContextParams>);
typedef _WhisperFullNative =
    Int32 Function(
      Pointer<_WhisperContext>,
      _WhisperFullParams,
      Pointer<Float>,
      Int32,
    );
typedef _WhisperFullDart =
    int Function(
      Pointer<_WhisperContext>,
      _WhisperFullParams,
      Pointer<Float>,
      int,
    );
typedef _WhisperFullNSegmentsNative = Int32 Function(Pointer<_WhisperContext>);
typedef _WhisperFullNSegmentsDart = int Function(Pointer<_WhisperContext>);
typedef _WhisperGetSegmentTextNative =
    Pointer<Utf8> Function(Pointer<_WhisperContext>, Int32);
typedef _WhisperGetSegmentTextDart =
    Pointer<Utf8> Function(Pointer<_WhisperContext>, int);
typedef _WhisperGetSegmentTimeNative =
    Int64 Function(Pointer<_WhisperContext>, Int32);
typedef _WhisperGetSegmentTimeDart =
    int Function(Pointer<_WhisperContext>, int);

final class WhisperCppRawBindings {
  WhisperCppRawBindings._(this.library)
    : version = library
          .lookupFunction<_WhisperVersionNative, _WhisperVersionDart>(
            'whisper_version',
          ),
      contextDefaultParamsByRef = library
          .lookupFunction<
            _WhisperContextDefaultParamsByRefNative,
            _WhisperContextDefaultParamsByRefDart
          >('whisper_context_default_params_by_ref'),
      fullDefaultParamsByRef = library
          .lookupFunction<
            _WhisperFullDefaultParamsByRefNative,
            _WhisperFullDefaultParamsByRefDart
          >('whisper_full_default_params_by_ref'),
      initFromFileWithParams = library
          .lookupFunction<
            _WhisperInitFromFileWithParamsNative,
            _WhisperInitFromFileWithParamsDart
          >('whisper_init_from_file_with_params'),
      free = library.lookupFunction<_WhisperFreeNative, _WhisperFreeDart>(
        'whisper_free',
      ),
      freeParams = library
          .lookupFunction<_WhisperFreeParamsNative, _WhisperFreeParamsDart>(
            'whisper_free_params',
          ),
      freeContextParams = library
          .lookupFunction<
            _WhisperFreeContextParamsNative,
            _WhisperFreeContextParamsDart
          >('whisper_free_context_params'),
      full = library.lookupFunction<_WhisperFullNative, _WhisperFullDart>(
        'whisper_full',
      ),
      fullNSegments = library
          .lookupFunction<
            _WhisperFullNSegmentsNative,
            _WhisperFullNSegmentsDart
          >('whisper_full_n_segments'),
      getSegmentText = library
          .lookupFunction<
            _WhisperGetSegmentTextNative,
            _WhisperGetSegmentTextDart
          >('whisper_full_get_segment_text'),
      getSegmentT0 = library
          .lookupFunction<
            _WhisperGetSegmentTimeNative,
            _WhisperGetSegmentTimeDart
          >('whisper_full_get_segment_t0'),
      getSegmentT1 = library
          .lookupFunction<
            _WhisperGetSegmentTimeNative,
            _WhisperGetSegmentTimeDart
          >('whisper_full_get_segment_t1');

  final DynamicLibrary library;
  final _WhisperVersionDart version;
  final _WhisperContextDefaultParamsByRefDart contextDefaultParamsByRef;
  final _WhisperFullDefaultParamsByRefDart fullDefaultParamsByRef;
  final _WhisperInitFromFileWithParamsDart initFromFileWithParams;
  final _WhisperFreeDart free;
  final _WhisperFreeParamsDart freeParams;
  final _WhisperFreeContextParamsDart freeContextParams;
  final _WhisperFullDart full;
  final _WhisperFullNSegmentsDart fullNSegments;
  final _WhisperGetSegmentTextDart getSegmentText;
  final _WhisperGetSegmentTimeDart getSegmentT0;
  final _WhisperGetSegmentTimeDart getSegmentT1;

  static WhisperCppRawBindings load(final WhisperCppRawRuntimeConfig config) =>
      WhisperCppRawBindings._(
        WhisperCppRawLibraryLoader(runtimeConfig: config).load(),
      );
}

String resolveWhisperCppRawModelPath({
  required final WhisperCppRawModelConfig modelConfig,
  required final WhisperCppRawRuntimeConfig runtimeConfig,
}) {
  final direct = modelConfig.modelPath.trim();
  if (File(direct).existsSync()) {
    return direct;
  }
  final root = (runtimeConfig.modelsDirectory ?? '').trim();
  if (root.isNotEmpty) {
    final joined = p.join(root, direct);
    if (File(joined).existsSync()) {
      return joined;
    }
  }
  throw WhisperCppRawException(
    code: 'engine_unavailable',
    message: 'whisper.cpp model file was not found',
    details: <String, dynamic>{
      'model_path': modelConfig.modelPath,
      if (root.isNotEmpty) 'models_directory': root,
    },
  );
}

final class WhisperCppRawBatchRuntime {
  WhisperCppRawBatchRuntime({
    required this.runtimeConfig,
    required this.modelConfig,
  });

  final WhisperCppRawRuntimeConfig runtimeConfig;
  final WhisperCppRawModelConfig modelConfig;
  late final WhisperCppRawBindings _bindings = WhisperCppRawBindings.load(
    runtimeConfig,
  );

  String version() => _bindings.version().toDartString();

  Future<WhisperCppRawRecognitionResult> transcribe(
    final WhisperCppRawAudioInput input,
  ) async {
    final samples = input.isWavContainer
        ? extractWhisperCppRawFloatSamplesFromWav(input.bytes)
        : pcm16leToWhisperCppRawFloatSamples(input.bytes);
    return _decodeSamples(
      samples: samples,
      sampleRateHz: input.sampleRateHz,
      config: const WhisperCppRawRealtimeConfig(),
      isFinal: true,
    );
  }

  WhisperCppRawRecognitionResult _decodeSamples({
    required final Float32List samples,
    required final int sampleRateHz,
    required final WhisperCppRawRealtimeConfig config,
    required final bool isFinal,
  }) {
    if (sampleRateHz != 16000) {
      throw WhisperCppRawException(
        code: 'audio_input_invalid',
        message: 'whisper.cpp wrapper currently expects 16000 Hz PCM',
        details: sampleRateHz,
      );
    }
    final modelPath = resolveWhisperCppRawModelPath(
      modelConfig: modelConfig,
      runtimeConfig: runtimeConfig,
    );
    final contextParamsPtr = _bindings.contextDefaultParamsByRef();
    final fullParamsPtr = _bindings.fullDefaultParamsByRef(0);
    final modelPathPtr = modelPath.toNativeUtf8();
    try {
      final contextParams = contextParamsPtr.ref;
      contextParams.use_gpu = _boolExtra(
        modelConfig.providerExtras,
        'use_gpu',
        false,
      );
      contextParams.flash_attn = _boolExtra(
        modelConfig.providerExtras,
        'flash_attn',
        false,
      );
      contextParams.gpu_device = _intExtra(
        modelConfig.providerExtras,
        'gpu_device',
        0,
      );

      final context = _bindings.initFromFileWithParams(
        modelPathPtr,
        contextParams,
      );
      if (context == nullptr) {
        throw WhisperCppRawException(
          code: 'engine_unavailable',
          message: 'Failed to initialize whisper.cpp context',
          details: modelPath,
        );
      }

      try {
        final fullParams = fullParamsPtr.ref;
        fullParams.n_threads = _intExtra(
          modelConfig.providerExtras,
          'threads',
          config.threads,
        );
        fullParams.translate = config.translate;
        fullParams.no_context = true;
        fullParams.no_timestamps = false;
        fullParams.single_segment = !isFinal;
        fullParams.print_special = false;
        fullParams.print_progress = false;
        fullParams.print_realtime = false;
        fullParams.print_timestamps = false;
        fullParams.token_timestamps = false;
        fullParams.language = _stringOrNull(config.language).toNativeUtf8();
        fullParams.detect_language =
            config.language.trim().isEmpty || config.language == 'auto';
        fullParams.suppress_blank = true;
        fullParams.suppress_nst = false;
        fullParams.temperature = 0;
        fullParams.max_initial_ts = 1.0;
        fullParams.length_penalty = -1;
        fullParams.temperature_inc = 0.2;
        fullParams.entropy_thold = 2.4;
        fullParams.logprob_thold = -1.0;
        fullParams.no_speech_thold = 0.6;

        final samplesPtr = calloc<Float>(samples.length);
        samplesPtr.asTypedList(samples.length).setAll(0, samples);
        try {
          final rc = _bindings.full(
            context,
            fullParams,
            samplesPtr,
            samples.length,
          );
          if (rc != 0) {
            throw WhisperCppRawException(
              code: 'engine_unavailable',
              message: 'whisper_full returned a non-zero status',
              details: rc,
            );
          }
        } finally {
          calloc.free(samplesPtr);
          calloc.free(fullParams.language);
        }

        final segmentCount = _bindings.fullNSegments(context);
        final segments = <WhisperCppRawSegment>[];
        final transcriptBuffer = StringBuffer();
        for (var i = 0; i < segmentCount; i++) {
          final text = _bindings
              .getSegmentText(context, i)
              .toDartString()
              .trim();
          if (text.isEmpty) {
            continue;
          }
          final startMs = _bindings.getSegmentT0(context, i) * 10;
          final endMs = _bindings.getSegmentT1(context, i) * 10;
          if (transcriptBuffer.isNotEmpty) {
            transcriptBuffer.write(' ');
          }
          transcriptBuffer.write(text);
          segments.add(
            WhisperCppRawSegment(text: text, startMs: startMs, endMs: endMs),
          );
        }
        return WhisperCppRawRecognitionResult(
          transcript: transcriptBuffer.toString().trim(),
          isFinal: isFinal,
          segments: segments,
        );
      } finally {
        _bindings.free(context);
      }
    } finally {
      calloc.free(modelPathPtr);
      _bindings.freeContextParams(contextParamsPtr);
      _bindings.freeParams(fullParamsPtr);
    }
  }
}

final class WhisperCppRawRealtimeRuntime {
  WhisperCppRawRealtimeRuntime({
    required this.modelConfig,
    required this.runtimeConfig,
    required this.realtimeConfig,
  }) : _batchRuntime = WhisperCppRawBatchRuntime(
         runtimeConfig: runtimeConfig,
         modelConfig: modelConfig,
       );

  final WhisperCppRawModelConfig modelConfig;
  final WhisperCppRawRuntimeConfig runtimeConfig;
  final WhisperCppRawRealtimeConfig realtimeConfig;
  final WhisperCppRawBatchRuntime _batchRuntime;
  final BytesBuilder _pcmBuffer = BytesBuilder(copy: false);

  int _sinceLastEmitBytes = 0;
  String _lastTranscript = '';

  Future<void> start() async {
    resolveWhisperCppRawModelPath(
      modelConfig: modelConfig,
      runtimeConfig: runtimeConfig,
    );
    _sinceLastEmitBytes = 0;
    _lastTranscript = '';
  }

  WhisperCppRawRecognitionResult? sendAudioChunk(final List<int> audioBytes) {
    if (audioBytes.isEmpty || audioBytes.length.isOdd) {
      throw const WhisperCppRawException(
        code: 'audio_input_invalid',
        message: 'whisper.cpp expects non-empty PCM16LE audio chunks',
      );
    }
    _pcmBuffer.add(audioBytes);
    _sinceLastEmitBytes += audioBytes.length;
    final bytesPerStep =
        (realtimeConfig.sampleRate * 2 * realtimeConfig.stepMs) ~/ 1000;
    if (_sinceLastEmitBytes < bytesPerStep) {
      return null;
    }
    _sinceLastEmitBytes = 0;
    final result = _decodeCurrentBuffer(isFinal: false);
    if (result.transcript.isEmpty || result.transcript == _lastTranscript) {
      return null;
    }
    _lastTranscript = result.transcript;
    return result;
  }

  WhisperCppRawRecognitionResult? commit() {
    final result = _decodeCurrentBuffer(isFinal: true);
    if (result.transcript.isEmpty) {
      return null;
    }
    _lastTranscript = result.transcript;
    return result;
  }

  Future<void> stop() async {
    _pcmBuffer.clear();
    _sinceLastEmitBytes = 0;
    _lastTranscript = '';
  }

  WhisperCppRawRecognitionResult _decodeCurrentBuffer({
    required final bool isFinal,
  }) {
    final allBytes = _pcmBuffer.takeBytes();
    final retained = _retainTail(allBytes);
    if (retained.isNotEmpty) {
      _pcmBuffer.add(retained);
    }
    final samples = pcm16leToWhisperCppRawFloatSamples(allBytes);
    return _batchRuntime._decodeSamples(
      samples: samples,
      sampleRateHz: realtimeConfig.sampleRate,
      config: realtimeConfig,
      isFinal: isFinal,
    );
  }

  Uint8List _retainTail(final Uint8List bytes) {
    final keepBytes =
        (realtimeConfig.sampleRate * 2 * realtimeConfig.keepMs) ~/ 1000;
    if (keepBytes <= 0 || bytes.length <= keepBytes) {
      return bytes;
    }
    return Uint8List.sublistView(bytes, bytes.length - keepBytes);
  }
}

Float32List pcm16leToWhisperCppRawFloatSamples(final Uint8List pcmBytes) {
  final data = ByteData.sublistView(pcmBytes);
  final samples = Float32List(pcmBytes.length ~/ 2);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return samples;
}

Float32List extractWhisperCppRawFloatSamplesFromWav(final Uint8List wavBytes) {
  if (wavBytes.length < 44) {
    throw const WhisperCppRawException(
      code: 'audio_input_invalid',
      message: 'WAV payload is too small',
    );
  }
  final bytes = ByteData.sublistView(wavBytes);
  final riff = String.fromCharCodes(wavBytes.sublist(0, 4));
  final wave = String.fromCharCodes(wavBytes.sublist(8, 12));
  if (riff != 'RIFF' || wave != 'WAVE') {
    throw const WhisperCppRawException(
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
    final chunkId = String.fromCharCodes(wavBytes.sublist(offset, offset + 4));
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
    throw const WhisperCppRawException(
      code: 'audio_input_invalid',
      message: 'Only PCM16 WAV input is supported',
    );
  }
  final end = dataOffset + dataLength;
  if (end > wavBytes.length) {
    throw const WhisperCppRawException(
      code: 'audio_input_invalid',
      message: 'WAV data chunk exceeds payload size',
    );
  }
  return pcm16leToWhisperCppRawFloatSamples(
    Uint8List.sublistView(wavBytes, dataOffset, end),
  );
}

String _stringOrNull(final String value) =>
    value.trim().isEmpty ? 'auto' : value;

bool _boolExtra(
  final Map<String, dynamic> extras,
  final String key,
  final bool fallback,
) {
  final value = extras[key];
  return value is bool ? value : fallback;
}

int _intExtra(
  final Map<String, dynamic> extras,
  final String key,
  final int fallback,
) {
  final value = extras[key];
  return value is num ? value.toInt() : fallback;
}
