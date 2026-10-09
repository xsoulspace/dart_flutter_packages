import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'laya_native_lfm2_chat_template.dart';
import 'laya_native_lfm2_client.dart';
import 'laya_native_qwen_chat_template.dart';
import 'laya_native_qwen_client.dart';

/// The EOS stop's emitted token must not ride the answer (HF convention —
/// the native stop keeps the token; the wire and the unified client strip
/// its literal).
String _stripEosLiteral(final String text) => text
    .replaceAll(RegExp(r'<\|im_end\|>$'), '')
    .replaceAll(RegExp(r'<\|endoftext|>$'), '')
    .trim();

/// One normalized completion from either driver (the two engines expose
/// differently-named but identically-shaped completions).
typedef _Generate =
    Future<({List<int> promptIds, List<int> ids, String text})> Function({
    required String prompt,
    required int maxTokens,
    required bool stopOnEos,
    required List<int> eosIds,
  });

typedef _Render =
    String Function(String system, String user, List<Object?>? tools);

/// A loaded native text engine (Qwen3 or LFM2.5) bound as an
/// [InferenceClient] — the unified interface every provider in the
/// monorepo answers to (ADR 0058).
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
/// model's answer carries its tool call in the checkpoint's own textual
/// format (parse it like the bench does — no structured tool-call
/// channel exists on this rung).
///
/// Loading happens at construction ([loadQwen]/[loadLfm2] or an engine
/// passed in), so [isAvailable] is a live snapshot of the client, and
/// dispatch rides the engines' `generateAsync` (isolate escape) — a long
/// decode never blocks the calling isolate.
final class MlxNativeTextClient implements InferenceClient {
  MlxNativeTextClient._({
    required this._id,
    required this._eosIds,
    required this._generate,
    required this._render,
    required this.thinking,
    required this.model,
    required this.defaultMaxTokens,
    required this.defaultTemperature,
  });

  /// The Qwen3 cast: ChatML with the thinking switch, EOS stop on
  /// `<|im_end|>`/`<|endoftext|>`, tools rendered via the fixture-gated
  /// `# Tools` system block.
  factory MlxNativeTextClient.qwen(
    final NativeQwenTextEngine engine, {
    final bool thinking = false,
    final String model = 'qwen3-mlx-4bit',
    final int defaultMaxTokens = 320,
    final double defaultTemperature = 0.0,
  }) {
    Future<({List<int> promptIds, List<int> ids, String text})> generate({
      required final String prompt,
      required final int maxTokens,
      required final bool stopOnEos,
      required final List<int> eosIds,
    }) async {
      final completion = await engine.generateAsync(
        prompt: prompt,
        maxTokens: maxTokens,
        stopOnEos: stopOnEos,
        eosIds: eosIds,
      );
      return (
        promptIds: completion.promptIds,
        ids: completion.ids,
        text: completion.text,
      );
    }

    String render(
      final String system,
      final String user,
      final List<Object?>? tools,
    ) => renderQwenChatPrompt(
      messages: <QwenChatMessage>[
        if (system.isNotEmpty) QwenChatMessage(role: 'system', content: system),
        QwenChatMessage(role: 'user', content: user),
      ],
      tools: tools,
      enableThinking: thinking,
    );

    return MlxNativeTextClient._(
      id: 'mlx_native_qwen',
      eosIds: const <int>[151645, 151643], // <|im_end|>, <|endoftext|>
      generate: generate,
      render: render,
      thinking: thinking,
      model: model,
      defaultMaxTokens: defaultMaxTokens,
      defaultTemperature: defaultTemperature,
    );
  }

  /// The LFM2.5 cast: the fixture-gated instruct template (tools render
  /// into the system block), EOS stop on `<|im_end|>`/`<|endoftext|>`.
  /// No thinking switch — the checkpoint ships none (non-claim).
  factory MlxNativeTextClient.lfm2(
    final NativeLfm2TextEngine engine, {
    final String model = 'lfm2.5-instruct-mlx-4bit',
    final int defaultMaxTokens = 320,
    final double defaultTemperature = 0.0,
  }) {
    Future<({List<int> promptIds, List<int> ids, String text})> generate({
      required final String prompt,
      required final int maxTokens,
      required final bool stopOnEos,
      required final List<int> eosIds,
    }) async {
      final completion = await engine.generateAsync(
        prompt: prompt,
        maxTokens: maxTokens,
        stopOnEos: stopOnEos,
        eosIds: eosIds,
      );
      return (
        promptIds: completion.promptIds,
        ids: completion.ids,
        text: completion.text,
      );
    }

    String render(
      final String system,
      final String user,
      final List<Object?>? tools,
    ) => renderLfm2ChatPrompt(
      messages: <Lfm2ChatMessage>[
        if (system.isNotEmpty) Lfm2ChatMessage(role: 'system', content: system),
        Lfm2ChatMessage(role: 'user', content: user),
      ],
      // The render omits the BOS: the native text path prepends the BOS
      // id itself, so exactly one lands in the token stream.
      includeBos: false,
      tools: tools,
    );

    return MlxNativeTextClient._(
      id: 'mlx_native_lfm2',
      // The checkpoint's own ids (7/2 on the 1.2B; 124900/… on the 2.6B).
      eosIds: engine.specialIds().chatStopIds,
      generate: generate,
      render: render,
      thinking: false,
      model: model,
      defaultMaxTokens: defaultMaxTokens,
      defaultTemperature: defaultTemperature,
    );
  }

