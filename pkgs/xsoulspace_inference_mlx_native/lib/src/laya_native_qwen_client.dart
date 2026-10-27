import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:xsoulspace_inference_local_serve/xsoulspace_inference_local_serve.dart';

import 'laya_native_decision_engine.dart';
import 'laya_native_qwen_chat_template.dart';

// Native bindings over the R2 qwen engine (ADR 0054): the SAME
// native-assets code asset the decision engine registers; on machines
// without it these throw at first call and the tests skip honestly.

@Native<Int64 Function(Pointer<Uint8>)>(
  symbol: 'mlx_native_qwen_load',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external int _qwenLoad(Pointer<Uint8> modelDir);

@Native<Pointer<Uint8> Function(Int64, Pointer<Uint8>)>(
  symbol: 'mlx_native_qwen_generate',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external Pointer<Uint8> _qwenGenerate(int handle, Pointer<Uint8> requestJson);

@Native<Void Function(Int64)>(
  symbol: 'mlx_native_qwen_unload',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external void _qwenUnload(int handle);

@Native<Int32 Function(Int64, Pointer<Uint8>)>(
  symbol: 'mlx_native_qwen_clear_cache',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external int _qwenClearCache(int handle, Pointer<Uint8> actor);

@Native<Int32 Function()>(
  symbol: 'mlx_native_qwen_cancel_api_version',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external int _qwenCancelApiVersion();

@Native<Int64 Function(Int64)>(
  symbol: 'mlx_native_qwen_request_create',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external int _qwenRequestCreate(int handle);

@Native<Int32 Function(Int64, Int64)>(
  symbol: 'mlx_native_qwen_request_cancel',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external int _qwenRequestCancel(int handle, int requestId);

@Native<Int32 Function(Int64, Int64)>(
  symbol: 'mlx_native_qwen_request_finish',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external int _qwenRequestFinish(int handle, int requestId);

@Native<Pointer<Uint8> Function(Int64, Int64, Pointer<Uint8>)>(
  symbol: 'mlx_native_qwen_generate_request',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external Pointer<Uint8> _qwenGenerateRequest(
  int handle,
  int requestId,
  Pointer<Uint8> requestJson,
);

@Native<Int32 Function()>(
  symbol: 'mlx_native_qwen_batch_api_version',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external int _qwenBatchApiVersion();

@Native<Pointer<Uint8> Function(Int64, Pointer<Uint8>)>(
  symbol: 'mlx_native_qwen_generate_batched',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external Pointer<Uint8> _qwenGenerateBatched(int handle, Pointer<Uint8> requestJson);

/// One in-process greedy completion: prompt ids, full token sequence, and
/// the generated text (decoded by the checkpoint's byte-level BPE in the
/// dylib).
/// Host-supplied binding, never inferred from model output. Include the trust
/// realm/world in actor; rotate epoch when visibility or authorization changes.
/// One engine retains at most four scopes, each at most 8192 reserved tokens.
final class QwenCacheScope {
  const QwenCacheScope({required this.actor, required this.epoch});
  final String actor;
  final String epoch;
  Map<String, String> toJson() => {'actor': actor, 'epoch': epoch};
}

final class NativeQwenCompletion {
  const NativeQwenCompletion({
    required this.promptIds,
    required this.ids,
    required this.text,
    this.cacheReusedTokens = 0,
  });

  final List<int> promptIds;
  final List<int> ids;
  final String text;
  final int cacheReusedTokens;
}

final class NativeQwenRequestCancelled implements Exception {
  const NativeQwenRequestCancelled();
}

final class NativeQwenCancellationUnavailable implements Exception {
  const NativeQwenCancellationUnavailable();
}

/// One row of a batched generation request (Tier-A fused path): prompt as
/// raw text (tokenized by the checkpoint BPE) or explicit ids, with its
/// own generation cap.
final class NativeQwenBatchRequestRow {
  const NativeQwenBatchRequestRow({this.prompt, this.promptIds, this.maxTokens = 64});

  final String? prompt;
  final List<int>? promptIds;
  final int maxTokens;
}

/// One row of a batched generation outcome, in request order.
final class NativeQwenBatchRowResult {
  const NativeQwenBatchRowResult({
    required this.promptIds,
    required this.completionIds,
    required this.text,
    required this.stopReason,
  });

  final List<int> promptIds;
  final List<int> completionIds;
  final String text;

  /// `"stop"` (a stop id was emitted) or `"max_tokens"`.
  final String stopReason;
}

/// A fused batched decode outcome: one [NativeQwenBatchRowResult] per
/// request plus the batch's clock split. The timing fields are power
/// facts (ADR 0061) — throughput quoted from them is an AC-only claim.
final class NativeQwenBatchCompletion {
  const NativeQwenBatchCompletion({
    required this.rows,
    required this.batch,
    required this.prefillSeconds,
    required this.decodeSeconds,
    required this.generatedTokens,
  });

  final List<NativeQwenBatchRowResult> rows;
  final int batch;
  final double prefillSeconds;
  final double decodeSeconds;
  final int generatedTokens;
}

/// The R2 dense text engine in-process: greedy decode over the cached
/// Qwen3 snapshot through the same dylib that serves laya decisions
/// (64/64 token-for-token parity vs mlx-lm — the fixture gate).
///
/// The engine is process-global and single-flight per generate call (the
/// FFI serializes internally); each generate blocks its caller until the
/// tokens are materialized — [generateAsync] moves that block off the
/// calling isolate.
final class NativeQwenTextEngine {
  NativeQwenTextEngine._(this._handle, this.snapshotDir);

  final int _handle;
  final String snapshotDir;

  /// False on older native assets that implement only legacy generation.
  bool get supportsRequestCancellation {
    try {
      return _qwenCancelApiVersion() == 1;
    } on ArgumentError {
      return false;
    }
  }

  /// False on older native assets without the fused batched generation —
  /// callers degrade to the solo path instead of failing the wire.
  bool get supportsBatchGeneration {
    try {
      return _qwenBatchApiVersion() == 1;
    } on ArgumentError {
      return false;
    }
  }

  /// Loads the cached snapshot: [snapshotDir], else `QWEN3_SNAPSHOT`, else
  /// the Qwen3-0.6B-4bit checkout under the HF hub cache (never downloads).
  static Future<NativeQwenTextEngine> load({String? snapshotDir}) async {
    final dir = resolveQwenSnapshotDir(snapshotDir);
    if (dir == null) {
      throw StateError(
        'qwen snapshot absent: pass snapshotDir or QWEN3_SNAPSHOT, or cache '
        'Qwen3-0.6B-4bit under the HF hub (the runtime never downloads)',
      );
    }
    final packageRoot = await resolveNativePackageRoot();
    ensureNativeBindingsAvailable(packageRoot: packageRoot);
    final dirNative = toNativeUtf8(dir);
    final handle = _qwenLoad(dirNative);
    malloc.free(dirNative);
    if (handle <= 0) {
      throw StateError(
        'laya qwen load failed (code $handle) for snapshot $dir',
      );
    }
    return NativeQwenTextEngine._(handle, dir);
  }

  /// Greedy decode. Supply [prompt] (tokenized by the checkpoint BPE) or
  /// explicit [promptIds]; [maxTokens] caps the generated length.
  /// [stopOnEos] is strictly opt-in (native default OFF — the parity
  /// fixture pins a stream that runs through `<|endoftext|>`): when true,
  /// generation breaks right after emitting any id in [eosIds], keeping
  /// that EOS token itself (HF convention).
  NativeQwenCompletion generate({
    String? prompt,
    List<int>? promptIds,
    int maxTokens = 64,
    bool stopOnEos = false,
    List<int>? eosIds,
    QwenCacheScope? cacheScope,
    bool cacheReset = false,
  }) => generateByHandle(
    _handle,
    prompt: prompt,
    promptIds: promptIds,
    maxTokens: maxTokens,
    stopOnEos: stopOnEos,
    eosIds: eosIds,
    cacheScope: cacheScope,
    cacheReset: cacheReset,
  );

  /// The [generate] FFI body, keyed by the process-global engine handle —
  /// the handle lives inside the dylib, so ANY isolate (in this process,
  /// after [load] opened the asset) can drive the engine with it. The
  /// native side creates its MLX stream per call on the calling thread.
  static NativeQwenCompletion generateByHandle(
    int handle, {
    String? prompt,
    List<int>? promptIds,
    int maxTokens = 64,
    bool stopOnEos = false,
    List<int>? eosIds,
    QwenCacheScope? cacheScope,
    bool cacheReset = false,
  }) {
    final request = jsonEncode(<String, Object?>{
      'prompt': ?prompt,
      'prompt_ids': ?promptIds,
      'max_tokens': maxTokens,
      'stop_on_eos': stopOnEos,
      'eos_ids': ?eosIds,
      'cache_scope': ?cacheScope?.toJson(),
      'cache_reset': cacheReset,
    });
    final requestNative = toNativeUtf8(request);
    final reply = _qwenGenerate(handle, requestNative);
    final payload = fromNativeUtf8(reply);
    malloc.free(requestNative);
    final json = jsonDecode(payload) as Map<String, dynamic>;
    if (json['error'] != null) {
      throw StateError('laya qwen generate failed: ${json['error']}');
    }
    return NativeQwenCompletion(
      promptIds: <int>[for (final v in json['prompt_ids'] as List) v as int],
      ids: <int>[for (final v in json['ids'] as List) v as int],
      text: json['text'] as String? ?? '',
      cacheReusedTokens: json['cache_reused_tokens'] as int? ?? 0,
    );
  }

  /// [generate] off the caller's isolate: runs
  /// [NativeQwenTextEngine.generateByHandle] in a fresh isolate capturing
  /// only the int handle plus plain sendable args, so a long decode never
  /// blocks the calling isolate (e.g. the UI). Generation itself is
  /// unchanged — same native serialization, same greedy path.
  Future<NativeQwenCompletion> generateAsync({
    String? prompt,
    List<int>? promptIds,
    int maxTokens = 64,
    bool stopOnEos = false,
    List<int>? eosIds,
    QwenCacheScope? cacheScope,
    bool cacheReset = false,
  }) {
    final handle = _handle;
    return Isolate.run(
      () => NativeQwenTextEngine.generateByHandle(
        handle,
        prompt: prompt,
        promptIds: promptIds,
        maxTokens: maxTokens,
        stopOnEos: stopOnEos,
        eosIds: eosIds,
        cacheScope: cacheScope,
        cacheReset: cacheReset,
      ),
    );
  }

  /// FUSED batched greedy decode (the Tier-A lever): ONE left-padded
  /// batched prefill, then ONE [B, 1] forward per decode step — the weight
  /// read amortizes across the batch. DECISION-LEVEL INVARIANCE is the
  /// law (the fused gate): decision-shaped answers are token-exact across
  /// batch sizes and row positions; free-form streams may tie-flip under
  /// the kernel floor. The prefix pool is not consulted (fresh KV per
  /// batch). A row whose prompt resolves to fewer than 2 tokens refuses
  /// the whole batch (the fused prefill needs a real position beyond the
  /// last token) — callers fall back to the solo path per row.
  NativeQwenBatchCompletion generateBatch({
    required List<NativeQwenBatchRequestRow> rows,
    bool stopOnEos = false,
    List<int>? eosIds,
  }) => generateBatchByHandleJson(
    _handle,
    jsonEncode(_batchRequestBody(rows, stopOnEos, eosIds)),
  );

  /// [generateBatch] off the caller's isolate: the fused batch runs in a
  /// fresh worker isolate keyed by the process-global engine handle, so a
  /// long batch never blocks the calling isolate.
  Future<NativeQwenBatchCompletion> generateBatchAsync({
    required List<NativeQwenBatchRequestRow> rows,
    bool stopOnEos = false,
    List<int>? eosIds,
  }) {
    final handle = _handle;
    final request = jsonEncode(_batchRequestBody(rows, stopOnEos, eosIds));
    return Isolate.run(() => generateBatchByHandleJson(handle, request));
  }

  static Map<String, Object?> _batchRequestBody(
    List<NativeQwenBatchRequestRow> rows,
    bool stopOnEos,
    List<int>? eosIds,
  ) => <String, Object?>{
    'requests': <Object?>[
      for (final row in rows)
        <String, Object?>{
          'prompt': ?row.prompt,
          'prompt_ids': ?row.promptIds,
          'max_tokens': row.maxTokens,
        },
    ],
    'stop_on_eos': stopOnEos,
    'eos_ids': ?eosIds,
  };

  /// Blocking batched FFI entry used by [generateBatch] and the worker
  /// isolate. [request] is the encoded `_batchRequestBody`.
  static NativeQwenBatchCompletion generateBatchByHandleJson(
    int handle,
    String request,
  ) {
    final requestNative = toNativeUtf8(request);
    try {
      final reply = _qwenGenerateBatched(handle, requestNative);
      final payload = fromNativeUtf8(reply);
      final json = jsonDecode(payload) as Map<String, dynamic>;
      if (json['error'] != null) {
        throw StateError('laya qwen batched generate failed: ${json['error']}');
      }
      final timing = json['timing'] as Map<String, dynamic>? ?? const {};
      return NativeQwenBatchCompletion(
        batch: json['batch'] as int? ?? 0,
        rows: <NativeQwenBatchRowResult>[
          for (final raw in (json['results'] as List?) ?? const <Object?>[])
            _batchRowFromJson(raw as Map<String, dynamic>),
        ],
        prefillSeconds: (timing['prefill_s'] as num?)?.toDouble() ?? 0,
        decodeSeconds: (timing['decode_s'] as num?)?.toDouble() ?? 0,
        generatedTokens: timing['tokens'] as int? ?? 0,
      );
    } finally {
      malloc.free(requestNative);
    }
  }

  static NativeQwenBatchRowResult _batchRowFromJson(Map<String, dynamic> row) =>
      NativeQwenBatchRowResult(
        promptIds: <int>[for (final v in row['prompt_ids'] as List) v as int],
        completionIds: <int>[
          for (final v in row['completion_ids'] as List) v as int,
        ],
        text: row['text'] as String? ?? '',
        stopReason: row['stop_reason'] as String? ?? 'max_tokens',
      );

  /// Request-scoped generation for independently cancellable clients. The
  /// request id is created synchronously before worker dispatch so a host
  /// cancellation cannot race ahead of native request registration.
  Future<NativeQwenCompletion> generateRequestAsync({
    required void Function(int requestId) onRequestCreated,
    String? prompt,
    List<int>? promptIds,
    int maxTokens = 64,
    bool stopOnEos = false,
    List<int>? eosIds,
    QwenCacheScope? cacheScope,
    bool cacheReset = false,
  }) {
    if (!supportsRequestCancellation) {
      throw const NativeQwenCancellationUnavailable();
    }
    final requestId = _qwenRequestCreate(_handle);
    if (requestId <= 0) {
      throw StateError('native Qwen request registration failed ($requestId)');
    }
    try {
      onRequestCreated(requestId);
      final request = jsonEncode(<String, Object?>{
        'prompt': ?prompt,
        'prompt_ids': ?promptIds,
        'max_tokens': maxTokens,
        'stop_on_eos': stopOnEos,
        'eos_ids': ?eosIds,
        'cache_scope': ?cacheScope?.toJson(),
        'cache_reset': cacheReset,
      });
      return Isolate.run(
        () => generateRequestByHandle(_handle, requestId, request),
      ).whenComplete(() {
        _qwenRequestFinish(_handle, requestId);
      });
    } on Object {
      _qwenRequestFinish(_handle, requestId);
      rethrow;
    }
  }

  /// Blocking request-scoped FFI entry used only by the worker isolate.
  static NativeQwenCompletion generateRequestByHandle(
    int handle,
    int requestId,
    String request,
  ) {
    final requestNative = toNativeUtf8(request);
    try {
      final reply = _qwenGenerateRequest(handle, requestId, requestNative);
      final payload = fromNativeUtf8(reply);
      final json = jsonDecode(payload) as Map<String, dynamic>;
      if (json['cancelled'] == true) {
        throw const NativeQwenRequestCancelled();
      }
      if (json['error'] != null) {
        throw StateError('laya qwen generate failed: ${json['error']}');
      }
      return NativeQwenCompletion(
        promptIds: <int>[for (final v in json['prompt_ids'] as List) v as int],
        ids: <int>[for (final v in json['ids'] as List) v as int],
        text: json['text'] as String? ?? '',
        cacheReusedTokens: json['cache_reused_tokens'] as int? ?? 0,
      );
    } finally {
      malloc.free(requestNative);
    }
  }

  /// Sets the native cancellation flag for exactly one registered request.
  void cancelRequest(int requestId) {
    final result = _qwenRequestCancel(_handle, requestId);
    if (result == -1) throw StateError('native Qwen engine is unloaded');
  }

  /// Purge all epochs for this host-bound actor after in-flight inference ends.
  void clearCache(String actor) {
    final nativeActor = toNativeUtf8(actor);
    try {
      if (_qwenClearCache(_handle, nativeActor) != 0) {
        throw StateError('qwen_cache_clear_failed');
      }
    } finally {
      malloc.free(nativeActor);
    }
  }

  void dispose() {
    _qwenUnload(_handle);
  }
}

/// R2's in-process client behind the existing serve wire: the same
/// OpenAI-compatible chat routes `mlx_lm.server` answers (`/health`,
/// `POST /v1/chat/completions`), served from the in-process engine on the
/// shared loopback core — no Python, no spawned process.
///
/// Wire mapping: the engine is a raw-completion model (no chat template),
/// so the message contents are concatenated in order (role prefixes for
/// non-user turns) as the prompt. Generation is identical to the tested
/// parity path; a chat template layer would be additive.
/// The chat wire's answer text: the native EOS stop emits the EOS token
/// itself (HF convention); its literal must not ride the wire.
String _qwenWireText(String text) => text
    .replaceAll(RegExp(r'<\|im_end\|>$'), '')
    .replaceAll(RegExp(r'<\|endoftext\|>$'), '')
    .trim();

final class LayaQwenChatServer {
  LayaQwenChatServer({
    required NativeQwenTextEngine engine,
    this.model = 'qwen3-0.6b-4bit',
    this.defaultMaxTokens = 64,
    this.useTemplate = true,
    this.thinking = false,
    this.maxBatchSize = 8,
    Duration? coalesceWindow,
    String? apiKey,
    InternetAddress? address,
    int port = 0,
  }) : _coalescer = (coalesceWindow != null && engine.supportsBatchGeneration)
           ? _QwenChatCoalescer(
               engine: engine,
               window: coalesceWindow,
               maxBatch: maxBatchSize,
               modelName: model,
             )
           : null {
    _server = LoopbackJsonServer(
      apiKey: apiKey,
      address: address,
      port: port,
      // Coalescing must SEE concurrency to batch it: a full window's worth
      // of requests is admitted at once. Solo mode keeps the serial
      // fixture semantics (excess requests 429 either way).
      maxConcurrentRequests: _coalescer == null ? 1 : maxBatchSize,
      healthPayload: () => <String, Object?>{
        'status': 'ok',
        'model': model,
        'engine': 'laya-native-qwen',
      },
      route: (LoopbackRequest request) => _route(
        request,
        engine,
        model,
        defaultMaxTokens,
        useTemplate,
        thinking,
        _coalescer,
      ),
    );
  }

  final String model;
  final int defaultMaxTokens;

  /// Template mode (default) renders the checkpoint's chat template and
  /// stops at `<|im_end|>`/`<|endoftext|>`. Raw mode is the legacy
  /// role-prefixed concatenation with no EOS stop — the bench's raw cell.
  final bool useTemplate;

  /// Qwen3's thinking switch: renders the generation prompt WITHOUT the
  /// empty `<think></think>` prefix, so the model reasons before answering
  /// (napbench's default is thinking OFF; the bench's thinking cells flip
  /// this). LFM2.5-Instruct has no such switch — recorded as its non-claim.
  final bool thinking;

  /// The largest fused batch the coalescer forms (Tier A measured B8
  /// 1.93× / B16 3.19×; the default stays at the conservative rung).
  final int maxBatchSize;

  final _QwenChatCoalescer? _coalescer;
  late final LoopbackJsonServer _server;

  /// The bound base URL (`http://127.0.0.1:<port>`), after [start].
  Uri get url => _server.url;

  /// Batch evidence since start — zero in every form when coalescing is
  /// off or the dylib lacks the batched ABI (the coalescer is then null
  /// and the wire is byte-identical to the pre-change solo path).
  int get batchRuns => _coalescer?.batchRuns ?? 0;
  int get batchedRows => _coalescer?.batchedRows ?? 0;
  int get lastBatchSize => _coalescer?.lastBatchSize ?? 0;

  /// Rows a failed batch re-served through the solo path. A batch failure
  /// must never fail the wire — but a nonzero count means the wire was
  /// served by fallback, not by the lever (the gate asserts 0).
  int get soloFallbackRows => _coalescer?.soloFallbackRows ?? 0;

  Future<void> start() => _server.start();
  Future<void> stop() => _server.stop();

  static Future<LoopbackReply?> _route(
    LoopbackRequest request,
    NativeQwenTextEngine engine,
    String model,
    int maxTokens,
    bool useTemplate,
    bool thinking,
    _QwenChatCoalescer? coalescer,
  ) async {
    if (request.method != 'POST' || request.path != '/v1/chat/completions') {
      return null;
    }
    final body = request.jsonBody!;
    final messages = body['messages'];
    if (messages is! List || messages.isEmpty) {
      return const LoopbackReply(422, <String, Object?>{
        'error': <String, Object?>{'message': 'messages required'},
      });
    }
    if (useTemplate) {
      for (final raw in messages) {
        if (raw is! Map) {
          return const LoopbackReply(422, <String, Object?>{
            'error': <String, Object?>{'message': 'messages must be objects'},
          });
        }
      }
      final rendered = <QwenChatMessage>[
        for (final raw in messages)
          QwenChatMessage(
            role: '${raw['role'] ?? 'user'}',
            content: '${raw['content'] ?? ''}',
          ),
      ];
      final prompt = renderQwenChatPrompt(
        messages: rendered,
        // OpenAI-style tool schemas render into the `# Tools` system block
        // (fixture-gated, ADR 0058 tools rung).
        tools: body['tools'] is List && (body['tools'] as List).isNotEmpty
            ? (body['tools'] as List).toList()
            : null,
        enableThinking: thinking,
      );
      final requested = body['max_tokens'];
      return _finishChat(
        prompt: prompt,
        maxTokens: requested is int ? requested : maxTokens,
        stopOnEos: true,
        eosIds: const <int>[151645, 151643], // <|im_end|>, <|endoftext|>
        modelName: model,
        engine: engine,
        coalescer: coalescer,
      );
    }
    final promptBuffer = StringBuffer();
    for (final raw in messages) {
      if (raw is! Map) {
        return const LoopbackReply(422, <String, Object?>{
          'error': <String, Object?>{'message': 'messages must be objects'},
        });
      }
      final role = '${raw['role'] ?? 'user'}';
      final content = '${raw['content'] ?? ''}';
      if (promptBuffer.isNotEmpty) {
        promptBuffer.write('\n');
      }
      promptBuffer.write(role == 'user' ? content : '$role: $content');
    }
    final requested = body['max_tokens'];
    return _finishChat(
      prompt: promptBuffer.toString(),
      maxTokens: requested is int ? requested : maxTokens,
      stopOnEos: false,
      eosIds: const <int>[],
      modelName: model,
      engine: engine,
      coalescer: coalescer,
    );
  }

  /// Serve one resolved chat prompt: inline solo generation when no
  /// coalescer is active, otherwise through the coalescing window.
  static Future<LoopbackReply> _finishChat({
    required String prompt,
    required int maxTokens,
    required bool stopOnEos,
    required List<int> eosIds,
    required String modelName,
    required NativeQwenTextEngine engine,
    required _QwenChatCoalescer? coalescer,
  }) {
    if (coalescer == null) {
      final completion = engine.generate(
        prompt: prompt,
        maxTokens: maxTokens,
        stopOnEos: stopOnEos,
        eosIds: stopOnEos ? eosIds : null,
      );
      return Future.value(
        _wireReply(
          model: modelName,
          promptTokens: completion.promptIds.length,
          completionTokens: completion.ids.length - completion.promptIds.length,
          text: completion.text,
        ),
      );
    }
    return coalescer.enqueue(
      _PendingChat(
        prompt: prompt,
        maxTokens: maxTokens,
        stopOnEos: stopOnEos,
        eosIds: eosIds,
      ),
    );
  }

  /// The chat wire answer. The wire contract is byte-stable across the
  /// solo and fused paths (finish_reason stays 'stop' — the batched row's
  /// finer `stop_reason` is carried by the engine API, not this wire).
  static LoopbackReply _wireReply({
    required String model,
    required int promptTokens,
    required int completionTokens,
    required String text,
  }) => LoopbackReply(200, <String, Object?>{
    'id': 'chatcmpl-laya-qwen',
    'model': model,
    'choices': <Object?>[
      <String, Object?>{
        'index': 0,
        'finish_reason': 'stop',
        'message': <String, Object?>{
          'role': 'assistant',
          // EOS stops emit the EOS token itself (HF convention); its
          // literal must not ride the wire answer.
          'content': _qwenWireText(text),
        },
      },
    ],
    'usage': <String, Object?>{
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
    },
  });
}

/// One chat request parked for the current coalescing window.
final class _PendingChat {
  _PendingChat({
    required this.prompt,
    required this.maxTokens,
    required this.stopOnEos,
    required this.eosIds,
  });

  final String prompt;
  final int maxTokens;
  final bool stopOnEos;
  final List<int> eosIds;
  final Completer<LoopbackReply> done = Completer<LoopbackReply>();
}

/// Collects concurrent `/v1/chat/completions` requests for one window and
/// serves the window as ONE fused batch (the Tier-A lever at the wire).
///
/// Laws:
/// - A LONE request (the window expires with one job pending) is served
///   through the engine's SOLO path — coalescing changes nothing for
///   traffic with no co-requests, and a size-1 window never enters the
///   fused path (its numerics differ from solo; the wire stays exact).
/// - A window with ≥ 2 jobs runs ONE fused batch; replies split in
///   request order. Decision-shaped answers are byte-equal to the solo
///   path (the fused gate's decision-invariance bar at the wire);
///   free-form streams may tie-flip under the kernel floor — the
///   recorded trade this opt-in window makes.
/// - A batch failure falls back to per-row solo generation: the wire
///   never fails because batching did (counted in `soloFallbackRows`).
final class _QwenChatCoalescer {
  _QwenChatCoalescer({
    required this.engine,
    required this.window,
    required this.maxBatch,
    required this.modelName,
  });

  final NativeQwenTextEngine engine;
  final Duration window;
  final int maxBatch;
  final String modelName;

  final List<_PendingChat> _pending = <_PendingChat>[];
  Timer? _timer;
  bool _draining = false;

  int batchRuns = 0;
  int batchedRows = 0;
  int lastBatchSize = 0;
  int soloFallbackRows = 0;

  Future<LoopbackReply> enqueue(_PendingChat job) {
    _pending.add(job);
    if (_pending.length >= maxBatch) {
      _timer?.cancel();
      _timer = null;
      unawaited(_drain());
    } else {
      _timer ??= Timer(window, () {
        _timer = null;
        unawaited(_drain());
      });
    }
    return job.done.future;
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      // One drain loop owns the queue; enqueue during a batch appends and
      // this loop picks the stragglers up on its next pass.
      while (_pending.isNotEmpty) {
        final take = _pending.take(maxBatch).toList(growable: false);
        _pending.removeRange(0, take.length);
        if (take.length == 1) {
          await _serveSolo(take.single);
          continue;
        }
        try {
          final batch = await engine.generateBatchAsync(
            rows: <NativeQwenBatchRequestRow>[
              for (final job in take)
                NativeQwenBatchRequestRow(
                  prompt: job.prompt,
                  maxTokens: job.maxTokens,
                ),
            ],
            stopOnEos: take.first.stopOnEos,
            eosIds: take.first.eosIds,
          );
          batchRuns++;
          batchedRows += take.length;
          lastBatchSize = take.length;
          for (var i = 0; i < take.length; i++) {
            take[i].done.complete(_rowReply(batch.rows[i]));
          }
        } on Object {
          // The batch refused (e.g. a too-short prompt row) or the native
          // call failed: re-serve every job solo, in order.
          for (final job in take) {
            try {
              await _serveSolo(job);
              soloFallbackRows++;
            } on Object catch (error) {
              job.done.completeError(error);
            }
          }
        }
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _serveSolo(_PendingChat job) async {
    try {
      final completion = await engine.generateAsync(
        prompt: job.prompt,
        maxTokens: job.maxTokens,
        stopOnEos: job.stopOnEos,
        eosIds: job.stopOnEos ? job.eosIds : null,
      );
      job.done.complete(
        LayaQwenChatServer._wireReply(
          model: modelName,
          promptTokens: completion.promptIds.length,
          completionTokens: completion.ids.length - completion.promptIds.length,
          text: completion.text,
        ),
      );
    } on Object catch (error) {
      job.done.completeError(error);
    }
  }

  LoopbackReply _rowReply(NativeQwenBatchRowResult row) =>
      LayaQwenChatServer._wireReply(
        model: modelName,
        promptTokens: row.promptIds.length,
        completionTokens: row.completionIds.length,
        text: row.text,
      );
}
