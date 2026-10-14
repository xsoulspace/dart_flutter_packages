import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'laya_native_lfm2_chat_template.dart';
import 'laya_native_lfm2_client.dart';
import 'laya_native_qwen_chat_template.dart';
import 'laya_native_qwen_client.dart';
import 'native_text_protocol.dart';

export 'native_text_model_names.dart';

/// The EOS stop's emitted token must not ride the answer (HF convention —
/// the native stop keeps the token; the wire and the unified client strip
/// its literal).
String _stripEosLiteral(String text) => text
    .replaceAll(RegExp(r'<\|im_end\|>$'), '')
    .replaceAll(RegExp(r'<\|endoftext\|>$'), '')
    .trim();

({List<int> promptIds, List<int> ids, String text}) _toRecord(
  List<int> promptIds,
  List<int> ids,
  String text,
) => (promptIds: promptIds, ids: ids, text: text);

/// One normalized completion from either driver (the two engines expose
/// identically-shaped completions; this signature is the seam that lets
/// one client serve both casts, eager or lazy).
typedef _Generate =
    Future<({List<int> promptIds, List<int> ids, String text})> Function({
      required String prompt,
      required int maxTokens,
      required bool stopOnEos,
      required List<int> eosIds,
    });

typedef _Render =
    String Function({
      required String system,
      required String user,
      required List<ChatMessage> messages,
      required List<Object?>? tools,
      required bool thinking,
    });

/// A native text engine (Qwen3 or LFM2.5) bound as an [InferenceClient]
/// — the unified interface every provider in the monorepo answers to
/// (ADR 0058).
///
/// The client IS the bench's winning cell: requests render through the
/// checkpoint's fixture-gated chat template and generation stops at the
/// model's EOS ids (emitted, then stripped from the answer). There is no
/// raw mode here on purpose — raw cells are a bench reproduction, not a
/// serving shape (the bench reproduces them with its own flags).
///
/// Capability honesty, mirroring `MlxLocalTextClient`: `id` names the
/// cast; only [InferenceTask.text] is supported; the engines decode
/// greedily, so a non-zero request temperature lands in
/// [InferenceResult.warnings] instead of being silently pretended; tool
/// rendering is a template fact — both casts render a [ToolRegistry]
/// into their fixture-gated template (ADR 0058 tools rung), and the
/// Qwen's delimited JSON answer is normalized into typed tool calls with
/// its raw source retained. Unqualified checkpoint formats refuse explicitly.
/// A request-level `thinking` overrides the cast's constructor
/// default on Qwen3 and draws an honest warning on LFM2.5 (no switch);
/// non-empty `request.messages` render as the full conversation; otherwise
/// only the projected context cut is reconstructed through the core codec.
///
/// Loading is a construction detail, not a lifecycle requirement: the
/// eager factories ([loadQwen]/[loadLfm2], a passed-in engine) hold a
/// loaded engine, while the LAZY constructors ([lazyQwen]/[lazyLfm2])
/// defer the weight load to the first [load] — the readiness contract
/// `ModelRuntime` already speaks. A lazy client answers `isAvailable`
/// false until the load succeeds; a failed load is recorded (see
/// [loadError]) and re-attempted by the next [load]; [infer] before a
/// successful load returns the typed `unavailable` failure (retryable) —
/// never a socket error, never a hang, never a crash (ADR 0059 palette
/// law). Dispatch rides the engines' `generateAsync` (isolate escape) —
/// a long decode never blocks the calling isolate.
final class MlxNativeTextClient implements InferenceClient {
  MlxNativeTextClient._({
    required this._id,
    required this._eosIds,
    required this._generate,
    required this._render,
    required this.hasThinkingSwitch,
    required this.thinking,
    required this.model,
    required this.defaultMaxTokens,
    required this.defaultTemperature,
    required this.toolSyntax,
    this._loadEngine,
    this._qwenEngine,
    this._qwenCacheScope,
  });