  /// Loads the cached Qwen3 snapshot and returns the client. See
  /// [NativeQwenTextEngine.load] for the resolution order (never
  /// downloads).
  static Future<MlxNativeTextClient> loadQwen({
    final String? snapshotDir,
    final bool thinking = false,
    final String model = 'qwen3-mlx-4bit',
  }) async => MlxNativeTextClient.qwen(
    await NativeQwenTextEngine.load(snapshotDir: snapshotDir),
    thinking: thinking,
    model: model,
  );

  /// Loads the cached LFM2.5 snapshot and returns the client. See
  /// [NativeLfm2TextEngine.load] for the resolution order (never
  /// downloads).
  static Future<MlxNativeTextClient> loadLfm2({
    final String? snapshotDir,
    final String model = 'lfm2.5-instruct-mlx-4bit',
  }) async => MlxNativeTextClient.lfm2(
    await NativeLfm2TextEngine.load(snapshotDir: snapshotDir),
    model: model,
  );

  final String _id;
  final List<int> _eosIds;
  final _Generate _generate;
  final _Render _render;

  /// Qwen3's thinking switch (`enable_thinking` on the rendered
  /// generation prompt). Always false on the LFM2.5 cast.
  final bool thinking;

  /// Wire label reported in the response meta.
  final String model;
  final int defaultMaxTokens;
  final double defaultTemperature;

  bool _disposed = false;

  @override
  String get id => _id;

  @override
  Set<InferenceTask> get supportedTasks => const <InferenceTask>{
    InferenceTask.text,
  };

  /// A constructed client has a loaded engine; only [dispose] makes it
  /// unavailable. No I/O, no probes.
  @override
  bool get isAvailable => !_disposed;

  @override
  Future<bool> refreshAvailability() async => !_disposed;

  @override
  Future<void> load() async {}

  @override
  void resetAvailabilityCache() {
    // No availability cache: status is a live snapshot.
  }

  @override
  Future<InferenceResult<InferenceResponse>> infer(
    final InferenceRequest request, {
    final ToolRegistry? toolRegistry,
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
    final warnings = <String>[];
    final temperature = request.temperature ?? defaultTemperature;
    if (temperature != 0.0) {
      warnings.add(
        'mlx_native decodes greedily; temperature $temperature ignored',
      );
    }
    List<Object?>? tools;
    if (toolRegistry != null && toolRegistry.tools.isNotEmpty) {
      tools = toolRegistry.getToolsJsons();
    }
    final maxTokens = request.maxTokens ?? defaultMaxTokens;
    final ({List<int> promptIds, List<int> ids, String text}) completion;
    try {
      completion = await _generate(
        prompt: _render(request.systemPrompt, request.prompt, tools),
        maxTokens: maxTokens,
        stopOnEos: true,
        eosIds: _eosIds,
      );
    } on StateError catch (error) {
      return InferenceResult.fail(
        code: 'native_engine',
        message: error.message,
        details: <String, Object?>{'retryable': false},
      );
    }
    return InferenceResult.ok(
      InferenceResponse(
        task: InferenceTask.text,
        rawOutput: _stripEosLiteral(completion.text),
        meta: <String, dynamic>{
          'usage': <String, dynamic>{
            'prompt_tokens': completion.promptIds.length,
            'completion_tokens':
                completion.ids.length - completion.promptIds.length,
          },
          'model': model,
          'finish_reason': 'stop',
        },
      ),
      warnings: warnings,
    );
  }

  /// Marks this client disposed (subsequent [infer] calls answer the
  /// typed `unavailable` failure). Does NOT unload the injected engine —
  /// whoever loaded it owns its lifetime ([NativeQwenTextEngine.dispose]
  /// / [NativeLfm2TextEngine.dispose]). Not part of the
  /// [InferenceClient] contract.
  void dispose() {
    _disposed = true;
  }
}
