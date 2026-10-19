import 'dart:async';
// ADR 0026: the client is PURE — it depends only on inference_core; the
// situation→messages codec lives in the harness and is composed above this
// transport (the client renders whatever `messages` arrive via the request
// fragments contract).
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// Model names for OpenRouter-backed models.
///
/// Register these in a [ModelRouter] alongside [DefaultModelNames] so an actor
/// can swap inference backends at runtime by changing its [ActorModel].
enum OpenRouterModelNames implements ModelName { openRouter }

/// Explicit caller qualification of the routed model's breakpoint dialect.
/// Unknown routes never inherit another provider's cache policy.
enum OpenRouterCacheBreakpointPolicy { unknown, anthropicEphemeral }

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
/// The chat-completions endpoint for a declared API root.
///
/// The root is the API VERSION path (`https://openrouter.ai/api/v1`, a
/// proxy's `https://gateway.internal/v1`); the operation is appended. A
/// root that already names the operation is used verbatim. The default root
/// yields exactly the historical endpoint, so an unconfigured client is
/// byte-identical to before.
Uri chatCompletionsUri(String baseUrl) {
  final trimmed = baseUrl.trim();
  if (trimmed.isEmpty) {
    return Uri.https('openrouter.ai', '/api/v1/chat/completions');
  }
  final root = Uri.parse(trimmed);
  final path = root.path;
  if (path.endsWith('/chat/completions')) return root;
  final suffix = path.endsWith('/') ? 'chat/completions' : '/chat/completions';
  return root.replace(path: '$path$suffix');
}

