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

/// One in-process greedy completion: prompt ids, full token sequence, and
/// the generated text (decoded by the checkpoint's byte-level BPE in the
/// dylib).
final class NativeQwenCompletion {
  const NativeQwenCompletion({
    required this.promptIds,
    required this.ids,
    required this.text,
  });

  final List<int> promptIds;
  final List<int> ids;
  final String text;
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

  /// Loads the cached snapshot: [snapshotDir], else `QWEN3_SNAPSHOT`, else
  /// the Qwen3-0.6B-4bit checkout under the HF hub cache (never downloads).
  static Future<NativeQwenTextEngine> load({final String? snapshotDir}) async {
    final dir = resolveQwenSnapshotDir(snapshotDir);
    if (dir == null) {
      throw StateError(
        'qwen snapshot absent: pass snapshotDir or QWEN3_SNAPSHOT, or cache '
        'Qwen3-0.6B-4bit under the HF hub (the runtime never downloads)',
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
  static NativeQwenCompletion generateByHandle(
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
    final reply = _qwenGenerate(handle, requestNative);
    final payload = fromNativeUtf8(reply);
    malloc.free(requestNative);
    final json = jsonDecode(payload) as Map<String, dynamic>;
    if (json['error'] != null) {
      throw StateError('laya qwen generate failed: ${json['error']}');
    }
    return NativeQwenCompletion(
      promptIds: <int>[
        for (final v in json['prompt_ids'] as List) v as int,
      ],
      ids: <int>[for (final v in json['ids'] as List) v as int],
      text: json['text'] as String? ?? '',
    );
  }

  /// [generate] off the caller's isolate: runs
  /// [NativeQwenTextEngine.generateByHandle] in a fresh isolate capturing
  /// only the int handle plus plain sendable args, so a long decode never
  /// blocks the calling isolate (e.g. the UI). Generation itself is
  /// unchanged — same native serialization, same greedy path.
  Future<NativeQwenCompletion> generateAsync({
    final String? prompt,
    final List<int>? promptIds,
    final int maxTokens = 64,
    final bool stopOnEos = false,
    final List<int>? eosIds,
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
      ),
    );
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
String _qwenWireText(final String text) => text
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
           'engine': 'laya-native-qwen',
         },
         route: (final LoopbackRequest request) async =>
             _route(
                 request, engine, model, defaultMaxTokens, useTemplate, thinking),
       );

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
  final LoopbackJsonServer _server;

  /// The bound base URL (`http://127.0.0.1:<port>`), after [start].
  Uri get url => _server.url;

  Future<void> start() => _server.start();
  Future<void> stop() => _server.stop();

  static Future<LoopbackReply?> _route(
    final LoopbackRequest request,
    final NativeQwenTextEngine engine,
    final String model,
    final int maxTokens,
    final bool useTemplate,
    final bool thinking,
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
      final completion = engine.generate(
        prompt: prompt,
        maxTokens: requested is int ? requested : maxTokens,
        stopOnEos: true,
        eosIds: const <int>[151645, 151643], // <|im_end|>, <|endoftext|>
      );
      return _completionReply(
        id: 'chatcmpl-laya-qwen',
        model: model,
        completion: completion,
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
    final completion = engine.generate(
      prompt: promptBuffer.toString(),
      maxTokens: requested is int ? requested : maxTokens,
    );
    return _completionReply(
      id: 'chatcmpl-laya-qwen',
      model: model,
      completion: completion,
    );
  }

  static LoopbackReply _completionReply({
    required final String id,
    required final String model,
    required final NativeQwenCompletion completion,
  }) => LoopbackReply(200, <String, Object?>{
    'id': id,
    'model': model,
    'choices': <Object?>[
      <String, Object?>{
        'index': 0,
        'finish_reason': 'stop',
        'message': <String, Object?>{
          'role': 'assistant',
          // Template mode stopped at EOS natively; the emitted EOS
          // token's literal must not ride the wire answer.
          'content': _qwenWireText(completion.text),
        },
      },
    ],
    'usage': <String, Object?>{
      'prompt_tokens': completion.promptIds.length,
      'completion_tokens': completion.ids.length - completion.promptIds.length,
    },
  });
}
