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
  AppleFoundationNativeClient({XsFmLibraryLoader? loader})
    : _loader = loader ?? XsFmLibraryLoader() {
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

  XsFmBindings? _bindings;
  NativeCallable<ToolCbNative>? _toolCallable;
  NativeCallable<DoneCbNative>? _doneCallable;
  NativeCallable<StreamCbNative>? _streamCallable;

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
        final id = payload['id'] as String;
        final name = payload['name'] as String;
        final argumentsJson = payload['arguments'] as String? ?? '{}';

        final handler = toolRegistry?.tools[name]?.execute;
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
            '[xs_fm/dart] done: ok=${response["ok"]} '
            'error=${response["error"] ?? "none"}',
          );
        }
        done.complete(response);
      } on Object catch (e, st) {
        done.completeError(e, st);
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

    final accepted = _withCString(requestJson, (requestC) {
      return _b.generateAsync(
        requestC,
        _toolCallable!.nativeFunction,
        _doneCallable!.nativeFunction,
      );
    });

    if (accepted != 0 || done.isCompleted) {
      _closeCallables();
      // Immediate synchronous failure was delivered via done_cb; give the
      // listener event a moment to arrive, otherwise report rejection.
      try {
        final response = await done.future.timeout(const Duration(seconds: 1));
        return _toResult(response);
      } on TimeoutException {
        return InferenceResult<InferenceResponse>.fail(
          code: 'generation_error',
          message: 'Bridge rejected the request (accepted=$accepted)',
          meta: <String, dynamic>{'provider': id},
        );
      }
    }

    try {
      final response = await done.future.timeout(const Duration(minutes: 5));
      return _toResult(response);
    } on TimeoutException {
      return InferenceResult<InferenceResponse>.fail(
        code: 'generation_timeout',
        message: 'Generation exceeded 5 minutes',
        meta: <String, dynamic>{'provider': id},
      );
    } finally {
      _closeCallables();
    }
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
      return InferenceResult<InferenceResponse>.ok(
        InferenceResponse(
          structuredOutput: {'text': rawOutput},
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
        done.complete(response);
      } on Object catch (e, st) {
        done.completeError(e, st);
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

    final accepted = _withCString(requestJson, (requestC) {
      return _b.generateStreamAsync(
        requestC,
        _toolCallable!.nativeFunction,
        _streamCallable!.nativeFunction,
        _doneCallable!.nativeFunction,
      );
    });

    if (accepted != 0) {
      _closeCallables();
      throw StateError('Bridge rejected the streaming request ($accepted)');
    }

    return _NativeStreamSession(
      events: controller.stream,
      resultFuture: () async {
        try {
          final response = await done.future.timeout(
            const Duration(minutes: 5),
          );
          return _toResult(response);
        } on TimeoutException {
          return InferenceResult<InferenceResponse>.fail(
            code: 'generation_timeout',
            message: 'Streaming generation exceeded 5 minutes',
            meta: <String, dynamic>{'provider': id},
          );
        } finally {
          await controller.close();
          _closeCallables();
        }
      }(),
      onCancel: () async {
        // The bridge has no cancel entrypoint yet; closing the callables
        // detaches Dart from the turn. The native task runs to completion and
        // its done callback lands on a closed callable (no-op).
        _closeCallables();
        await controller.close();
      },
    );
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