  /// The Qwen3 cast: ChatML with the thinking switch, EOS stop on
  /// `<|im_end|>`/`<|endoftext|>`, tools rendered via the fixture-gated
  /// `# Tools` system block.
  factory MlxNativeTextClient.qwen(
    NativeQwenTextEngine engine, {
    bool thinking = false,
    QwenCacheScope? cacheScope,
    String model = 'qwen3-mlx-4bit',
    int defaultMaxTokens = 320,
    double defaultTemperature = 0.0,
    ToolCallSyntax? toolSyntax = ToolCallSyntax.qwenJson,
  }) => MlxNativeTextClient._(
    id: 'mlx_native_qwen',
    eosIds: () => const <int>[151645, 151643], // <|im_end|>, <|endoftext|>
    generate:
        ({
          required String prompt,
          required int maxTokens,
          required bool stopOnEos,
          required List<int> eosIds,
        }) async {
          final completion = await engine.generateAsync(
            prompt: prompt,
            cacheScope: cacheScope,
            maxTokens: maxTokens,
            stopOnEos: stopOnEos,
            eosIds: eosIds,
          );
          return _toRecord(
            completion.promptIds,
            completion.ids,
            completion.text,
          );
        },
    render: _qwenRender,
    hasThinkingSwitch: true,
    thinking: thinking,
    model: model,
    defaultMaxTokens: defaultMaxTokens,
    defaultTemperature: defaultTemperature,
    toolSyntax: toolSyntax,
    qwenEngine: () => engine,
    qwenCacheScope: cacheScope,
  );

  /// The LFM2.5 cast: the fixture-gated instruct template (tools render
  /// into the system block), EOS stop on the checkpoint's own ids. No
  /// thinking switch — the checkpoint ships none (non-claim).
  factory MlxNativeTextClient.lfm2(
    NativeLfm2TextEngine engine, {
    String model = 'lfm2.5-instruct-mlx-4bit',
    int defaultMaxTokens = 320,
    double defaultTemperature = 0.0,
    ToolCallSyntax? toolSyntax,
  }) => MlxNativeTextClient._(
    id: 'mlx_native_lfm2',
    eosIds: () => engine.specialIds().chatStopIds,
    generate:
        ({
          required String prompt,
          required int maxTokens,
          required bool stopOnEos,
          required List<int> eosIds,
        }) async {
          final completion = await engine.generateAsync(
            prompt: prompt,
            maxTokens: maxTokens,
            stopOnEos: stopOnEos,
            eosIds: eosIds,
          );
          return _toRecord(
            completion.promptIds,
            completion.ids,
            completion.text,
          );
        },
    render: _lfmRender,
    hasThinkingSwitch: false,
    thinking: false,
    model: model,
    defaultMaxTokens: defaultMaxTokens,
    defaultTemperature: defaultTemperature,
    toolSyntax: toolSyntax,
  );

  /// The lazy Qwen3 cast: the weight load happens on the first [load]
  /// (composition stays cheap; a bounded last-in-order lane is used only
  /// on explicit cast). Same render/stop behavior as
  /// [MlxNativeTextClient.qwen].
  factory MlxNativeTextClient.lazyQwen({
    String? snapshotDir,
    bool thinking = false,
    String model = 'qwen3-mlx-4bit',
    int defaultMaxTokens = 320,
    double defaultTemperature = 0.0,
    ToolCallSyntax? toolSyntax = ToolCallSyntax.qwenJson,
  }) {
    NativeQwenTextEngine? engine;
    final client = MlxNativeTextClient._(
      id: 'mlx_native_qwen',
      eosIds: () => const <int>[151645, 151643],
      generate: _boxedQwenGenerate(() => engine),
      render: _qwenRender,
      hasThinkingSwitch: true,
      thinking: thinking,
      model: model,
      defaultMaxTokens: defaultMaxTokens,
      defaultTemperature: defaultTemperature,
      toolSyntax: toolSyntax,
      loadEngine: () async {
        engine = await NativeQwenTextEngine.load(snapshotDir: snapshotDir);
      },
      qwenEngine: () => engine,
    );
    client._onUnloadEngine = () {
      engine?.dispose();
      engine = null;
    };
    return client;
  }

