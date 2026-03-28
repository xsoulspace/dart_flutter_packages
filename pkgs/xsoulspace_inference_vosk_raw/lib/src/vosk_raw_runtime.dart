import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'vosk_raw_exception.dart';
import 'vosk_raw_library_loader.dart';
import 'vosk_raw_models.dart';

final class _VoskModel extends Opaque {}

final class _VoskRecognizer extends Opaque {}

typedef _VoskModelNewNative = Pointer<_VoskModel> Function(Pointer<Utf8>);
typedef _VoskModelNewDart = Pointer<_VoskModel> Function(Pointer<Utf8>);
typedef _VoskModelFreeNative = Void Function(Pointer<_VoskModel>);
typedef _VoskModelFreeDart = void Function(Pointer<_VoskModel>);
typedef _VoskRecognizerNewNative =
    Pointer<_VoskRecognizer> Function(Pointer<_VoskModel>, Float);
typedef _VoskRecognizerNewDart =
    Pointer<_VoskRecognizer> Function(Pointer<_VoskModel>, double);
typedef _VoskRecognizerNewGrammarNative =
    Pointer<_VoskRecognizer> Function(
      Pointer<_VoskModel>,
      Float,
      Pointer<Utf8>,
    );
typedef _VoskRecognizerNewGrammarDart =
    Pointer<_VoskRecognizer> Function(
      Pointer<_VoskModel>,
      double,
      Pointer<Utf8>,
    );
typedef _VoskRecognizerFreeNative = Void Function(Pointer<_VoskRecognizer>);
typedef _VoskRecognizerFreeDart = void Function(Pointer<_VoskRecognizer>);
typedef _VoskRecognizerAcceptWaveformNative =
    Int32 Function(Pointer<_VoskRecognizer>, Pointer<Uint8>, Int32);
typedef _VoskRecognizerAcceptWaveformDart =
    int Function(Pointer<_VoskRecognizer>, Pointer<Uint8>, int);
typedef _VoskRecognizerResultNative =
    Pointer<Utf8> Function(Pointer<_VoskRecognizer>);
typedef _VoskRecognizerResultDart =
    Pointer<Utf8> Function(Pointer<_VoskRecognizer>);
typedef _VoskRecognizerResetNative = Void Function(Pointer<_VoskRecognizer>);
typedef _VoskRecognizerResetDart = void Function(Pointer<_VoskRecognizer>);
typedef _VoskSetPartialWordsNative =
    Void Function(Pointer<_VoskRecognizer>, Int32);
typedef _VoskSetPartialWordsDart = void Function(Pointer<_VoskRecognizer>, int);
typedef _VoskSetWordsNative = Void Function(Pointer<_VoskRecognizer>, Int32);
typedef _VoskSetWordsDart = void Function(Pointer<_VoskRecognizer>, int);
typedef _VoskSetMaxAlternativesNative =
    Void Function(Pointer<_VoskRecognizer>, Int32);
typedef _VoskSetMaxAlternativesDart =
    void Function(Pointer<_VoskRecognizer>, int);
typedef _VoskSetLogLevelNative = Void Function(Int32);
typedef _VoskSetLogLevelDart = void Function(int);

