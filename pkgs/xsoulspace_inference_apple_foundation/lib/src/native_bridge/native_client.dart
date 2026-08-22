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
class AppleFoundationNativeClient implements InferenceClient {
  AppleFoundationNativeClient({XsFmLibraryLoader? loader})
    : _loader = loader ?? XsFmLibraryLoader();

  final XsFmLibraryLoader _loader;

  XsFmBindings? _bindings;
  NativeCallable<ToolCbNative>? _toolCallable;
  NativeCallable<DoneCbNative>? _doneCallable;

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

  XsFmBindings get _b => _bindings ??= XsFmBindings.fromLibrary(_loader.load());

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
          _respondTool(id, '{"error":"no handler for $name"}');
          return;
        }
        final arguments =
            jsonDecode(argumentsJson) as Map<String, dynamic>? ?? {};

        handler(arguments)
            .then((result) {
              _respondTool(id, jsonEncode(result));
            })
            .catchError((Object e) {
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
        done.complete(
          jsonDecode(responseC.cast<Utf8>().toDartString())
              as Map<String, dynamic>,
        );
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
}
