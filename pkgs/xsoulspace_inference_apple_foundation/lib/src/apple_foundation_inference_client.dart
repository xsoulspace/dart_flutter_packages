import 'dart:convert';
import 'dart:developer';

import 'package:flutter/services.dart';
import 'package:xsoulspace_inference_apple_foundation/src/dynamic_scheme/foundation_api.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

const MethodChannel _channel = MethodChannel(
  'xsoulspace_inference_apple_foundation',
);

/// Apple Foundation Models (SystemLanguageModel) implementation of [InferenceClient].
/// macOS only; returns standardized [InferenceResult] with codes
/// [engine_unavailable], [schema_validation_failed], etc.
class AppleFoundationInferenceClient implements InferenceClient {
  const AppleFoundationInferenceClient({required this._api});
  final FoundationApi _api;
  static FoundationApi initApi() => FoundationApi(channel: _channel)..init();
  @override
  String get id => 'apple_foundation';

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
  static int _seq = 0;

  /// Refreshes the availability cache. Idempotent.
  @override
  Future<bool> refreshAvailability() async {
    try {
      final result = await _api.isAvailable();
      _cachedAvailable = result == true;
      _availabilityChecked = true;
    } on PlatformException catch (_) {
      _cachedAvailable = false;
      _availabilityChecked = true;
    } catch (_) {
      _cachedAvailable = false;
      _availabilityChecked = true;
    }
    return _cachedAvailable;
  }

  Future<bool> _checkAvailability() async {
    if (!_availabilityChecked) {
      await refreshAvailability();
    }
    return _cachedAvailable;
  }

  @override
  void resetAvailabilityCache() {
    _availabilityChecked = false;
    _cachedAvailable = false;
  }

  @override
  Future<InferenceResult<InferenceResponse>> infer(
    final InferenceRequest request, {
    ToolRegistry? toolRegistry,
  }) async {
    if (!supportedTasks.contains(request.task)) {
      return InferenceResult<InferenceResponse>.fail(
        code: errorCodeTaskUnsupported,
        message: 'Task ${request.task.name} is not supported by $id',
        details: <String, dynamic>{
          'supported_tasks': supportedTasks
              .map((final task) => task.name)
              .toList(),
          'requested_task': request.task.name,
        },
      );
    }

    final requestValidation = validateInferenceRequest(request);
    if (!requestValidation.success) {
      return InferenceResult<InferenceResponse>.fail(
        code: requestValidation.error?.code ?? 'request_invalid',
        message:
            requestValidation.error?.message ??
            'Inference request validation failed',
        details: requestValidation.error?.details,
      );
    }

    final available = await _checkAvailability();
    if (!available) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message:
            'Apple Foundation Model unavailable (Apple Intelligence or device)',
      );
    }

    try {
      var systemPrompt = request.systemPrompt;
      if (request.task case .implicitlyStructuredText) {
        final promptBuilder = PromptBuilder(systemPrompt);
        promptBuilder.writeStructuredOutputPrompt(request.outputSchema);
        systemPrompt = promptBuilder.toString();
      } else if (request.task case .nativelyStructuredText) {
        // noop
      }

      // True per-request tool isolation: own handlers for this request only.
      final requestId = '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';
      if (toolRegistry != null) _api.beginRequest(requestId, toolRegistry);
      try {
        final schema = request.outputSchema;
        log(jsonEncode(schema), name: 'pregeneration');
        final rawOutput = await _api.generate(
          json: {
            'requestId': requestId,
            'prompt':
                "${request.contextFragmentsJson.isEmpty ? "" : '/nCONTEXT: ${request.contextFragmentsJson}\nPROMPT:\n'}${request.prompt}",
            'instructions': systemPrompt.isEmpty ? null : systemPrompt,
            // 'workingDirectory': request.workingDirectory,
            if (schema.isNotEmpty) 'schema': schema,
            "tools": toolRegistry?.getToolsJsons(),

            /// TODO(arenukvern): temporary disabled, because it doesnt work - need a proper fix
            // 'transcript': request.contextFragmentsJson.isEmpty
            //     ? null
            //     : request.contextFragmentsJson,
          },
        );

        if (rawOutput.trim().isEmpty) {
          return InferenceResult<InferenceResponse>.fail(
            code: 'output_empty',
            message: 'Apple Foundation Model produced no output',
            meta: <String, dynamic>{'provider': id},
          );
        }
        InferenceResponse response;
        final meta = <String, dynamic>{'provider': id};
        final isStructuredOutput = schema.isNotEmpty;
        if (isStructuredOutput) {
          final parsed = parseStrictJsonObject(rawOutput);
          final data = parsed.data;
          if (!parsed.success || data == null) {
            return InferenceResult<InferenceResponse>.fail(
              code: parsed.error?.code ?? 'json_parse_failed',
              message: parsed.error?.message ?? 'Failed to parse Apple FM JSON',
              details: parsed.error?.details ?? _truncate(rawOutput),
              meta: <String, dynamic>{'provider': id},
            );
          }

          final schemaValidation = validateJsonAgainstSchema(
            value: data,
            schema: request.outputSchema,
          );
          if (!schemaValidation.success) {
            return InferenceResult<InferenceResponse>.fail(
              code: schemaValidation.error?.code ?? 'schema_validation_failed',
              message:
                  schemaValidation.error?.message ??
                  'Apple FM output does not match schema',
              details: schemaValidation.error?.details,
              meta: <String, dynamic>{'provider': id},
            );
          }
          response = InferenceResponse(
            structuredOutput: data,
            rawOutput: rawOutput,
            meta: meta,
          );
        } else {
          response = InferenceResponse(rawOutput: rawOutput, meta: meta);
        }

        return InferenceResult<InferenceResponse>.ok(response, meta: meta);
      } finally {
        // Release this request's handlers (isolated per request).
        if (toolRegistry != null) _api.endRequest(requestId);
      }
    } on PlatformException catch (e, st) {
      final code = e.code.isEmpty ? 'engine_unavailable' : e.code;
      log('Apple Foundation Model invocation failed', error: e, stackTrace: st);
      return InferenceResult<InferenceResponse>.fail(
        code: code,
        message: e.message ?? 'Apple Foundation Model invocation failed',
        details: e.details,
        meta: <String, dynamic>{'provider': id},
      );
    } catch (e, st) {
      log('Apple Foundation Model failed', error: e, stackTrace: st);
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'Apple Foundation Model failed',
        details: e.toString(),
        meta: <String, dynamic>{'provider': id},
      );
    }
  }

  String _truncate(String value, {int max = 2000}) {
    if (value.length <= max) return value;
    return '${value.substring(0, max)}...[truncated ${value.length - max} chars]';
  }

  @override
  Future<void> load() async {
    // TODO(arenukvern): implement load
  }
}
