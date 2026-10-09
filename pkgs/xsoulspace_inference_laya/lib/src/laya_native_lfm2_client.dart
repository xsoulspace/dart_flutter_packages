import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'laya_native_decision_engine.dart';

// Native bindings over the LFM2 hybrid short-conv/GQA engine (ADR 0055
// LFM2 rung): the SAME native-assets code asset the decision engine
// registers; on machines without it these throw at first call and the
// tests skip honestly.

@Native<Int64 Function(Pointer<Uint8>)>(
  symbol: 'laya_native_lfm2_load',
  assetId: 'package:xsoulspace_inference_laya/laya_native',
)
external int _lfm2Load(Pointer<Uint8> modelDir);

@Native<Pointer<Uint8> Function(Int64, Pointer<Uint8>)>(
  symbol: 'laya_native_lfm2_generate',
  assetId: 'package:xsoulspace_inference_laya/laya_native',
)
external Pointer<Uint8> _lfm2Generate(int handle, Pointer<Uint8> requestJson);

@Native<Void Function(Int64)>(
  symbol: 'laya_native_lfm2_unload',
  assetId: 'package:xsoulspace_inference_laya/laya_native',
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
/// tokens are materialized.
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
        'package:xsoulspace_inference_laya/xsoulspace_inference_laya.dart',
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
  /// [maxTokens] caps the generated length.
  NativeLfm2Completion generate({
    final String? prompt,
    final List<int>? promptIds,
    final int maxTokens = 64,
  }) {
    final request = jsonEncode(<String, Object?>{
      'prompt': ?prompt,
      'prompt_ids': ?promptIds,
      'max_tokens': maxTokens,
    });
    final requestNative = toNativeUtf8(request);
    final reply = _lfm2Generate(_handle, requestNative);
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

  void dispose() {
    _lfm2Unload(_handle);
  }
}
