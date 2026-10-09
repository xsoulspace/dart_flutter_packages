// Serve the production line (ADR 0057): load one native text engine and
// answer the OpenAI-compatible chat wire on loopback. The Rust line serves;
// the Swift line is benchmark-only.
//
//   dart run tool/serve_text.dart [--engine qwen|lfm2] [--port 8765] [--raw]
//
// Template mode (default) renders the checkpoint's chat template and stops
// at its EOS; --raw is the legacy no-template/no-EOS cell the bench
// reproduces. Ctrl-C stops the server.
import 'dart:async';
import 'dart:io';

import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

Future<void> main(final List<String> args) async {
  var engine = 'qwen';
  var port = 8765;
  var raw = false;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--engine' && i + 1 < args.length) {
      engine = args[++i];
    } else if (arg.startsWith('--engine=')) {
      engine = arg.split('=').last;
    } else if (arg.startsWith('--port=')) {
      port = int.parse(arg.split('=').last);
    } else if (arg == '--raw') {
      raw = true;
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
      port: port,
    );
    await server.start();
    stdout.writeln(_banner('qwen', raw, server.url));
    served = _untilInterrupted(server.stop);
  } else {
    stderr.writeln('unknown engine "$engine" (qwen | lfm2)');
    exit(2);
  }
  await served;
}

String _banner(final String engine, final bool raw, final Uri url) =>
    'serving ${raw ? 'raw' : 'template+EOS'} $engine on '
    '$url/v1/chat/completions (health: $url/health)';

/// Completes when SIGINT/SIGTERM arrives, after [stop] runs once.
Future<void> _untilInterrupted(final Future<void> Function() stop) {
  final done = Completer<void>();
  var stopping = false;
  Future<void> shutdown(final ProcessSignal signal) async {
    if (stopping) return;
    stopping = true;
    await stop();
    done.complete();
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  ProcessSignal.sigterm.watch().listen(shutdown);
  return done.future;
}
