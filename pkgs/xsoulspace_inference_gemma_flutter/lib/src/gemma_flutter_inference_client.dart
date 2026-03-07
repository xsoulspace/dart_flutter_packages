import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'gemma_model_setup.dart';

/// Gemma Flutter (flutter_gemma) implementation of [InferenceClient].
/// Uses active inference model from FlutterGemma; returns standardized
/// [InferenceResult] with codes like [engine_unavailable], [schema_validation_failed].
class GemmaFlutterInferenceClient implements InferenceClient {
  GemmaFlutterInferenceClient({
    this.maxTokens = 1024,
    this.modelSetup,
  }) : _modelSetup = modelSetup ?? GemmaModelSetup();

  final int maxTokens;
  final GemmaModelSetup? modelSetup;
  final GemmaModelSetup _modelSetup;

  @override
  String get id => 'gemma_flutter';

  @override
  bool get isAvailable => _cachedAvailable;

  static bool _cachedAvailable = false;
  static bool _availabilityChecked = false;

  /// Refreshes the availability cache (e.g. after model install). Idempotent.
  static Future<bool> refreshAvailability() async {
    try {
      _cachedAvailable = await FlutterGemma.hasActiveModel();
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
        message: 'No Gemma model active; install via model setup',
      );
    }

    try {
      final model = await FlutterGemma.getActiveModel(maxTokens: maxTokens);
      final session = await model.createSession();
      try {
        final prompt = _buildPromptWithSchema(request);
        await session.addQueryChunk(Message.text(text: prompt, isUser: true));
        final rawOutput = await session.getResponse();
        if (rawOutput.trim().isEmpty) {
          return InferenceResult<InferenceResponse>.fail(
            code: 'codex_output_empty',
            message: 'Gemma produced no output',
            meta: <String, dynamic>{'provider': id},
          );
        }

        final parsed = parseStrictJsonObject(rawOutput);
        if (!parsed.success || parsed.data == null) {
          return InferenceResult<InferenceResponse>.fail(
            code: parsed.error?.code ?? 'json_parse_failed',
            message: parsed.error?.message ?? 'Failed to parse Gemma JSON',
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
                'Gemma output does not match schema',
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
      } finally {
        await session.close();
      }
    } on Exception catch (e) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'Gemma inference failed',
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

  /// Refresh availability cache (e.g. after model install).
  static void resetAvailabilityCache() {
    _availabilityChecked = false;
    _cachedAvailable = false;
  }
}
