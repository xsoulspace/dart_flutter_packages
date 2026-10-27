// Serve the production line (ADR 0057): load one native text engine and
// answer the OpenAI-compatible chat wire on loopback. The Rust line serves;
// the Swift line is benchmark-only.
//
//   dart run tool/serve_text.dart [--engine qwen|lfm2] [--port 8765]
//       [--raw] [--thinking] [--coalesce-ms 15] [--max-batch 8]
//
// Template mode (default) renders the checkpoint's chat template and stops
// at its EOS; --raw is the legacy no-template/no-EOS cell the bench
// reproduces. The default engine is lfm2 — the measured production cast
// (instruct quality at the best latency per quality, ADR 0057 evidence);
// qwen is the quality cast, and --thinking flips Qwen3's thinking switch
// on. --coalesce-ms turns on the qwen server's fused-batch coalescing
// window (opt-in: concurrent requests inside the window are served as ONE
// fused batch — decision answers stay byte-exact, free-form streams may
// tie-flip under the kernel floor; measured in
// bench/nursery/experiments/RESULTS-wire-batch-2026-10-27.md).
// Ctrl-C stops the server.
import 'dart:async';
import 'dart:io';

import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

Future<void> main(List<String> args) async {
  var engine = 'lfm2';
  var port = 8765;
  var raw = false;
  var thinking = false;
  var coalesceMs = 0;
  var maxBatch = 8;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--engine' && i + 1 < args.length) {
      engine = args[++i];
    } else if (arg.startsWith('--engine=')) {
      engine = arg.split('=').last;
    } else if (arg.startsWith('--port=')) {
      port = int.parse(arg.split('=').last);
    } else if (arg == '--port' && i + 1 < args.length) {
      port = int.parse(args[++i]);
    } else if (arg == '--raw') {
      raw = true;
    } else if (arg == '--thinking') {
      thinking = true;
    } else if (arg.startsWith('--coalesce-ms=')) {
      coalesceMs = int.parse(arg.split('=').last);
    } else if (arg == '--coalesce-ms' && i + 1 < args.length) {
      coalesceMs = int.parse(args[++i]);
    } else if (arg.startsWith('--max-batch=')) {
      maxBatch = int.parse(arg.split('=').last);
    } else if (arg == '--max-batch' && i + 1 < args.length) {
      maxBatch = int.parse(args[++i]);
    }
  }
  final Future<void> served;
  if (engine == 'lfm2') {
    final server = LayaLfm2ChatServer(
      engine: await NativeLfm2TextEngine.load(),
      useTemplate: !raw,
      port: port,
    );
    await server.start();
    stdout.writeln(_banner('lfm2', raw, server.url));
    served = _untilInterrupted(server.stop);
  } else if (engine == 'qwen') {
    final server = LayaQwenChatServer(
      engine: await NativeQwenTextEngine.load(),
      useTemplate: !raw,
      thinking: thinking,
      port: port,
      coalesceWindow: coalesceMs > 0 ? Duration(milliseconds: coalesceMs) : null,
      maxBatchSize: maxBatch,
    );
    await server.start();
    stdout.writeln(
      _banner('qwen', raw, server.url, thinking: thinking, coalesceMs: coalesceMs),
    );
    served = _untilInterrupted(server.stop);
  } else {
    stderr.writeln('unknown engine "$engine" (qwen | lfm2)');
    exit(2);
  }
  await served;
}

String _banner(
  String engine,
  bool raw,
  Uri url, {
  bool thinking = false,
  int coalesceMs = 0,
}) =>
    'serving ${raw ? 'raw' : 'template+EOS'} $engine'
    '${thinking ? ' (thinking on)' : ''}'
    '${coalesceMs > 0 ? ' (fused-batch coalescing: ${coalesceMs}ms window)' : ''} on '
    '$url/v1/chat/completions (health: $url/health)';

/// Completes when SIGINT/SIGTERM arrives, after [stop] runs once.
Future<void> _untilInterrupted(Future<void> Function() stop) {
  final done = Completer<void>();
  var stopping = false;
  Future<void> shutdown(ProcessSignal signal) async {
    if (stopping) return;
    stopping = true;
    await stop();
    done.complete();
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  ProcessSignal.sigterm.watch().listen(shutdown);
  return done.future;
}
