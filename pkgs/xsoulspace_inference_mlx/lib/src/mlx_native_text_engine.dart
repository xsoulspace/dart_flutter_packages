import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

/// Native bindings for the `mlx_text_native` dylib — resolved through the
/// package's native-assets code asset (hook/build.dart builds
/// `native/mlx_text_native` via SPM). On machines without the Apple
/// toolchain the hook registers no asset and these throw a named error at
/// first use; the native test skips honestly.
@Native<Int64 Function(Pointer<Uint8>)>(
  symbol: 'mlx_text_load',
  assetId: 'package:xsoulspace_inference_mlx/mlx_text_native',
)
external int _mlxTextLoad(Pointer<Uint8> modelDir);

@Native<Pointer<Uint8> Function(Int64, Pointer<Uint8>)>(
  symbol: 'mlx_text_generate',
  assetId: 'package:xsoulspace_inference_mlx/mlx_text_native',
)
external Pointer<Uint8> _mlxTextGenerate(
  int handle,
  Pointer<Uint8> requestJson,
);

@Native<Void Function(Pointer<Uint8>)>(
  symbol: 'mlx_text_free',
  assetId: 'package:xsoulspace_inference_mlx/mlx_text_native',
)
external void _mlxTextFree(Pointer<Uint8> pointer);

@Native<Void Function(Int64)>(
  symbol: 'mlx_text_unload',
  assetId: 'package:xsoulspace_inference_mlx/mlx_text_native',
)
external void _mlxTextUnload(int handle);

/// One completed generation from the native engine: text plus the
/// library-reported measured facts (token counts and MLX timings).
final class MlxNativeGeneration {
  const MlxNativeGeneration({
    required this.text,
    required this.promptTokens,
    required this.completionTokens,
    required this.promptTimeMs,
    required this.generateTimeMs,
    required this.stopReason,
    this.templateMs = 0,
  });

  final String text;
  final int promptTokens;
  final int completionTokens;
  final int promptTimeMs;
  final int generateTimeMs;
  final String stopReason;

  /// Wall time of the chat-template application that produced the prompt
  /// (0 from dylibs predating the field).
  final int templateMs;
}

/// One chat request in the native engine's JSON contract.
final class MlxNativeRequest {
  const MlxNativeRequest({
    required this.prompt,
    this.system,
    this.maxTokens = 320,
    this.temperature = 0.0,
    this.kvBits,
    this.stop = const <String>[],
    this.templateArgs,
    this.prefillStep,
    this.prefillUnchunked = false,
  });

  final String prompt;
  final String? system;
  final int maxTokens;
  final double temperature;
  final int? kvBits;
  final List<String> stop;
  final Map<String, Object?>? templateArgs;

  /// Ceiling on tokens evaluated per prefill forward (nil = engine default,
  /// 512 on the generic path).
  final int? prefillStep;

  /// Prefill the whole prompt in one forward.
  final bool prefillUnchunked;

  Map<String, Object?> toJson() => <String, Object?>{
    'prompt': prompt,
    'system': ?system,
    'max_tokens': maxTokens,
    'temperature': temperature,
    'kv_bits': ?kvBits,
    if (stop.isNotEmpty) 'stop': stop,
    'template_args': ?templateArgs,
    'prefill_step': ?prefillStep,
    'prefill_unchunked': prefillUnchunked,
  };
}

/// The native MLX text engine: an in-process Swift dylib over
/// mlx-swift-lm (mlx-swift-lm provides the model registry, chat
/// templates, KV cache, and samplers; this class is only the FFI shim's
/// Dart face).
///
/// The C ABI is synchronous and single-flight (the native side holds a
/// generate lock; the MLX wired-memory limit is per-process), so [load]
/// and [generate] run on a worker isolate and the calling isolate —
/// typically a loopback server — stays responsive between calls.
final class NativeMlxTextEngine {
  NativeMlxTextEngine._(this._handle);

  final int? _handle;
  bool _unloaded = false;

  int get handle => _handle ?? (throw StateError('mlx_text_native not loaded'));

  /// Loads a local MLX snapshot directory (the Hugging Face checkout shape:
  /// config.json + model.safetensors + tokenizer files). Throws a named
  /// error when the native asset is absent or the weights are unusable.
  static Future<NativeMlxTextEngine> load(final String modelDir) async {
    final result = await Isolate.run(() => _loadSync(modelDir));
    return result;
  }

  static NativeMlxTextEngine _loadSync(final String modelDir) {
    final pointer = modelDir.toNativeUtf8();
    try {
      final handle = _mlxTextLoad(pointer.cast<Uint8>());
      if (handle <= 0) {
        throw StateError(
          'mlx_text_native load failed (code $handle): the snapshot dir '
          'must contain config.json, safetensors weights and tokenizer files',
        );
      }
      return NativeMlxTextEngine._(handle);
    } finally {
      calloc.free(pointer);
    }
  }

  /// Runs one generation. The engine is single-flight: concurrent callers
  /// serialize behind the native lock.
  Future<MlxNativeGeneration> generate(final MlxNativeRequest request) async {
    final handle = this.handle;
    if (_unloaded) {
      throw StateError('mlx_text_native engine was unloaded');
    }
    return Isolate.run(() => _generateSync(handle, request));
  }

  static MlxNativeGeneration _generateSync(
    final int handle,
    final MlxNativeRequest request,
  ) {
    final json = jsonEncode(request.toJson());
    final requestPointer = json.toNativeUtf8();
    Pointer<Uint8> responsePointer = nullptr;
    try {
      responsePointer = _mlxTextGenerate(handle, requestPointer.cast<Uint8>());
      if (responsePointer == nullptr) {
        throw StateError('mlx_text_native generate returned null');
      }
      final response = responsePointer.cast<Utf8>().toDartString();
      final decoded = jsonDecode(response);
      if (decoded is! Map) {
        throw StateError('mlx_text_native response was not an object');
      }
      final error = decoded['error'];
      if (error != null) {
        throw StateError('mlx_text_native error: $error');
      }
      int intOf(final Object? value, final String name) =>
          value is int ? value : (throw StateError('missing int "$name"'));
      return MlxNativeGeneration(
        text: '${decoded['text'] ?? ''}',
        promptTokens: intOf(decoded['prompt_tokens'], 'prompt_tokens'),
        completionTokens: intOf(
          decoded['completion_tokens'],
          'completion_tokens',
        ),
        promptTimeMs: intOf(decoded['prompt_time_ms'], 'prompt_time_ms'),
        generateTimeMs: intOf(decoded['generate_time_ms'], 'generate_time_ms'),
        stopReason: '${decoded['stop_reason'] ?? 'stop'}',
        templateMs: decoded['template_ms'] is int
            ? decoded['template_ms'] as int
            : 0,
      );
    } finally {
      calloc.free(requestPointer);
      if (responsePointer != nullptr) {
        _mlxTextFree(responsePointer);
      }
    }
  }

  /// Drops the model from the process. The engine is unusable afterwards.
  void unload() {
    if (_unloaded) return;
    _unloaded = true;
    _mlxTextUnload(handle);
  }
}