final class VoskRawBindings {
  VoskRawBindings._(this.library)
    : modelNew = library.lookupFunction<_VoskModelNewNative, _VoskModelNewDart>(
        'vosk_model_new',
      ),
      modelFree = library
          .lookupFunction<_VoskModelFreeNative, _VoskModelFreeDart>(
            'vosk_model_free',
          ),
      recognizerNew = library
          .lookupFunction<_VoskRecognizerNewNative, _VoskRecognizerNewDart>(
            'vosk_recognizer_new',
          ),
      recognizerNewGrammar = library
          .lookupFunction<
            _VoskRecognizerNewGrammarNative,
            _VoskRecognizerNewGrammarDart
          >('vosk_recognizer_new_grm'),
      recognizerFree = library
          .lookupFunction<_VoskRecognizerFreeNative, _VoskRecognizerFreeDart>(
            'vosk_recognizer_free',
          ),
      acceptWaveform = library
          .lookupFunction<
            _VoskRecognizerAcceptWaveformNative,
            _VoskRecognizerAcceptWaveformDart
          >('vosk_recognizer_accept_waveform'),
      result = library
          .lookupFunction<
            _VoskRecognizerResultNative,
            _VoskRecognizerResultDart
          >('vosk_recognizer_result'),
      partialResult = library
          .lookupFunction<
            _VoskRecognizerResultNative,
            _VoskRecognizerResultDart
          >('vosk_recognizer_partial_result'),
      finalResult = library
          .lookupFunction<
            _VoskRecognizerResultNative,
            _VoskRecognizerResultDart
          >('vosk_recognizer_final_result'),
      reset = library
          .lookupFunction<_VoskRecognizerResetNative, _VoskRecognizerResetDart>(
            'vosk_recognizer_reset',
          ),
      setPartialWords = library
          .lookupFunction<_VoskSetPartialWordsNative, _VoskSetPartialWordsDart>(
            'vosk_recognizer_set_partial_words',
          ),
      setWords = library.lookupFunction<_VoskSetWordsNative, _VoskSetWordsDart>(
        'vosk_recognizer_set_words',
      ),
      setMaxAlternatives = library
          .lookupFunction<
            _VoskSetMaxAlternativesNative,
            _VoskSetMaxAlternativesDart
          >('vosk_recognizer_set_max_alternatives'),
      setLogLevel = library
          .lookupFunction<_VoskSetLogLevelNative, _VoskSetLogLevelDart>(
            'vosk_set_log_level',
          );

  final DynamicLibrary library;
  final _VoskModelNewDart modelNew;
  final _VoskModelFreeDart modelFree;
  final _VoskRecognizerNewDart recognizerNew;
  final _VoskRecognizerNewGrammarDart recognizerNewGrammar;
  final _VoskRecognizerFreeDart recognizerFree;
  final _VoskRecognizerAcceptWaveformDart acceptWaveform;
  final _VoskRecognizerResultDart result;
  final _VoskRecognizerResultDart partialResult;
  final _VoskRecognizerResultDart finalResult;
  final _VoskRecognizerResetDart reset;
  final _VoskSetPartialWordsDart setPartialWords;
  final _VoskSetWordsDart setWords;
  final _VoskSetMaxAlternativesDart setMaxAlternatives;
  final _VoskSetLogLevelDart setLogLevel;

  static VoskRawBindings load(final VoskRawRuntimeConfig config) =>
      VoskRawBindings._(VoskRawLibraryLoader(runtimeConfig: config).load());
}

String resolveVoskRawModelPath({
  required final VoskRawModelConfig modelConfig,
  required final VoskRawRuntimeConfig runtimeConfig,
}) {
  final direct = modelConfig.modelPath.trim();
  if (direct.isNotEmpty && Directory(direct).existsSync()) {
    return direct;
  }
  final root = (runtimeConfig.modelDirectory ?? '').trim();
  if (root.isNotEmpty) {
    final joined = p.join(root, direct);
    if (Directory(joined).existsSync()) {
      return joined;
    }
  }
  throw VoskRawException(
    code: 'engine_unavailable',
    message: 'Vosk model path does not exist',
    details: <String, dynamic>{
      'model_path': modelConfig.modelPath,
      if (root.isNotEmpty) 'model_directory': root,
    },
  );
}

final class VoskRawBatchRuntime {
  VoskRawBatchRuntime({required this.runtimeConfig, required this.modelConfig});

  final VoskRawRuntimeConfig runtimeConfig;
  final VoskRawModelConfig modelConfig;

  Future<VoskRawRecognitionResult> transcribe(
    final VoskRawAudioInput input,
  ) async {
    final pcm = input.isWavContainer
        ? _extractWavPcm16Le(input.bytes)
        : input.bytes;
    return _runRecognition(
      pcmBytes: pcm,
      sampleRate: input.sampleRateHz,
      finalize: true,
    );
  }

