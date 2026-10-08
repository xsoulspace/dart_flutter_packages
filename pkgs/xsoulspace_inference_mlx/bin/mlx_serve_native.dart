#!/usr/bin/env dart

/// Native MLX text server: loads a local MLX snapshot (Hugging Face
/// checkout shape) into the Swift mlx-swift-lm dylib (via the package's
/// native-assets hook) and serves the OpenAI-compatible chat wire on the
/// loopback interface — the same wire `mlx_lm.server` speaks, with no
/// Python.
///
///   dart run bin/mlx_serve_native.dart --model `<snapshot-dir>` [--port N]
///   [--max-tokens N] [--temperature T] [--api-key K] [--no-think]
///
/// The engine is single-flight (one generation at a time — the MLX
/// wired-memory limit is per-process). Health answers between generations.
library;

import 'dart:async';
import 'dart:io';

import 'package:xsoulspace_inference_mlx/xsoulspace_inference_mlx.dart';

Never _fail(final String message) {
  stderr.writeln(message);
  exit(2);
}

Future<void> main(final List<String> arguments) async {
  String? modelDir;
  var port = 8765;
  var maxTokens = 320;
  var temperature = 0.0;
  String? apiKey;
  var noThink = false;
  for (var i = 0; i < arguments.length; i++) {
    String? value(final String name) {
      final prefix = '--$name=';
      return arguments[i].startsWith(prefix)
          ? arguments[i].substring(prefix.length)
          : null;
    }

    if (arguments[i] == '--model') {
      modelDir = arguments[++i];
    } else if (value('model') != null) {
      modelDir = value('model');
    } else if (arguments[i] == '--port') {
      port = int.parse(arguments[++i]);
    } else if (value('port') != null) {
      port = int.parse(value('port')!);
    } else if (arguments[i] == '--max-tokens') {
      maxTokens = int.parse(arguments[++i]);
    } else if (arguments[i] == '--temperature') {
      temperature = double.parse(arguments[++i]);
    } else if (arguments[i] == '--api-key') {
      apiKey = arguments[++i];
    } else if (arguments[i] == '--no-think') {
      // Qwen3-style soft switch, passed as the chat template's
      // additional context (the Python path's --chat-template-args
      // '{"enable_thinking": false}').
      noThink = true;
    } else {
      _fail(
        'usage: mlx_serve_native --model `<snapshot-dir>` [--port N] '
        '[--max-tokens N] [--temperature T] [--api-key K]',
      );
    }
  }
  final dir = modelDir;
  if (dir == null || dir.isEmpty) {
    _fail('--model `<snapshot-dir>` is required');
  }
  if (!Directory(dir).existsSync()) {
    _fail('no model snapshot at $dir');
  }

  final loadWatch = Stopwatch()..start();
  final endpoint = await NativeMlxChatEndpoint.load(dir);
  loadWatch.stop();

  final server = MlxChatWireServer(
    completeRequest: (request) => endpoint.complete(
      MlxChatRequest(
        model: 'native',
        messages: request.messages,
        maxTokens: request.maxTokens ?? maxTokens,
        temperature: request.temperature ?? temperature,
        stop: request.stop,
        templateArgs: noThink
            ? const <String, Object?>{'enable_thinking': false}
            : request.templateArgs,
      ),
    ),
    model: 'mlx_text_native',
    apiKey: apiKey,
    port: port,
  );
  await server.start();
  stdout.writeln(
    'mlx_text_native serving ${server.url} (model loaded in '
    '${loadWatch.elapsedMilliseconds}ms; loopback only)',
  );

  final done = Completer<void>();
  ProcessSignal.sigterm.watch().listen((_) => done.complete());
  ProcessSignal.sigint.watch().listen((_) => done.complete());
  await done.future;
  await server.stop();
  await endpoint.dispose();
  stdout.writeln('mlx_text_native stopped.');
}
