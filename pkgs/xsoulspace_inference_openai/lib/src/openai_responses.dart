import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'chatgpt_auth.dart';

part 'openai_session.dart';

/// Provider-native items are a codec, never the durable conversation owner.
/// Store outputs with the originating actor/request and reconstruct only the
/// currently authorized working set. Tool call/output IDs remain atomic.
final class ResponsesInput {
  ResponsesInput(Iterable<Map<String, dynamic>> items)
    : items = List.unmodifiable(
        items.map(
          (item) => jsonDecode(jsonEncode(item)) as Map<String, dynamic>,
        ),
      );
  final List<Map<String, dynamic>> items;

  static Map<String, dynamic> toolOutput(String callId, String output) => {
    'type': 'function_call_output',
    'call_id': callId,
    'output': output,
  };

  InferenceRequest attach(InferenceRequest request) => request.copyWith(
    metadata: {...request.metadata, 'openai_responses_input': items},
  );
}

final class ChatGptModel {
  const ChatGptModel({required this.slug, required this.displayName});
  final String slug;
  final String displayName;
}

/// Bounded structural observation of one settled request. Contains counts and
/// allowlisted numeric usage, request hashes/lengths and tool names only; never
/// text, arguments, request IDs or credentials. Separately opt-in diagnostics
/// may retain safe response identifiers and cache diagnostic enums.
final class ResponsesDecisionReceipt {
  ResponsesDecisionReceipt({
    required this.advertisedTools,
    required this.schemaRequested,
    required this.httpStatus,
    required this.elapsedMs,
    required this.outputKinds,
    required this.eventKinds,
    required this.terminalOutputItems,
    required this.streamedDoneItems,
    required this.wireTextChars,
    required this.streamedTextChars,
    required this.parsedTextChars,
    required this.parsedToolCalls,
    required this.structuredKeys,
    required this.usage,
    required this.outcome,
    this.reasoningEffort,
    this.requestSegments = const {},
    this.advertisedToolNames = const [],
    this.omittedInputSegments = 0,
    this.contextDiagnostic,
    this.usageReported = false,
    this.usageFieldPresence = const {},
    this.responseFieldPresence = const {},
    this.responseId,
    this.responseModel,
    this.serviceTier,
    this.promptCacheDiagnostics = const {},
    this.providerErrorCode,
    this.providerErrorType,
    this.providerErrorParam,
    this.providerErrorFieldPresence = const {},
  });

  final int advertisedTools;
  final bool schemaRequested;
  final int? httpStatus;
  final int elapsedMs;
  final Map<String, int> outputKinds;
  final Map<String, int> eventKinds;
  final int terminalOutputItems;
  final int streamedDoneItems;
  final int wireTextChars;
  final int streamedTextChars;
  final int parsedTextChars;
  final int parsedToolCalls;
  final int structuredKeys;
  final Map<String, int> usage;
  final String outcome;
  final String? reasoningEffort;
  final Map<String, Map<String, Object>> requestSegments;
  final List<String> advertisedToolNames;
  final int omittedInputSegments;
  final ContextDiagnosticSnapshot? contextDiagnostic;
  final bool usageReported;
  final Map<String, bool> usageFieldPresence;
  final Map<String, bool> responseFieldPresence;
  final String? responseId;
  final String? responseModel;
  final String? serviceTier;
  final Map<String, Object> promptCacheDiagnostics;
  final String? providerErrorCode;
  final String? providerErrorType;
  final String? providerErrorParam;
  final Map<String, bool> providerErrorFieldPresence;

  Map<String, Object?> toJson() => {
    'advertisedTools': advertisedTools,
    'advertisedToolNames': List<String>.of(advertisedToolNames),
    'requestSegments': {
      for (final entry in requestSegments.entries)
        entry.key: Map<String, Object>.of(entry.value),
    },
    'omittedInputSegments': omittedInputSegments,
    'schemaRequested': schemaRequested,
    'httpStatus': httpStatus,
    'elapsedMs': elapsedMs,
    'outputKinds': Map<String, int>.of(outputKinds),
    'eventKinds': Map<String, int>.of(eventKinds),
    'terminalOutputItems': terminalOutputItems,
    'streamedDoneItems': streamedDoneItems,
    'wireTextChars': wireTextChars,
    'streamedTextChars': streamedTextChars,
    'parsedTextChars': parsedTextChars,
    'parsedToolCalls': parsedToolCalls,
    'structuredKeys': structuredKeys,
    'usage': Map<String, int>.of(usage),
    'usageReported': usageReported,
    'usageFieldPresence': Map<String, bool>.of(usageFieldPresence),
    'responseFieldPresence': Map<String, bool>.of(responseFieldPresence),
    if (responseId != null) 'responseId': responseId,
    if (responseModel != null) 'responseModel': responseModel,
    if (serviceTier != null) 'serviceTier': serviceTier,
    if (promptCacheDiagnostics.isNotEmpty)
      'promptCacheDiagnostics': Map<String, Object>.of(promptCacheDiagnostics),
    if (contextDiagnostic != null)
      'contextDiagnostic': contextDiagnostic!.toJson(),
    'outcome': outcome,
    if (providerErrorCode != null) 'providerErrorCode': providerErrorCode,
    if (providerErrorType != null) 'providerErrorType': providerErrorType,
    if (providerErrorParam != null) 'providerErrorParam': providerErrorParam,
    if (providerErrorFieldPresence.isNotEmpty)
      'providerErrorFieldPresence': Map<String, bool>.of(
        providerErrorFieldPresence,
      ),
    if (reasoningEffort != null) 'reasoningEffort': reasoningEffort,
  };
}

