/// The app-path probe: load the 4-bit Qwen3.5 convert through
/// [NativeQwenTextEngine.loadAsync] (the discovery + gate + FFI chain the
/// LA runtime rides) and decode a few tokens. Exits 0 on a coherent load.
library;

import 'dart:io';

import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

Future<void> main(List<String> args) async {
  final dir = args.isNotEmpty
      ? args.first
      : '${Platform.environment['HOME']}/.cache/huggingface/hub/'
          'models--mlx-community--Qwen3.5-0.8B-4bit/snapshots/la-manager';
  stdout.writeln('probe snapshot: $dir');
  try {
    final engine = await NativeQwenTextEngine.loadAsync(snapshotDir: dir);
    stdout.writeln('LOADED');
    final completion = engine.generate(
      prompt: 'The capital of France is',
      maxTokens: 12,
    );
    stdout.writeln('TEXT: ${completion.text}');
    // The runtime surface's cycle (the UI's Load/Unload verbs): the
    // dylib registry answers isLoaded true, unload frees, a reload
    // adopts-or-loads again — one engine per snapshot throughout.
    final runtime = MlxModelRuntime.instance;
    stdout.writeln('isLoaded: ${runtime.isQwenLoaded(dir)}');
    runtime.unloadQwen(dir);
    stdout.writeln('after unload isLoaded: ${runtime.isQwenLoaded(dir)}');
    await runtime.loadQwen(dir);
    stdout.writeln('after reload isLoaded: ${runtime.isQwenLoaded(dir)}');
    exit(0);
  } on Object catch (error) {
    stdout.writeln('FAILED: $error');
    exit(1);
  }
}