  VoskRawRecognitionResult _runRecognition({
    required final Uint8List pcmBytes,
    required final int sampleRate,
    required final bool finalize,
  }) {
    if (sampleRate <= 0) {
      throw const VoskRawException(
        code: 'audio_input_invalid',
        message: 'Sample rate must be greater than zero',
      );
    }
    if (pcmBytes.isEmpty || pcmBytes.length.isOdd) {
      throw const VoskRawException(
        code: 'audio_input_invalid',
        message: 'Vosk expects non-empty PCM16LE byte input',
      );
    }

    final bindings = VoskRawBindings.load(runtimeConfig);
    bindings.setLogLevel(-1);
    final modelPath = resolveVoskRawModelPath(
      modelConfig: modelConfig,
      runtimeConfig: runtimeConfig,
    );
    final modelPathPtr = modelPath.toNativeUtf8();
    final model = bindings.modelNew(modelPathPtr);
    calloc.free(modelPathPtr);
    if (model == nullptr) {
      throw VoskRawException(
        code: 'engine_unavailable',
        message: 'Failed to initialize Vosk model',
        details: modelPath,
      );
    }

    try {
      final recognizer = _createRecognizer(
        bindings,
        model,
        sampleRate.toDouble(),
      );
      try {
        _configureRecognizer(bindings, recognizer, partialWords: true);
        final ptr = calloc<Uint8>(pcmBytes.length);
        ptr.asTypedList(pcmBytes.length).setAll(0, pcmBytes);
        try {
          bindings.acceptWaveform(recognizer, ptr, pcmBytes.length);
        } finally {
          calloc.free(ptr);
        }
        final payload = finalize
            ? bindings.finalResult(recognizer).toDartString()
            : bindings.result(recognizer).toDartString();
        return parseVoskRawRecognitionResult(payload, isFinal: finalize);
      } finally {
        bindings.recognizerFree(recognizer);
      }
    } finally {
      bindings.modelFree(model);
    }
  }

  Pointer<_VoskRecognizer> _createRecognizer(
    final VoskRawBindings bindings,
    final Pointer<_VoskModel> model,
    final double sampleRate,
  ) {
    final grammar = modelConfig.providerExtras['grammar'];
    if (grammar is String && grammar.trim().isNotEmpty) {
      final ptr = grammar.toNativeUtf8();
      try {
        final recognizer = bindings.recognizerNewGrammar(
          model,
          sampleRate,
          ptr,
        );
        if (recognizer != nullptr) {
          return recognizer;
        }
      } finally {
        calloc.free(ptr);
      }
    }
    if (grammar is List && grammar.isNotEmpty) {
      final normalized = jsonEncode(grammar.map((final e) => '$e').toList());
      final ptr = normalized.toNativeUtf8();
      try {
        final recognizer = bindings.recognizerNewGrammar(
          model,
          sampleRate,
          ptr,
        );
        if (recognizer != nullptr) {
          return recognizer;
        }
      } finally {
        calloc.free(ptr);
      }
    }
    final recognizer = bindings.recognizerNew(model, sampleRate);
    if (recognizer == nullptr) {
      throw const VoskRawException(
        code: 'engine_unavailable',
        message: 'Failed to create Vosk recognizer',
      );
    }
    return recognizer;
  }

  void _configureRecognizer(
    final VoskRawBindings bindings,
    final Pointer<_VoskRecognizer> recognizer, {
    required final bool partialWords,
  }) {
    bindings.setPartialWords(recognizer, partialWords ? 1 : 0);
    bindings.setWords(recognizer, 1);
    final maxAlternatives = _intExtra(
      modelConfig.providerExtras,
      'max_alternatives',
      0,
    );
    bindings.setMaxAlternatives(recognizer, maxAlternatives);
  }
}