class OpenRouterInferenceClient implements InferenceClient {
  OpenRouterInferenceClient({
    this._apiKey = '',
    this.defaultModel = 'openai/gpt-4o-mini',
    this.baseUrl = 'https://openrouter.ai/api/v1',
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
    this.useMessagesCodec = true,
    this.onTransportDiagnostic,
    this.diagnosticCapture,
    this.cacheBreakpointPolicy = OpenRouterCacheBreakpointPolicy.unknown,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  static int _diagnosticClientCounter = 0;
  final String _diagnosticClientCohort =
      'openrouter-http-${++_diagnosticClientCounter}';

  final String _apiKey;
  final String defaultModel;

  /// The API root this client posts to (e.g. `https://openrouter.ai/api/v1`,
  /// or a proxy's `https://gateway.internal/v1`). The chat-completions
  /// endpoint is DERIVED from it, so a configured provider actually reaches
  /// its declared host instead of silently falling back to openrouter.ai.
  final String baseUrl;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Duration timeout;

  /// When true (default), projected context fragments are rendered into a
  /// native multi-turn `messages` array via [SituationMessagesCodec] instead
  /// of a flattened `CONTEXT:` block inside the single user message. The
  /// messages array is computed per call (codec, not state) — per
  /// ADR 0013, native chat-completions shape is the default; the legacy
  /// flattened path is kept only for the A/B against the old single-shot
  /// shape (fair-comparison plan Step 1).
  final bool useMessagesCodec;

  /// Optional observer for the exact HTTP request body at the transport
  /// boundary. Events omit headers and credentials. Observer errors are
  /// ignored so diagnostics cannot change inference behavior.
  final void Function(Map<String, Object?> event)? onTransportDiagnostic;

  /// Caller-owned generic observation; exact source bodies are opt-in only.
  final ContextTransportDiagnosticCapture? diagnosticCapture;

  /// A qualified cache dialect, independent of the transport's default model.
  final OpenRouterCacheBreakpointPolicy cacheBreakpointPolicy;

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
    InferenceRequest request, {
    ToolRegistry? toolRegistry,
  }) async {
    if (!supportedTasks.contains(request.task)) {
      return InferenceResult<InferenceResponse>.fail(
        code: errorCodeTaskUnsupported,
        message: 'Task ${request.task.name} is not supported by $id',
        details: <String, dynamic>{
          'supported_tasks': supportedTasks.map((task) => task.name).toList(),
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
    // Structured tasks: many OpenRouter models silently ignore
    // response_format=json_object — and the API itself requires the prompt to
    // mention "json" — so the schema is also spelled out in the system
    // message (same contract as PromptBuilder.writeStructuredOutputPrompt).
    final structured =
        request.task == InferenceTask.nativelyStructuredText &&
        request.outputSchema.isNotEmpty;
    var systemPrompt = request.systemPrompt;
    Map<String, dynamic>? jsonSchemaFormat;
    if (structured) {
      // Strict json_schema beats json_object: the API enforces the grammar
      // server-side instead of hoping the model cooperates.
      final schema = bundleToJsonSchema(
        SchemaBundle.fromJson(request.outputSchema),
      );
      jsonSchemaFormat = {
        'type': 'json_schema',
        'json_schema': {'name': 'response', 'strict': true, 'schema': schema},
      };
      final schemaJson = const JsonEncoder.withIndent('  ').convert(schema);
      systemPrompt =
          '$systemPrompt\n\n'
          'You must respond with ONLY a valid JSON object (no markdown, no '
          'prose, no code fences) matching this JSON schema:\n$schemaJson';
    }
    final messages = <Map<String, dynamic>>[
      if (systemPrompt.isNotEmpty) {'role': 'system', 'content': systemPrompt},
      if (useMessagesCodec)
        ...SituationMessagesCodec.render(
          prompt: request.prompt,
          systemPrompt: '', // already emitted as the system message above
          fragments: request.contextFragments,
        )
      else
        {'role': 'user', 'content': _buildUserContent(request)},
    ];

    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      if (request.maxTokens != null) 'max_tokens': request.maxTokens,
      if (request.temperature != null) 'temperature': request.temperature,
      if (toolRegistry != null &&
          toolRegistry.tools.isNotEmpty) ...<String, dynamic>{
        'tools': _buildTools(toolRegistry),
        'tool_choice': 'auto',
      },
      'response_format': ?jsonSchemaFormat,
    };

    final intentValue = request.metadata['context_cache_intent'];
    ContextCacheIntent intent;
    try {
      intent = intentValue == null
          ? ContextCacheIntent()
          : ContextCacheIntent.fromJson(
              Map<String, Object?>.from(intentValue as Map),
            );
      intent = ContextCacheIntent(
        writeAfterSegmentIds: intent.writeAfterSegmentIds
            .map(_wireCacheId)
            .toSet()
            .toList(),
        lookupAfterSegmentIds: intent.lookupAfterSegmentIds
            .map(_wireCacheId)
            .toSet()
            .toList(),
        policyId: intent.policyId,
      );
      if (request.metadata.containsKey(contextCacheComparisonMetadataKey)) {
        throw const FormatException('cache_comparison_unsupported');
      }
      _applyCacheIntent(body, intent, model);
      final session = InferenceSessionContext.fromRequest(request)?.session;
      if (session != null) {
        body['session_id'] = session.effectiveAffinityKey;
        body['prompt_cache_key'] = session.effectiveCacheGroup;
      }
    } on FormatException catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: error.message,
        message: 'Cache intent is unsupported for this route',
      );
    } on Object {
      return InferenceResult<InferenceResponse>.fail(
        code: 'cache_intent_invalid',
        message: 'Invalid cache intent',
      );
    }

    Map<String, dynamic>? diagnosticResponse;
    int? diagnosticHttpStatus;
    var safeError = <String, Object?>{};
    var diagnosticOutcome = 'failed';
    var transport = <String, Object?>{};
    try {
      final uri = chatCompletionsUri(baseUrl);
      final encodedBody = jsonEncode(body);
      final headers = <String, String>{
        'authorization': 'Bearer $_apiKey',
        'content-type': 'application/json',
        'accept': 'application/json',
      };
      if (diagnosticCapture != null) {
        transport = captureContextTransportMetadata(
          endpoint: uri,
          method: 'POST',
          requestHeaders: headers,
          requestBody: body,
          clientCohort: _diagnosticClientCohort,
          followRedirects: true,
        );
      }
      _diagnostic(
        body,
        intent,
        model,
        ContextTransportDiagnosticStage.request,
        encodedBody: encodedBody,
        transport: transport,
      );
      _notifyTransportDiagnostic(<String, Object?>{
        'type': 'openrouter.post',
        'uri': uri.toString(),
        'body': encodedBody,
        'metadata': Map<String, Object?>.from(request.metadata),
      });
      final response = await _httpClient
          .post(uri, headers: headers, body: encodedBody)
          .timeout(timeout);
      if (diagnosticCapture != null) {
        transport = captureContextTransportMetadata(
          endpoint: uri,
          method: 'POST',
          requestHeaders: headers,
          requestBody: body,
          clientCohort: _diagnosticClientCohort,
          followRedirects: true,
          responseHeaders: response.headers,
        );
      }
      diagnosticHttpStatus = response.statusCode;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        diagnosticOutcome = 'http_${response.statusCode}';
        if (response.statusCode != 401 &&
            response.statusCode != 429 &&
            utf8.encode(response.body).length <= 16 * 1024) {
          try {
            final errorBody = jsonDecode(response.body);
            safeError = {
              if (errorBody is Map && errorBody['error'] is Map)
                ..._safeHttpError(errorBody['error'] as Map, body),
              'messageHint': contextProviderErrorMessageHint(errorBody),
            };
          } on Object {
            /* Untrusted error bodies do not become diagnostics. */
          }
        }
        return InferenceResult<InferenceResponse>.fail(
          code: _mapHttpStatus(response.statusCode),
          message: _errorMessage(response.body),
          details: <String, dynamic>{
            'http_status': response.statusCode,
            'body': response.body,
          },
          meta: <String, dynamic>{
            'provider': id,
            'model': model,
            if (diagnosticCapture != null && safeError.isNotEmpty)
              'provider_error': safeError,
          },
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
      diagnosticResponse = decoded;

      final parsed = _parseChatCompletion(decoded);
      if (parsed == null) {
        return InferenceResult<InferenceResponse>.fail(
          code: 'output_empty',
          message: 'OpenRouter returned no completion content',
          meta: <String, dynamic>{'provider': id},
        );
      }

      diagnosticOutcome = 'completed';
      return InferenceResult<InferenceResponse>.ok(
        parsed,
        meta: <String, dynamic>{'provider': id, 'model': model},
      );
    } on TimeoutException catch (_) {
      diagnosticOutcome = 'timeout';
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'OpenRouter request timed out',
        meta: <String, dynamic>{'provider': id},
      );
    } on SocketException catch (error) {
      diagnosticOutcome = 'transport_error';
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
    } finally {
      _diagnostic(
        body,
        intent,
        model,
        ContextTransportDiagnosticStage.settled,
        response: diagnosticResponse,
        outcome: diagnosticOutcome,
        httpStatus: diagnosticHttpStatus,
        safeError: safeError,
        transport: transport,
      );
    }
  }

  static String _wireCacheId(String id) =>
      id.replaceFirst(RegExp(r'^context(?=\[)'), 'messages');

  void _applyCacheIntent(
    Map<String, dynamic> body,
    ContextCacheIntent intent,
    String model,
  ) {
    if (intent.writeAfterSegmentIds.isEmpty &&
        intent.lookupAfterSegmentIds.isEmpty) {
      return;
    }
    if (cacheBreakpointPolicy !=
            OpenRouterCacheBreakpointPolicy.anthropicEphemeral ||
        !model.startsWith('anthropic/')) {
      throw const FormatException('cache_breakpoint_support_unknown');
    }
    if (intent.writeAfterSegmentIds.length > 4) {
      throw const FormatException('cache_breakpoint_limit');
    }
    for (final id in intent.lookupAfterSegmentIds) {
      if (!intent.writeAfterSegmentIds.contains(id)) {
        throw const FormatException('cache_lookup_intent_unsupported');
      }
    }
    final messages = body['messages'] as List;
    for (final id in intent.writeAfterSegmentIds) {
      final match = RegExp(r'^messages\[(\d+)\](?:\.content\[(\d+)\])?$')
          .firstMatch(id);
      if (match == null) {
        throw const FormatException('cache_breakpoint_invalid');
      }
      final index = int.parse(match[1]!);
      if (index >= messages.length) {
        throw const FormatException('cache_breakpoint_invalid');
      }
      final item = Map<String, dynamic>.from(messages[index] as Map);
      final content = item['content'];
      final parts = content is String
          ? <dynamic>[
              {'type': 'text', 'text': content},
            ]
          : content is List
          ? List<dynamic>.of(content)
          : null;
      if (parts == null || parts.isEmpty) {
        throw const FormatException('cache_breakpoint_invalid');
      }
      final partIndex = match[2] == null
          ? parts.length - 1
          : int.parse(match[2]!);
      if (partIndex >= parts.length || parts[partIndex] is! Map) {
        throw const FormatException('cache_breakpoint_invalid');
      }
      final part = Map<String, dynamic>.from(parts[partIndex] as Map);
      if (part['type'] != 'text' || part['text'] is! String) {
        throw const FormatException('cache_breakpoint_invalid');
      }
      part['cache_control'] = {'type': 'ephemeral'};
      parts[partIndex] = part;
      item['content'] = parts;
      messages[index] = item;
    }
  }

  void _diagnostic(
    Map<String, dynamic> body,
    ContextCacheIntent intent,
    String model,
    ContextTransportDiagnosticStage stage, {
    String? encodedBody,
    Map<String, dynamic>? response,
    String? outcome,
    int? httpStatus,
    Map<String, Object?> safeError = const {},
    Map<String, Object?> transport = const {},
  }) {
    final capture = diagnosticCapture;
    if (capture == null) return;
    try {
      final reported = response?.containsKey('usage') ?? false;
      final raw = response?['usage'];
      final usage = <String, int>{};
      void keep(String key, Object? value) {
        if (value is int && value >= 0) usage[key] = value;
      }

      if (raw is Map) {
        for (final key in [
          'prompt_tokens',
          'completion_tokens',
          'total_tokens',
        ]) {
          keep(key, raw[key]);
        }
        final details = raw['prompt_tokens_details'];
        if (details is Map) {
          keep('cached_tokens', details['cached_tokens']);
          keep('cache_write_tokens', details['cache_write_tokens']);
        }
      }
      const policy = 'openrouter-anthropic-explicit-ephemeral';
      const provenance = [
        'https://openrouter.ai/docs/guides/best-practices/prompt-caching',
      ];
      final snapshot = ContextCacheAnalyzer.captureJsonRequest(
        body,
        messageListPath: ['messages'],
        representationId: 'openrouter-chat-json-utf8-v1',
        exactWire: true,
        compatibility: ContextRequestCompatibility(provider: id, model: model),
        writeEndpoints: [
          for (final id in intent.writeAfterSegmentIds)
            CacheWriteEndpoint(
              afterSegmentId: id,
              policyId: policy,
              support: ContextCacheSupport.known,
              provenanceRefs: provenance,
            ),
        ],
        lookupEndpoints: [
          for (final id in {
            ...intent.lookupAfterSegmentIds,
            ...intent.writeAfterSegmentIds,
          })
            CacheLookupEndpoint(
              afterSegmentId: id,
              policyId: policy,
              support: ContextCacheSupport.known,
              provenanceRefs: provenance,
            ),
        ],
        usage: reported
            ? ContextCacheUsage(
                inputTokens: usage['prompt_tokens'],
                cachedTokens: usage['cached_tokens'],
                cacheWriteTokens: usage['cache_write_tokens'],
                outputTokens: usage['completion_tokens'],
              )
            : null,
      );
      capture.observer(
        ContextTransportDiagnosticEvent(
          stage: stage,
          snapshot: snapshot,
          exactEncodedBody: capture.includeEncodedBody && snapshot.exactWire
              ? encodedBody
              : null,
          usageReported: reported,
          numericUsage: usage,
          responseId: _safeIdentifier(response?['id']),
          model: _safeIdentifier(response?['model']) ?? model,
          serviceTier: _safeIdentifier(response?['service_tier']),
          outcome: outcome,
          httpStatus: httpStatus,
          transport: transport,
          providerErrorCode: safeError['code'] as String?,
          providerErrorType: safeError['type'] as String?,
          providerErrorParam: safeError['param'] as String?,
          providerErrorMessageHint:
              (safeError['messageHint'] as Map?)?.cast<String, Object?>() ??
              const {},
          providerErrorFieldPresence:
              (safeError['presence'] as Map?)?.cast<String, bool>() ?? const {},
        ),
      );
    } on Object {
      // Observation has no inference or transport authority.
    }
  }

  static String? _safeIdentifier(Object? value) =>
      value is String && RegExp(r'^[a-zA-Z0-9_.:/-]{1,160}$').hasMatch(value)
      ? value
      : null;

  static Map<String, Object?> _safeHttpError(
    Map error,
    Map<String, dynamic> request,
  ) => {
    'presence': {
      for (final key in ['code', 'type', 'param']) key: error.containsKey(key),
    },
    'code':
        error['code'] is int &&
            const [
              400,
              401,
              402,
              403,
              404,
              408,
              413,
              422,
              429,
              500,
              502,
              503,
              504,
              529,
            ].contains(error['code'])
        ? '${error['code']}'
        : const [
            'invalid_request_error',
            'invalid_value',
            'unsupported_parameter',
            'unsupported_value',
            'unknown_parameter',
            'invalid_json_schema',
            'model_not_found',
            'context_length_exceeded',
            'insufficient_quota',
            'rate_limit_exceeded',
            'invalid_api_key',
            'permission_denied',
            'bad_request',
          ].contains(error['code'])
        ? error['code']
        : null,
    'type':
        const [
          'invalid_request_error',
          'authentication_error',
          'permission_error',
          'rate_limit_error',
          'api_error',
          'server_error',
          'not_found_error',
          'bad_request_error',
        ].contains(error['type'])
        ? error['type']
        : null,
    'param': _requestParam(error['param'], request),
  };

  static String? _requestParam(Object? value, Map<String, dynamic> request) {
    if (value is! String ||
        value.length > 160 ||
        !RegExp(
          r'^[a-zA-Z_][a-zA-Z0-9_]*(?:(?:\.[a-zA-Z_][a-zA-Z0-9_]*)|(?:\[\d{1,6}\]))*$',
        ).hasMatch(value)) {
      return null;
    }
    Object? node = request;
    for (final match in RegExp(
      r'([a-zA-Z_][a-zA-Z0-9_]*)|\[(\d+)\]',
    ).allMatches(value)) {
      if (match[1] case final key?) {
        if (node is! Map || !node.containsKey(key)) return null;
        node = node[key];
      } else {
        final index = int.parse(match[2]!);
        if (node is! List || index >= node.length) return null;
        node = node[index];
      }
    }
    return value;
  }

  void _notifyTransportDiagnostic(Map<String, Object?> event) {
    try {
      onTransportDiagnostic?.call(event);
    } on Object {
      // Diagnostic observers are explicitly non-authoritative.
    }
  }

  String _resolveModel(InferenceRequest request) {
    final metadataModel = request.metadata['model'];
    if (metadataModel is String && (metadataModel).isNotEmpty) {
      return metadataModel;
    }
    return defaultModel;
  }

  String _buildUserContent(InferenceRequest request) {
    final context = request.contextFragmentsJson;
    if (context.isEmpty) return request.prompt;
    // TODO(arenukvern): this is wrong - and should be rewritten to messages
    // (completion api)
    return '${request.prompt}\n\nCONTEXT:\n$context';
  }

  List<Map<String, dynamic>> _buildTools(ToolRegistry registry) {
    final functions = <Map<String, dynamic>>[];
    for (var MapEntry(key: name, value: tool) in registry.tools.entries) {
      functions.add(<String, dynamic>{
        'type': 'function',
        'function': {
          'name': name.value,
          'description': tool.description,
          // Providers require standard JSON Schema here — the internal
          // kind-tagged format is meaningless to them and silently breaks
          // argument generation.
          'parameters': bundleToJsonSchema(tool.argsSchema),
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
  InferenceResponse? _parseChatCompletion(Map<String, dynamic> decoded) {
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
    final parsedCalls = <ToolCall>[];
    if (toolCalls is List) {
      for (final call in toolCalls) {
        if (call is! Map<String, dynamic>) continue;
        final fnMap = (call)['function'];
        if (fnMap is! Map<String, dynamic>) continue;
        final name = fnMap['name'];
        final arguments = fnMap['arguments'];
        if (name is! String) continue;
        parsedCalls.add(
          ToolCall(name: ToolName(name), arguments: _parseArguments(arguments)),
        );
      }
    }

    final output = <String, dynamic>{};

    // ignore: avoid_print
    if (contentStr.isEmpty && parsedCalls.isEmpty) {
      print(
        '[OR-DBG] empty completion; messageKeys=${messageMap.keys.toList()} '
        'content=${content == null ? '<null>' : jsonEncode(content)} '
        'finish=${first['finish_reason']}',
      );
    }

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
        'usage_reported': decoded.containsKey('usage'),
        'usage_field_presence': {
          if (decoded['usage'] case final Map usage) ...{
            for (final key in [
              'prompt_tokens',
              'completion_tokens',
              'total_tokens',
              'prompt_tokens_details',
            ])
              key: usage.containsKey(key),
            for (final key in ['cached_tokens', 'cache_write_tokens'])
              'prompt_tokens_details.$key':
                  usage['prompt_tokens_details'] is Map &&
                  (usage['prompt_tokens_details'] as Map).containsKey(key),
          },
        },
        'response_field_presence': {
          for (final key in ['id', 'model', 'service_tier'])
            key: decoded.containsKey(key),
        },
        if (diagnosticCapture != null) ...{
          'response_id': ?_safeIdentifier(decoded['id']),
          'response_model': ?_safeIdentifier(decoded['model']),
          'service_tier': ?_safeIdentifier(decoded['service_tier']),
        },
        // Provider-reported token usage passes through as reported; honest
        // absence when the API response carries none.
        if (decoded['usage'] is Map<String, dynamic>)
          'usage': decoded['usage'] as Map<String, dynamic>,
      },
    );
  }

  /// Parse a tool call's `arguments` (a JSON string from OpenRouter) into a map.
  Map<String, dynamic> _parseArguments(Object? arguments) {
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

  String _mapHttpStatus(int statusCode) => switch (statusCode) {
    401 || 403 => 'auth_failed',
    429 => 'rate_limited',
    >= 500 => 'engine_unavailable',
    _ => 'http_error',
  };

  String _errorMessage(String body) {
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