/// Native HTTP/SSE provider using the user's explicitly authorized ChatGPT
/// plan. Tool execution belongs to the calling host; infer never runs tools.
final class OpenAiResponsesClient
    implements
        StructuredTextStreamingInferenceClient,
        ToolStreamingInferenceClient,
        ReasoningEffortInferenceClient,
        CancellableInferenceClient {
  OpenAiResponsesClient({
    required this.auth,
    required this.clientId,
    required this.model,
    http.Client? client,
    this.deadline = const Duration(minutes: 5),
    this.maxResponseBytes = 4 * 1024 * 1024,
    this.observeDecision,
    this.diagnosticCapture,
    OpenAiSessionState? sessionState,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _sessionState = sessionState ?? OpenAiSessionState();

  final OpenAiSessionState _sessionState;

  static int _diagnosticClientCounter = 0;
  final String _diagnosticClientCohort =
      'openai-http-${++_diagnosticClientCounter}';

  final ChatGptAuth auth;
  final String clientId;
  final String model;
  @override
  Set<String> get supportedReasoningEfforts => const {
    'none',
    'minimal',
    'low',
    'medium',
    'high',
    'xhigh',
  };
  final http.Client _client;
  final bool _ownsClient;
  final Duration deadline;
  final int maxResponseBytes;

  /// Best-effort observer; throwing cannot change inference or settlement.
  final void Function(ResponsesDecisionReceipt receipt)? observeDecision;

  /// Optional caller-owned context diagnostics. Source bodies require explicit
  /// opt-in and are never captured for encrypted continuation input.
  final ContextTransportDiagnosticCapture? diagnosticCapture;
  bool _available = false;
  final _sessions = <_ResponsesSession>{};
  final _catalogRequests = <_CatalogRequest>{};

  @override
  void cancelActive() {
    for (final operation in _catalogRequests.toList()) {
      operation.cancel('model_catalog_cancelled');
    }
    for (final session in _sessions.toList()) {
      session.stop('inference_cancelled');
    }
  }

  @override
  Future<void> settleActive() async {
    await Future.wait([
      ..._sessions.map((session) => session.settled.future),
      ..._catalogRequests.map((operation) => operation.settled.future),
    ]);
  }

  @override
  String get id => 'openai_chatgpt_plan';
  @override
  bool get isAvailable => _available;
  @override
  Set<InferenceTask> get supportedTasks => const {
    InferenceTask.text,
    InferenceTask.implicitlyStructuredText,
    InferenceTask.nativelyStructuredText,
  };

  Future<List<ChatGptModel>> listModels() async {
    final operation = _CatalogRequest();
    _catalogRequests.add(operation);
    final timer = Timer(
      deadline,
      () => operation.cancel('model_catalog_timeout'),
    );
    try {
      final account = await Future.any<ChatGptAccount>([
        auth.accountForInference(clientId),
        operation.abort.future.then(
          (_) => throw ChatGptAuthException(operation.failureCode),
        ),
      ]);
      if (operation.abort.isCompleted) {
        throw ChatGptAuthException(operation.failureCode);
      }
      final catalog =
          http.AbortableRequest(
              'GET',
              Uri.parse('https://api.openai.com/v1/models'),
              abortTrigger: operation.abort.future,
            )
            ..followRedirects = false
            ..headers['Authorization'] = 'Bearer ${account.accessToken}';
      final response = await http.Response.fromStream(
        await _client.send(catalog),
      );
      if (response.statusCode != 200) {
        throw const ChatGptAuthException('model_catalog_unavailable');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (body['models'] as List)
          .cast<Map<String, dynamic>>()
          .where((model) => model['visibility'] == 'list')
          .map(
            (model) => ChatGptModel(
              slug: model['slug'] as String,
              displayName: model['display_name'] as String,
            ),
          )
          .toList();
    } on ChatGptAuthException {
      rethrow;
    } catch (_) {
      throw ChatGptAuthException(
        operation.abort.isCompleted
            ? operation.failureCode
            : 'model_catalog_transport_failed',
      );
    } finally {
      timer.cancel();
      operation.settled.complete();
      _catalogRequests.remove(operation);
    }
  }

  @override
  Future<bool> refreshAvailability() async {
    try {
      _available = (await listModels()).any((m) => m.slug == model);
    } catch (_) {
      _available = false;
    }
    return _available; // Catalog presence is not successful-inference evidence.
  }

  @override
  Future<void> load() async {
    await refreshAvailability();
  }

  @override
  void resetAvailabilityCache() {
    _available = false;
  }

  @override
  Future<InferenceResult<InferenceResponse>> infer(
    InferenceRequest request, {
    ToolRegistry? toolRegistry,
  }) async {
    final session = _ResponsesSession();
    unawaited(_run(request, session, toolRegistry));
    try {
      return await session.result;
    } finally {
      await session.dispose();
    }
  }

  @override
  Future<InferenceStructuredTextStreamSession> streamStructuredText(
    InferenceRequest request,
  ) async {
    final session = _ResponsesSession();
    unawaited(_run(request, session, null));
    return session;
  }

  /// Native optional streaming capability. Core's legacy structured stream has
  /// no tool parameter; this additive method advertises host-supplied tools.
  Future<InferenceStructuredTextStreamSession> streamResponses(
    InferenceRequest request, {
    ToolRegistry? toolRegistry,
  }) async {
    final session = _ResponsesSession();
    unawaited(_run(request, session, toolRegistry));
    return session;
  }

  @override
  Future<InferenceStructuredTextStreamSession> streamWithTools(
    InferenceRequest request, {
    required ToolRegistry toolRegistry,
  }) => streamResponses(request, toolRegistry: toolRegistry);

  Map<String, dynamic> encodeRequest(
    InferenceRequest request, {
    ToolRegistry? tools,
  }) {
    if (!supportedTasks.contains(request.task)) {
      throw const _ResponseFailure('task_unsupported');
    }
    if (request.maxTokens != null ||
        request.temperature != null ||
        request.stopSequences.isNotEmpty ||
        request.thinking != null) {
      throw const _ResponseFailure('generation_option_unsupported');
    }
    final effort = request.reasoningEffort;
    if (effort != null && !supportedReasoningEfforts.contains(effort)) {
      throw const _ResponseFailure('reasoning_effort_unsupported');
    }
    final instructions = <String>[
      if (request.systemPrompt.isNotEmpty) request.systemPrompt,
    ];
    final input = <Map<String, dynamic>>[];
    final native = request.metadata['openai_responses_input'];
    if (native != null) {
      if (native is! List) throw const _ResponseFailure('invalid_native_input');
      // Continuation is additive to the current authorized context, never a
      // replacement for its mandatory raycast facts or actor instructions.
      if (request.messages.isNotEmpty) {
        for (final message in request.messages) {
          if (message.role == ChatRole.system) {
            instructions.add(message.content);
          } else if (message.role == ChatRole.tool) {
            throw const _ResponseFailure('tool_call_identity_required');
          } else {
            input.add({
              'role': message.role.toJson(),
              'content': message.content,
            });
          }
        }
      } else {
        for (final fragment in request.contextFragments) {
          final text = fragment.toString();
          input.add({
            'role': text.startsWith(ContextFragmentProtocol.assistantPrefix)
                ? 'assistant'
                : 'user',
            'content': ContextFragmentProtocol.stripPrefixes(text),
          });
        }
      }
      for (final item in native) {
        if (item is! Map<String, dynamic>) {
          throw const _ResponseFailure('invalid_native_input');
        }
        final type = item['type'];
        if (type == null || type == 'message') {
          if (item['role'] != 'user' && item['role'] != 'assistant') {
            throw const _ResponseFailure('native_role_unsupported');
          }
        } else if (type != 'reasoning' &&
            type != 'function_call' &&
            type != 'function_call_output') {
          throw const _ResponseFailure('native_item_unsupported');
        }
        input.add(Map.of(item));
      }
      final pending = <String>{};
      final seen = <String>{};
      for (final item in input) {
        if (item['type'] == 'function_call') {
          final callId = item['call_id'];
          if (callId is! String || callId.isEmpty || !seen.add(callId)) {
            throw const _ResponseFailure('invalid_tool_call');
          }
          pending.add(callId);
        } else if (item['type'] == 'function_call_output') {
          final callId = item['call_id'];
          if (callId is! String || !pending.remove(callId)) {
            throw const _ResponseFailure('tool_pair_incomplete');
          }
        }
      }
      if (pending.isNotEmpty) {
        throw const _ResponseFailure('tool_pair_incomplete');
      }
    } else if (request.messages.isNotEmpty) {
      for (final message in request.messages) {
        switch (message.role) {
          case ChatRole.system:
            instructions.add(message.content);
          case ChatRole.tool:
            // Text-only tool messages cannot reconstruct a correlated call.
            throw const _ResponseFailure('tool_call_identity_required');
          case ChatRole.user:
          case ChatRole.assistant:
            input.add({
              'role': message.role.toJson(),
              'content': message.content,
            });
        }
      }
    } else {
      for (final fragment in request.contextFragments) {
        final text = fragment.toString();
        input.add({
          'role': text.startsWith(ContextFragmentProtocol.assistantPrefix)
              ? 'assistant'
              : 'user',
          'content': ContextFragmentProtocol.stripPrefixes(text),
        });
      }
    }
    if (request.prompt.isNotEmpty) {
      input.add({'role': 'user', 'content': request.prompt});
    }
    if (input.isEmpty || model.isEmpty) {
      throw const _ResponseFailure('empty_request');
    }
    final definitions = tools?.tools.values.toList() ?? <ToolDef>[];
    definitions.sort((a, b) => a.name.value.compareTo(b.name.value));
    final body = <String, dynamic>{
      'model': model,
      'store': false,
      'stream': true,
      if (effort != null) 'reasoning': {'effort': effort},
      'input': input,
      if (instructions.isNotEmpty) 'instructions': instructions.join('\n\n'),
      if (definitions.isNotEmpty)
        'tools': [
          {
            'type': 'namespace',
            'name': 'harness',
            'description': 'Host-authorized actions; execution and acceptance are host-owned.',
            'tools': definitions
                .map(
                  (t) => {
                    'type': 'function',
                    'name': t.name.value,
                    'description': t.description,
                    // Host schemas retain optional and open fields. Responses
                    // otherwise normalizes these into strict required fields.
                    // The existing host still validates every returned action.
                    'strict': false,
                    'parameters': t.argsSchema.isEmpty
                        ? {'type': 'object', 'properties': <String, dynamic>{}}
                        : _wireSchema(t.argsSchema),
                  },
                )
                .toList(),
          },
        ],
      if (request.outputSchema.isNotEmpty)
        'text': {
          'format': {
            'type': 'json_schema',
            'name': 'result',
            'schema': _outputSchema(request),
            'strict': false,
          },
        },
    };
    _applyCacheIntent(body, request);
    final context = InferenceSessionContext.fromRequest(request);
    final sessionOptions = OpenAiSessionOptions.fromRequest(request);
    if (sessionOptions != null && context == null) {
      throw const FormatException('inference_session_required');
    }
    if (sessionOptions?.turnAffinity == true && context?.turn == null) {
      throw const FormatException('inference_turn_required');
    }
    if (context != null) {
      body['prompt_cache_key'] = context.session.effectiveCacheGroup;
    }
    final comparison = request.metadata[contextCacheComparisonMetadataKey];
    if (comparison != null) {
      try {
        final option = ContextCacheComparisonRequest.fromJson(
          (comparison as Map).cast<String, Object?>(),
        );
        body['prompt_cache_options'] = {
          'comparison_response_id': option.baselineResponseId,
        };
      } on Object {
        throw const _ResponseFailure('cache_comparison_invalid');
      }
    }

    return body;
  }

  ContextCacheIntent _cacheIntent(InferenceRequest request) {
    final value = request.metadata['context_cache_intent'];
    if (value == null) return ContextCacheIntent();
    if (value is! Map) throw const _ResponseFailure('cache_intent_invalid');
    try {
      final intent = ContextCacheIntent.fromJson(
        Map<String, Object?>.from(value),
      );
      return ContextCacheIntent(
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
    } on Object {
      throw const _ResponseFailure('cache_intent_invalid');
    }
  }

  static String _wireCacheId(String id) =>
      id.replaceFirst(RegExp(r'^context(?=\[)'), 'input');

  bool get _modernCacheModel =>
      RegExp(r'^gpt-(?:5\.[6-9]|[6-9](?:\.|-)|[1-9][0-9])').hasMatch(model);

  void _applyCacheIntent(Map<String, dynamic> body, InferenceRequest request) {
    final intent = _cacheIntent(request);
    if (intent.writeAfterSegmentIds.isEmpty &&
        intent.lookupAfterSegmentIds.isEmpty) {
      return;
    }
    if (!_modernCacheModel) {
      throw const _ResponseFailure('cache_breakpoint_unsupported');
    }
    // Keep implicit policy: it writes one implicit plus the latest three
    // explicit boundaries. Do not silently change request-wide caching mode.
    if (intent.writeAfterSegmentIds.length > 3) {
      throw const _ResponseFailure('cache_breakpoint_limit');
    }
    for (final id in intent.lookupAfterSegmentIds) {
      if (!intent.writeAfterSegmentIds.contains(id)) {
        throw const _ResponseFailure('cache_lookup_intent_unsupported');
      }
    }
    final input = body['input'] as List;
    for (final id in intent.writeAfterSegmentIds) {
      final match = RegExp(r'^input\[(\d+)\](?:\.content\[(\d+)\])?$')
          .firstMatch(id);
      if (match == null) {
        throw const _ResponseFailure('cache_breakpoint_invalid');
      }
      final index = int.parse(match[1]!);
      if (index >= input.length || input[index] is! Map) {
        throw const _ResponseFailure('cache_breakpoint_invalid');
      }
      final item = Map<String, dynamic>.from(input[index] as Map);
      if ((item['type'] != null && item['type'] != 'message') ||
          !['user', 'assistant'].contains(item['role'])) {
        throw const _ResponseFailure('cache_breakpoint_invalid');
      }
      final content = item['content'];
      final parts = content is String
          ? <dynamic>[
              {'type': 'input_text', 'text': content},
            ]
          : content is List
          ? List<dynamic>.of(content)
          : null;
      if (parts == null || parts.isEmpty) {
        throw const _ResponseFailure('cache_breakpoint_invalid');
      }
      final partIndex = match[2] == null
          ? parts.length - 1
          : int.parse(match[2]!);
      if (partIndex >= parts.length || parts[partIndex] is! Map) {
        throw const _ResponseFailure('cache_breakpoint_invalid');
      }
      final part = Map<String, dynamic>.from(parts[partIndex] as Map);
      if (part['type'] != 'input_text' || part['text'] is! String) {
        throw const _ResponseFailure('cache_breakpoint_invalid');
      }
      part['prompt_cache_breakpoint'] = {'mode': 'explicit'};
      parts[partIndex] = part;
      item['content'] = parts;
      input[index] = item;
    }
  }

  ContextDiagnosticSnapshot? _diagnostic(
    Map<String, dynamic> body,
    InferenceRequest request,
    ContextTransportDiagnosticStage stage, {
    String? encodedBody,
    Map<String, int> usage = const {},
    bool usageReported = false,
    String? responseId,
    String? responseModel,
    String? serviceTier,
    String? outcome,
    int? httpStatus,
    Map<String, Object?> safeError = const {},
    Map<String, Object?> transport = const {},
  }) {
    final capture = diagnosticCapture;
    if (capture == null) return null;
    try {
      final intent = _cacheIntent(request);
      const policy = 'openai-gpt56plus-implicit-siwc-unqualified';
      const provenance = [
        'https://developers.openai.com/api/docs/guides/prompt-caching',
      ];
      final eligible = <String>[
        if (_modernCacheModel &&
            body['instructions'] is String &&
            (body['instructions'] as String).isNotEmpty)
          'instructions',
        if (_modernCacheModel)
          for (var i = 0; i < (body['input'] as List).length; i++)
            if ((body['input'] as List)[i] case final Map item
                when ((item['type'] == null || item['type'] == 'message') &&
                        item['role'] == 'user') ||
                    (item['type'] == 'function_call_output' &&
                        (i + 1 == (body['input'] as List).length ||
                            ((body['input'] as List)[i + 1] as Map)['type'] !=
                                'function_call_output')))
              'input[$i]',
      ];
      final snapshot = ContextCacheAnalyzer.captureJsonRequest(
        body,
        messageListPath: ['input'],
        configurationIgnoredPaths: const [
          ['prompt_cache_options', 'comparison_response_id'],
        ],
        representationId: 'openai-responses-json-utf8-v1',
        exactWire: true,
        compatibility: ContextRequestCompatibility(provider: id, model: model),
        writeEndpoints: [
          if (eligible.isNotEmpty)
            CacheWriteEndpoint(
              afterSegmentId: eligible.last,
              policyId: policy,
              provenanceRefs: provenance,
            ),
          for (final id in intent.writeAfterSegmentIds)
            CacheWriteEndpoint(
              afterSegmentId: id,
              policyId: policy,
              provenanceRefs: provenance,
            ),
        ],
        lookupEndpoints: [
          if (_modernCacheModel &&
              body['instructions'] is String &&
              (body['instructions'] as String).isNotEmpty)
            CacheLookupEndpoint(
              afterSegmentId: 'instructions',
              policyId: policy,
              provenanceRefs: provenance,
            ),
          for (final id
              in eligible
                  .skip((eligible.length - 21).clamp(0, eligible.length))
                  .where((id) => id != 'instructions'))
            CacheLookupEndpoint(
              afterSegmentId: id,
              policyId: policy,
              provenanceRefs: provenance,
            ),
          for (final id in {
            ...intent.lookupAfterSegmentIds,
            ...intent.writeAfterSegmentIds,
          })
            CacheLookupEndpoint(
              afterSegmentId: id,
              policyId: policy,
              provenanceRefs: provenance,
            ),
        ],
        usage: usageReported
            ? ContextCacheUsage(
                inputTokens: usage['input_tokens'],
                cachedTokens: usage['cached_tokens'],
                cacheWriteTokens: usage['cache_write_tokens'],
                outputTokens: usage['output_tokens'],
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
          usageReported: usageReported,
          numericUsage: usage,
          responseId: responseId,
          model: responseModel ?? model,
          serviceTier: serviceTier,
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
      return snapshot;
    } on Object {
      // Caller diagnostics cannot change transport, results or settlement.
      return null;
    }
  }

  Future<void> _run(
    InferenceRequest request,
    _ResponsesSession session,
    ToolRegistry? tools,
  ) async {
    _sessions.add(session);
    final elapsed = Stopwatch()..start();
    int? httpStatus;
    var wireTextChars = 0;
    var streamedTextChars = 0;
    final outputKinds = <String, int>{};
    final eventKinds = <String, int>{};
    final finalizedItems = <int, Map<String, dynamic>>{};
    var terminalOutputItems = 0;
    var usage = <String, int>{};
    var usageReported = false;
    Map<String, dynamic>? diagnosticBody;
    String? responseId;
    String? responseModel;
    String? serviceTier;
    var usageFieldPresence = <String, bool>{};
    var responseFieldPresence = <String, bool>{};
    var promptCacheDiagnostics = <String, Object>{};
    var safeError = <String, Object?>{};
    var transport = <String, Object?>{};
    var requestSegments = <String, Map<String, Object>>{};
    var omittedInputSegments = 0;
    final advertisedToolNames =
        tools?.tools.keys.map((name) => name.value).toList() ?? <String>[];
    advertisedToolNames.sort();
    final timer = Timer(deadline, () => session.stop('inference_timeout'));
    try {
      final body = encodeRequest(request, tools: tools);
      final encodedBody = jsonEncode(body);
      diagnosticBody = body;
      if (observeDecision != null) {
        requestSegments = _requestSegments(body);
        final input = body['input'] as List;
        omittedInputSegments = input.length > 64 ? input.length - 64 : 0;
      }
      // A cancelled cast detaches from shared auth work; it does not cancel
      // another actor's refresh or dispatch inference after auth later settles.
      final account = await Future.any<ChatGptAccount>([
        auth.accountForInference(clientId),
        session.abort.future.then(
          (_) => throw const _ResponseFailure('inference_cancelled'),
        ),
      ]);
      if (session.stopped) return;
      final context = InferenceSessionContext.fromRequest(request);
      final sessionOptions = OpenAiSessionOptions.fromRequest(request);
      final routing = context == null || sessionOptions?.turnAffinity != true
          ? null
          : _sessionState._reconcile(context, account, auth, model);
      final wire =
          http.AbortableRequest(
              'POST',
              Uri.parse('https://api.openai.com/v1/responses'),
              abortTrigger: session.abort.future,
            )
            ..followRedirects = false
            ..headers.addAll({
              'Authorization': 'Bearer ${account.accessToken}',
              'Content-Type': 'application/json',
              'Accept': 'text/event-stream',
              if (context != null && sessionOptions?.sessionAffinity == true)
                'session-id': context.session.effectiveAffinityKey,
              if (context != null && sessionOptions?.sessionAffinity == true)
                'thread-id': context.session.id,
              if (routing?.token != null) 'x-codex-turn-state': routing!.token!,
            })
            ..body = encodedBody;
      if (diagnosticCapture != null) {
        transport = captureContextTransportMetadata(
          endpoint: wire.url,
          method: wire.method,
          requestHeaders: wire.headers,
          requestBody: body,
          clientCohort: _diagnosticClientCohort,
          followRedirects: wire.followRedirects,
        );
      }
      _diagnostic(
        body,
        request,
        ContextTransportDiagnosticStage.request,
        encodedBody: encodedBody,
        transport: transport,
      );
      final response = await _client.send(wire);
      if (response.statusCode == 200 && routing != null) {
        _sessionState._observe(routing, response.headers);
      }
      if (diagnosticCapture != null) {
        transport = captureContextTransportMetadata(
          endpoint: wire.url,
          method: wire.method,
          requestHeaders: wire.headers,
          requestBody: body,
          clientCohort: _diagnosticClientCohort,
          followRedirects: wire.followRedirects,
          responseHeaders: response.headers,
        );
      }
      httpStatus = response.statusCode;
      if (response.statusCode != 200) {
        _available = false;
        throw _ResponseFailure(
          await _httpFailure(response, body, (value) => safeError = value),
        );
      }
      session.emit(
        InferenceStructuredTextStreamEventType.lifecycle,
        lifecycle: InferenceStructuredTextLifecycleState.running,
      );
      var bytes = 0;
      final bounded = response.stream.map((chunk) {
        bytes += chunk.length;
        if (bytes > maxResponseBytes) {
          throw const _ResponseFailure('response_too_large');
        }
        return chunk;
      });
      final data = <String>[];
      await for (final line
          in bounded.transform(utf8.decoder).transform(const LineSplitter())) {
        if (session.stopped) break;
        if (line.startsWith('data:')) data.add(line.substring(5).trimLeft());
        if (line.isEmpty && data.isNotEmpty) {
          final payload = data.join('\n');
          data.clear();
          if (payload == '[DONE]') continue;
          final event = jsonDecode(payload) as Map<String, dynamic>;
          final type = event['type'];
          final eventKind = switch (type) {
            'response.created' => 'created',
            'response.in_progress' => 'in_progress',
            'response.output_item.added' => 'item_added',
            'response.output_item.done' => 'item_done',
            'response.function_call_arguments.delta' => 'arguments_delta',
            'response.function_call_arguments.done' => 'arguments_done',
            'response.output_text.delta' => 'text_delta',
            'response.output_text.done' => 'text_done',
            'response.completed' => 'completed',
            'response.failed' => 'failed',
            'response.incomplete' => 'incomplete',
            'error' => 'error',
            _ => 'other',
          };
          eventKinds.update(eventKind, (count) => count + 1, ifAbsent: () => 1);
          if (type == 'response.output_item.done') {
            final index = event['output_index'];
            final item = event['item'];
            if (index is! int || index < 0 || item is! Map<String, dynamic>) {
              throw const _ResponseFailure('response_output_invalid');
            }
            final prior = finalizedItems[index];
            if (prior != null &&
                _canonicalItem(prior) != _canonicalItem(item)) {
              throw const _ResponseFailure('response_output_conflict');
            }
            finalizedItems[index] = item;
          } else if (type == 'response.output_text.delta') {
            final delta = event['delta'];
            if (delta is String) streamedTextChars += delta.length;
            session.emit(
              InferenceStructuredTextStreamEventType.partialOutput,
              delta: event['delta'] as String?,
            );
          } else if (type == 'response.completed') {
            final completed = event['response'] as Map<String, dynamic>;
            if (completed['status'] != 'completed') {
              throw const _ResponseFailure('invalid_terminal_status');
            }
            usage = _numericUsage(completed['usage']);
            usageReported = completed.containsKey('usage');
            responseId = _safeIdentifier(completed['id']);
            responseModel = _safeIdentifier(completed['model']);
            serviceTier = _safeIdentifier(completed['service_tier']);
            promptCacheDiagnostics = _safeCacheDiagnostics(
              completed['prompt_cache_diagnostics'],
            );
            responseFieldPresence = {
              for (final key in [
                'id',
                'model',
                'service_tier',
                'prompt_cache_diagnostics',
                'cache_diagnostics',
              ])
                key: completed.containsKey(key),
            };
            final rawUsage = completed['usage'];
            if (rawUsage is Map) {
              usageFieldPresence = {
                for (final key in [
                  'input_tokens',
                  'output_tokens',
                  'total_tokens',
                  'cache_write_tokens',
                  'input_tokens_details',
                  'output_tokens_details',
                ])
                  key: rawUsage.containsKey(key),
                for (final key in ['cached_tokens', 'cache_write_tokens'])
                  'input_tokens_details.$key':
                      rawUsage['input_tokens_details'] is Map &&
                      (rawUsage['input_tokens_details'] as Map).containsKey(
                        key,
                      ),
              };
            }
            final terminal = (completed['output'] as List)
                .cast<Map<String, dynamic>>();
            terminalOutputItems = terminal.length;
            final output = terminal.isEmpty && finalizedItems.isNotEmpty
                ? _finalizedOutput(finalizedItems)
                : terminal;
            if (output.isEmpty) {
              throw const _ResponseFailure('response_empty_output');
            }
            for (final entry in finalizedItems.entries) {
              if (entry.key >= output.length ||
                  _canonicalItem(entry.value) !=
                      _canonicalItem(output[entry.key])) {
                throw const _ResponseFailure('response_output_conflict');
              }
            }
            for (final item in output) {
              if (item['status'] != null && item['status'] != 'completed') {
                throw const _ResponseFailure('response_item_incomplete');
              }
              final kind = switch (item['type']) {
                'message' => 'message',
                'reasoning' => 'reasoning',
                'function_call' => 'function_call',
                _ => 'other',
              };
              outputKinds.update(kind, (count) => count + 1, ifAbsent: () => 1);
              if (item['type'] == 'message' && item['content'] is List) {
                for (final content in item['content'] as List) {
                  if (content is Map &&
                      content['type'] == 'output_text' &&
                      content['text'] is String) {
                    wireTextChars += (content['text'] as String).length;
                  }
                }
              }
            }
            final text = StringBuffer();
            final calls = <ToolCall>[];
            final callIds = <String>{};
            for (final item in output) {
              if (item['type'] == 'message') {
                for (final content
                    in (item['content'] as List).cast<Map<String, dynamic>>()) {
                  if (content['type'] == 'output_text') {
                    text.write(content['text'] as String);
                  }
                  if (content['type'] == 'refusal') {
                    throw const _ResponseFailure('model_refusal');
                  }
                }
              } else if (item['type'] == 'function_call') {
                final name = item['name'] as String;
                final callId = item['call_id'];
                if (callId is! String ||
                    callId.isEmpty ||
                    !callIds.add(callId)) {
                  throw const _ResponseFailure('invalid_tool_call');
                }
                final arguments = jsonDecode(item['arguments'] as String);
                if (arguments is! Map<String, dynamic>) {
                  throw const _ResponseFailure('invalid_tool_arguments');
                }
                final namespace = item['namespace'];
                if (namespace != null && namespace != 'harness') {
                  throw const _ResponseFailure('tool_namespace_unsupported');
                }
                if (tools == null || tools.get(ToolName(name)) == null) {
                  throw const _ResponseFailure('tool_not_advertised');
                }
                calls.add(
                  ToolCall(
                    name: ToolName(name),
                    arguments: arguments,
                    callId: callId,
                    namespace: namespace as String?,
                  ),
                );
              } else if (item['type'] != 'reasoning') {
                throw const _ResponseFailure('response_item_unsupported');
              }
            }
            Map<String, dynamic> structured = const {};
            if (request.outputSchema.isNotEmpty && calls.isEmpty) {
              final parsed = parseStrictJsonObject(text.toString());
              if (!parsed.success || parsed.data == null) {
                throw const _ResponseFailure('invalid_structured_output');
              }
              final valid = validateJsonAgainstSchema(
                value: parsed.data,
                schema: _outputSchema(request),
              );
              if (!valid.success) {
                throw const _ResponseFailure('invalid_structured_output');
              }
              structured = parsed.data!;
            }
            _available = true;
            session.finish(
              InferenceResult.ok(
                InferenceResponse(
                  task: request.task,
                  rawOutput: text.toString(),
                  structuredOutput: structured,
                  toolCalls: calls,
                  meta: {
                    'provider': id,
                    'model': model,
                    'response_id': completed['id'],
                    'usage': completed['usage'],
                    'responses_output': output,
                    'tool_call_ids': callIds.toList(),
                  },
                ),
              ),
            );
            break;
          } else if (type == 'response.failed' ||
              type == 'response.incomplete' ||
              type == 'error') {
            final error =
                (event['response'] as Map?)?['error'] ?? event['error'];
            final code = error is Map ? error['code'] : event['code'];
            throw _ResponseFailure(switch (code) {
              'subscription_sharing_usage_limit_exceeded' =>
                'subscription_usage_limit_exceeded',
              'subscription_sharing_usage_unavailable' =>
                'subscription_usage_unavailable',
              'subscription_sharing_unsupported_capability' =>
                'subscription_capability_unsupported',
              _ =>
                type == 'response.incomplete'
                    ? 'response_incomplete'
                    : 'response_failed',
            });
          }
        }
      }
      if (!session.stopped) throw const _ResponseFailure('stream_interrupted');
    } on _ResponseFailure catch (error) {
      session.stop(error.code);
    } on ChatGptAuthException catch (error) {
      session.stop(error.code);
    } catch (_) {
      session.stop('responses_transport_failed');
    } finally {
      timer.cancel();
      ContextDiagnosticSnapshot? contextDiagnostic;
      if (diagnosticBody case final body?) {
        final result = await session.result;
        contextDiagnostic = _diagnostic(
          body,
          request,
          ContextTransportDiagnosticStage.settled,
          usage: usage,
          usageReported: usageReported,
          responseId: responseId,
          responseModel: responseModel,
          serviceTier: serviceTier,
          outcome: result.success
              ? 'completed'
              : result.error?.code ?? 'failed',
          httpStatus: httpStatus,
          safeError: safeError,
          transport: transport,
        );
      }
      if (observeDecision case final observer?) {
        final result = await session.result;
        final data = result.data;
        try {
          observer(
            ResponsesDecisionReceipt(
              advertisedTools: tools?.tools.length ?? 0,
              advertisedToolNames: List.unmodifiable(advertisedToolNames),
              requestSegments: Map.unmodifiable(requestSegments),
              omittedInputSegments: omittedInputSegments,
              schemaRequested: request.outputSchema.isNotEmpty,
              httpStatus: httpStatus,
              elapsedMs: elapsed.elapsedMilliseconds,
              reasoningEffort:
                  supportedReasoningEfforts.contains(request.reasoningEffort)
                  ? request.reasoningEffort
                  : null,
              outputKinds: Map.unmodifiable(outputKinds),
              eventKinds: Map.unmodifiable(eventKinds),
              terminalOutputItems: terminalOutputItems,
              streamedDoneItems: finalizedItems.length,
              wireTextChars: wireTextChars,
              streamedTextChars: streamedTextChars,
              parsedTextChars: data?.rawOutput?.length ?? 0,
              parsedToolCalls: data?.toolCalls.length ?? 0,
              structuredKeys: data?.structuredOutput.length ?? 0,
              usage: Map.unmodifiable(usage),
              usageReported: usageReported,
              usageFieldPresence: Map.unmodifiable(usageFieldPresence),
              responseFieldPresence: Map.unmodifiable(responseFieldPresence),
              responseId: diagnosticCapture == null ? null : responseId,
              responseModel: diagnosticCapture == null ? null : responseModel,
              serviceTier: diagnosticCapture == null ? null : serviceTier,
              promptCacheDiagnostics: diagnosticCapture == null
                  ? const {}
                  : Map.unmodifiable(promptCacheDiagnostics),
              contextDiagnostic: contextDiagnostic,
              providerErrorCode: safeError['code'] as String?,
              providerErrorType: safeError['type'] as String?,
              providerErrorParam: safeError['param'] as String?,
              providerErrorFieldPresence:
                  (safeError['presence'] as Map?)?.cast<String, bool>() ??
                  const {},
              outcome: result.success
                  ? 'completed'
                  : result.error?.code ?? 'failed',
            ),
          );
        } on Object {
          // Observation must never alter the provider result or physical owner.
        }
      }
      session.settled.complete();
      _sessions.remove(session);
    }
  }

  static List<Map<String, dynamic>> _finalizedOutput(
    Map<int, Map<String, dynamic>> items,
  ) {
    final output = <Map<String, dynamic>>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      if (item == null) {
        throw const _ResponseFailure('response_output_incomplete');
      }
      output.add(item);
    }
    return output;
  }

  static String _canonicalItem(Map<String, dynamic> item) {
    Object? ordered(Object? value) {
      if (value is Map<String, dynamic>) {
        final keys = value.keys.toList()..sort();
        return {for (final key in keys) key: ordered(value[key])};
      }
      if (value is List) return value.map(ordered).toList();
      return value;
    }

    return jsonEncode(ordered(item));
  }

  /// Hash encoded request segments without retaining their content. Provider
  /// encrypted continuation material is excluded even from fingerprints.
  static Map<String, Map<String, Object>> _requestSegments(
    Map<String, dynamic> body,
  ) {
    Object? scrub(Object? value) {
      if (value is Map) {
        return {
          for (final entry in value.entries)
            if (entry.key != 'encrypted_content') entry.key: scrub(entry.value),
        };
      }
      if (value is List) return value.map(scrub).toList();
      return value;
    }

    Map<String, Object> fingerprint(Object? value) {
      final bytes = utf8.encode(jsonEncode(scrub(value)));
      return {
        'bytes': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      };
    }

    final input = body['input'] as List;
    return {
      for (final name in [
        'model',
        'instructions',
        'tools',
        'reasoning',
        'text',
      ])
        if (body.containsKey(name)) name: fingerprint(body[name]),
      'input': fingerprint(input),
      for (var i = 0; i < input.length && i < 64; i++)
        'input[$i]': fingerprint(input[i]),
    };
  }

  static String? _safeIdentifier(Object? value) =>
      value is String && RegExp(r'^[a-zA-Z0-9_.:/-]{1,160}$').hasMatch(value)
      ? value
      : null;

  static Map<String, Object> _safeCacheDiagnostics(Object? value) {
    if (value is! Map) return {};
    return {
      if (const [
        'cache_hit',
        'cache_miss',
        'comparison_response_not_found',
        'unavailable',
      ].contains(value['type']))
        'type': value['type'] as String,
      if (const [
        'model_changed',
        'prompt_cache_key_changed',
        'service_tier_changed',
        'tools_changed',
        'parallel_tool_calls_changed',
        'response_format_changed',
        'text_format_changed',
        'reasoning_effort_changed',
        'text_verbosity_changed',
        'verbosity_changed',
        'context_management_changed',
        'context_compacted',
        'input_changed',
        'instructions_changed',
      ].contains(value['reason']))
        'reason': value['reason'] as String,
      for (final key in ['comparison_reusable_tokens', 'cache_missed_tokens'])
        if (value[key] is int && (value[key] as int) >= 0)
          key: value[key] as int,
    };
  }

  static Map<String, int> _numericUsage(Object? value) {
    if (value is! Map) return {};
    final result = <String, int>{};
    void retain(String name, Object? number) {
      if (number is int && number >= 0) result[name] = number;
    }

    for (final name in ['input_tokens', 'output_tokens', 'total_tokens']) {
      retain(name, value[name]);
    }
    final input = value['input_tokens_details'];
    final output = value['output_tokens_details'];
    if (input is Map) {
      retain('cached_tokens', input['cached_tokens']);
      retain('cache_write_tokens', input['cache_write_tokens']);
    }
    if (!result.containsKey('cache_write_tokens')) {
      retain('cache_write_tokens', value['cache_write_tokens']);
    }
    if (output is Map) retain('reasoning_tokens', output['reasoning_tokens']);
    return result;
  }

  @override
  void close() {
    cancelActive();
    if (_ownsClient) _client.close();
  }

  /// Remote messages can echo credentials or document content. Retain only a
  /// fixed diagnostic category and broad parameter family from bounded JSON.
  static Future<String> _httpFailure(
    http.StreamedResponse response,
    Map<String, dynamic> request,
    void Function(Map<String, Object?>) observeSafeError,
  ) async {
    if (response.statusCode == 401 || response.statusCode == 429) {
      await response.stream.listen((_) {}).cancel();
      return response.statusCode == 401
          ? 'subscription_auth_failed'
          : 'subscription_usage_unavailable';
    }
    final base = 'responses_http_failed_${response.statusCode}';
    final bytes = <int>[];
    try {
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > 16 * 1024) return base;
        bytes.addAll(chunk);
      }
      final body = jsonDecode(utf8.decode(bytes));
      final error = body is Map ? body['error'] : null;
      observeSafeError({
        if (error is Map) ..._safeHttpError(error, request),
        'messageHint': contextProviderErrorMessageHint(body),
      });
      if (error is! Map) return base;
      final code = error['code'];
      if (code != 'invalid_json_schema' &&
          code != 'invalid_function_parameters' &&
          code != 'invalid_value' &&
          code != 'unsupported_parameter') {
        return base;
      }
      final param = error['param'];
      final family = param is String && param.startsWith('text.')
          ? 'text'
          : param is String && param.startsWith('tools')
          ? 'tools'
          : 'other';
      return '${base}_${code}_$family';
    } on Object {
      return base;
    }
  }

  static Map<String, Object?> _safeHttpError(
    Map error,
    Map<String, dynamic> request,
  ) => {
    'presence': {
      for (final key in ['code', 'type', 'param']) key: error.containsKey(key),
    },
    'code':
        const [
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

  static Map<String, dynamic> _outputSchema(InferenceRequest request) {
    final schema = request.outputSchema;
    final root = schema['root'];
    if (!schema.containsKey('type') &&
        root is Map &&
        root['kind'] is String &&
        schema['dependencies'] is List) {
      try {
        return _wireSchema(SchemaBundle.fromJson(schema));
      } on _ResponseFailure {
        rethrow;
      } on Object {
        throw const _ResponseFailure('schema_invalid');
      }
    }
    return schema;
  }

  static Map<String, dynamic> _wireSchema(SchemaBundle bundle) {
    try {
      return bundleToJsonSchema(bundle);
    } on ArgumentError {
      // The shared converter requires references to be resolved by the caller.
      throw const _ResponseFailure('schema_unsupported');
    }
  }
}

final class _ResponseFailure implements Exception {
  const _ResponseFailure(this.code);
  final String code;
}

final class _ResponsesSession implements InferenceStructuredTextStreamSession {
  final _events = StreamController<InferenceStructuredTextStreamEvent>();
  final _result = Completer<InferenceResult<InferenceResponse>>();
  final abort = Completer<void>();
  final settled = Completer<void>();
  bool get stopped => _result.isCompleted;
  @override
  Stream<InferenceStructuredTextStreamEvent> get events => _events.stream;
  @override
  Future<InferenceResult<InferenceResponse>> get result => _result.future;
  void emit(
    InferenceStructuredTextStreamEventType type, {
    String? delta,
    InferenceStructuredTextLifecycleState? lifecycle,
    InferenceStructuredTextCompletion? completion,
  }) {
    if (!_events.isClosed) {
      _events.add(
        InferenceStructuredTextStreamEvent(
          type: type,
          timestamp: DateTime.now().toUtc(),
          textDelta: delta,
          lifecycleState: lifecycle,
          completion: completion,
        ),
      );
    }
  }

  void finish(InferenceResult<InferenceResponse> result) {
    if (stopped) return;
    emit(
      InferenceStructuredTextStreamEventType.completion,
      completion: InferenceStructuredTextCompletion(result: result),
    );
    _result.complete(result);
    unawaited(_events.close());
  }

  void stop(String code) {
    if (stopped) return;
    if (!abort.isCompleted) abort.complete();
    finish(
      InferenceResult.fail(
        code: code,
        message: 'Native Responses request did not complete.',
      ),
    );
  }

  @override
  Future<void> cancel() async {
    stop('inference_cancelled');
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await settled.future;
  }
}

final class _CatalogRequest {
  final abort = Completer<void>();
  final settled = Completer<void>();
  String failureCode = 'model_catalog_cancelled';
  void cancel(String code) {
    if (abort.isCompleted) return;
    failureCode = code;
    abort.complete();
  }
}
