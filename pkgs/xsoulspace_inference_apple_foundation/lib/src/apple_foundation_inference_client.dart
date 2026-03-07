import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

const MethodChannel _channel =
    MethodChannel('xsoulspace_inference_apple_foundation');

/// Apple Foundation Models (SystemLanguageModel) implementation of [InferenceClient].
/// macOS only; returns standardized [InferenceResult] with codes
/// [engine_unavailable], [schema_validation_failed], etc.
class AppleFoundationInferenceClient implements InferenceClient {
  AppleFoundationInferenceClient();

  @override
  String get id => 'apple_foundation';

  @override
  bool get isAvailable => _cachedAvailable;

  static bool _cachedAvailable = false;
  static bool _availabilityChecked = false;

  /// Refreshes the availability cache. Idempotent.
  static Future<bool> refreshAvailability() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
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

  static Future<bool> _checkAvailability() async {
    if (!_availabilityChecked) {
      await refreshAvailability();
    }
    return _cachedAvailable;
  }

  @override
  Future<InferenceResult<InferenceResponse>> infer(
    final InferenceRequest request,
  ) async {
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
      final prompt = _buildPromptWithSchema(request);
      final rawOutput = await _channel.invokeMethod<String>(
        'generate',
        <String, dynamic>{
          'prompt': prompt,
          'workingDirectory': request.workingDirectory,
        },
      );

      if (rawOutput == null || rawOutput.trim().isEmpty) {
        return InferenceResult<InferenceResponse>.fail(
          code: 'codex_output_empty',
          message: 'Apple Foundation Model produced no output',
          meta: <String, dynamic>{'provider': id},
        );
      }

      final parsed = parseStrictJsonObject(rawOutput);
      if (!parsed.success || parsed.data == null) {
        return InferenceResult<InferenceResponse>.fail(
          code: parsed.error?.code ?? 'json_parse_failed',
          message: parsed.error?.message ?? 'Failed to parse Apple FM JSON',
          details: parsed.error?.details ?? _truncate(rawOutput),
          meta: <String, dynamic>{'provider': id},
        );
      }

      final schemaValidation = validateJsonAgainstSchema(
        value: parsed.data!,
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

      return InferenceResult<InferenceResponse>.ok(
        InferenceResponse(
          output: parsed.data!,
          rawOutput: rawOutput,
          meta: <String, dynamic>{'provider': id},
        ),
        meta: <String, dynamic>{'provider': id},
      );
    } on PlatformException catch (e) {
      final code = e.code.isEmpty ? 'engine_unavailable' : e.code;
      return InferenceResult<InferenceResponse>.fail(
        code: code,
        message: e.message ?? 'Apple Foundation Model invocation failed',
        details: e.details,
        meta: <String, dynamic>{'provider': id},
      );
    } catch (e) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'Apple Foundation Model failed',
        details: e.toString(),
        meta: <String, dynamic>{'provider': id},
      );
    }
  }

  String _buildPromptWithSchema(InferenceRequest request) {
    final schemaJson = const JsonEncoder.withIndent('  ').convert(
      request.outputSchema,
    );
    return '${request.prompt}\n\nRespond with a single JSON object that conforms to this schema (no other text):\n$schemaJson';
  }

  String _truncate(String value, {int max = 2000}) {
    if (value.length <= max) return value;
    return '${value.substring(0, max)}...[truncated ${value.length - max} chars]';
  }
}
