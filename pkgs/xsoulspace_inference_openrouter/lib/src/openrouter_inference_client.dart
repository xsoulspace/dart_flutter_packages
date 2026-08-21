import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// Model names for OpenRouter-backed models.
///
/// Register these in a [ModelRouter] alongside [DefaultModelNames] so an actor
/// can swap inference backends at runtime by changing its [ActorModel].
enum OpenRouterModelNames implements ModelName { openRouter }

/// OpenRouter API-backed [InferenceClient].
///
/// Calls the OpenRouter `/chat/completions` endpoint. Supports free text and
/// structured output (via `response_format: {type: "json_object"}`), and
/// native tool calling.
///
/// ## Tool calls
///
/// OpenRouter returns native `tool_calls` in the response JSON. This client
/// parses them and re-emits them as
/// [InferenceResponse.toolCalls], so the harness's
/// [DefaultGenerationHandler] could route
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
    if (metadataModel is String && (metadataModel).isNotEmpty) {
      return metadataModel;
    }
    return defaultModel;
  }

  String _buildUserContent(final InferenceRequest request) {
    final context = request.contextFragmentsJson;
    if (context.isEmpty) return request.prompt;
    // TODO(arenukvern): this is wrong - and should be rewritten to messages
    // (completion api)
    return '${request.prompt}\n\nCONTEXT:\n$context';
  }

  List<Map<String, dynamic>> _buildTools(final ToolRegistry registry) {
    final functions = <Map<String, dynamic>>[];
    for (var MapEntry(key: name, value: tool) in registry.tools.entries) {
      functions.add(<String, dynamic>{
        'type': 'function',
        'function': {
          'name': name.value,
          'description': tool.description,
          'parameters': tool.argsSchema.toJson(),
        },
      });
    }

    return functions;
  }

  /// Parse the OpenRouter chat completion response into an [InferenceResponse].
  ///
  /// Extracts the assistant message content and any native `tool_calls`.
  /// Tool calls are returned as structured records on
  /// [InferenceResponse.toolCalls] — no tag round-trip. The harness routes
  /// them to the world's tool execution system directly.
  InferenceResponse? _parseChatCompletion(final Map<String, dynamic> decoded) {
    final choices = decoded['choices'];
    if (choices is! List) return null;
    final first = (choices).firstOrNull;
    if (first is! Map<String, dynamic>) return null;

    final messageMap = (first)['message'];
    if (messageMap is! Map<String, dynamic>) return null;

    final content = messageMap['content'];
    final contentStr = content is String ? content : '';

    // Extract native tool_calls as structured records.
    final toolCalls = messageMap['tool_calls'];
    final parsedCalls = <({String name, Map<String, dynamic> arguments})>[];
    if (toolCalls is List) {
      for (final call in toolCalls) {
        if (call is! Map<String, dynamic>) continue;
        final fnMap = (call)['function'];
        if (fnMap is! Map<String, dynamic>) continue;
        final name = fnMap['name'];
        final arguments = fnMap['arguments'];
        if (name is! String) continue;
        parsedCalls.add((name: name, arguments: _parseArguments(arguments)));
      }
    }

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
      structuredOutput: output,
      rawOutput: contentStr,
      task: InferenceTask.text,
      toolCalls: parsedCalls,
      meta: <String, dynamic>{'provider': id},
    );
  }

  /// Parse a tool call's `arguments` (a JSON string from OpenRouter) into a map.
  Map<String, dynamic> _parseArguments(final Object? arguments) {
    if (arguments is Map<String, dynamic>) return arguments;
    if (arguments is Map) {
      return arguments.map((k, v) => MapEntry('$k', v));
    }
    if (arguments is String) {
      final trimmed = (arguments).trim();
      if (trimmed.isEmpty) return <String, dynamic>{};
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry('$k', v));
        }
      } catch (_) {
        // Fall through to empty.
      }
    }
    return <String, dynamic>{};
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
        final error = (decoded)['error'];
        if (error is Map<String, dynamic>) {
          final message = (error)['message'];
          if (message is String) return message;
        }
      }
    } catch (_) {
      // Fall through to raw body.
    }
    return 'OpenRouter request failed with status $body';
  }
}