  /// The lazy LFM2.5 cast: see [lazyQwen]. The EOS stop ids resolve from
  /// the checkpoint's own tokenizer once loaded (never carried across
  /// checkpoints); until then the empty list simply never matches, and
  /// [infer] refuses before reaching a generate call anyway.
  factory MlxNativeTextClient.lazyLfm2({
    String? snapshotDir,
    String model = 'lfm2.5-instruct-mlx-4bit',
    int defaultMaxTokens = 320,
    double defaultTemperature = 0.0,
    ToolCallSyntax? toolSyntax,
  }) {
    NativeLfm2TextEngine? engine;
    final client = MlxNativeTextClient._(
      id: 'mlx_native_lfm2',
      eosIds: () => engine?.specialIds().chatStopIds ?? const <int>[],
      generate: _boxedLfmGenerate(() => engine),
      render: _lfmRender,
      hasThinkingSwitch: false,
      thinking: false,
      model: model,
      defaultMaxTokens: defaultMaxTokens,
      defaultTemperature: defaultTemperature,
      toolSyntax: toolSyntax,
      loadEngine: () async {
        engine = await NativeLfm2TextEngine.load(snapshotDir: snapshotDir);
      },
    );
    client._onUnloadEngine = () {
      engine?.dispose();
      engine = null;
    };
    return client;
  }

  /// The shared per-engine generate closure: eager clients close over a
  /// loaded engine; lazy clients over the nullable box their loader
  /// fills ([infer] refuses before a generate when still null).
  static _Generate _boxedQwenGenerate(
    NativeQwenTextEngine? Function() engineBox,
  ) =>
      ({
        required String prompt,
        required int maxTokens,
        required bool stopOnEos,
        required List<int> eosIds,
      }) async {
        final engine = engineBox();
        if (engine == null) {
          throw StateError('native engine not loaded for this client');
        }
        final completion = await engine.generateAsync(
          prompt: prompt,
          maxTokens: maxTokens,
          stopOnEos: stopOnEos,
          eosIds: eosIds,
        );
        return _toRecord(completion.promptIds, completion.ids, completion.text);
      };

  static _Generate _boxedLfmGenerate(
    NativeLfm2TextEngine? Function() engineBox,
  ) =>
      ({
        required String prompt,
        required int maxTokens,
        required bool stopOnEos,
        required List<int> eosIds,
      }) async {
        final engine = engineBox();
        if (engine == null) {
          throw StateError('native engine not loaded for this client');
        }
        final completion = await engine.generateAsync(
          prompt: prompt,
          maxTokens: maxTokens,
          stopOnEos: stopOnEos,
          eosIds: eosIds,
        );
        return _toRecord(completion.promptIds, completion.ids, completion.text);
      };

  /// Qwen's fixture-gated ChatML render: the request's `messages` when
  /// present, else the synthesized system+user pair.
  static String _qwenRender({
    required String system,
    required String user,
    required List<ChatMessage> messages,
    required List<Object?>? tools,
    required bool thinking,
  }) => renderQwenChatPrompt(
    messages: <QwenChatMessage>[
      if (messages.isNotEmpty)
        for (final message in messages)
          QwenChatMessage(role: message.role.name, content: message.content)
      else ...[
        if (system.isNotEmpty) QwenChatMessage(role: 'system', content: system),
        QwenChatMessage(role: 'user', content: user),
      ],
    ],
    tools: tools,
    enableThinking: thinking,
  );

  /// LFM2.5's fixture-gated instruct render. Tool-role turns have no
  /// fixture-gated rendering on this template — [infer] warns; here they
  /// render as user turns.
  static String _lfmRender({
    required String system,
    required String user,
    required List<ChatMessage> messages,
    required List<Object?>? tools,
    required bool thinking,
  }) => renderLfm2ChatPrompt(
    messages: <Lfm2ChatMessage>[
      if (messages.isNotEmpty)
        for (final message in messages)
          Lfm2ChatMessage(
            role: message.role == ChatRole.tool ? 'user' : message.role.name,
            content: message.content,
          )
      else ...[
        if (system.isNotEmpty) Lfm2ChatMessage(role: 'system', content: system),
        Lfm2ChatMessage(role: 'user', content: user),
      ],
    ],
    // The render omits the BOS: the native text path prepends the BOS
    // id itself, so exactly one lands in the token stream.
    includeBos: false,
    tools: tools,
  );

