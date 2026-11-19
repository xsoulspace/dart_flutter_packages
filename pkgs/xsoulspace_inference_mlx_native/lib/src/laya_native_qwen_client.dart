import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:xsoulspace_inference_local_serve/xsoulspace_inference_local_serve.dart';

import 'laya_native_decision_engine.dart';
import 'laya_native_qwen_chat_template.dart';
import 'native_text_protocol.dart'
    show NativeLoraAttachUnavailable, NativeLoraAttachment;

// Native bindings over the R2 qwen engine (ADR 0054): the SAME
// native-assets code asset the decision engine registers; on machines
// without it these throw at first call and the tests skip honestly.

@Native<Int64 Function(Pointer<Uint8>)>(
  symbol: 'mlx_native_qwen_load',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external int _qwenLoad(Pointer<Uint8> modelDir);

/// The last load failure's payload — `{"error": <the dense MlxError Debug
/// print | the qwen3_5 loader's NAMED QWEN35_* string | null>}` — so a
/// rejected checkpoint is diagnosable instead of a bare `-2` (mirror of
/// the lfm2 last-error ABI).
@Native<Pointer<Uint8> Function()>(
  symbol: 'mlx_native_qwen_last_load_error',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external Pointer<Uint8> _qwenLastLoadError();

/// The loaded engine's handle for a snapshot dir, or -1 — the
/// one-engine-per-snapshot probe (the load itself is idempotent per dir,
/// so an adopter and a loader can never hold the weights twice).
@Native<Int64 Function(Pointer<Uint8>)>(
  symbol: 'mlx_native_qwen_lookup',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external int _qwenLookup(Pointer<Uint8> modelDir);

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

@Native<Int32 Function()>(
  symbol: 'mlx_native_qwen_sampling_api_version',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external int _qwenSamplingApiVersion();

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

@Native<Int32 Function()>(
  symbol: 'mlx_native_qwen_stream_api_version',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external int _qwenStreamApiVersion();

@Native<Int64 Function(Int64, Pointer<Uint8>)>(
  symbol: 'mlx_native_qwen_stream_start',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external int _qwenStreamStart(int handle, Pointer<Uint8> requestJson);

@Native<Pointer<Uint8> Function(Int64, Int64, Int64, Int64)>(
  symbol: 'mlx_native_qwen_stream_poll',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external Pointer<Uint8> _qwenStreamPoll(
  int handle,
  int session,
  int idsSeen,
  int bytesSeen,
);

@Native<Int32 Function(Int64, Int64)>(
  symbol: 'mlx_native_qwen_stream_free',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external int _qwenStreamFree(int handle, int session);

@Native<Int32 Function()>(
  symbol: 'mlx_native_qwen_lora_api_version',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external int _qwenLoraApiVersion();

/// Reply: `{"digest": …, "applied": N}` or `{"error": …}` (attach is
/// idempotent on (digest, scale) Rust-side; the forward lock serializes it
/// against in-flight generation).
@Native<Pointer<Uint8> Function(Int64, Pointer<Uint8>, Double)>(
  symbol: 'mlx_native_qwen_attach_lora',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external Pointer<Uint8> _qwenAttachLora(
  int handle,
  Pointer<Uint8> adapterPath,
  double scale,
);

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

/// Raised when the dylib lacks the streaming ABI; callers degrade to the
/// completion path instead of failing.
final class NativeQwenStreamingUnavailable implements Exception {
  const NativeQwenStreamingUnavailable();

  @override
  String toString() => 'native dylib lacks the streaming ABI';
}

/// One streaming generation delta: ONLY the work since the previous
/// event — [newIds] and their decoded [text] — plus the session's
/// progress. Text is cut at UTF-8 boundaries (a multibyte character
/// arrives whole on a later event); the FINAL event carries [done] with
/// the terminal [stopReason] (`stop` | `max_tokens` | `cancelled`).
final class NativeQwenStreamDelta {
  const NativeQwenStreamDelta({
    required this.newIds,
    required this.text,
    required this.totalIds,
    required this.promptTokens,
    this.done = false,
    this.cancelled = false,
    this.stopReason,
  });

  final List<int> newIds;
  final String text;
  final int totalIds;
  final int promptTokens;
  final bool done;
  final bool cancelled;
  final String? stopReason;
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

  /// Runtime capability probe for the opt-in sampling ABI (solo generate:
  /// request-level temperature + repetition penalty). Static — the probe
  /// needs no loaded engine, only the dylib. Older dylibs lack the symbol
  /// and stay usable through greedy generation (callers warn honestly).
  static bool get samplingApiSupported {
    try {
      return _qwenSamplingApiVersion() == 1;
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

  /// False on older native assets without the streaming ABI — callers
  /// degrade to the completion path instead of failing.
  bool get supportsStreaming {
    try {
      return _qwenStreamApiVersion() == 1;
    } on ArgumentError {
      return false;
    }
  }

  /// Runtime capability probe for the additive LoRA-attach ABI (the qwen
  /// engine's runtime adapter surface). Static — the probe needs no loaded
  /// engine, only the dylib. A lora-bearing request on an older dylib
  /// refuses with the named [NativeLoraAttachUnavailable] — it never
  /// silently decodes without the adapter.
  static bool get loraApiSupported {
    try {
      return _qwenLoraApiVersion() == 1;
    } on ArgumentError {
      return false;
    }
  }

  /// Attaches (or re-confirms) a RUNTIME (unmerged) LoRA adapter: every
  /// later decode on this engine computes `y = x·Wᵀ + scale·((x·a_t)·b_t)`
  /// inside the linears the adapter targets. Idempotent Rust-side on
  /// (adapter digest, scale) — an unchanged pair re-confirms the state
  /// without rebuilding the pair set; a changed file re-attaches for real
  /// and the weight identity folds the new digest, so the native exact-prefix
  /// pool drops every entry computed under the bare base by itself. The
  /// declared-plan path is refused while an adapter is attached (the engine's
  /// own gate) — perf claims under an adapter are imperative-path numbers.
  NativeLoraAttachment attachLora(String adapterPath, {double scale = 1.0}) =>
      attachLoraByHandle(_handle, adapterPath, scale: scale);

  /// The [attachLora] FFI body, keyed by the process-global engine handle —
  /// the handle lives inside the dylib, so ANY isolate (in this process,
  /// after [load] opened the asset) can attach with it. Throws the named
  /// [NativeLoraAttachUnavailable] when the dylib predates the ABI, and the
  /// native refusal message when the adapter targets modules this model
  /// does not have (embeddings and norms are never runtime targets).
  static NativeLoraAttachment attachLoraByHandle(
    int handle,
    String adapterPath, {
    double scale = 1.0,
  }) {
    if (!loraApiSupported) {
      throw const NativeLoraAttachUnavailable();
    }
    final pathNative = toNativeUtf8(adapterPath);
    try {
      final reply = _qwenAttachLora(handle, pathNative, scale);
      final payload = fromNativeUtf8(reply);
      final json = jsonDecode(payload) as Map<String, dynamic>;
      if (json['error'] != null) {
        throw StateError('laya qwen attach lora failed: ${json['error']}');
      }
      return NativeLoraAttachment(
        digest: json['digest'] as String,
        applied: json['applied'] as int,
      );
    } finally {
      malloc.free(pathNative);
    }
  }

  /// Greedy decode as a live delta stream (the streaming ABI). The native
  /// session runs the SAME decode loop plain greedy runs — one
  /// implementation, so the 64/64 parity gates cover streaming by
  /// construction — on its own thread under the global forward lock, and
  /// each event carries only NEW work: [NativeQwenStreamDelta.newIds] and
  /// their decoded [text] since the previous event, cut at UTF-8
  /// boundaries. The final event sets [done] with the terminal
  /// [stopReason]. Cancelling the subscription sets the native request's
  /// cancellation flag (observed at the next step boundary) and releases
  /// the session. The prefix pool is not consulted (fresh KV per stream).
  Stream<NativeQwenStreamDelta> generateStream({
    String? prompt,
    List<int>? promptIds,
    int maxTokens = 64,
    bool stopOnEos = false,
    List<int>? eosIds,
  }) async* {
    if (!supportsStreaming) {
      throw const NativeQwenStreamingUnavailable();
    }
    final request = jsonEncode(<String, Object?>{
      'prompt': ?prompt,
      'prompt_ids': ?promptIds,
      'max_tokens': maxTokens,
      'stop_on_eos': stopOnEos,
      'eos_ids': ?eosIds,
    });
    final requestNative = toNativeUtf8(request);
    int session;
    try {
      session = _qwenStreamStart(_handle, requestNative);
    } finally {
      malloc.free(requestNative);
    }
    if (session <= 0) {
      throw StateError('native qwen stream start failed ($session)');
    }
    var idsSeen = 0;
    var bytesSeen = 0;
    try {
      while (true) {
        final reply = _qwenStreamPoll(_handle, session, idsSeen, bytesSeen);
        final payload = fromNativeUtf8(reply);
        final json = jsonDecode(payload) as Map<String, dynamic>;
        if (json['error'] != null) {
          throw StateError('laya qwen stream failed: ${json['error']}');
        }
        final newIds = <int>[for (final v in json['new_ids'] as List) v as int];
        final text = json['new_text'] as String? ?? '';
        idsSeen = json['total_ids'] as int? ?? idsSeen;
        bytesSeen = json['emitted_bytes'] as int? ?? bytesSeen;
        final done = json['done'] == true;
        if (newIds.isNotEmpty || text.isNotEmpty || done) {
          yield NativeQwenStreamDelta(
            newIds: newIds,
            text: text,
            totalIds: idsSeen,
            promptTokens: json['prompt_tokens'] as int? ?? 0,
            done: done,
            cancelled: json['cancelled'] == true,
            stopReason: json['stop_reason'] as String?,
          );
        }
        if (done) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
    } finally {
      // An abandoned subscription must stop the native decode: the flag is
      // observed at the next step boundary; free releases the session
      // (idempotent after a done stream).
      try {
        _qwenRequestCancel(_handle, session);
      } on Object {
        // A dylib unloaded mid-stream has nothing left to cancel.
      }
      try {
        _qwenStreamFree(_handle, session);
      } on Object {
        // Same.
      }
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
    // Adopt-first (the one-engine-per-snapshot law): a snapshot the
    // runtime already holds needs neither a reload nor the gate — the
    // weights are in RAM, the load is the registry lookup.
    final adopted = NativeQwenTextEngine._adoptIfLoaded(dir);
    if (adopted != null) return adopted;
    final dirNative = toNativeUtf8(dir);
    final handle = _qwenLoad(dirNative);
    malloc.free(dirNative);
    if (handle <= 0) {
      final detail = jsonDecode(
        fromNativeUtf8(_qwenLastLoadError()),
      ) as Map<String, dynamic>;
      throw StateError(
        'laya qwen load failed (code $handle) for snapshot $dir: '
        '${detail['error']}',
      );
    }
    return NativeQwenTextEngine._(handle, dir);
  }

  /// Adopts the ALREADY-LOADED engine for [dir], or null — the
  /// one-engine-per-snapshot read side: the dylib itself is the registry
  /// (handles are process-global), so a UI preload and an engine-host
  /// cast resolve to ONE engine instead of holding the weights twice.
  /// Sync by design: the probe is a map scan, never a load.
  static NativeQwenTextEngine? adoptLoaded(String dir) =>
      NativeQwenTextEngine._adoptIfLoaded(dir);

  static NativeQwenTextEngine? _adoptIfLoaded(String dir) {
    final dirNative = toNativeUtf8(dir);
    final handle = _qwenLookup(dirNative);
    malloc.free(dirNative);
    if (handle <= 0) return null;
    return NativeQwenTextEngine._(handle, dir);
  }

  /// Whether the dylib already holds a loaded engine for [dir]. The
  /// runtime surface's cheap poll (a map scan, no load, no isolate hop).
  static bool isLoaded(String dir) {
    final dirNative = toNativeUtf8(dir);
    final handle = _qwenLookup(dirNative);
    malloc.free(dirNative);
    return handle > 0;
  }

  /// [load] off the caller's isolate: snapshot resolution and binding
  /// preload stay on the caller (asset state lives there), then the FFI
  /// weight load — the seconds-long deserialize that otherwise freezes
  /// whatever isolate called [load] (the daemon's main loop included) —
  /// runs in a fresh worker. The returned handle is process-global, the
  /// same discipline [generateByHandle] already rides.
  static Future<NativeQwenTextEngine> loadAsync({String? snapshotDir}) async {
    final dir = resolveQwenSnapshotDir(snapshotDir);
    if (dir == null) {
      throw StateError(
        'qwen snapshot absent: pass snapshotDir or QWEN3_SNAPSHOT, or cache '
        'Qwen3-0.6B-4bit under the HF hub (the runtime never downloads)',
      );
    }
    // Adopt-first (the one-engine-per-snapshot law): the weights may
    // already be in RAM — a lookup beats an isolate spawn, and an
    // already-loaded snapshot needs neither a reload nor the gate.
    final adopted = NativeQwenTextEngine._adoptIfLoaded(dir);
    if (adopted != null) return adopted;
    final packageRoot = await resolveNativePackageRoot();
    ensureNativeBindingsAvailable(packageRoot: packageRoot);
    final handle = await Isolate.run(() {
      final dirNative = toNativeUtf8(dir);
      final handle = _qwenLoad(dirNative);
      malloc.free(dirNative);
      if (handle <= 0) {
        final detail = jsonDecode(
          fromNativeUtf8(_qwenLastLoadError()),
        ) as Map<String, dynamic>;
        throw StateError(
          'laya qwen load failed (code $handle) for snapshot $dir: '
          '${detail['error']}',
        );
      }
      return handle;
    });
    return NativeQwenTextEngine._(handle, dir);
  }

  /// Greedy decode by default; opt-in sampled decode when [temperature] or
  /// [repetitionPenalty] is supplied (native sampling rung — needs
  /// [samplingApiSupported]). Supply [prompt] (tokenized by the checkpoint
  /// BPE) or explicit [promptIds]; [maxTokens] caps the generated length.
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
    double? temperature,
    double? repetitionPenalty,
    String? loraPath,
    double loraScale = 1.0,
  }) => generateByHandle(
    _handle,
    prompt: prompt,
    promptIds: promptIds,
    maxTokens: maxTokens,
    stopOnEos: stopOnEos,
    eosIds: eosIds,
    cacheScope: cacheScope,
    cacheReset: cacheReset,
    temperature: temperature,
    repetitionPenalty: repetitionPenalty,
    loraPath: loraPath,
    loraScale: loraScale,
  );

  /// The [generate] FFI body, keyed by the process-global engine handle —
  /// the handle lives inside the dylib, so ANY isolate (in this process,
  /// after [load] opened the asset) can drive the engine with it. The
  /// native side creates its MLX stream per call on the calling thread.
  /// [temperature]/[repetitionPenalty] ride the request JSON only when
  /// non-null: old request shapes stay byte-identical, and a dylib without
  /// the sampling ABI ignores the unknown keys (the caller warns).
  ///
  /// [loraPath] is the ADDITIVE runtime-adapter knob: null keeps the
  /// byte-identical bare-base path; non-null attaches FIRST (same isolate,
  /// under the native forward lock — the attach→generate pairing is
  /// explicit) and throws the named [NativeLoraAttachUnavailable] when the
  /// dylib predates the ABI — never a silent bare-base decode. Attach is
  /// idempotent Rust-side on (digest, scale), so passing the same adapter
  /// on every call is cheap.
  static NativeQwenCompletion generateByHandle(
    int handle, {
    String? prompt,
    List<int>? promptIds,
    int maxTokens = 64,
    bool stopOnEos = false,
    List<int>? eosIds,
    QwenCacheScope? cacheScope,
    bool cacheReset = false,
    double? temperature,
    double? repetitionPenalty,
    String? loraPath,
    double loraScale = 1.0,
  }) {
    if (loraPath != null) {
      attachLoraByHandle(handle, loraPath, scale: loraScale);
    }
    final request = jsonEncode(<String, Object?>{
      'prompt': ?prompt,
      'prompt_ids': ?promptIds,
      'max_tokens': maxTokens,
      'stop_on_eos': stopOnEos,
      'eos_ids': ?eosIds,
      'cache_scope': ?cacheScope?.toJson(),
      'cache_reset': cacheReset,
      'temperature': ?temperature,
      'repetition_penalty': ?repetitionPenalty,
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
  /// unchanged — same native serialization, greedy unless sampling params
  /// are supplied.
  Future<NativeQwenCompletion> generateAsync({
    String? prompt,
    List<int>? promptIds,
    int maxTokens = 64,
    bool stopOnEos = false,
    List<int>? eosIds,
    QwenCacheScope? cacheScope,
    bool cacheReset = false,
    double? temperature,
    double? repetitionPenalty,
    String? loraPath,
    double loraScale = 1.0,
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
        temperature: temperature,
        repetitionPenalty: repetitionPenalty,
        loraPath: loraPath,
        loraScale: loraScale,
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
    double? temperature,
    double? repetitionPenalty,
    String? loraPath,
    double loraScale = 1.0,
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
        'temperature': ?temperature,
        'repetition_penalty': ?repetitionPenalty,
      });
      return Isolate.run(
        () => generateRequestByHandle(
          _handle,
          requestId,
          request,
          loraPath: loraPath,
          loraScale: loraScale,
        ),
      ).whenComplete(() {
        _qwenRequestFinish(_handle, requestId);
      });
    } on Object {
      _qwenRequestFinish(_handle, requestId);
      rethrow;
    }
  }

  /// Blocking request-scoped FFI entry used only by the worker isolate.
  /// [loraPath]/[loraScale] mirror [generateByHandle]'s additive knob: the
  /// attach lands FIRST, on the same worker isolate, under the native
  /// forward lock — a lora-bearing request never decodes on the bare base.
  static NativeQwenCompletion generateRequestByHandle(
    int handle,
    int requestId,
    String request, {
    String? loraPath,
    double loraScale = 1.0,
  }) {
    if (loraPath != null) {
      attachLoraByHandle(handle, loraPath, scale: loraScale);
    }
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
    Duration coalesceWindow = defaultCoalesceWindow,
    String? apiKey,
    InternetAddress? address,
    int port = 0,
  }) : _coalescer = (coalesceWindow > Duration.zero && engine.supportsBatchGeneration)
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
      streamRoute: (LoopbackRequest request, LoopbackStreamSink sink) =>
          _streamRoute(request, sink, engine, model, defaultMaxTokens, useTemplate, thinking),
    );
  }

  /// The coalescing window the owner defaulted ON (2026-10-28 decision,
  /// informed by the W-G1/G2/G3 wire evidence): genuinely concurrent
  /// requests inside 15 ms are served as ONE fused batch — decision
  /// answers byte-equal solo, a lone request still routes solo — while
  /// adding at most the window itself to a solo request's latency.
  /// [Duration.zero] serves the legacy coalescing-OFF wire.
  static const defaultCoalesceWindow = Duration(milliseconds: 15);

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

  /// Whether the fused-batch coalescer is active on this server: the
  /// default window is ON (owner decision 2026-10-28), [Duration.zero]
  /// serves the legacy coalescing-OFF wire, and a dylib without the
  /// batched ABI degrades to solo either way.
  bool get coalescingActive => _coalescer != null;

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

  /// One resolved chat wire body: the rendered prompt, its token cap, and
  /// the EOS profile (template mode stops at the checkpoint's EOS ids; raw
  /// mode never stops). [error] is non-null for an invalid body.
  static (String?, String, int, bool, List<int>) resolveChat(
    LoopbackRequest request, {
    required bool useTemplate,
    required bool thinking,
    required int defaultMaxTokens,
  }) {
    final body = request.jsonBody;
    if (body == null) {
      return ('messages required', '', 0, false, const <int>[]);
    }
    final messages = body['messages'];
    if (messages is! List || messages.isEmpty) {
      return ('messages required', '', 0, false, const <int>[]);
    }
    if (useTemplate) {
      for (final raw in messages) {
        if (raw is! Map) {
          return ('messages must be objects', '', 0, false, const <int>[]);
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
      return (
        null,
        prompt,
        requested is int ? requested : defaultMaxTokens,
        true,
        const <int>[151645, 151643], // <|im_end|>, <|endoftext|>
      );
    }
    final promptBuffer = StringBuffer();
    for (final raw in messages) {
      if (raw is! Map) {
        return ('messages must be objects', '', 0, false, const <int>[]);
      }
      final role = '${raw['role'] ?? 'user'}';
      final content = '${raw['content'] ?? ''}';
      if (promptBuffer.isNotEmpty) {
        promptBuffer.write('\n');
      }
      promptBuffer.write(role == 'user' ? content : '$role: $content');
    }
    final requested = body['max_tokens'];
    return (
      null,
      promptBuffer.toString(),
      requested is int ? requested : defaultMaxTokens,
      false,
      const <int>[],
    );
  }

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
    final (error, prompt, resolvedMaxTokens, stopOnEos, eosIds) = resolveChat(
      request,
      useTemplate: useTemplate,
      thinking: thinking,
      defaultMaxTokens: maxTokens,
    );
    if (error != null) {
      return LoopbackReply(422, <String, Object?>{
        'error': <String, Object?>{'message': error},
      });
    }
    return _finishChat(
      prompt: prompt,
      maxTokens: resolvedMaxTokens,
      stopOnEos: stopOnEos,
      eosIds: eosIds,
      modelName: model,
      engine: engine,
      coalescer: coalescer,
    );
  }

  /// The SSE streaming route (OpenAI chat-chunks shape): serves
  /// `POST /v1/chat/completions` bodies with `"stream": true`, declines
  /// everything else. LAWS: streaming is a SOLO-path feature (a fused
  /// batch has no per-row token order to stream — coalesced traffic keeps
  /// completion semantics); the EOS literals never ride the wire (stripped
  /// per delta; the end-trim stays the client's, matching how streamed
  /// text assembles); a dylib without the streaming ABI serves the
  /// completion shape instead of failing the wire.
  static Future<bool> _streamRoute(
    LoopbackRequest request,
    LoopbackStreamSink sink,
    NativeQwenTextEngine engine,
    String model,
    int maxTokens,
    bool useTemplate,
    bool thinking,
  ) async {
    if (request.method != 'POST' || request.path != '/v1/chat/completions') {
      return false;
    }
    final body = request.jsonBody;
    if (body == null || body['stream'] != true) {
      return false;
    }
    final (error, prompt, resolvedMaxTokens, stopOnEos, eosIds) = resolveChat(
      request,
      useTemplate: useTemplate,
      thinking: thinking,
      defaultMaxTokens: maxTokens,
    );
    if (error != null) {
      await sink.open(contentType: 'application/json');
      sink.data(<String, Object?>{
        'error': <String, Object?>{'message': error},
      });
      await sink.close();
      return true;
    }
    if (!engine.supportsStreaming) {
      final reply = await _finishChat(
        prompt: prompt,
        maxTokens: resolvedMaxTokens,
        stopOnEos: stopOnEos,
        eosIds: eosIds,
        modelName: model,
        engine: engine,
        coalescer: null,
      );
      await sink.open(contentType: 'application/json');
      sink.data(reply.body);
      await sink.close();
      return true;
    }
    await sink.open();
    var frames = 0;
    void chunk({
      required Map<String, Object?> delta,
      String? finishReason,
      Map<String, Object?>? usage,
    }) {
      sink.data(<String, Object?>{
        'id': 'chatcmpl-laya-qwen',
        'object': 'chat.completion.chunk',
        'model': model,
        'choices': <Object?>[
          <String, Object?>{
            'index': 0,
            'delta': delta,
            'finish_reason': finishReason,
          },
        ],
        'usage': ?usage,
      });
      frames++;
    }

    chunk(delta: <String, Object?>{'role': 'assistant'});
    var promptTokens = 0;
    var completionTokens = 0;
    try {
      await for (final delta in engine.generateStream(
        prompt: prompt,
        maxTokens: resolvedMaxTokens,
        stopOnEos: stopOnEos,
        eosIds: stopOnEos ? eosIds : null,
      )) {
        promptTokens = delta.promptTokens;
        completionTokens = delta.totalIds;
        final text = delta.text
            .replaceAll('<|im_end|>', '')
            .replaceAll('<|endoftext|>', '');
        if (text.isNotEmpty) {
          chunk(delta: <String, Object?>{'content': text});
        }
        if (delta.done) {
          // The wire contract's finish_reason stays 'stop' (the finer
          // native stop_reason is carried by the engine API, not this wire).
          chunk(
            delta: const <String, Object?>{},
            finishReason: 'stop',
            usage: <String, Object?>{
              'prompt_tokens': promptTokens,
              'completion_tokens': completionTokens,
            },
          );
        }
      }
    } on Object {
      // A decode that died mid-stream still must terminate the SSE wire.
      chunk(delta: const <String, Object?>{}, finishReason: 'stop');
    }
    sink.raw('data: [DONE]\n\n');
    await sink.close();
    assert(frames > 0, 'a served stream wrote at least the role frame');
    return true;
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
