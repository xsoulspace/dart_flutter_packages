import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'bindings.dart';
import 'library_loader.dart';

/// FFI transport for Apple Foundation Models.
///
/// Implements [InferenceClient] without a Flutter engine. Tool calls flow
/// Swift → Dart through a `NativeCallable.listener` callback; Dart resumes
/// each pending call via `xs_fm_tool_respond`.
///
/// Symbol resolution prefers the code asset registered by `hook/build.dart`
/// (via the `@Native` bindings in `native_bindings.dart`); when code assets
/// are unavailable it falls back to [XsFmLibraryLoader] path resolution.
class AppleFoundationNativeClient
    implements InferenceClient, StructuredTextStreamingInferenceClient {
  /// [bindings] and [inferTimeout] are injection points for tests: a fake
  /// [XsFmBindings] can simulate bridge behaviour (hanging generations,
  /// late callbacks) without the macOS runtime, and [inferTimeout] shrinks
  /// the 5-minute generation timeout to something testable.
  AppleFoundationNativeClient({
    XsFmLibraryLoader? loader,
    XsFmBindings? bindings,
    this.inferTimeout = const Duration(minutes: 5),

    /// AFM reliability guard (P1 follow-up): the on-device context window is
    /// ~4k tokens. A request whose estimated total (system + prompt +
    /// fragments + transcript) exceeds the budget is rejected with the named
    /// code `context_window_exceeded` BEFORE the bridge is called — the
    /// over-window call was the precursor of the P1 VM crash, and a named
    /// failure beats a native crash. tokens ≈ chars/4 (the harness default
    /// estimator).
    this.maxContextTokens = 3800,
  }) : _loader = loader ?? XsFmLibraryLoader(),
       _injectedBindings = bindings {
    _instance = this;
    if (_debugEnabled) {
      // Apply after first load; safe to call repeatedly.
      Future<void>.microtask(() {
        try {
          _b.setDebug(1);
        } on Object {
          // Load failure surfaces on first use instead.
        }
      });
    }
  }

  final XsFmLibraryLoader _loader;
  final XsFmBindings? _injectedBindings;

  /// How long a generation may run before it is cancelled. On timeout the
  /// Swift side is cancelled FIRST (see `cancelGeneration`) so no callback
  /// can arrive after Dart releases the call.
  final Duration inferTimeout;

  /// P1 follow-up: pre-flight context budget (see constructor doc).
  final int maxContextTokens;

  XsFmBindings? _bindings;
  NativeCallable<ToolCbNative>? _toolCallable;
  NativeCallable<DoneCbNative>? _doneCallable;
  NativeCallable<StreamCbNative>? _streamCallable;

  /// Generation-id dispatch. Callback payloads carry `{"generation": id}`;
  /// payloads carrying a foreign id are DROPPED. This is what makes a late
  /// (in-flight) callback from a cancelled generation harmless instead of a
  /// wrong-completion or a crash.
  int? _activeGeneration;

  /// Whether the last load used the code-asset path (vs the fallback loader).
  static bool usedCodeAsset = false;

  @override
  String get id => 'apple_foundation_native';

  @override
  bool get isAvailable => _cachedAvailable;

  @override
  Set<InferenceTask> get supportedTasks => const <InferenceTask>{
    InferenceTask.text,
    InferenceTask.implicitlyStructuredText,
    InferenceTask.nativelyStructuredText,
  };

  static bool _cachedAvailable = false;
  static bool _availabilityChecked = false;

  /// Enables/disables native + Dart debug traces (stderr). On by default.
  /// Traces cover: request receipt, schema materialization, tool
  /// preparation, tool call payloads, tool responses, and completion.
  static void setDebug({bool enabled = true}) {
    _debugEnabled = enabled;
    try {
      _instance?._b.setDebug(enabled ? 1 : 0);
    } on Object {
      // Bridge not loaded yet; flag applies when it loads.
    }
  }

  static bool _debugEnabled = true;
  static AppleFoundationNativeClient? _instance;

  XsFmBindings get _b {
    if (_bindings != null) return _bindings!;
    if (_injectedBindings != null) {
      _bindings = _injectedBindings;
      return _bindings!;
    }
    // Resolution order:
    // 1. Loader path (works today, all supported SDKs).
    // 2. Code-asset path (`@Native` bindings) once the workspace SDK is
    //    3.14+ and `DynamicLibrary.codeAsset` ships — see
    //    `native_bindings.dart`, kept ready for that migration.
    usedCodeAsset = false;
    _bindings = LibraryXsFmBindings.fromLibrary(_loader.load());
    return _bindings!;
  }

  @override
  Future<bool> refreshAvailability() async {
    try {
      _cachedAvailable = _b.isAvailable() != 0;
    } on Object {
      _cachedAvailable = false;
    }
    _availabilityChecked = true;
    return _cachedAvailable;
  }

  @override
  void resetAvailabilityCache() {
    _availabilityChecked = false;
    _cachedAvailable = false;
  }

  @override
  Future<void> load() async {
    // Force-load the dylib eagerly.
    _b;
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

    // P1 follow-up — pre-flight context budget. The recorded on-device
    // crash was preceded by 'Exceeded model context window size': a request
    // whose native transcript overflowed AFM's ~4k window. Estimate the
    // total the bridge will build and fail NAMED before touching it.
    final estimateChars = request.systemPrompt.length +
        request.prompt.length +
        [for (final f in request.contextFragments) f.toString().length]
            .fold(0, (a, b) => a + b) +
        ((request.metadata['transcript'] as String?)?.length ?? 0);
    final estimateTokens = estimateChars ~/ 4;
    if (estimateTokens > maxContextTokens) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'context_window_exceeded',
        message:
            'estimated $estimateTokens tokens > $maxContextTokens budget — '
            'shrink the cut (composition/zoom) before calling AFM',
        meta: <String, dynamic>{
          'provider': id,
          'estimated_tokens': estimateTokens,
          'budget_tokens': maxContextTokens,
        },
      );
    }

    if (!_availabilityChecked) await refreshAvailability();
    if (!_cachedAvailable) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message:
            'Apple Foundation Model unavailable (Apple Intelligence or device)',
      );
    }

    var systemPrompt = request.systemPrompt;
    if (request.task case .implicitlyStructuredText) {
      final promptBuilder = PromptBuilder(systemPrompt);
      promptBuilder.writeStructuredOutputPrompt(request.outputSchema);
      systemPrompt = promptBuilder.toString();
    }

    final requestJson = jsonEncode(<String, dynamic>{
      'prompt': request.prompt,
      'instructions': systemPrompt.isEmpty ? null : systemPrompt,
      if (request.outputSchema.isNotEmpty) 'schema': request.outputSchema,
      'tools': toolRegistry?.getToolsJsons(),
    });

    if (_debugEnabled) {
      final toolNames = toolRegistry?.tools.keys.map((t) => t.value).join(', ');
      stderr.writeln(
        '[xs_fm/dart] infer: prompt=${request.prompt.length}ch '
        'schema=${request.outputSchema.isEmpty ? "absent" : "present"} '
        'tools=[${toolNames ?? "none"}]',
      );
      for (final entry
          in toolRegistry?.tools.entries ??
              const <MapEntry<ToolName, ToolDef>>[]) {
        final schema = entry.value.argsSchema.toJson();
        stderr.writeln(
          '[xs_fm/dart] tool ${entry.key.value}: '
          'argsSchema=${schema.isEmpty ? "EMPTY (optional args)" : "present"}',
        );
      }
    }

    // The completion of the whole generation turn. Tool calls are resumed
    // inline: the Swift side suspends its tool continuation until Dart calls
    // xs_fm_tool_respond, so no queue is needed here.
    final done = Completer<Map<String, dynamic>>();

    void handleToolPayload(Pointer<Char> payloadC) {
      try {
        final payloadJson = payloadC.cast<Utf8>().toDartString();
        final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
        final generation = payload['generation'] as int?;
        // Generation guard (see handleDone): drop payloads carrying a foreign
        // generation id — a stale callback from a cancelled generation.
        if (generation != null &&
            _activeGeneration != null &&
            generation != _activeGeneration) {
          return;
        }
        final id = payload['id'] as String;
        final name = payload['name'] as String;
        final argumentsJson = payload['arguments'] as String? ?? '{}';

        // Payload name is a raw String; the registry is keyed by ToolName.
        final handler = toolRegistry?.tools[ToolName(name)]?.execute;
        if (handler == null) {
          if (_debugEnabled) {
            stderr.writeln(
              '[xs_fm/dart] tool call "$name": NO HANDLER registered '
              '(known: ${toolRegistry?.tools.keys.map((t) => t.value).join(", ") ?? "none"})',
            );
          }
          _respondTool(id, '{"error":"no handler for $name"}');
          return;
        }
        final arguments =
            jsonDecode(argumentsJson) as Map<String, dynamic>? ?? {};

        handler(arguments)
            .then((result) {
              if (_debugEnabled) {
                stderr.writeln(
                  '[xs_fm/dart] tool "$name" handler ok → responding',
                );
              }
              _respondTool(id, jsonEncode(result));
            })
            .catchError((Object e) {
              if (_debugEnabled) {
                stderr.writeln('[xs_fm/dart] tool "$name" handler error: $e');
              }
              _respondTool(id, '{"error":${jsonEncode(e.toString())}}');
            });
      } on Object catch (e) {
        stderr.writeln('xs_fm tool payload error: $e');
      } finally {
        _b.freeString(payloadC);
      }
    }

    void handleDone(Pointer<Char> responseC) {
      try {
        final response =
            jsonDecode(responseC.cast<Utf8>().toDartString())
                as Map<String, dynamic>;
        if (_debugEnabled) {
          stderr.writeln(
            '[xs_fm/dart] done: gen=${response["generation"]} '
            'ok=${response["ok"]} error=${response["error"] ?? "none"}',
          );
        }
        final generation = response['generation'] as int?;
        // Callables are per-call, so payloads delivered here belong to this
        // call — except a stale payload from a previously CANCELLED
        // generation that was still in flight when teardown happened. Such a
        // payload carries a foreign generation id: drop it instead of
        // completing the wrong future (callback-after-delete fix).
        if (generation != null &&
            _activeGeneration != null &&
            generation != _activeGeneration) {
          return;
        }
        if (!done.isCompleted) done.complete(response);
      } on Object catch (e, st) {
        if (!done.isCompleted) done.completeError(e, st);
      } finally {
        _b.freeString(responseC);
      }
    }

    _toolCallable?.close();
    _doneCallable?.close();
    _toolCallable = NativeCallable<ToolCbNative>.listener(handleToolPayload)
      ..keepIsolateAlive = false;
    _doneCallable = NativeCallable<DoneCbNative>.listener(handleDone)
      ..keepIsolateAlive = false;

    // xs_fm_generate_async returns the generation id (> 0) on accept, or
    // -1 on immediate failure (done_cb was invoked with the error).
    final accepted = _withCString(requestJson, (requestC) {
      return _b.generateAsync(
        requestC,
        _toolCallable!.nativeFunction,
        _doneCallable!.nativeFunction,
      );
    });

    if (accepted <= 0) {
      // Immediate synchronous failure was delivered via done_cb; give the
      // listener event a moment to arrive, otherwise cancel + report
      // rejection. Cancel FIRST (idempotent: the bridge returns 1 for an
      // unknown id) so no callback can land after teardown.
      try {
        final response = await done.future.timeout(const Duration(seconds: 1));
        return _toResult(response);
      } on TimeoutException {
        _cancelGeneration(accepted);
        return InferenceResult<InferenceResponse>.fail(
          code: 'generation_error',
          message: 'Bridge rejected the request (accepted=$accepted)',
          meta: <String, dynamic>{'provider': id},
        );
      }
    }

    _activeGeneration = accepted;
    try {
      final response = await done.future.timeout(inferTimeout);
      return _toResult(response);
    } on TimeoutException {
      // Callback-after-delete fix: CANCEL the pending Swift call and release
      // the done completer BEFORE any teardown. The bridge gates every
      // callback path for the cancelled generation (pending tool
      // continuations are resumed with an error, finish() becomes a no-op);
      // any payload already in flight is dropped by the generation guard
      // above. Only then does Dart release the call.
      _cancelGeneration(accepted);
      return InferenceResult<InferenceResponse>.fail(
        code: 'generation_timeout',
        message:
            'Generation exceeded '
            '${inferTimeout.inMinutes >= 1 ? '${inferTimeout.inMinutes} minute(s)' : '${inferTimeout.inMilliseconds} ms'}',
        meta: <String, dynamic>{'provider': id, 'cancelled': true},
      );
    } finally {
      if (_activeGeneration == accepted) _activeGeneration = null;
    }
  }

  /// Cancels a bridge generation and detaches it from this client. Safe to
  /// call for unknown ids (the bridge returns 1).
  void _cancelGeneration(int generationId) {
    if (generationId <= 0) return;
    try {
      _b.cancelGeneration(generationId);
    } on Object {
      // Older bridge without the cancel symbol — the per-call callables +
      // generation guard still drop any late callback.
    }
    if (_activeGeneration == generationId) _activeGeneration = null;
  }

  /// Best-effort decode of a JSON object payload. Returns null when the
  /// output is not a JSON object (plain text answers stay wrapped as text).
  static Map<String, dynamic>? _tryDecodeStructured(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Plain text — caller falls back to {'text': raw}.
    }
    return null;
  }

  InferenceResult<InferenceResponse> _toResult(Map<String, dynamic> response) {
    if (response['ok'] == true) {
      final rawOutput = response['output'] as String? ?? '';
      if (rawOutput.trim().isEmpty) {
        return InferenceResult<InferenceResponse>.fail(
          code: 'output_empty',
          message: 'Apple Foundation Model produced no output',
          meta: <String, dynamic>{'provider': id},
        );
      }
      // Guided generation returns the constrained JSON as raw text; decode
      // it so structuredOutput honors the requested schema instead of the
      // lossy {'text': raw} wrapper.
      final structured = _tryDecodeStructured(rawOutput);
      return InferenceResult<InferenceResponse>.ok(
        InferenceResponse(
          structuredOutput: structured ?? {'text': rawOutput},
          rawOutput: rawOutput,
          meta: <String, dynamic>{'provider': id},
        ),
        meta: <String, dynamic>{'provider': id},
      );
    }
    final error = response['error'] as Map<String, dynamic>? ?? {};
    return InferenceResult<InferenceResponse>.fail(
      code: error['code'] as String? ?? 'generation_error',
      message: error['message'] as String? ?? 'Generation failed',
      meta: <String, dynamic>{'provider': id},
    );
  }

  void _respondTool(String id, String resultJson) {
    _withCString(id, (idC) {
      _withCString(resultJson, (resultC) => _b.toolRespond(idC, resultC));
    });
  }

  void _closeCallables() {
    _toolCallable?.close();
    _toolCallable = null;
    _doneCallable?.close();
    _doneCallable = null;
    _streamCallable?.close();
    _streamCallable = null;
  }

  /// Runs [body] with [value] encoded as a NUL-terminated UTF-8 C string.
  static R _withCString<R>(String value, R Function(Pointer<Char>) body) {
    final cString = value.toNativeUtf8();
    try {
      return body(cString.cast());
    } finally {
      malloc.free(cString);
    }
  }

  /// Streaming generation: returns a session whose [events] stream delivers
  /// text deltas as they arrive, and whose [result] completes when the turn
  /// finishes. Tool calls are resumed inline exactly like [infer].
  ///
  /// Structured-output requests fall back to the blocking path on the Swift
  /// side (the framework delivers structured content atomically).
  @override
  Future<InferenceStructuredTextStreamSession> streamStructuredText(
    InferenceRequest request,
  ) async {
    if (!supportedTasks.contains(request.task)) {
      throw UnsupportedError(
        'Task ${request.task.name} is not supported by $id',
      );
    }

    if (!_availabilityChecked) await refreshAvailability();
    if (!_cachedAvailable) {
      throw StateError(
        'Apple Foundation Model unavailable (Apple Intelligence or device)',
      );
    }

    var systemPrompt = request.systemPrompt;
    if (request.task case .implicitlyStructuredText) {
      final promptBuilder = PromptBuilder(systemPrompt);
      promptBuilder.writeStructuredOutputPrompt(request.outputSchema);
      systemPrompt = promptBuilder.toString();
    }

    final requestJson = jsonEncode(<String, dynamic>{
      'prompt': request.prompt,
      'instructions': systemPrompt.isEmpty ? null : systemPrompt,
      // No schema: streaming is text-only; structured output uses infer().
      'tools': null,
    });

    final controller = StreamController<InferenceStructuredTextStreamEvent>();
    final done = Completer<Map<String, dynamic>>();

    void handleStreamPayload(Pointer<Char> payloadC) {
      try {
        final payload =
            jsonDecode(payloadC.cast<Utf8>().toDartString())
                as Map<String, dynamic>;
        final generation = payload['generation'] as int?;
        if (generation != null &&
            _activeGeneration != null &&
            generation != _activeGeneration) {
          return; // stale delta from a cancelled generation
        }
        final delta = payload['delta'] as String? ?? '';
        if (delta.isNotEmpty) {
          controller.add(
            InferenceStructuredTextStreamEvent(
              type: .partialOutput,
              timestamp: DateTime.now(),
              textDelta: delta,
            ),
          );
        }
      } on Object catch (e) {
        stderr.writeln('xs_fm stream payload error: $e');
      } finally {
        _b.freeString(payloadC);
      }
    }

    void handleToolPayload(Pointer<Char> payloadC) {
      // Streaming sessions carry no tool registry — nothing to resume.
      try {
        final payload =
            jsonDecode(payloadC.cast<Utf8>().toDartString())
                as Map<String, dynamic>;
        _respondTool(payload['id'] as String, '{"error":"no tools in stream"}');
      } on Object {
        // ignore
      } finally {
        _b.freeString(payloadC);
      }
    }

    void handleDone(Pointer<Char> responseC) {
      try {
        final response =
            jsonDecode(responseC.cast<Utf8>().toDartString())
                as Map<String, dynamic>;
        final generation = response['generation'] as int?;
        // Same generation guard as infer's handleDone: a stale done from a
        // cancelled generation never completes this session's future.
        if (generation != null &&
            _activeGeneration != null &&
            generation != _activeGeneration) {
          return;
        }
        if (!done.isCompleted) done.complete(response);
      } on Object catch (e, st) {
        if (!done.isCompleted) done.completeError(e, st);
      } finally {
        _b.freeString(responseC);
      }
    }

    _closeCallables();
    _toolCallable = NativeCallable<ToolCbNative>.listener(handleToolPayload)
      ..keepIsolateAlive = false;
    _streamCallable = NativeCallable<StreamCbNative>.listener(
      handleStreamPayload,
    )..keepIsolateAlive = false;
    _doneCallable = NativeCallable<DoneCbNative>.listener(handleDone)
      ..keepIsolateAlive = false;

    // xs_fm_generate_stream_async returns the generation id (> 0) on accept,
    // or -1 on immediate failure (done_cb invoked with the error).
    final accepted = _withCString(requestJson, (requestC) {
      return _b.generateStreamAsync(
        requestC,
        _toolCallable!.nativeFunction,
        _streamCallable!.nativeFunction,
        _doneCallable!.nativeFunction,
      );
    });

    if (accepted <= 0) {
      _closeCallables();
      throw StateError('Bridge rejected the streaming request ($accepted)');
    }
    _activeGeneration = accepted;

    return _NativeStreamSession(
      events: controller.stream,
      resultFuture: () async {
        try {
          final response = await done.future.timeout(inferTimeout);
          return _toResult(response);
        } on TimeoutException {
          // Cancel the Swift side BEFORE releasing the callables (see infer).
          _cancelGeneration(accepted);
          return InferenceResult<InferenceResponse>.fail(
            code: 'generation_timeout',
            message:
                'Streaming generation exceeded ${inferTimeout.inMinutes}'
                ' minute(s)',
            meta: <String, dynamic>{'provider': id, 'cancelled': true},
          );
        } finally {
          if (_activeGeneration == accepted) _activeGeneration = null;
          await controller.close();
          _closeCallables();
        }
      }(),
      onCancel: () async {
        // Cancel the Swift turn first: pending continuations resume with an
        // error and every callback path for this generation becomes a no-op,
        // so no callback can land on the callables being closed.
        _cancelGeneration(accepted);
        await controller.close();
        _closeCallables();
      },
    );
  }

  /// Releases the native callables. Call only when no generation is in
  /// flight (after a cancel or a completed turn) — see the cancel contract
  /// in `bridge.h`.
  void dispose() {
    _cancelGeneration(_activeGeneration ?? 0);
    _closeCallables();
  }
}

/// [InferenceStructuredTextStreamSession] over the FFI bridge callbacks.
final class _NativeStreamSession
    implements InferenceStructuredTextStreamSession {
  _NativeStreamSession({
    required Stream<InferenceStructuredTextStreamEvent> events,
    required Future<InferenceResult<InferenceResponse>> resultFuture,
    required Future<void> Function() onCancel,
  }) : _events = events,
       _resultFuture = resultFuture,
       _onCancel = onCancel;

  final Stream<InferenceStructuredTextStreamEvent> _events;
  final Future<InferenceResult<InferenceResponse>> _resultFuture;
  final Future<void> Function() _onCancel;
  var _disposed = false;

  @override
  Stream<InferenceStructuredTextStreamEvent> get events => _events;

  @override
  Future<InferenceResult<InferenceResponse>> get result => _resultFuture;

  @override
  Future<void> cancel() async {
    if (_disposed) return;
    _disposed = true;
    await _onCancel();
  }

  @override
  Future<void> dispose() => cancel();
}