  /// Loads the cached Qwen3 snapshot and returns the client. See
  /// [NativeQwenTextEngine.load] for the resolution order (never
  /// downloads).
  static Future<MlxNativeTextClient> loadQwen({
    String? snapshotDir,
    bool thinking = false,
    String model = 'qwen3-mlx-4bit',
  }) async => MlxNativeTextClient.qwen(
    await NativeQwenTextEngine.load(snapshotDir: snapshotDir),
    thinking: thinking,
    model: model,
  );

  /// Loads the cached LFM2.5 snapshot and returns the client. See
  /// [NativeLfm2TextEngine.load] for the resolution order (never
  /// downloads).
  static Future<MlxNativeTextClient> loadLfm2({
    String? snapshotDir,
    String model = 'lfm2.5-instruct-mlx-4bit',
  }) async => MlxNativeTextClient.lfm2(
    await NativeLfm2TextEngine.load(snapshotDir: snapshotDir),
    model: model,
  );

  final String _id;
  final List<int> Function() _eosIds;
  final _Generate _generate;
  final _Render _render;

  /// Performs the deferred weight load (lazy form only; null = eager).
  final Future<void> Function()? _loadEngine;
  final NativeQwenTextEngine? Function()? _qwenEngine;
  final QwenCacheScope? _qwenCacheScope;

  /// The cast's constructor-default thinking switch. Requests override
  /// per call (`request.thinking`).
  final bool thinking;

  /// Whether this cast can mean a thinking switch at all (Qwen3: yes;
  /// LFM2.5: the checkpoint ships none).
  final bool hasThinkingSwitch;

  /// Wire label reported in the response meta.
  final String model;
  final int defaultMaxTokens;
  final double defaultTemperature;

  /// Explicit checkpoint/finetune syntax; null refuses unqualified envelopes.
  final ToolCallSyntax? toolSyntax;

  bool _disposed = false;
  bool _loaded = false;
  Object? _loadError;
  Future<void>? _pendingLoad;

  @override
  String get id => _id;

  @override
  Set<InferenceTask> get supportedTasks => const <InferenceTask>{
    InferenceTask.text,
  };

  /// Eager clients hold a loaded engine from construction; lazy clients
  /// become available when the first [load] succeeds.
  @override
  bool get isAvailable => !_disposed && (_loaded || _loadEngine == null);

  /// Performs the deferred weight load once per success — a failed load
  /// is recorded ([loadError]) and the next call retries. Concurrent
  /// callers share one attempt. Never throws.
  @override
  Future<void> load() {
    if (_loaded || _disposed || _loadEngine == null) return Future.value();
    final pending = _pendingLoad ??= () async {
      try {
        await _loadEngine();
        _loaded = true;
      } on Object catch (error) {
        _loadError = error;
      }
    }().whenComplete(() => _pendingLoad = null);
    return pending;
  }

  /// The recorded load failure (lazy form; null = no failed attempt).
  Object? get loadError => _loadError;

  @override
  Future<bool> refreshAvailability() async => isAvailable;

  @override
  void resetAvailabilityCache() {
    // No availability cache: status is a live snapshot.
  }

  @override
  Future<InferenceResult<InferenceResponse>> infer(
    InferenceRequest request, {
    ToolRegistry? toolRegistry,
  }) => _inferUsing(request, toolRegistry: toolRegistry, generate: _generate);

