// ignore_for_file: lines_longer_as_80_chars

/// WEB stub for the AFM FFI transport (ADR 0003).
///
/// `native_client.dart` needs `dart:ffi` (`NativeCallable`, `Pointer`,
/// `package:ffi`), which does not exist on the web target. This stub is
/// selected by the conditional import/export in the package barrel
/// (`if (dart.library.js_interop)`) and keeps the public API shape — the
/// class name, id, and task set — while honestly reporting the backend
/// UNAVAILABLE: `refreshAvailability()` is false, `load()` and
/// `streamStructuredText()` throw, and `infer()` fails with the named
/// code `engine_unavailable`. No fake success anywhere.
///
/// The web peer is a viewer/answerer (ADR 0003): it never runs the AFM
/// backend; an unresolvable backend yields a binding whose client refuses
/// with named data, which the host surfaces instead of hanging.
library;

import 'dart:async';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// Web stand-in for [AppleFoundationNativeClient] (same public shape the
/// barrel exposes on the VM; the FFI-only `loader`/`bindings` constructor
/// parameters are absent here — they have no meaning without dart:ffi).
class AppleFoundationNativeClient
    implements InferenceClient, StructuredTextStreamingInferenceClient {
  AppleFoundationNativeClient({
    this.inferTimeout = const Duration(minutes: 5),
    this.maxContextTokens = 3800,
    this.outputReserveTokens = 1024,
  });

  /// Generation timeout — accepted for API parity; never armed on web
  /// (no generation can start).
  final Duration inferTimeout;

  /// Pre-flight context budget — API parity with the VM client.
  final int maxContextTokens;

  /// Generation space reserved out of [maxContextTokens] — API parity.
  final int outputReserveTokens;

  @override
  String get id => 'apple_foundation_native';

  /// Honest, constant: the native bridge (dylib + Apple Intelligence)
  /// does not exist on the web platform.
  @override
  bool get isAvailable => false;

  /// Same task set as the VM client so callers see the backend's real
  /// capability table; the refusal happens at availability, with the
  /// named code — never a fake success.
  @override
  Set<InferenceTask> get supportedTasks => const <InferenceTask>{
    InferenceTask.text,
    InferenceTask.implicitlyStructuredText,
    InferenceTask.nativelyStructuredText,
  };

  /// Whether the last load used the code-asset path. Always false on web.
  static bool usedCodeAsset = false;

  static bool _debugEnabled = true;

  /// Whether debug traces are requested. There is no bridge on web, so
  /// nothing consumes the flag — surfaced read-only for API honesty.
  static bool get debugEnabled => _debugEnabled;

  /// Debug-flag API parity with the VM client. There is no bridge to
  /// trace on web; the flag is stored so setDebug round-trips honestly.
  static void setDebug({bool enabled = true}) {
    _debugEnabled = enabled;
  }

  @override
  Future<bool> refreshAvailability() async => false;

  @override
  void resetAvailabilityCache() {
    // Nothing is cached on web — availability is a constant false.
  }

  @override
  Future<void> load() async {
    throw UnsupportedError(
      'apple_foundation_afm requires the native FFI bridge '
      '(libxs_fm_bridge.dylib + Apple Intelligence) — unavailable on the '
      'web platform (ADR 0003: the web peer is a viewer/answerer)',
    );
  }

  @override
  Future<InferenceResult<InferenceResponse>> infer(
    InferenceRequest request, {
    ToolRegistry? toolRegistry,
  }) async {
    if (!supportedTasks.contains(request.task)) {
      return InferenceResult<InferenceResponse>.fail(
        code: errorCodeTaskUnsupported,
        message: 'Task ${request.task.name} is not supported by $id',
        details: <String, dynamic>{
          'supported_tasks': supportedTasks.map((t) => t.name).toList(),
          'requested_task': request.task.name,
        },
      );
    }
    return InferenceResult<InferenceResponse>.fail(
      code: 'engine_unavailable',
      message:
          'Apple Foundation Model unavailable on the web platform — the '
          'AFM backend needs the native dart:ffi bridge (ADR 0003)',
      meta: <String, dynamic>{
        'provider': id,
        'requested_task': request.task.name,
      },
    );
  }

  @override
  Future<InferenceStructuredTextStreamSession> streamStructuredText(
    InferenceRequest request,
  ) async {
    if (!supportedTasks.contains(request.task)) {
      throw UnsupportedError(
        'Task ${request.task.name} is not supported by $id',
      );
    }
    throw StateError(
      'Apple Foundation Model unavailable on the web platform — the AFM '
      'backend needs the native dart:ffi bridge (ADR 0003)',
    );
  }

  /// API parity with the VM client — nothing is ever in flight on web.
  void cancelActiveGeneration() {}

  /// API parity with the VM client — nothing to release on web.
  void dispose() {}
}
