import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:xsoulspace_inference_local_serve/xsoulspace_inference_local_serve.dart';

import 'laya_native_decision_engine.dart';
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

/// Locates the cached LFM2.5 snapshot: [override], else `LFM2_SNAPSHOT`,
/// else the LiquidAI LFM2.5-1.2B checkout under the HF hub cache (never
/// downloads). Null when absent — callers skip honestly.
String? resolveLfm2SnapshotDir(final String? override) {
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
        if (snap is Directory && File('${snap.path}/config.json').existsSync()) {
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

  /// Loads the cached snapshot: [snapshotDir], else `LFM2_SNAPSHOT`, else
  /// the LiquidAI LFM2.5-1.2B checkout under the HF hub cache (never
  /// downloads).
  static Future<NativeLfm2TextEngine> load({final String? snapshotDir}) async {
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
    final dirNative = toNativeUtf8(dir);
    final handle = _lfm2Load(dirNative);
    malloc.free(dirNative);
    if (handle <= 0) {
      throw StateError('laya lfm2 load failed (code $handle) for snapshot $dir');
    }
    return NativeLfm2TextEngine._(handle, dir);
  }

  /// Greedy decode. Supply [prompt] (tokenized by the checkpoint BPE, with
  /// `<|startoftext|>` prepended natively) or explicit [promptIds];
  /// [maxTokens] caps the generated length. [stopOnEos] is strictly
  /// opt-in (native default OFF — the parity fixtures pin streams that run
  /// through EOS): when true, generation breaks right after emitting any
  /// id in [eosIds], keeping that EOS token itself (HF convention — the
  /// chat server stops at `<|im_end|>`/`<|endoftext|>` this way).
  NativeLfm2Completion generate({
    final String? prompt,
    final List<int>? promptIds,
    final int maxTokens = 64,
    final bool stopOnEos = false,
    final List<int>? eosIds,
  }) =>
      generateByHandle(
        _handle,
        prompt: prompt,
        promptIds: promptIds,
        maxTokens: maxTokens,
        stopOnEos: stopOnEos,
        eosIds: eosIds,
      );

  /// The [generate] FFI body, keyed by the process-global engine handle —
  /// the handle lives inside the dylib, so ANY isolate (in this process,
  /// after [load] opened the asset) can drive the engine with it. The
  /// native side creates its MLX stream per call on the calling thread.
  static NativeLfm2Completion generateByHandle(
    final int handle, {
    final String? prompt,
    final List<int>? promptIds,
    final int maxTokens = 64,
    final bool stopOnEos = false,
    final List<int>? eosIds,
  }) {
    final request = jsonEncode(<String, Object?>{
      'prompt': ?prompt,
      'prompt_ids': ?promptIds,
      'max_tokens': maxTokens,
      'stop_on_eos': stopOnEos,
      'eos_ids': ?eosIds,
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
  /// unchanged — same native serialization, same greedy path.
  Future<NativeLfm2Completion> generateAsync({
    final String? prompt,
    final List<int>? promptIds,
    final int maxTokens = 64,
    final bool stopOnEos = false,
    final List<int>? eosIds,
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
String _wireText(final String text) => text
    .replaceAll(RegExp(r'<\|im_end\|>$'), '')
    .replaceAll(RegExp(r'<\|endoftext\|>$'), '')
    .trim();

final class LayaLfm2ChatServer {
  LayaLfm2ChatServer({
    required NativeLfm2TextEngine engine,
    this.model = 'lfm2.5-1.2b-instruct-mlx-4bit',
    this.defaultMaxTokens = 64,
    this.useTemplate = true,
    final String? apiKey,
    final InternetAddress? address,
    final int port = 0,
  }) : _server = LoopbackJsonServer(
         apiKey: apiKey,
         address: address,
         port: port,
         healthPayload: () => <String, Object?>{
           'status': 'ok',
           'model': model,
           'engine': 'laya-native-lfm2',
         },
         route: (final LoopbackRequest request) async =>
             _route(request, engine, model, defaultMaxTokens, useTemplate),
       );

  final String model;
  final int defaultMaxTokens;

  /// Template mode (default) renders the checkpoint's chat template and
  /// stops at `<|im_end|>`/`<|endoftext|>`. Raw mode is the legacy
  /// concatenation with no EOS stop — the bench's raw cell.
  final bool useTemplate;
  final LoopbackJsonServer _server;

  /// The bound base URL (`http://127.0.0.1:<port>`), after [start].
  Uri get url => _server.url;

  Future<void> start() => _server.start();
  Future<void> stop() => _server.stop();

  static Future<LoopbackReply?> _route(
    final LoopbackRequest request,
    final NativeLfm2TextEngine engine,
    final String model,
    final int maxTokens,
    final bool useTemplate,
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
    );
    final requested = body['max_tokens'];
    final completion = engine.generate(
      prompt: prompt,
      maxTokens: requested is int ? requested : maxTokens,
      stopOnEos: true,
      eosIds: const <int>[7, 2], // <|im_end|>, <|endoftext|>
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
        'completion_tokens': completion.ids.length - completion.promptIds.length,
      },
    });
  }
}