  Future<InferenceResult<InferenceResponse>> _inferUsing(
    InferenceRequest request, {
    required ToolRegistry? toolRegistry,
    required _Generate generate,
  }) async {
    if (request.task != InferenceTask.text) {
      return InferenceResult.fail(
        code: 'unsupported_task',
        message:
            '$id supports InferenceTask.text only '
            '(requested ${request.task.name})',
      );
    }
    if (_disposed) {
      return InferenceResult.fail(
        code: 'unavailable',
        message: 'The native engine client was disposed',
        details: <String, Object?>{'retryable': false},
      );
    }
    List<Object?>? tools;
    if (toolRegistry != null && toolRegistry.tools.isNotEmpty) {
      try {
        tools = nativeTextFunctionTools(toolRegistry);
      } on ArgumentError catch (error) {
        return InferenceResult.fail(
          code: 'tool_schema_unsupported',
          message: 'Native function schema cannot be materialized: $error',
        );
      }
    }
    if (!isAvailable) {
      await load();
      if (!isAvailable) {
        return InferenceResult.fail(
          code: 'unavailable',
          message:
              'The native engine for $id is not loaded '
              '(${_loadError ?? 'weights absent or load deferred'})',
          details: <String, Object?>{'retryable': true},
        );
      }
    }
    final warnings = <String>[];
    final temperature = request.temperature ?? defaultTemperature;
    if (temperature != 0.0) {
      warnings.add(
        'mlx_native decodes greedily; temperature $temperature ignored',
      );
    }
    final requestThinking = request.thinking;
    final effectiveThinking = requestThinking ?? thinking;
    if (requestThinking != null && requestThinking && !hasThinkingSwitch) {
      warnings.add(
        '$id has no thinking switch; thinking=true on the request is '
        'honored as a plain generation',
      );
    }
    final messages = nativeTextMessages(request);
    if (!hasThinkingSwitch &&
        messages.any((message) => message.role == ChatRole.tool)) {
      warnings.add(
        '$id has no fixture-gated tool-result rendering; tool turns '
        'render as user turns',
      );
    }
    final maxTokens = request.maxTokens ?? defaultMaxTokens;
    final ({List<int> promptIds, List<int> ids, String text}) completion;
    try {
      completion = await generate(
        prompt: _render(
          system: request.systemPrompt,
          user: request.prompt,
          messages: messages,
          tools: tools,
          thinking: effectiveThinking,
        ),
        maxTokens: maxTokens,
        stopOnEos: true,
        eosIds: _eosIds(),
      );
    } on NativeQwenRequestCancelled {
      return InferenceResult.fail(
        code: 'cancelled',
        message: 'Native Qwen generation was cancelled before completion',
        details: <String, Object?>{'retryable': false},
      );
    } on NativeQwenCancellationUnavailable {
      return InferenceResult.fail(
        code: 'unavailable',
        message:
            'This native Qwen library does not support request cancellation',
        details: <String, Object?>{'retryable': false},
      );
    } on StateError catch (error) {
      return InferenceResult.fail(
        code: 'native_engine',
        message: error.message,
        details: <String, Object?>{'retryable': false},
      );
    }
    final rawOutput = _stripEosLiteral(completion.text);
    final normalized = normalizeNativeTextCalls(
      text: rawOutput,
      syntax: toolSyntax,
      registry: toolRegistry,
      thinkingPrefilled: hasThinkingSwitch && effectiveThinking,
    );
    if (!normalized.success) {
      return nativeTextNormalizationRefusal(
        normalized: normalized,
        rawOutput: rawOutput,
        promptTokens: completion.promptIds.length,
        completionTokens: completion.ids.length - completion.promptIds.length,
      );
    }
    return InferenceResult.ok(
      InferenceResponse(
        task: InferenceTask.text,
        rawOutput: rawOutput,
        presentationText: normalized.data!.presentationText,
        toolCalls: normalized.data!.calls,
        meta: <String, dynamic>{
          'usage': <String, dynamic>{
            'prompt_tokens': completion.promptIds.length,
            'completion_tokens':
                completion.ids.length - completion.promptIds.length,
          },
          'model': model,
          'tool_syntax': toolSyntax?.id,
          'tool_calls_normalized': true,
          'tool_call_sources': normalized.data!.sources,
          'finish_reason': 'stop',
        },
      ),
      warnings: warnings,
    );
  }

  /// Creates a request-cancellable view of this Qwen client. The view shares
  /// the same lazy engine and weights while keeping cancellation request IDs
  /// local to that view, so sibling routers cannot cancel one another.
  CancellableInferenceClient cancellableQwenScope() =>
      _NativeQwenInferenceScope(this);

