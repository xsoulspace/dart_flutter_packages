import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'grok_auth.dart';

/// Hosts may already attach Responses continuation items under this key.
const grokResponsesInputKey = 'grok_responses_input';
const grokLegacyResponsesInputKey = 'openai_responses_input';

/// One Responses call against the registered client's API base.
/// Tool execution stays with the host. Text is delivered as one delta
/// after the response completes; this is not token streaming.
final class GrokResponsesClient
    implements
        StructuredTextStreamingInferenceClient,
        ToolStreamingInferenceClient,
        ReasoningEffortInferenceClient,
        CancellableInferenceClient {
  GrokResponsesClient({
    required this.auth,
    required this.subject,
    required this.model,
    http.Client? client,
    this.deadline = const Duration(minutes: 5),
    this.maxResponseBytes = 4 * 1024 * 1024,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final GrokAuth auth;
  final String subject;
  final String model;
  final http.Client _client;
  final bool _ownsClient;
  final Duration deadline;
  final int maxResponseBytes;
  bool _available = false;
  bool _closed = false;
  int _epoch = 0;
  final _active = <Completer<void>>{};

  static const _efforts = {'low', 'medium', 'high'};

  @override
  String get id => 'xai_grok_plan';
  @override
  bool get isAvailable => _available && !_closed;
  @override
  Set<InferenceTask> get supportedTasks => const {
    InferenceTask.text,
    InferenceTask.implicitlyStructuredText,
    InferenceTask.nativelyStructuredText,
  };
  @override
  Set<String> get supportedReasoningEfforts => _efforts;

  @override
  Future<bool> refreshAvailability() async {
    try {
      _available = (await listModels()).any((entry) => entry.slug == model);
    } on Object {
      _available = false;
    }
    return _available;
  }

  @override
  Future<void> load() async {
    await refreshAvailability();
  }

  @override
  void resetAvailabilityCache() {
    _available = false;
  }

  Future<List<({String slug, String displayName})>> listModels() async {
    final account = await auth.accountForInference(subject);
    final response = await _get(
      Uri.parse('${_base()}/models'),
      account.accessToken,
    );
    if (response.statusCode != 200) {
      throw const GrokAuthException('model_catalog_unavailable');
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic> || body['data'] is! List) {
      throw const GrokAuthException('model_catalog_unavailable');
    }
    return [
      for (final item in body['data'] as List)
        if (item is Map && item['id'] is String)
          (
            slug: item['id'] as String,
            displayName: item['id'] as String,
          ),
    ];
  }

  @override
  Future<InferenceResult<InferenceResponse>> infer(
    InferenceRequest request, {
    ToolRegistry? toolRegistry,
  }) {
    final epoch = _epoch;
    final done = Completer<void>();
    _active.add(done);
    return _infer(request, toolRegistry, epoch).whenComplete(() {
      if (!done.isCompleted) done.complete();
      _active.remove(done);
    });
  }

  Future<InferenceResult<InferenceResponse>> _infer(
    InferenceRequest request,
    ToolRegistry? tools,
    int epoch,
  ) async {
    try {
      if (_closed || epoch != _epoch) {
        throw const GrokAuthException('inference_cancelled');
      }
      final body = _encode(request, tools);
      final account = await auth.accountForInference(subject);
      if (_closed || epoch != _epoch) {
        throw const GrokAuthException('inference_cancelled');
      }
      final response = await _client
          .post(
            Uri.parse('${_base()}/responses'),
            headers: {
              'authorization': 'Bearer ${account.accessToken}',
              'content-type': 'application/json',
              'accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(deadline);
      if (response.bodyBytes.length > maxResponseBytes) {
        throw const GrokAuthException('response_too_large');
      }
      if (_closed || epoch != _epoch) {
        throw const GrokAuthException('inference_cancelled');
      }
      if (response.statusCode == 401) {
        throw const GrokAuthException('sign_in_required');
      }
      if (response.statusCode != 200) {
        throw const GrokAuthException('response_failed');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const GrokAuthException('response_failed');
      }
      return InferenceResult.ok(_decode(decoded, request));
    } on GrokAuthException catch (error) {
      return InferenceResult.fail(code: error.code, message: error.code);
    } on TimeoutException {
      return InferenceResult.fail(
        code: 'response_timeout',
        message: 'response_timeout',
      );
    } on Object {
      if (_closed || epoch != _epoch) {
        return InferenceResult.fail(
          code: 'inference_cancelled',
          message: 'inference_cancelled',
        );
      }
      return InferenceResult.fail(
        code: 'response_failed',
        message: 'response_failed',
      );
    }
  }

  @override
  Future<InferenceStructuredTextStreamSession> streamStructuredText(
    InferenceRequest request,
  ) => _stream(request, null);

  @override
  Future<InferenceStructuredTextStreamSession> streamWithTools(
    InferenceRequest request, {
    required ToolRegistry toolRegistry,
  }) => _stream(request, toolRegistry);

  Future<InferenceStructuredTextStreamSession> _stream(
    InferenceRequest request,
    ToolRegistry? tools,
  ) async {
    final result = infer(request, toolRegistry: tools);
    final controller = StreamController<InferenceStructuredTextStreamEvent>();
    final session = _GrokStream(result, controller.stream, this);
    unawaited(() async {
      final value = await result;
      final text = value.data?.presentationText;
      if (text != null && text.isNotEmpty && !controller.isClosed) {
        controller.add(
          InferenceStructuredTextStreamEvent(
            type: InferenceStructuredTextStreamEventType.partialOutput,
            timestamp: DateTime.now().toUtc(),
            textDelta: text,
          ),
        );
      }
      await controller.close();
    }());
    return session;
  }

  Map<String, dynamic> _encode(InferenceRequest request, ToolRegistry? tools) {
    if (!supportedTasks.contains(request.task)) {
      throw const GrokAuthException('task_unsupported');
    }
    if (request.maxTokens != null ||
        request.temperature != null ||
        request.stopSequences.isNotEmpty ||
        request.thinking != null) {
      throw const GrokAuthException('generation_option_unsupported');
    }
    final effort = request.reasoningEffort;
    if (effort != null && !_efforts.contains(effort)) {
      throw const GrokAuthException('reasoning_effort_unsupported');
    }
    if (model.isEmpty) throw const GrokAuthException('empty_request');
    final instructions = <String>[
      if (request.systemPrompt.isNotEmpty) request.systemPrompt,
    ];
    final input = <Map<String, dynamic>>[];
    for (final message in request.messages) {
      if (message.role == ChatRole.system) {
        instructions.add(message.content);
      } else if (message.role == ChatRole.tool) {
        throw const GrokAuthException('tool_call_identity_required');
      } else {
        input.add({'role': message.role.toJson(), 'content': message.content});
      }
    }
    for (final fragment in request.contextFragments) {
      input.add({'role': 'user', 'content': fragment.toString()});
    }
    final native =
        request.metadata[grokResponsesInputKey] ??
        request.metadata[grokLegacyResponsesInputKey];
    if (native != null) {
      if (native is! List) throw const GrokAuthException('invalid_native_input');
      for (final item in native) {
        if (item is! Map) {
          throw const GrokAuthException('invalid_native_input');
        }
        input.add(Map<String, dynamic>.from(item));
      }
    }
    if (request.prompt.isNotEmpty) {
      input.add({'role': 'user', 'content': request.prompt});
    }
    if (input.isEmpty) throw const GrokAuthException('empty_request');
    final definitions = tools?.tools.values.toList() ?? <ToolDef>[];
    definitions.sort((a, b) => a.name.value.compareTo(b.name.value));
    return {
      'model': model,
      'input': input,
      if (instructions.isNotEmpty) 'instructions': instructions.join('\n\n'),
      if (effort != null) 'reasoning': {'effort': effort},
      if (request.seed != null) 'seed': request.seed,
      if (definitions.isNotEmpty)
        'tools': [
          for (final tool in definitions)
            {
              'type': 'function',
              'name': tool.name.value,
              'description': tool.description,
              'parameters': {'type': 'object', 'additionalProperties': true},
            },
        ],
    };
  }

  InferenceResponse _decode(
    Map<String, dynamic> body,
    InferenceRequest request,
  ) {
    final text = StringBuffer();
    final calls = <ToolCall>[];
    final output = body['output'];
    if (output is List) {
      for (final item in output) {
        if (item is! Map) continue;
        if (item['type'] == 'function_call') {
          final name = item['name'];
          if (name is! String || name.isEmpty) {
            throw const GrokAuthException('response_failed');
          }
          calls.add(
            ToolCall(
              name: ToolName(name),
              arguments: _arguments(item['arguments']),
              callId: item['call_id'] as String?,
            ),
          );
        } else if (item['type'] == 'message') {
          final content = item['content'];
          if (content is List) {
            for (final part in content) {
              if (part is Map && part['text'] is String) {
                text.write(part['text']);
              }
            }
          }
        }
      }
    }
    if (text.isEmpty && body['output_text'] is String) {
      text.write(body['output_text']);
    }
    final usage = body['usage'];
    return InferenceResponse(
      presentationText: text.toString(),
      rawOutput: text.toString(),
      task: request.task,
      toolCalls: calls,
      meta: {
        'response_id': body['id'],
        if (usage is Map) 'usage': usage.cast<String, Object?>(),
        if (request.seed != null) inferenceSeedMetaKey: request.seed,
      },
    );
  }

  Map<String, dynamic> _arguments(Object? value) {
    if (value is Map) return value.cast<String, dynamic>();
    if (value is String && value.isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
    }
    return const {};
  }

  String _base() {
    final base = auth.registration.apiBase;
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }

  Future<http.Response> _get(Uri uri, String accessToken) => _client
      .get(uri, headers: {'authorization': 'Bearer $accessToken'})
      .timeout(deadline);

  @override
  void cancelActive() {
    _epoch++;
  }

  @override
  Future<void> settleActive() => Future.wait(_active.map((done) => done.future));

  @override
  void close() {
    _closed = true;
    cancelActive();
    if (_ownsClient) _client.close();
  }
}

final class _GrokStream implements InferenceStructuredTextStreamSession {
  _GrokStream(this.result, this.events, this._client);
  @override
  final Future<InferenceResult<InferenceResponse>> result;
  @override
  final Stream<InferenceStructuredTextStreamEvent> events;
  final GrokResponsesClient _client;

  @override
  Future<void> cancel() async {
    _client.cancelActive();
  }

  @override
  Future<void> dispose() async {}
}
