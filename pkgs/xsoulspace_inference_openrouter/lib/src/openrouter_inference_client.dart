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
/// ## Image generation
///
/// When [imageEndpointStyle] is declared, the client also serves
/// [InferenceTask.textToImage] and [InferenceTask.imageToImage] through the
/// provider's images endpoint ([imagesUri]). Undeclared (the default), image
/// tasks refuse with the honest `task_unsupported` gate — a chat-only base
/// URL never pretends to generate pixels.
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

/// Which images-endpoint shape the declared provider speaks.
///
/// The two live wires differ in BOTH the operation path and the
/// image-to-image parameter, so the style is DECLARED (the palette knows
/// the transport it named) — never sniffed from the host.
enum ImageEndpointStyle {
  /// OpenAI-images-compatible: `{root}/images/generations`, the reference
  /// image rides `image` as a data URL. ModelScope and most self-hosted
  /// image servers speak this shape.
  openAiGenerations,

  /// OpenRouter's dedicated Images API: `{root}/images` (NOT
  /// `/images/generations`), the reference image rides `input_references`.
  /// Responses are base64-only on this style.
  openRouterImages,
}

/// The images endpoint for a declared API root and style. A root that
/// already names the operation is used verbatim; otherwise the style's
/// operation path is appended (the same derivation law as
/// [chatCompletionsUri]).
Uri imagesUri(String baseUrl, ImageEndpointStyle style) {
  final trimmed = baseUrl.trim();
  final root = trimmed.isEmpty
      ? Uri.https('openrouter.ai', '/api/v1')
      : Uri.parse(trimmed);
  final operation = switch (style) {
    ImageEndpointStyle.openAiGenerations => 'images/generations',
    ImageEndpointStyle.openRouterImages => 'images',
  };
  final path = root.path;
  if (path.endsWith('/$operation')) return root;
  final suffix = path.endsWith('/') ? operation : '/$operation';
  return root.replace(path: '$path$suffix');
}

