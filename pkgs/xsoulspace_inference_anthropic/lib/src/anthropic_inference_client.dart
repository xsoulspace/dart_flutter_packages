import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// Model names for Anthropic-backed models.
///
/// Register these in a [ModelRouter] alongside [DefaultModelNames] so an actor
/// can swap inference backends at runtime by changing its [ActorModel].
enum AnthropicModelNames implements ModelName { anthropic }

/// Anthropic Messages API-backed [InferenceClient].
///
/// Calls `POST /v1/messages` with the `x-api-key` and `anthropic-version`
/// headers. Supports free text, best-effort structured output (schema spelled
/// out in the system prompt — Anthropic has no server-enforced
/// `response_format`), and native tool calling via `tool_use` content blocks.
///
/// ## Required generation budget
///
/// The Messages API requires `max_tokens` on every request. This client takes
/// it from [InferenceRequest.maxTokens]; when absent the request is rejected
/// with the named code `missing_max_tokens` instead of inventing a
/// provider-specific default. [InferenceRequest.temperature] and
/// [InferenceRequest.stopSequences] pass through when set.
///
/// ## Tool calls
///
/// Anthropic returns `tool_use` content blocks. This client parses them and
/// re-emits them as [InferenceResponse.toolCalls]; it never executes tools —
/// the harness routes them the same way as every other backend. Streaming
/// (SSE) is not implemented yet; the wire client is request/response only.
class AnthropicInferenceClient implements InferenceClient {
  AnthropicInferenceClient({
    final String apiKey = '',
    this.defaultModel = 'claude-sonnet-4-5',
    this.baseUrl = 'https://api.anthropic.com',
    this.anthropicVersion = '2023-06-01',
    final http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
    this.useMessagesCodec = true,
    this.onTransportDiagnostic,
    // A named parameter cannot spell the private initializing formal.
    // ignore: prefer_initializing_formals
  }) : _apiKey = apiKey,
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  final String _apiKey;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  /// Fallback model when the request metadata carries no `model` override.
  final String defaultModel;
  final String baseUrl;
  final String anthropicVersion;
  final Duration timeout;

  /// When true (default), projected context fragments are rendered into a
  /// native multi-turn `messages` array via [SituationMessagesCodec] instead
  /// of a flattened `CONTEXT:` block inside the single user message.
  final bool useMessagesCodec;

  /// Opt-in observer for exact POST bodies at the HTTP transport boundary.
  /// Events contain request metadata but no credentials. Observer exceptions
  /// are ignored.
  final void Function(Map<String, Object?> event)? onTransportDiagnostic;

  static const String _messagesPath = '/v1/messages';

  @override
  String get id => 'anthropic_messages';

  @override
  bool get isAvailable => _apiKey.isNotEmpty;

  @override
  Set<InferenceTask> get supportedTasks => const <InferenceTask>{
    InferenceTask.text,
    InferenceTask.implicitlyStructuredText,
    InferenceTask.nativelyStructuredText,
  };

  @override
  Future<bool> refreshAvailability() async => isAvailable;

  @override
  Future<void> load() async {}

  @override
  void resetAvailabilityCache() {}