  /// Marks this client disposed (subsequent [infer] calls answer the
  /// typed `unavailable` failure). Does NOT unload the engine — whoever
  /// loaded it owns its lifetime ([NativeQwenTextEngine.dispose] /
  /// [NativeLfm2TextEngine.dispose]). Not part of the
  /// [InferenceClient] contract.
  void dispose() {
    _disposed = true;
  }

  /// Lazy form only: unloads the engine this client loaded (its
  /// `dispose()`) and returns the client to the not-loaded state — the
  /// next [load] re-loads. This is how a long-lived embed (the LA host
  /// restarts its daemon in-process) frees a cast it stopped using
  /// instead of orphaning the weights. No-op on eager clients (they
  /// never own the engine).
  void unloadEngine() {
    _onUnloadEngine?.call();
    _loaded = false;
    _loadError = null;
  }

  /// Set by the lazy factories: disposes the loaded engine box.
  void Function()? _onUnloadEngine;
}

final class _NativeQwenInferenceScope implements CancellableInferenceClient {
  _NativeQwenInferenceScope(this._base);

  final MlxNativeTextClient _base;
  final Set<int> _requestIds = <int>{};
  final Set<Future<InferenceResult<InferenceResponse>>> _inflight =
      <Future<InferenceResult<InferenceResponse>>>{};
  int _cancelEpoch = 0;
  bool _closed = false;

  NativeQwenTextEngine? get _engine => _base._qwenEngine?.call();
  bool get _canCancel => _engine?.supportsRequestCancellation ?? false;

  @override
  String get id => _base.id;
  @override
  Set<InferenceTask> get supportedTasks => _base.supportedTasks;
  @override
  bool get isAvailable => _base.isAvailable && _canCancel && !_closed;

  @override
  Future<void> load() async {
    await _base.load();
  }

  @override
  Future<bool> refreshAvailability() async {
    await _base.refreshAvailability();
    return isAvailable;
  }

  @override
  void resetAvailabilityCache() => _base.resetAvailabilityCache();

  @override
  Future<InferenceResult<InferenceResponse>> infer(
    InferenceRequest request, {
    ToolRegistry? toolRegistry,
  }) {
    if (_closed) {
      return Future.value(
        InferenceResult.fail(
          code: 'unavailable',
          message: 'The cancellable native Qwen scope is closed',
          details: <String, Object?>{'retryable': false},
        ),
      );
    }
    final epoch = _cancelEpoch;
    late final Future<InferenceResult<InferenceResponse>> future;
    future = _base._inferUsing(
      request,
      toolRegistry: toolRegistry,
      generate:
          ({
            required String prompt,
            required int maxTokens,
            required bool stopOnEos,
            required List<int> eosIds,
          }) async {
            if (_closed) {
              throw StateError('cancellable native Qwen scope is closed');
            }
            final engine = _engine;
            if (engine == null || !engine.supportsRequestCancellation) {
              throw const NativeQwenCancellationUnavailable();
            }
            var requestId = 0;
            final completionFuture = engine.generateRequestAsync(
              onRequestCreated: (value) {
                requestId = value;
                _requestIds.add(value);
                if (epoch < _cancelEpoch) engine.cancelRequest(value);
              },
              prompt: prompt,
              maxTokens: maxTokens,
              stopOnEos: stopOnEos,
              eosIds: eosIds,
              cacheScope: _base._qwenCacheScope,
            );
            try {
              final result = await completionFuture;
              return _toRecord(result.promptIds, result.ids, result.text);
            } finally {
              if (requestId != 0) _requestIds.remove(requestId);
            }
          },
    );
    _inflight.add(future);
    return future.whenComplete(() => _inflight.remove(future));
  }

  @override
  void cancelActive() {
    _cancelEpoch++;
    final engine = _engine;
    if (engine == null || !engine.supportsRequestCancellation) return;
    for (final id in List<int>.of(_requestIds)) {
      engine.cancelRequest(id);
    }
  }

  @override
  Future<void> settleActive() async {
    while (_inflight.isNotEmpty) {
      final current = List<Future<InferenceResult<InferenceResponse>>>.of(
        _inflight,
      );
      await Future.wait(
        current.map((future) async {
          try {
            await future;
          } on Object {
            // Settlement is about native completion, not task success.
          }
        }),
      );
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    cancelActive();
  }
}