class OpenRouterInferenceClient
    implements InferenceClient, ReasoningEffortInferenceClient {
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
    this.imageEndpointStyle,
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

  /// The declared images-endpoint shape, or null when the provider declared
  /// NO image lane (the default — image tasks then refuse at the gate).
  /// The binding composes this from the palette transport: `openrouter` →
  /// [ImageEndpointStyle.openRouterImages], `openai_compatible` →
  /// [ImageEndpointStyle.openAiGenerations].
  final ImageEndpointStyle? imageEndpointStyle;

  @override
  Future<void> load() async {
    // No model download needed — OpenRouter is a hosted API.
  }

  @override
  String get id => 'openrouter';

  @override
  bool get isAvailable => _apiKey.isNotEmpty;

  @override
  Set<InferenceTask> get supportedTasks => <InferenceTask>{
    InferenceTask.text,
    InferenceTask.nativelyStructuredText,

    // VISION (native-image-assets wave C): the input image rides the
    // SAME chat endpoint as a typed content part — every
    // chat-completions-compatible transport serves the shape, so the
    // task is supported unconditionally (the palette's `vision` key,
    // not the transport, decides who gets eyes).
    InferenceTask.imageToText,
    if (imageEndpointStyle != null) ...<InferenceTask>{
      InferenceTask.textToImage,
      InferenceTask.imageToImage,
    },
  };

  /// OpenRouter exposes reasoning as NAMED tiers, not a numeric 1-100 scale:
  /// the wire parameter is `reasoning_effort` with one of these values.
  @override
  Set<String> get supportedReasoningEfforts => const {
    'minimal',
    'low',
    'medium',
    'high',
    'xhigh',
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

    // Image tasks take the images-endpoint lane — a different wire (path,
    // body, response shape) that shares this class's transport, error
    // mapping and outcome diagnostics.
    if (request.task == InferenceTask.textToImage ||
        request.task == InferenceTask.imageToImage) {
      return _inferImages(request, model);
    }

    // Build the messages array. The actor's context fragments are appended as
    // a trailing user message so the model sees the projected context.
    // VISION (wave C): the chat lane accepts an image input — the same
    // bytes-or-file carrier the images lane reads.
    List<int>? inputBytes;
    final chatImageInput = request.imageInput;
    if (chatImageInput != null) {
      try {
        inputBytes = _imageInputBytes(chatImageInput);
      } on ImageInputException catch (error) {
        return InferenceResult<InferenceResponse>.fail(
          code: error.code,
          message: error.message,
        );
      }
    }

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
    // VISION (wave C): the user turn's content becomes a typed array
    // (text + image_url data-URL parts — the OpenAI-vision shape every
    // chat-completions-compatible vision model serves). The codec and
    // the plain string content are the TEXT paths and stay
    // byte-identical; vision never rides the codec.
    final visionContent = _visionUserContent(request, inputBytes);
    final messages = <Map<String, dynamic>>[
      if (systemPrompt.isNotEmpty) {'role': 'system', 'content': systemPrompt},
      if (visionContent != null)
        {'role': 'user', 'content': visionContent}
      else if (useMessagesCodec)
        ...SituationMessagesCodec.render(
          prompt: request.prompt,
          systemPrompt: '', // already emitted as the system message above
          fragments: request.contextFragments,
        )
      else
        {'role': 'user', 'content': _buildUserContent(request)},
    ];

    // OpenRouter has no `thinking` parameter: reasoning is expressed through
    // the named `reasoning_effort` tiers. An explicit `thinking: false` drops
    // the effort instead of inventing a 'none' tier that would change model
    // behaviour invisibly; `thinking: true` without an effort stays on the
    // provider default.
    final reasoningEffort = request.thinking == false
        ? null
        : request.reasoningEffort;

    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      if (request.maxTokens != null) 'max_tokens': request.maxTokens,
      if (request.temperature != null) 'temperature': request.temperature,
      // OpenRouter documents `repetition_penalty` as a top-level model
      // param: mapped when requested, absent otherwise (null = byte-
      // identical old body). The upstream model may ignore it; that is the
      // provider's business, not a silent drop here.
      'repetition_penalty': ?request.repetitionPenalty,
      // OpenRouter's chat completions API is OpenAI-compatible and accepts
      // the top-level integer `seed`: the seed is mapped to the wire, never
      // dropped (ADR 0059 — map or refuse). The upstream model may still
      // ignore it; that is the provider's business, not a silent drop here.
      'seed': ?request.seed,
      'reasoning_effort': ?reasoningEffort,
      'include_reasoning': ?request.includeReasoning,
      if (request.stopSequences.isNotEmpty)
        'stop_sequences': request.stopSequences,
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
      // The size law (ADR 0072, now on the chat lane too): a vision
      // request's data URLs become size markers in EVERY diagnostic
      // copy; text-only bodies keep their byte-identical diagnostics.
      final visionDiagnostic = _sanitizeChatBodyForDiagnostics(body);
      final diagnosticBody = visionDiagnostic ?? body;
      final encodedBody = jsonEncode(body);
      final encodedDiagnosticBody = visionDiagnostic == null
          ? encodedBody
          : jsonEncode(visionDiagnostic);
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
          requestBody: diagnosticBody,
          clientCohort: _diagnosticClientCohort,
          followRedirects: true,
        );
      }
      _diagnostic(
        diagnosticBody,
        intent,
        model,
        ContextTransportDiagnosticStage.request,
        encodedBody: encodedDiagnosticBody,
        transport: transport,
      );
      _notifyTransportDiagnostic(<String, Object?>{
        'type': 'openrouter.post',
        'uri': uri.toString(),
        'body': encodedDiagnosticBody,
        'metadata': Map<String, Object?>.from(request.metadata),
        'reasoning': <String, Object?>{
          'thinking': request.thinking,
          'effort': reasoningEffort,
          'effort_omitted':
              request.thinking == false && request.reasoningEffort != null,
        },
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
        final limitExhausted =
            (response.statusCode == 402 || response.statusCode == 403) &&
            response.body.contains('limit_source') &&
            (response.body.contains('key_limit') ||
                response.body.contains('Key limit exceeded'));
        if (limitExhausted) {
          return InferenceResult<InferenceResponse>.fail(
            code: 'provider_key_limit_exhausted',
            message: _errorMessage(response.body),
            details: <String, dynamic>{
              'http_status': response.statusCode,
              'body': response.body,
            },
            meta: <String, dynamic>{
              'provider': id,
              'model': model,
            },
          );
        }
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

      final parsed = _parseChatCompletion(decoded, seed: request.seed);
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
      // A spent REQUEST BUDGET is our own clock, not the backend's health:
      // a slow-but-healthy agentic generate (big tool transcript) used to be
      // mislabeled `engine_unavailable` here, which the rebind and ladder
      // planes read as backend absence and switched palettes over (paid for
      // live 2026-11-05: scout's drop came exactly 60.19s after its last
      // tool result). Name it honestly; transport failures below keep the
      // absence code.
      diagnosticOutcome = 'timeout';
      return InferenceResult<InferenceResponse>.fail(
        code: 'generate_timeout',
        message:
            'request budget expired after ${timeout.inSeconds}s — a slow '
            'generate hit OUR client timeout, not backend absence',
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
      // The OUTCOME diagnostic (ADR 0119 runtime health): the request
      // diagnostic above only proves a send; the composition root needs
      // the settled verdict to mark a palette entry ok/failed at runtime.
      _notifyTransportDiagnostic(<String, Object?>{
        'type': 'openrouter.result',
        'ok': diagnosticOutcome == 'completed',
        'outcome': diagnosticOutcome,
        'model': model,
        if (diagnosticHttpStatus != null) 'http_status': diagnosticHttpStatus,
      });
    }
  }

  /// The images-endpoint lane for [InferenceTask.textToImage] /
  /// [InferenceTask.imageToImage]. Shares the chat lane's transport,
  /// timeout, HTTP-error mapping and outcome diagnostics; the wire (path,
  /// body, response shape) is the declared [imageEndpointStyle]'s.
  Future<InferenceResult<InferenceResponse>> _inferImages(
    InferenceRequest request,
    String model,
  ) async {
    final style = imageEndpointStyle;
    if (style == null) {
      // Unreachable through infer() (the task gate refuses first); kept as
      // the lane's own precondition.
      return InferenceResult<InferenceResponse>.fail(
        code: errorCodeTaskUnsupported,
        message: 'Task ${request.task.name} requires a declared '
            'imageEndpointStyle',
      );
    }

    // Cache intent is a CHAT-lane concept (prompt-prefix reuse). A
    // non-empty intent on an image request is refused by name, never
    // silently dropped; the default empty intent is a no-op here.
    final intentValue = request.metadata['context_cache_intent'];
    if (intentValue != null) {
      try {
        final intent = ContextCacheIntent.fromJson(
          Map<String, Object?>.from(intentValue as Map),
        );
        if (intent.writeAfterSegmentIds.isNotEmpty ||
            intent.lookupAfterSegmentIds.isNotEmpty) {
          return InferenceResult<InferenceResponse>.fail(
            code: 'cache_intent_unsupported_for_task',
            message:
                'Cache intent is a chat-lane concept; '
                '${request.task.name} does not carry it',
          );
        }
      } on Object {
        return InferenceResult<InferenceResponse>.fail(
          code: 'cache_intent_invalid',
          message: 'Invalid cache intent',
        );
      }
    }

    List<int>? inputBytes;
    final input = request.imageInput;
    if (input != null) {
      try {
        inputBytes = _imageInputBytes(input);
      } on ImageInputException catch (error) {
        return InferenceResult<InferenceResponse>.fail(
          code: error.code,
          message: error.message,
        );
      }
    }

    final body = _buildImageBody(request, model, style, inputBytes);
    // The diagnostic copy carries SIZE MARKERS, never pixels: image data
    // URLs and b64 payloads must not ride transport diagnostics.
    final diagnosticBody = _sanitizeImageBodyForDiagnostics(body);

    // The response body is NEVER stored for diagnostics on the image lane:
    // b64 outputs are megabytes, and the cache analyzer is a chat-lane
    // instrument. The outcome event below is the health record.
    int? diagnosticHttpStatus;
    var diagnosticOutcome = 'failed';
    try {
      final uri = imagesUri(baseUrl, style);
      final encodedBody = jsonEncode(body);
      final headers = <String, String>{
        'authorization': 'Bearer $_apiKey',
        'content-type': 'application/json',
        'accept': 'application/json',
      };
      _notifyTransportDiagnostic(<String, Object?>{
        'type': 'openrouter.post',
        'lane': 'images',
        'uri': uri.toString(),
        // Sanitized: the encoded wire body with image payloads replaced by
        // size markers.
        'body': jsonEncode(diagnosticBody),
        'metadata': Map<String, Object?>.from(request.metadata),
      });
      final response = await _httpClient
          .post(uri, headers: headers, body: encodedBody)
          .timeout(timeout);
      diagnosticHttpStatus = response.statusCode;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        diagnosticOutcome = 'http_${response.statusCode}';
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
          message: 'Images endpoint returned a non-object response',
          meta: <String, dynamic>{'provider': id},
        );
      }

      final parsed = _parseImagesResponse(
        decoded,
        task: request.task,
        seed: request.seed,
      );
      if (parsed == null) {
        return InferenceResult<InferenceResponse>.fail(
          code: 'output_empty',
          message: 'Images endpoint returned no image data',
          details: <String, dynamic>{'body': response.body},
          meta: <String, dynamic>{'provider': id, 'model': model},
        );
      }

      diagnosticOutcome = 'completed';
      return InferenceResult<InferenceResponse>.ok(
        parsed,
        meta: <String, dynamic>{'provider': id, 'model': model},
      );
    } on TimeoutException catch (_) {
      // Same budget law as the chat lane: a spent REQUEST BUDGET is our
      // clock, not backend absence. Image generation is slow by nature —
      // mislabeling it `engine_unavailable` would flip palette health.
      diagnosticOutcome = 'timeout';
      return InferenceResult<InferenceResponse>.fail(
        code: 'generate_timeout',
        message:
            'request budget expired after ${timeout.inSeconds}s — a slow '
            'image generation hit OUR client timeout, not backend absence',
        meta: <String, dynamic>{'provider': id},
      );
    } on SocketException catch (error) {
      diagnosticOutcome = 'transport_error';
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'Images endpoint network connection failed',
        details: error.toString(),
        meta: <String, dynamic>{'provider': id},
      );
    } catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'Images endpoint request failed unexpectedly',
        details: error.toString(),
        meta: <String, dynamic>{'provider': id},
      );
    } finally {
      // The OUTCOME diagnostic (ADR 0119 runtime health): the same event
      // vocabulary as the chat lane, so palette health marks image
      // entries ok/failed like any other dispatch.
      _notifyTransportDiagnostic(<String, Object?>{
        'type': 'openrouter.result',
        'lane': 'images',
        'ok': diagnosticOutcome == 'completed',
        'outcome': diagnosticOutcome,
        'model': model,
        'http_status': ?diagnosticHttpStatus,
      });
    }
  }

  /// The images wire body for the declared style. Typed options map to
  /// their snake_case wire names; [InferenceImageOptions.providerExtras]
  /// passes verbatim LAST (an explicit extra overrides a typed field — a
  /// deliberate caller choice, never a collision). A parameter a provider
  /// does not support surfaces as that provider's error — mapped or
  /// refused, never silently dropped.
  Map<String, dynamic> _buildImageBody(
    InferenceRequest request,
    String model,
    ImageEndpointStyle style,
    List<int>? inputBytes,
  ) {
    final options = request.imageOptions;
    final body = <String, dynamic>{
      'model': model,
      'prompt': request.prompt,
      'seed': ?request.seed,
      'n': ?options?.n,
      'size': ?options?.size,
      'aspect_ratio': ?options?.aspectRatio,
      'quality': ?options?.quality,
      'output_format': ?options?.outputFormat,
      'negative_prompt': ?options?.negativePrompt,
      'strength': ?options?.strength,
    };
    final input = request.imageInput;
    if (input != null && inputBytes != null) {
      final dataUrl =
          'data:${input.mimeType};base64,${base64Encode(inputBytes)}';
      switch (style) {
        case ImageEndpointStyle.openRouterImages:
          body['input_references'] = <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'image_url',
              'image_url': <String, dynamic>{'url': dataUrl},
            },
          ];
        case ImageEndpointStyle.openAiGenerations:
          // The OpenAI-images-compatible convention: the reference image
          // rides `image` as a data URL. A provider that names the field
          // differently overrides via providerExtras (verbatim).
          body['image'] = dataUrl;
      }
    }
    final extras = options?.providerExtras;
    if (extras != null && extras.isNotEmpty) {
      body.addAll(extras.cast<String, dynamic>());
    }
    return body;
  }

  /// Resolves the input image's bytes. Bytes inputs pass through; file
  /// inputs are read here (the transport owns the wire, so it owns the
  /// encoding). Read failures name themselves.
  List<int> _imageInputBytes(InferenceImageInput input) {
    final bytes = input.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return bytes;
    }
    final filePath = input.filePath;
    if (filePath == null || filePath.trim().isEmpty) {
      throw const ImageInputException(
        code: 'image_input_invalid',
        message: 'Image input carries neither bytes nor a readable filePath',
      );
    }
    try {
      return File(filePath).readAsBytesSync();
    } on Object {
      throw ImageInputException(
        code: 'image_input_unreadable',
        message: 'Image input filePath could not be read: $filePath',
      );
    }
  }

  /// VISION (wave C) user content: the typed part array for an
  /// imageToText request — text first, then the image as a data URL
  /// (the OpenAI-vision shape). Null for every other task (the text
  /// paths stay byte-identical).
  List<Map<String, dynamic>>? _visionUserContent(
    InferenceRequest request,
    List<int>? inputBytes,
  ) {
    if (request.task != InferenceTask.imageToText) return null;
    final bytes = inputBytes;
    if (bytes == null || bytes.isEmpty) return null;
    final mime = request.imageInput?.mimeType ?? 'image/png';
    return <Map<String, dynamic>>[
      {'type': 'text', 'text': request.prompt},
      {
        'type': 'image_url',
        'image_url': {'url': 'data:$mime;base64,${base64Encode(bytes)}'},
      },
    ];
  }

  /// The CHAT-lane size law: null when the body carries no image
  /// payload (text-only diagnostics stay byte-identical); otherwise the
  /// copy with data URLs replaced by size markers — the same pass the
  /// images lane applies unconditionally.
  static Map<String, Object?>? _sanitizeChatBodyForDiagnostics(
    Map<String, dynamic> body,
  ) => _containsDataImageUrl(body)
      ? Map<String, Object?>.from(_sanitizeValue(body) as Map)
      : null;

  static bool _containsDataImageUrl(Object? value) {
    if (value is String) return value.startsWith('data:image/');
    if (value is Map) return value.values.any(_containsDataImageUrl);
    if (value is List) return value.any(_containsDataImageUrl);
    return false;
  }

  /// The diagnostic view of an images body/response: image payloads
  /// (data URLs) replaced with size markers. b64 outputs ride responses —
  /// they are sanitized with the same pass before any diagnostic stores
  /// them.
  static Map<String, Object?> _sanitizeImageBodyForDiagnostics(
    Map<String, dynamic> value,
  ) => Map<String, Object?>.from(_sanitizeValue(value) as Map);

  static Object? _sanitizeValue(Object? value) {
    if (value is String && value.startsWith('data:image/')) {
      return '[[data-url:${value.length} chars]]';
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          '${entry.key}': _sanitizeValue(entry.value),
      };
    }
    if (value is List) {
      return <Object?>[for (final item in value) _sanitizeValue(item)];
    }
    return value;
  }

  /// Parse an images response into an [InferenceResponse].
  ///
  /// `data[]` items carry either `b64_json` (OpenRouter — pixels only,
  /// never URLs) or `url` (OpenAI-images-compatible — frequently EXPIRING
  /// links; the response names that with the `image_url_expiring`
  /// warning). `usage` passes through as reported, same as the chat lane.
  InferenceResponse? _parseImagesResponse(
    Map<String, dynamic> decoded, {
    required InferenceTask task,
    int? seed,
  }) {
    final data = decoded['data'];
    if (data is! List) return null;
    final artifacts = <InferenceImageArtifact>[];
    var urlCarried = false;
    for (final item in data) {
      if (item is! Map<String, dynamic>) continue;
      final b64 = item['b64_json'];
      final url = item['url'];
      final mediaType = _imageMediaType(item);
      if (b64 is String && b64.isNotEmpty) {
        artifacts.add(
          InferenceImageArtifact(mimeType: mediaType, bytesBase64: b64),
        );
      } else if (url is String && url.isNotEmpty) {
        artifacts.add(InferenceImageArtifact(mimeType: mediaType, url: url));
        urlCarried = true;
      }
    }
    if (artifacts.isEmpty) return null;

    final usage = decoded['usage'];
    return InferenceResponse(
      task: task,
      imageArtifacts: artifacts,
      warnings: urlCarried
          ? const <String>['image_url_expiring']
          : const <String>[],
      meta: <String, dynamic>{
        'provider': id,
        inferenceSeedMetaKey: ?seed,
        'usage_reported': decoded.containsKey('usage'),
        if (usage is Map<String, dynamic>) 'usage': usage,
      },
    );
  }

  /// The image's media type: the provider's explicit field when present,
  /// then the URL's extension, then the honest default.
  static String _imageMediaType(Map<String, dynamic> item) {
    for (final key in ['media_type', 'mime_type']) {
      final value = item[key];
      if (value is String && value.isNotEmpty) return value;
    }
    final url = item['url'];
    if (url is String) {
      final extension = Uri.parse(url).pathSegments.lastOrNull?.split('.').last;
      final mapped = switch (extension) {
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'webp' => 'image/webp',
        'svg' => 'image/svg+xml',
        'gif' => 'image/gif',
        _ => null,
      };
      if (mapped != null) return mapped;
    }
    return 'image/png';
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
  InferenceResponse? _parseChatCompletion(
    Map<String, dynamic> decoded, {
    int? seed,
  }) {
    final choices = decoded['choices'];
    if (choices is! List) return null;
    final first = (choices).firstOrNull;
    if (first is! Map<String, dynamic>) return null;

    final messageMap = (first)['message'];
    if (messageMap is! Map<String, dynamic>) return null;

    final content = messageMap['content'];
    final contentStr = content is String ? content : '';

    // OpenRouter returns the reasoning trace beside the answer when
    // `include_reasoning` is on.
    final reasoning = messageMap['reasoning'];
    final reasoningStr = reasoning is String ? reasoning : '';

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
        // HONOURED: the seed was sent on the wire (body `seed`), so the
        // response records it — no warning.
        inferenceSeedMetaKey: ?seed,
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
        if (reasoningStr.isNotEmpty) 'reasoning': reasoningStr,
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

/// A named failure while resolving an image input's bytes — the input
/// carried neither carrier, or its file could not be read.
final class ImageInputException implements Exception {
  const ImageInputException({required this.code, required this.message});

  /// `image_input_invalid` · `image_input_unreadable`.
  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}