  /// Closes the owned HTTP client, if this client created one.
  Future<void> dispose() async {
    if (_ownsHttpClient) _httpClient.close();
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
        message: '$id requires an Anthropic API key for HTTP inference',
      );
    }

    final maxTokens = request.maxTokens;
    if (maxTokens == null) {
      // The Messages API rejects requests without max_tokens. The neutral
      // request makes the budget explicit; inventing a provider default here
      // would silently truncate generations.
      return InferenceResult<InferenceResponse>.fail(
        code: 'missing_max_tokens',
        message:
            'Anthropic requires an explicit max_tokens budget; set '
            'InferenceRequest.maxTokens',
      );
    }

    final model = _resolveModel(request);

    final structured =
        request.task == InferenceTask.nativelyStructuredText &&
        request.outputSchema.isNotEmpty;
    var systemPrompt = request.systemPrompt;
    if (structured) {
      // Anthropic has no server-enforced response_format; the schema is
      // spelled out in the system message (same contract as
      // PromptBuilder.writeStructuredOutputPrompt) and the reply is parsed
      // best-effort.
      final schema = bundleToJsonSchema(
        SchemaBundle.fromJson(request.outputSchema),
      );
      final schemaJson = const JsonEncoder.withIndent('  ').convert(schema);
      systemPrompt =
          '$systemPrompt\n\n'
          'You must respond with ONLY a valid JSON object (no markdown, no '
          'prose, no code fences) matching this JSON schema:\n$schemaJson';
    }

    final messages = <Map<String, dynamic>>[
      if (useMessagesCodec)
        ...SituationMessagesCodec.render(
          prompt: request.prompt,
          systemPrompt: '', // emitted as the top-level system parameter
          fragments: request.contextFragments,
        )
      else
        {'role': 'user', 'content': _buildUserContent(request)},
    ];

    final body = <String, dynamic>{
      'model': model,
      'max_tokens': maxTokens,
      if (systemPrompt.isNotEmpty) 'system': systemPrompt,
      'messages': messages,
      if (request.temperature != null) 'temperature': request.temperature,
      if (request.stopSequences.isNotEmpty)
        'stop_sequences': request.stopSequences,
      if (toolRegistry != null && toolRegistry.tools.isNotEmpty) ...<
        String, dynamic
      >{
        'tools': _buildTools(toolRegistry),
      },
    };

    try {
      final uri = Uri.parse('$baseUrl$_messagesPath');
      final encodedBody = jsonEncode(body);
      _notifyTransportDiagnostic(<String, Object?>{
        'type': 'anthropic.messages.post',
        'uri': uri.toString(),
        'body': encodedBody,
        'metadata': Map<String, Object?>.from(request.metadata),
      });
      final response = await _httpClient
          .post(
            uri,
            headers: <String, String>{
              'x-api-key': _apiKey,
              'anthropic-version': anthropicVersion,
              'content-type': 'application/json',
              'accept': 'application/json',
            },
            body: encodedBody,
          )
          .timeout(timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return InferenceResult<InferenceResponse>.fail(
          code: _mapHttpStatus(response.statusCode),
          message: _errorMessage(response.body, response.statusCode),
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
          message: 'Anthropic returned a non-object response',
          meta: <String, dynamic>{'provider': id},
        );
      }

      final parsed = _parseMessage(decoded);
      if (parsed == null) {
        return InferenceResult<InferenceResponse>.fail(
          code: 'output_empty',
          message: 'Anthropic returned no message content',
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
        message: 'Anthropic request timed out',
        meta: <String, dynamic>{'provider': id},
      );
    } on SocketException catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'Anthropic network connection failed',
        details: error.toString(),
        meta: <String, dynamic>{'provider': id},
      );
    } catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'Anthropic request failed unexpectedly',
        details: error.toString(),
        meta: <String, dynamic>{'provider': id},
      );
    }
  }

  void _notifyTransportDiagnostic(Map<String, Object?> event) {
    try {
      onTransportDiagnostic?.call(event);
    } on Object {
      // Diagnostic observers are explicitly non-authoritative.
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
    return '${request.prompt}\n\nCONTEXT:\n$context';
  }

  List<Map<String, dynamic>> _buildTools(final ToolRegistry registry) {
    final tools = <Map<String, dynamic>>[];
    for (var MapEntry(key: name, value: tool) in registry.tools.entries) {
      tools.add(<String, dynamic>{
        'name': name.value,
        'description': tool.description,
        // Standard JSON Schema — the internal kind-tagged format is
        // meaningless to the API and silently breaks argument generation.
        'input_schema': bundleToJsonSchema(tool.argsSchema),
      });
    }
    return tools;
  }

  /// Parse a Messages API response into an [InferenceResponse].
  ///
  /// Concatenates `text` content blocks and extracts native `tool_use`
  /// blocks as structured [ToolCall] records; the harness routes them to the
  /// world's tool execution system directly.
  InferenceResponse? _parseMessage(final Map<String, dynamic> decoded) {
    final content = decoded['content'];
    if (content is! List) return null;

    final textBuffer = StringBuffer();
    final parsedCalls = <ToolCall>[];
    for (final block in content) {
      if (block is! Map<String, dynamic>) continue;
      switch (block['type']) {
        case 'text':
          final text = block['text'];
          if (text is String) textBuffer.write(text);
        case 'tool_use':
          final name = block['name'];
          if (name is! String) continue;
          parsedCalls.add(
            ToolCall(
              name: ToolName(name),
              arguments: _parseArguments(block['input']),
            ),
          );
      }
    }

    final contentStr = textBuffer.toString();
    if (contentStr.isEmpty && parsedCalls.isEmpty) return null;

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
      meta: <String, dynamic>{
        'provider': id,
        'stop_reason': ?decoded['stop_reason'],
        if (decoded['usage'] is Map<String, dynamic>)
          'usage': decoded['usage'] as Map<String, dynamic>,
      },
    );
  }

  Map<String, dynamic> _parseArguments(final Object? input) {
    if (input is Map<String, dynamic>) return input;
    if (input is Map) {
      return input.map((k, v) => MapEntry('$k', v));
    }
    return <String, dynamic>{};
  }

  String _mapHttpStatus(final int statusCode) => switch (statusCode) {
    401 || 403 => 'auth_failed',
    429 => 'rate_limited',
    >= 500 => 'engine_unavailable',
    _ => 'http_error',
  };

  String _errorMessage(final String body, final int statusCode) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          final message = error['message'];
          if (message is String) return message;
        }
      }
    } catch (_) {
      // Fall through to the status-line message.
    }
    return 'Anthropic request failed with HTTP $statusCode';
  }
}
