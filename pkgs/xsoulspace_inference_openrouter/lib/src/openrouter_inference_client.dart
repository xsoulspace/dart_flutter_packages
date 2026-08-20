import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// OpenRouter API-backed [InferenceClient].
///
/// Calls the OpenRouter `/chat/completions` endpoint. Supports free text and
/// structured output (via `response_format: {type: "json_object"}`), and
/// native tool calling.
///
/// ## Tool calls
///
/// OpenRouter returns native `tool_calls` in the response JSON. This client
/// parses them and re-emits them in the tag format (`<call|name|{json}>`) in
/// [InferenceResponse.rawOutput], so the harness's
/// [DefaultGenerationHandler] picks them up via `parseToolCalls` and routes
/// them to the world's `toolExecutionSystem` — the same path as raw LLM
/// backends. The client never executes tools itself.
class OpenRouterInferenceClient implements InferenceClient {
  OpenRouterInferenceClient({
    required this._apiKey,
    this.defaultModel = 'openai/gpt-4o-mini',
    this.baseUrl = 'https://openrouter.ai/api/v1',
    final http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  final String _apiKey;
  final String defaultModel;
  final String baseUrl;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Duration timeout;

  @override
  Future<void> load() async {
    // No model download needed — OpenRouter is a hosted API.
  }

  @override
  String get id => 'openrouter';

  @override
  bool get isAvailable => _apiKey.isNotEmpty;

  @override
  Set<InferenceTask> get supportedTasks => const <InferenceTask>{
    InferenceTask.text,
    InferenceTask.nativelyStructuredText,
  };

  @override
  Future<bool> refreshAvailability() async => isAvailable;

  @override
  void resetAvailabilityCache() {
    // No availability cache; API key checks happen during infer.
  }

  Future<void> dispose() async {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
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

    if (_apiKey.isEmpty) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'auth_failed',
        message: '$id requires an OpenRouter API key for HTTP inference',
      );
    }

    final model = _resolveModel(request);

    // Build the messages array. The actor's context fragments are appended as
    // a trailing user message so the model sees the projected context.
    final messages = <Map<String, dynamic>>[
      if (request.systemPrompt.isNotEmpty)
        {'role': 'system', 'content': request.systemPrompt},
      {'role': 'user', 'content': _buildUserContent(request)},
    ];

    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      if (request.task == InferenceTask.nativelyStructuredText &&
          request.outputSchema.isNotEmpty)
        'response_format': {'type': 'json_object'},
      if (toolRegistry != null && toolRegistry.tools.isNotEmpty)
        'tools': _buildTools(toolRegistry),
    };

    try {
      final response = await _httpClient
          .post(
            Uri.https('openrouter.ai', '/api/v1/chat/completions'),
            headers: <String, String>{
              'authorization': 'Bearer $_apiKey',
              'content-type': 'application/json',
              'accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return InferenceResult<InferenceResponse>.fail(
          code: _mapHttpStatus(response.statusCode),
          message: _errorMessage(response.body),
          details: <String, dynamic>{
            'http_status': response.statusCode,
            'body': response.body,
          },
          meta: <String, dynamic>{'provider': id, 'model': model},
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return InferenceResult<InferenceResponse>.fail(
          code: 'json_parse_failed',
          message: 'OpenRouter returned a non-object response',
          meta: <String, dynamic>{'provider': id},
        );
      }

      final parsed = _parseChatCompletion(decoded);
      if (parsed == null) {
        return InferenceResult<InferenceResponse>.fail(
          code: 'output_empty',
          message: 'OpenRouter returned no completion content',
          meta: <String, dynamic>{'provider': id},
        );
      }

      return InferenceResult<InferenceResponse>.ok(
        parsed,
        meta: <String, dynamic>{'provider': id, 'model': model},
      );
    } on TimeoutException catch (_) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'OpenRouter request timed out',
        meta: <String, dynamic>{'provider': id},
      );
    } on SocketException catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'OpenRouter network connection failed',
        details: error.toString(),
        meta: <String, dynamic>{'provider': id},
      );
    } catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'OpenRouter request failed unexpectedly',
        details: error.toString(),
        meta: <String, dynamic>{'provider': id},
      );
    }
  }

  String _resolveModel(final InferenceRequest request) {
    final metadataModel = request.metadata['model'];
    if (metadataModel is String && (metadataModel as String).isNotEmpty) {
      return metadataModel as String;
    }
    return defaultModel;
  }

  String _buildUserContent(final InferenceRequest request) {
    final context = request.contextFragmentsJson;
    if (context.isEmpty) return request.prompt;
    return '${request.prompt}\n\nCONTEXT:\n$context';
  }

  List<Map<String, dynamic>> _buildTools(final ToolRegistry registry) {
    return registry.getToolsJsons().map((tool) {
      final name = tool['name'];
      final nameStr = name is ToolName ? (name as ToolName).value : '$name';
      return <String, dynamic>{
        'type': 'function',
        'function': {
          'name': nameStr,
          'description': tool['description'],
          'parameters': tool['parameters'],
        },
      };
    }).toList();
  }

  /// Parse the OpenRouter chat completion response into an [InferenceResponse].
  ///
  /// Extracts the assistant message content and any native `tool_calls`.
  /// Tool calls are re-emitted as `<call|name|{json}>` tags in `rawOutput`
  /// so the harness's `parseToolCalls` can route them to the world.
  InferenceResponse? _parseChatCompletion(final Map<String, dynamic> decoded) {
    final choices = decoded['choices'];
    if (choices is! List) return null;
    final first = (choices as List).firstOrNull;
    if (first is! Map<String, dynamic>) return null;

    final messageMap = (first as Map<String, dynamic>)['message'];
    if (messageMap is! Map<String, dynamic>) return null;

    final content = messageMap['content'];
    final contentStr = content is String ? content as String : '';

    // Extract native tool_calls and re-emit as tags.
    final toolCalls = messageMap['tool_calls'];
    final toolTags = <String>[];
    if (toolCalls is List) {
      for (final call in toolCalls as List) {
        if (call is! Map<String, dynamic>) continue;
        final fnMap = (call as Map<String, dynamic>)['function'];
        if (fnMap is! Map<String, dynamic>) continue;
        final name = fnMap['name'];
        final arguments = fnMap['arguments'];
        if (name is! String) continue;
        toolTags.add(
          '<call|${name as String}|${arguments is String ? arguments as String : '{}'}>',
        );
      }
    }

    final rawOutput = contentStr.isEmpty && toolTags.isNotEmpty
        ? toolTags.join()
        : contentStr;

    final output = <String, dynamic>{};
    if (contentStr.isNotEmpty) {
      // For structured tasks, try to parse the content as JSON.
      final parsed = parseStrictJsonObject(contentStr);
      if (parsed.success && parsed.data != null) {
        output.addAll(parsed.data!);
      } else {
        output['text'] = contentStr;
      }
    }

    return InferenceResponse(
      output: output,
      rawOutput: rawOutput,
      task: InferenceTask.text,
      meta: <String, dynamic>{'provider': id},
    );
  }

  String _mapHttpStatus(final int statusCode) => switch (statusCode) {
    401 || 403 => 'auth_failed',
    429 => 'rate_limited',
    >= 500 => 'engine_unavailable',
    _ => 'http_error',
  };

  String _errorMessage(final String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = (decoded as Map<String, dynamic>)['error'];
        if (error is Map<String, dynamic>) {
          final message = (error as Map<String, dynamic>)['message'];
          if (message is String) return message as String;
        }
      }
    } catch (_) {
      // Fall through to raw body.
    }
    return 'OpenRouter request failed with status ${body}';
  }
}