final class VoskRawRealtimeRuntime {
  VoskRawRealtimeRuntime({
    required this.modelConfig,
    required this.runtimeConfig,
    required this.realtimeConfig,
  });

  final VoskRawModelConfig modelConfig;
  final VoskRawRuntimeConfig runtimeConfig;
  final VoskRawRealtimeConfig realtimeConfig;

  VoskRawBindings? _bindings;
  Pointer<_VoskModel> _model = nullptr;
  Pointer<_VoskRecognizer> _recognizer = nullptr;

  Future<void> start() async {
    final bindings = VoskRawBindings.load(runtimeConfig);
    bindings.setLogLevel(-1);
    final modelPath = resolveVoskRawModelPath(
      modelConfig: modelConfig,
      runtimeConfig: runtimeConfig,
    );
    final modelPathPtr = modelPath.toNativeUtf8();
    final model = bindings.modelNew(modelPathPtr);
    calloc.free(modelPathPtr);
    if (model == nullptr) {
      throw VoskRawException(
        code: 'engine_unavailable',
        message: 'Failed to initialize Vosk model',
        details: modelPath,
      );
    }

    final recognizer = VoskRawBatchRuntime(
      runtimeConfig: runtimeConfig,
      modelConfig: modelConfig,
    )._createRecognizer(bindings, model, realtimeConfig.sampleRate.toDouble());
    VoskRawBatchRuntime(
      runtimeConfig: runtimeConfig,
      modelConfig: modelConfig,
    )._configureRecognizer(
      bindings,
      recognizer,
      partialWords: realtimeConfig.emitPartialWords,
    );
    _bindings = bindings;
    _model = model;
    _recognizer = recognizer;
  }

  VoskRawRecognitionResult? sendAudioChunk(final List<int> audioBytes) {
    final bindings = _requireBindings();
    if (audioBytes.isEmpty || audioBytes.length.isOdd) {
      throw const VoskRawException(
        code: 'audio_input_invalid',
        message: 'Vosk expects non-empty PCM16LE audio chunks',
      );
    }
    final ptr = calloc<Uint8>(audioBytes.length);
    ptr.asTypedList(audioBytes.length).setAll(0, audioBytes);
    try {
      final accepted = bindings.acceptWaveform(
        _requireRecognizer(),
        ptr,
        audioBytes.length,
      );
      final json = accepted == 1
          ? bindings.result(_recognizer).toDartString()
          : bindings.partialResult(_recognizer).toDartString();
      final parsed = parseVoskRawRecognitionResult(
        json,
        isFinal: accepted == 1,
      );
      return parsed.transcript.isEmpty ? null : parsed;
    } finally {
      calloc.free(ptr);
    }
  }

  VoskRawRecognitionResult? commit() {
    final bindings = _requireBindings();
    final parsed = parseVoskRawRecognitionResult(
      bindings.finalResult(_requireRecognizer()).toDartString(),
      isFinal: true,
    );
    bindings.reset(_recognizer);
    return parsed.transcript.isEmpty ? null : parsed;
  }

  Future<void> stop() async {
    final bindings = _bindings;
    if (bindings != null && _recognizer != nullptr) {
      bindings.recognizerFree(_recognizer);
    }
    if (bindings != null && _model != nullptr) {
      bindings.modelFree(_model);
    }
    _bindings = null;
    _recognizer = nullptr;
    _model = nullptr;
  }

  VoskRawBindings _requireBindings() {
    final bindings = _bindings;
    if (bindings == null) {
      throw const VoskRawException(
        code: 'engine_unavailable',
        message: 'Vosk runtime is not initialized',
      );
    }
    return bindings;
  }

  Pointer<_VoskRecognizer> _requireRecognizer() {
    if (_recognizer == nullptr) {
      throw const VoskRawException(
        code: 'engine_unavailable',
        message: 'Vosk recognizer is not initialized',
      );
    }
    return _recognizer;
  }
}

