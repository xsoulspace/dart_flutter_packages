import 'dart:async';
import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'gemma_model_catalog.dart';
import 'gemma_model_setup.dart';

/// Gemma Flutter (flutter_gemma) implementation of [InferenceClient] and
/// [ProvisionableInferenceClient].
///
/// Uses the active inference model from FlutterGemma; returns standardized
/// [InferenceResult] with codes like [engine_unavailable],
/// [schema_validation_failed]. On schema failure, retries once with the
/// validation error appended to the prompt (small models frequently need one
/// repair round-trip).
class GemmaFlutterInferenceClient
    implements InferenceClient, ProvisionableInferenceClient {
  GemmaFlutterInferenceClient({
    this.maxTokens = 1024,
    this.preferredBackend,
    GemmaModelSetup? modelSetup,
    this.maxRepairAttempts = 1,
  }) : modelSetup = modelSetup ?? GemmaModelSetup();

  final int maxTokens;
  final PreferredBackend? preferredBackend;
  final GemmaModelSetup modelSetup;

  /// How many times a failed schema validation is retried with the error
  /// appended to the prompt. 0 disables repair.
  final int maxRepairAttempts;

  @override
  String get id => 'gemma_flutter';

  bool _loaded = false;

  @override
  bool get isAvailable => _loaded && FlutterGemma.hasActiveModel();

  @override
  Set<InferenceTask> get supportedTasks => const <InferenceTask>{
    InferenceTask.text,
    // JSON via prompt engineering; Gemma has no native constrained decoding,
    // so nativelyStructuredText is intentionally unsupported.
    InferenceTask.implicitlyStructuredText,
  };

  @override
  Future<void> load() async {
    if (_loaded && FlutterGemma.hasActiveModel()) return;
    await FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: preferredBackend,
    );
    _loaded = true;
  }

  @override
  Future<bool> refreshAvailability() async {
    try {
      return FlutterGemma.hasActiveModel();
    } catch (_) {
      return false;
    }
  }

  @override
  void resetAvailabilityCache() => _loaded = false;

  @override
  Stream<ProvisionProgress> get provisionProgress =>
      modelSetup.provisionProgress;

  @override
  Future<InferenceResult<ModelHandle>> ensureReady(
    final ModelPurpose purpose, {
    final ProvisionConstraints constraints = const ProvisionConstraints(),
    final GemmaPlatform? platform,
  }) async {
    final gemmaPurpose = switch (purpose.value) {
      'structured_tool_use' => GemmaPurpose.structuredToolUse,
      'chat_narrative' => GemmaPurpose.chatNarrative,
      'summarization' => GemmaPurpose.summarization,
      _ => null,
    };
    if (gemmaPurpose == null) {
      return InferenceResult<ModelHandle>.fail(
        code: 'model_not_found',
        message: 'Unknown Gemma purpose: ${purpose.value}',
      );
    }
    final result = await modelSetup.ensureReady(
      gemmaPurpose,
      constraints: constraints,
      platform: platform,
    );
    if (!result.success) {
      return InferenceResult<ModelHandle>.fail(
        code: result.error?.code ?? 'provision_failed',
        message: result.error?.message ?? 'Provisioning failed',
        details: result.error?.details,
      );
    }
    await load();
    return result;
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

    if (!await refreshAvailability()) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message:
            'No Gemma model active; call ensureReady or install via '
            'GemmaModelSetup first',
      );
    }

    try {
      final model = await FlutterGemma.getActiveModel(
        maxTokens: maxTokens,
        preferredBackend: preferredBackend,
      );
      var prompt = _buildPrompt(request);
      final wantsStructured =
          request.task == InferenceTask.implicitlyStructuredText;

      var attempt = 0;
      while (true) {
        final session = await model.createSession();
        try {
          await session.addQueryChunk(Message.text(text: prompt, isUser: true));
          final rawOutput = await session.getResponse();
          if (rawOutput.trim().isEmpty) {
            return InferenceResult<InferenceResponse>.fail(
              code: 'output_empty',
              message: 'Gemma produced no output',
              meta: <String, dynamic>{'provider': id},
            );
          }

          // Plain text task: no schema, no JSON parsing.
          if (!wantsStructured) {
            return InferenceResult<InferenceResponse>.ok(
              InferenceResponse(
                rawOutput: rawOutput,
                meta: <String, dynamic>{'provider': id},
              ),
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
          if (schemaValidation.success) {
            return InferenceResult<InferenceResponse>.ok(
              InferenceResponse(
                structuredOutput: parsed.data!,
                rawOutput: rawOutput,
                meta: <String, dynamic>{'provider': id},
              ),
              meta: <String, dynamic>{'provider': id},
            );
          }

          // One repair attempt: feed the validation error back to the model.
          if (attempt < maxRepairAttempts) {
            attempt++;
            final errorJson = const JsonEncoder.withIndent(
              '  ',
            ).convert(schemaValidation.error?.toJson());
            prompt =
                '${prompt.substring(0, _schemaInstructionStart(prompt))}'
                'Your previous reply failed validation:\n$errorJson\n'
                'Reply again with a single corrected JSON object.\n'
                '${prompt.substring(_schemaInstructionStart(prompt))}';
            continue;
          }

          return InferenceResult<InferenceResponse>.fail(
            code: schemaValidation.error?.code ?? 'schema_validation_failed',
            message:
                schemaValidation.error?.message ??
                'Gemma output does not match schema',
            details: schemaValidation.error?.details,
            meta: <String, dynamic>{'provider': id},
          );
        } finally {
          await session.close();
        }
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

  /// Builds the full prompt: system prompt, context fragments, user prompt,
  /// then the schema instruction.
  String _buildPrompt(final InferenceRequest request) {
    final buffer = StringBuffer();
    final systemPrompt = request.systemPrompt.trim();
    if (systemPrompt.isNotEmpty) {
      buffer
        ..writeln(systemPrompt)
        ..writeln();
    }
    final fragments = request.contextFragments;
    if (fragments.isNotEmpty) {
      buffer
        ..writeln('Context:')
        ..writeln(fragments.map(_fragmentToText).join('\n'))
        ..writeln();
    }
    buffer.write(request.prompt);
    if (request.task == InferenceTask.implicitlyStructuredText) {
      buffer
        ..writeln()
        ..writeln()
        ..writeln(
          'Respond with a single JSON object that conforms to this '
          'schema (no other text):',
        );
      buffer.writeln(
        const JsonEncoder.withIndent('  ').convert(request.outputSchema),
      );
    }
    return buffer.toString();
  }

  String _fragmentToText(final Object fragment) => switch (fragment) {
    final String text => text,
    final Map<String, dynamic> map => const JsonEncoder.withIndent(
      '  ',
    ).convert(map),
    final List<Object> list => list.map(_fragmentToText).join('\n'),
    final Object other => other.toString(),
  };

  /// Index where the trailing schema instruction begins, so repair prompts
  /// can be rebuilt without duplicating it.
  static final RegExp _schemaMarker = RegExp(
    r'Respond with a single JSON object',
  );

  int _schemaInstructionStart(final String prompt) =>
      _schemaMarker.firstMatch(prompt)?.start ?? prompt.length;

  String _truncate(final String value, {final int max = 2000}) {
    if (value.length <= max) return value;
    return '${value.substring(0, max)}...[truncated ${value.length - max} chars]';
  }
}
