import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:xsoulspace_inference_local_serve/xsoulspace_inference_local_serve.dart';

import 'laya_native_decision_engine.dart';
import 'native_text_protocol.dart'
    show NativeLoraAttachUnavailable, NativeLoraAttachment;
import 'laya_native_lfm2_chat_template.dart';

// Native bindings over the LFM2 hybrid short-conv/GQA engine (ADR 0055
// LFM2 rung): the SAME native-assets code asset the decision engine
// registers; on machines without it these throw at first call and the
// tests skip honestly.

@Native<Int64 Function(Pointer<Uint8>)>(
  symbol: 'mlx_native_lfm2_load',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external int _lfm2Load(Pointer<Uint8> modelDir);

/// The loaded engine's handle for a snapshot dir, or -1 — the
/// one-engine-per-snapshot probe (the load itself is idempotent per dir,
/// so an adopter and a loader can never hold the weights twice).
@Native<Int64 Function(Pointer<Uint8>)>(
  symbol: 'mlx_native_lfm2_lookup',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external int _lfm2Lookup(Pointer<Uint8> modelDir);

@Native<Pointer<Uint8> Function(Int64, Pointer<Uint8>)>(
  symbol: 'mlx_native_lfm2_generate',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external Pointer<Uint8> _lfm2Generate(int handle, Pointer<Uint8> requestJson);

@Native<Void Function(Int64)>(
  symbol: 'mlx_native_lfm2_unload',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external void _lfm2Unload(int handle);

@Native<Int32 Function()>(
  symbol: 'mlx_native_lfm2_sampling_api_version',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external int _lfm2SamplingApiVersion();

@Native<Pointer<Uint8> Function(Int64)>(
  symbol: 'mlx_native_lfm2_special_ids',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external Pointer<Uint8> _lfm2SpecialIds(int handle);

@Native<Pointer<Uint8> Function()>(
  symbol: 'mlx_native_lfm2_last_load_error',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external Pointer<Uint8> _lfm2LastLoadError();

@Native<Int32 Function()>(
  symbol: 'mlx_native_lfm2_lora_api_version',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external int _lfm2LoraApiVersion();

/// Reply: `{"digest": …, "applied": N}` or `{"error": …}` (attach is
/// idempotent on (digest, scale) Rust-side; the forward lock serializes it
/// against in-flight generation).
@Native<Pointer<Uint8> Function(Int64, Pointer<Uint8>, Double)>(
  symbol: 'mlx_native_lfm2_attach_lora',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external Pointer<Uint8> _lfm2AttachLora(
  int handle,
  Pointer<Uint8> adapterPath,
  double scale,
);

/// The checkpoint's special-token ids, resolved from its own tokenizer at
/// load (never guessed across checkpoints — the low-id-special LFM2.5-1.2B
/// vs the 2.6B's 128k vocab differ in every id).
final class NativeLfm2SpecialIds {
  const NativeLfm2SpecialIds({
    required this.bos,
    required this.imEnd,
    required this.endoftext,
  });

  final int bos;
  final int imEnd;
  final int endoftext;

  List<int> get chatStopIds => <int>[imEnd, endoftext];
}

/// Locates the cached LFM2.5 snapshot: [override], else `LFM2_SNAPSHOT`,
/// else the LiquidAI LFM2.5-1.2B checkout under the HF hub cache (never
/// downloads). Null when absent — callers skip honestly.
String? resolveLfm2SnapshotDir(String? override) {
  if (override != null) return override;
  final env = Platform.environment['LFM2_SNAPSHOT'];
  if (env != null && env.isNotEmpty) return env;
  final home = Platform.environment['HOME'];
  if (home == null) return null;
  final hub = Directory('$home/.cache/huggingface/hub');
  if (!hub.existsSync()) return null;
  for (final entry in hub.listSync()) {
    if (entry.path.contains('LFM2.5-1.2B')) {
      final snapshots = Directory('${entry.path}/snapshots');
      if (!snapshots.existsSync()) continue;
      for (final snap in snapshots.listSync()) {
        if (snap is! Directory) continue;
        // The dangling-blob law (the qwen discovery's 2026-11-18 twin):
        // a snapshot dir counts only when its weights RESOLVE — a
        // shared-blobs wipe leaves config.json behind, and naming it
        // would promise a load that can only answer file-absent.
        if (File('${snap.path}/config.json').existsSync() &&
            File('${snap.path}/model.safetensors').existsSync()) {
          return snap.path;
        }
      }
    }
  }
  return null;
}

/// One in-process greedy completion: prompt ids, full token sequence, and
/// the generated text (decoded by the checkpoint's byte-level BPE in the
/// dylib). With a [NativeLfm2TextEngine.generate] `prompt`, the native
/// side prepends `<|startoftext|>`; explicit `promptIds` are used verbatim.
final class NativeLfm2Completion {
  const NativeLfm2Completion({
    required this.promptIds,
    required this.ids,
    required this.text,
  });

  final List<int> promptIds;
  final List<int> ids;
  final String text;
}

/// The LFM2.5-1.2B hybrid engine in-process: greedy decode over the cached
/// snapshot through the same dylib that serves laya decisions (64/64
/// token-for-token parity vs mlx-lm — the fixture gate; the Rust tokenizer
/// reproduces the reference ids — the lfm2_parity tokenizer gate).
///
/// The engine is process-global and single-flight per generate call (the
/// FFI serializes internally); each generate blocks its caller until the
/// tokens are materialized — [generateAsync] moves that block off the
/// calling isolate.
final class NativeLfm2TextEngine {
  NativeLfm2TextEngine._(this._handle, this.snapshotDir);

  final int _handle;
  final String snapshotDir;

  /// Runtime capability probe for the opt-in sampling ABI (solo generate:
  /// request-level temperature + repetition penalty). Static — the probe
  /// needs no loaded engine, only the dylib. Older dylibs lack the symbol
  /// and stay usable through greedy generation (callers warn honestly).
  static bool get samplingApiSupported {
    try {
      return _lfm2SamplingApiVersion() == 1;
    } on ArgumentError {
      return false;
    }
  }

  /// Runtime capability probe for the additive LoRA-attach ABI (the LFM2
  /// port of the qwen engine's runtime adapter surface). Static — the probe
  /// needs no loaded engine, only the dylib. A lora-bearing request on an
  /// older dylib refuses with the named [NativeLoraAttachUnavailable] — it
  /// never silently decodes without the adapter.
  static bool get loraApiSupported {
    try {
      return _lfm2LoraApiVersion() == 1;
    } on ArgumentError {
      return false;
    }
  }

  /// Attaches (or re-confirms) a RUNTIME (unmerged) LoRA adapter — the
  /// qwen engine's attach contract, ported: every later decode computes
  /// `y = x·Wᵀ + scale·((x·a_t)·b_t)` inside the linear slots the adapter
  /// targets (attention projections on attention layers, conv in/out
  /// projections on conv blocks, the feed-forward triple everywhere); a
  /// target the model does not have is a native refusal, never a silent
  /// skip. Idempotent Rust-side on (adapter digest, scale); LFM2 keeps no
  /// cross-request prefix pool (fresh KV per request), so there is nothing
  /// stale to invalidate. The declared-plan path is refused while an
  /// adapter is attached (the engine's own gate).
  NativeLoraAttachment attachLora(String adapterPath, {double scale = 1.0}) =>
      attachLoraByHandle(_handle, adapterPath, scale: scale);

  /// The [attachLora] FFI body, keyed by the process-global engine handle —
  /// the handle lives inside the dylib, so ANY isolate (in this process,
  /// after [load] opened the asset) can attach with it. Throws the named
  /// [NativeLoraAttachUnavailable] when the dylib predates the ABI.
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
      final reply = _lfm2AttachLora(handle, pathNative, scale);
      final payload = fromNativeUtf8(reply);
      final json = jsonDecode(payload) as Map<String, dynamic>;
      if (json['error'] != null) {
        throw StateError('laya lfm2 attach lora failed: ${json['error']}');
      }
      return NativeLoraAttachment(
        digest: json['digest'] as String,
        applied: json['applied'] as int,
      );
    } finally {
      malloc.free(pathNative);
    }
  }

  /// Adopts the ALREADY-LOADED engine for [dir], or null — the
  /// one-engine-per-snapshot read side (the qwen law, 2026-11-18): the
  /// dylib itself is the registry (handles are process-global), so a UI
  /// preload and an engine-host cast resolve to ONE engine instead of
  /// holding the weights twice. Sync by design: the probe is a map
  /// scan, never a load.
  static NativeLfm2TextEngine? adoptLoaded(String dir) {
    final dirNative = toNativeUtf8(dir);
    final handle = _lfm2Lookup(dirNative);
    malloc.free(dirNative);
    if (handle <= 0) return null;
    return NativeLfm2TextEngine._(handle, dir);
  }

  /// Whether the dylib already holds a loaded engine for [dir]. The
  /// runtime surface's cheap poll (a map scan, no load, no isolate hop).
  static bool isLoaded(String dir) {
    final dirNative = toNativeUtf8(dir);
    final handle = _lfm2Lookup(dirNative);
    malloc.free(dirNative);
    return handle > 0;
  }

  /// Loads the cached snapshot: [snapshotDir], else `LFM2_SNAPSHOT`, else
  /// the LiquidAI LFM2.5-1.2B checkout under the HF hub cache (never
  /// downloads).
  static Future<NativeLfm2TextEngine> load({String? snapshotDir}) async {
    final dir = resolveLfm2SnapshotDir(snapshotDir);
    if (dir == null) {
      throw StateError(
        'lfm2 snapshot absent: pass snapshotDir or LFM2_SNAPSHOT, or cache '
        'LiquidAI/LFM2.5-1.2B under the HF hub (the runtime never downloads)',
      );
    }
    final library = await Isolate.resolvePackageUri(
      Uri.parse(
        'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart',
      ),
    );
    final packageRoot = library == null
        ? null
        : File.fromUri(library).parent.parent.path;
    ensureNativeBindingsAvailable(packageRoot: packageRoot);
    // The adopt-first law (the qwen twin, 2026-11-18): an
    // already-loaded snapshot needs neither reload nor the loading
    // isolate — the dylib registry is the fact.
    final adopted = NativeLfm2TextEngine.adoptLoaded(dir);
    if (adopted != null) return adopted;
    final dirNative = toNativeUtf8(dir);
    final handle = _lfm2Load(dirNative);
    malloc.free(dirNative);
    if (handle <= 0) {
      final detail = jsonDecode(
        fromNativeUtf8(_lfm2LastLoadError()),
      ) as Map<String, dynamic>;
      throw StateError(
        'laya lfm2 load failed (code $handle) for snapshot $dir: '
        '${detail['error']}',
      );
    }
    return NativeLfm2TextEngine._(handle, dir);
  }

  /// [load] off the caller's isolate: snapshot resolution and binding
  /// preload stay on the caller, then the FFI weight load — the
  /// seconds-long deserialize that otherwise freezes whatever isolate
  /// called [load] (the daemon's main loop included) — runs in a fresh
  /// worker. The returned handle is process-global, the same discipline
  /// [NativeLfm2TextEngine.generateAsync] already rides.
  static Future<NativeLfm2TextEngine> loadAsync({String? snapshotDir}) async {
    final dir = resolveLfm2SnapshotDir(snapshotDir);
    if (dir == null) {
      throw StateError(
        'lfm2 snapshot absent: pass snapshotDir or LFM2_SNAPSHOT, or cache '
        'LiquidAI/LFM2.5-1.2B under the HF hub (the runtime never downloads)',
      );
    }
    final library = await Isolate.resolvePackageUri(
      Uri.parse(
        'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart',
      ),
    );
    final packageRoot = library == null
        ? null
        : File.fromUri(library).parent.parent.path;
    ensureNativeBindingsAvailable(packageRoot: packageRoot);
    final adopted = NativeLfm2TextEngine.adoptLoaded(dir);
    if (adopted != null) return adopted;
    final handle = await Isolate.run(() {
      final dirNative = toNativeUtf8(dir);
      final handle = _lfm2Load(dirNative);
      malloc.free(dirNative);
      if (handle <= 0) {
        final detail = jsonDecode(
          fromNativeUtf8(_lfm2LastLoadError()),
        ) as Map<String, dynamic>;
        throw StateError(
          'laya lfm2 load failed (code $handle) for snapshot $dir: '
          '${detail['error']}',
        );
      }
      return handle;
    });
    return NativeLfm2TextEngine._(handle, dir);
  }

  /// The checkpoint's own special-token ids (BOS, `<|im_end|>`,
  /// `<|endoftext|>`).
  NativeLfm2SpecialIds specialIds() {
    final reply = fromNativeUtf8(_lfm2SpecialIds(_handle));
    final json = jsonDecode(reply) as Map<String, dynamic>;
    if (json['error'] != null) {
      throw StateError('laya lfm2 special ids failed: ${json['error']}');
    }
    return NativeLfm2SpecialIds(
      bos: json['bos'] as int,
      imEnd: json['im_end'] as int,
      endoftext: json['endoftext'] as int,
    );
  }

  /// Greedy decode by default; opt-in sampled decode when [temperature] or
  /// [repetitionPenalty] is supplied (native sampling rung — needs
  /// [samplingApiSupported]). Supply [prompt] (tokenized by the checkpoint
  /// BPE, with `<|startoftext|>` prepended natively) or explicit
  /// [promptIds]; [maxTokens] caps the generated length. [stopOnEos] is
  /// strictly opt-in (native default OFF — the parity fixtures pin streams
  /// that run through EOS): when true, generation breaks right after
  /// emitting any id in [eosIds], keeping that EOS token itself (HF
  /// convention — the chat server stops at `<|im_end|>`/`<|endoftext|>`
  /// this way).
  NativeLfm2Completion generate({
    String? prompt,
    List<int>? promptIds,
    int maxTokens = 64,
    bool stopOnEos = false,
    List<int>? eosIds,
    double? temperature,
    double? repetitionPenalty,
    String? loraPath,
    double loraScale = 1.0,
  }) =>
      generateByHandle(
        _handle,
        prompt: prompt,
        promptIds: promptIds,
        maxTokens: maxTokens,
        stopOnEos: stopOnEos,
        eosIds: eosIds,
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
  /// The [generate] FFI body, keyed by the process-global engine handle —
  /// the handle lives inside the dylib, so ANY isolate (in this process,
  /// after [load] opened the asset) can drive the engine with it. The
  /// native side creates its MLX stream per call on the calling thread.
  /// [temperature]/[repetitionPenalty] ride the request JSON only when
  /// non-null: old request shapes stay byte-identical, and a dylib without
  /// the sampling ABI ignores the unknown keys (the caller warns).
  ///
  /// [loraPath] is the ADDITIVE runtime-adapter knob (the qwen engine's
  /// contract, ported): null keeps the byte-identical bare-base path;
  /// non-null attaches FIRST (same isolate, under the native forward lock
  /// — the attach→generate pairing is explicit) and throws the named
  /// [NativeLoraAttachUnavailable] when the dylib predates the ABI — never
  /// a silent bare-base decode. Attach is idempotent Rust-side on
  /// (digest, scale), so passing the same adapter on every call is cheap.
  static NativeLfm2Completion generateByHandle(
    int handle, {
    String? prompt,
    List<int>? promptIds,
    int maxTokens = 64,
    bool stopOnEos = false,
    List<int>? eosIds,
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
      'temperature': ?temperature,
      'repetition_penalty': ?repetitionPenalty,
    });
    final requestNative = toNativeUtf8(request);
    final reply = _lfm2Generate(handle, requestNative);
    final payload = fromNativeUtf8(reply);
    malloc.free(requestNative);
    final json = jsonDecode(payload) as Map<String, dynamic>;
    if (json['error'] != null) {
      throw StateError('laya lfm2 generate failed: ${json['error']}');
    }
    return NativeLfm2Completion(
      promptIds: <int>[
        for (final v in json['prompt_ids'] as List) v as int,
      ],
      ids: <int>[for (final v in json['ids'] as List) v as int],
      text: json['text'] as String? ?? '',
    );
  }

  /// [generate] off the caller's isolate: runs
  /// [NativeLfm2TextEngine.generateByHandle] in a fresh isolate capturing
  /// only the int handle plus plain sendable args, so a long decode never
  /// blocks the calling isolate (e.g. the UI). Generation itself is
  /// unchanged — same native serialization, greedy unless sampling params
  /// are supplied.
  Future<NativeLfm2Completion> generateAsync({
    String? prompt,
    List<int>? promptIds,
    int maxTokens = 64,
    bool stopOnEos = false,
    List<int>? eosIds,
    double? temperature,
    double? repetitionPenalty,
    String? loraPath,
    double loraScale = 1.0,
  }) {
    final handle = _handle;
    return Isolate.run(
      () => NativeLfm2TextEngine.generateByHandle(
        handle,
        prompt: prompt,
        promptIds: promptIds,
        maxTokens: maxTokens,
        stopOnEos: stopOnEos,
        eosIds: eosIds,
        temperature: temperature,
        repetitionPenalty: repetitionPenalty,
        loraPath: loraPath,
        loraScale: loraScale,
      ),
    );
  }

  void dispose() {
    _lfm2Unload(_handle);
  }
}

/// The LFM2 rung's in-process client behind the serve wire: the same
/// OpenAI-compatible chat routes `mlx_lm.server` answers (`/health`,
/// `POST /v1/chat/completions`), served from the in-process engine on the
/// shared loopback core — no Python, no spawned process.
///
/// Wire mapping: messages render through the checkpoint's chat template
/// ([renderLfm2ChatPrompt], fixture-pinned subset — the BOS is left to the
/// native text path so exactly one `<|startoftext|>` lands in the ids),
/// and generation runs with the opt-in EOS stop on `<|im_end|>`/`<|endoftext|>`
/// so a chat completion ends at the model's own end-of-turn marker instead
/// of barreling through it.
/// The chat wire's answer text: the native EOS stop emits the EOS token
/// itself (HF convention); its literal must not ride the wire.
String _wireText(String text, {bool stripThinkClose = false}) {
  var out = text;
  if (stripThinkClose) {
    // The 2.6B template opens the think block at the generation prompt;
    // the model REASONS inside it, then closes it before the answer —
    // the wire answer is everything AFTER the (unpaired) close. No close
    // in the output means the budget ran out mid-reasoning: empty answer,
    // honestly.
    final close = out.indexOf('</think>');
    out = close < 0 ? '' : out.substring(close + '</think>'.length);
  }
  return out
      .replaceAll(RegExp(r'<\|im_end\|>$'), '')
      .replaceAll(RegExp(r'<\|endoftext\|>$'), '')
      .trim();
}

final class LayaLfm2ChatServer {
  LayaLfm2ChatServer({
    required NativeLfm2TextEngine engine,
    this.model = 'lfm2.5-1.2b-instruct-mlx-4bit',
    this.defaultMaxTokens = 64,
    this.useTemplate = true,
    this.variant = Lfm2ChatTemplateVariant.lfm25_12b,
    String? apiKey,
    InternetAddress? address,
    int port = 0,
  }) : _server = LoopbackJsonServer(
         apiKey: apiKey,
         address: address,
         port: port,
         healthPayload: () => <String, Object?>{
           'status': 'ok',
           'model': model,
           'engine': 'laya-native-lfm2',
         },
         route: (LoopbackRequest request) async => _route(
           request,
           engine,
           model,
           defaultMaxTokens,
           useTemplate,
           variant,
         ),
       );

  final String model;
  final int defaultMaxTokens;

  /// Template mode (default) renders the checkpoint's chat template and
  /// stops at `<|im_end|>`/`<|endoftext|>`. Raw mode is the legacy
  /// concatenation with no EOS stop — the bench's raw cell.
  final bool useTemplate;

  /// Which LFM2.5 template variant renders (the 2.6B checkpoint ships a
  /// different one — think-open generation prompt and last-user-based
  /// think strip; fixture-gated in testdata/lfm25_26b_chat_template_fixtures.json).
  final Lfm2ChatTemplateVariant variant;
  final LoopbackJsonServer _server;

  /// The bound base URL (`http://127.0.0.1:<port>`), after [start].
  Uri get url => _server.url;

  Future<void> start() => _server.start();
  Future<void> stop() => _server.stop();

  static Future<LoopbackReply?> _route(
    LoopbackRequest request,
    NativeLfm2TextEngine engine,
    String model,
    int maxTokens,
    bool useTemplate,
    Lfm2ChatTemplateVariant variant,
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
    if (!useTemplate) {
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
      final completion = engine.generate(
        prompt: promptBuffer.toString(),
        maxTokens: requested is int ? requested : maxTokens,
      );
      return LoopbackReply(200, <String, Object?>{
        'id': 'chatcmpl-laya-lfm2',
        'model': model,
        'choices': <Object?>[
          <String, Object?>{
            'index': 0,
            'finish_reason': 'stop',
            'message': <String, Object?>{
              'role': 'assistant',
              // Template mode stopped at EOS natively; the emitted EOS
            // token's literal must not ride the wire answer.
            'content': _wireText(completion.text),
            },
          },
        ],
        'usage': <String, Object?>{
          'prompt_tokens': completion.promptIds.length,
          'completion_tokens':
              completion.ids.length - completion.promptIds.length,
        },
      });
    }
    final rendered = <Lfm2ChatMessage>[];
    for (final raw in messages) {
      if (raw is! Map) {
        return const LoopbackReply(422, <String, Object?>{
          'error': <String, Object?>{'message': 'messages must be objects'},
        });
      }
      rendered.add(
        Lfm2ChatMessage(
          role: '${raw['role'] ?? 'user'}',
          content: '${raw['content'] ?? ''}',
        ),
      );
    }
    final tools = body['tools'];
    final prompt = renderLfm2ChatPrompt(
      messages: rendered,
      // Template renders carry the BOS text; the native text path adds the
      // BOS id itself, so the render omits it (exactly one BOS in the ids).
      includeBos: false,
      tools: tools is List && tools.isNotEmpty ? tools : null,
      variant: variant,
    );
    final requested = body['max_tokens'];
    final completion = engine.generate(
      prompt: prompt,
      maxTokens: requested is int ? requested : maxTokens,
      stopOnEos: true,
      // The checkpoint's own ids (7/2 on the 1.2B; 124900/… on the 2.6B).
      eosIds: engine.specialIds().chatStopIds,
    );
    return LoopbackReply(200, <String, Object?>{
      'id': 'chatcmpl-laya-lfm2',
      'model': model,
      'choices': <Object?>[
        <String, Object?>{
          'index': 0,
          'finish_reason': 'stop',
          'message': <String, Object?>{
            'role': 'assistant',
            // Template mode stopped at EOS natively; the emitted EOS
            // token's literal must not ride the wire answer. The 2.6B
            // variant's completion opens with the model's own think
            // close — the answer is the text after it.
            'content': _wireText(
              completion.text,
              stripThinkClose: variant == Lfm2ChatTemplateVariant.lfm25_26b,
            ),
          },
        },
      ],
      'usage': <String, Object?>{
        'prompt_tokens': completion.promptIds.length,
        'completion_tokens': completion.ids.length - completion.promptIds.length,
      },
    });
  }
}