VoskRawRecognitionResult parseVoskRawRecognitionResult(
  final String jsonPayload, {
  required final bool isFinal,
}) {
  if (jsonPayload.trim().isEmpty) {
    return VoskRawRecognitionResult(transcript: '', isFinal: isFinal);
  }
  final decoded = jsonDecode(jsonPayload);
  if (decoded is! Map<String, dynamic>) {
    return VoskRawRecognitionResult(
      transcript: '',
      isFinal: isFinal,
      rawJson: jsonPayload,
    );
  }

  final transcript = ((decoded['text'] ?? decoded['partial']) as String? ?? '')
      .trim();
  final alternatives = <String>{
    ...switch (decoded['alternatives']) {
      final List values =>
        values
            .whereType<Map>()
            .map((final value) => (value['text'] as String? ?? '').trim())
            .where((final value) => value.isNotEmpty),
      _ => const Iterable<String>.empty(),
    },
  }.toList(growable: false);

  final rawWords = switch (decoded['result'] ?? decoded['partial_result']) {
    final List values => values.whereType<Map>(),
    _ => const <Map>[],
  };
  final segments = rawWords
      .map(
        (final value) => VoskRawWordSegment(
          text: (value['word'] as String? ?? '').trim(),
          startMs: ((value['start'] as num?)?.toDouble() ?? 0) * 1000 ~/ 1,
          endMs: ((value['end'] as num?)?.toDouble() ?? 0) * 1000 ~/ 1,
          confidence: (value['conf'] as num?)?.toDouble(),
        ),
      )
      .where((final value) => value.text.isNotEmpty)
      .toList(growable: false);

  return VoskRawRecognitionResult(
    transcript: transcript,
    isFinal: isFinal,
    segments: segments,
    alternatives: alternatives,
    rawJson: jsonPayload,
  );
}

Uint8List extractVoskRawPcm16LeFromWav(final Uint8List wavBytes) =>
    _extractWavPcm16Le(wavBytes);

Future<Uint8List> readVoskRawAudioInput({
  required final String? filePath,
  required final List<int>? bytes,
  required final bool isBytes,
}) async {
  if (isBytes) {
    return _extractWavPcm16Le(Uint8List.fromList(bytes!));
  }
  final file = File(filePath!);
  if (!file.existsSync()) {
    throw VoskRawException(
      code: 'audio_input_invalid',
      message: 'Audio input file does not exist',
      details: filePath,
    );
  }
  return _extractWavPcm16Le(await file.readAsBytes());
}

Uint8List _extractWavPcm16Le(final Uint8List wavBytes) {
  if (wavBytes.length < 44) {
    throw const VoskRawException(
      code: 'audio_input_invalid',
      message: 'WAV payload is too small',
    );
  }
  final bytes = ByteData.sublistView(wavBytes);
  final riff = ascii.decode(wavBytes.sublist(0, 4), allowInvalid: true);
  final wave = ascii.decode(wavBytes.sublist(8, 12), allowInvalid: true);
  if (riff != 'RIFF' || wave != 'WAVE') {
    throw const VoskRawException(
      code: 'audio_input_invalid',
      message: 'Only RIFF/WAVE PCM input is supported',
    );
  }

  var offset = 12;
  var audioFormat = 0;
  var bitsPerSample = 0;
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
      final end = chunkDataOffset + chunkSize;
      if (audioFormat != 1 || bitsPerSample != 16 || end > wavBytes.length) {
        break;
      }
      return Uint8List.sublistView(wavBytes, chunkDataOffset, end);
    }
    offset = chunkDataOffset + chunkSize + (chunkSize.isOdd ? 1 : 0);
  }

  throw const VoskRawException(
    code: 'audio_input_invalid',
    message: 'Only PCM16 WAV input is supported',
  );
}

int _intExtra(
  final Map<String, dynamic> values,
  final String key,
  final int fallback,
) {
  final value = values[key];
  return value is num ? value.toInt() : fallback;
}
