import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_mlx/xsoulspace_inference_mlx.dart';

/// Native-engine smoke test: loads the mlx_text_native dylib (built by the
/// package hook) against a REAL local MLX snapshot and generates once.
///
/// Skips honestly when either is absent — the scripted fake covers the
/// whole non-native path; this test proves the FFI seam plus a real model
/// answer when an operator has weights on the machine. OPT-IN via
/// MLX_NATIVE_TEST=1 (the flutter_tester harness blocks on the blocking
/// FFI bridge — the production proof runs through
/// `bin/mlx_serve_native.dart`, which is how the benchmark drives it).
void main() {
  // The blocking FFI bridge hangs under flutter_tester (its run loop has
  // no thread to spare for the semaphore wait) — the smoke runs under the
  // PURE DART runner, which is this package's native lane: `dart test`.
  // Under `flutter test` it skips with the named reason; MLX_NATIVE_TEST=1
  // forces it anywhere.
  final resolved = Platform.resolvedExecutable;
  final underFlutterTester = resolved.contains('flutter_tester');
  final forced = Platform.environment['MLX_NATIVE_TEST'] == '1';
  if (underFlutterTester && !forced) {
    test('native engine smoke runs under the pure-Dart runner', () {
      markTestSkipped(
        'the blocking FFI bridge hangs under flutter_tester; run this '
        'package with `dart test` (pure Dart — no Flutter needed for '
        'native FFI) or force with MLX_NATIVE_TEST=1',
      );
    });
    return;
  }
  final snapshot = _snapshotDir();
  final dylibPresent = _dylibPresent();

  test('native engine loads and generates deterministically', () async {
    if (!dylibPresent) {
      markTestSkipped(
        'mlx_text_native dylib not built (Apple toolchain absent?) — '
        'the native seam is proven by the laya native tests pattern',
      );
    }
    if (snapshot == null) {
      markTestSkipped(
        'no local MLX snapshot; set MLX_NATIVE_TEST_MODEL to a snapshot '
        'dir to run the native smoke',
      );
    }

    final engine = await NativeMlxTextEngine.load(snapshot!);
    addTearDown(engine.unload);

    // Qwen3 family: disable thinking mode via chat-template kwargs, the
    // same switch the serve bin's --no-think passes.
    final request = const MlxNativeRequest(
      prompt: 'What is 2+2? Answer with the single digit only.',
      system: 'Reply with exactly one word, the answer only.',
      maxTokens: 8,
      temperature: 0.0,
      templateArgs: <String, Object?>{'enable_thinking': false},
    );
    final first = await engine.generate(request);
    final second = await engine.generate(request);

    expect(first.text.trim(), '4');
    // Greedy decoding is deterministic: two identical runs agree.
    expect(second.text, first.text);
    expect(first.completionTokens, greaterThan(0));
    expect(first.promptTokens, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// The snapshot dir from the environment, or the newest Qwen3-1.7B-4bit
/// checkout in the HF cache when present.
String? _snapshotDir() {
  final explicit = Platform.environment['MLX_NATIVE_TEST_MODEL'];
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final cache = '${Platform.environment['HOME']}/.cache/huggingface/hub';
  final dir = Directory(cache);
  if (!dir.existsSync()) return null;
  final candidates = dir
      .listSync()
      .whereType<Directory>()
      .where((d) => d.path.contains('Qwen3-1.7B-4bit'))
      .expand((d) => d.listSync().whereType<Directory>())
      .where((d) => d.path.contains('snapshots'))
      .expand((d) => d.listSync().whereType<Directory>())
      .where((d) => File('${d.path}/config.json').existsSync())
      .toList();
  return candidates.isEmpty ? null : candidates.first.path;
}

/// The dylib is present when the hook's load candidate exists — the same
/// probe the engine's first call would make, surfaced early for a named
/// skip.
bool _dylibPresent() {
  const candidates = <String>[
    '~/.cache/xsoulspace/mlx_text/native/libMlxTextNative.dylib',
  ];
  for (final candidate in candidates) {
    final expanded = candidate.replaceFirst(
      '~',
      Platform.environment['HOME'] ?? '/tmp',
    );
    if (File(expanded).existsSync()) return true;
  }
  // Registered native assets load through the package_config; presence of
  // the hook output means the asset resolution will find it.
  return File('build/native_assets/macos/libMlxTextNative.dylib').existsSync();
}
