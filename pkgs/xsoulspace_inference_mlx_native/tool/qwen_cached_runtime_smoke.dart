/// Harmless bounded-output native inference, separate from coding acceptance.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

import 'native_runtime_preflight.dart';

Future<String> digest(final File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<void> main(final List<String> args) async {
  if (args.length != 1) throw ArgumentError('EXPLICIT_QWEN_1_7B_SNAPSHOT');
  final snapshot = Directory(args.single).resolveSymbolicLinksSync();
  final config =
      jsonDecode(await File('$snapshot/config.json').readAsString()) as Map;
  if (config['model_type'] != 'qwen3' ||
      config['hidden_size'] != 2048 ||
      config['num_hidden_layers'] != 28) {
    throw StateError('qwen_smoke_checkpoint_identity_mismatch');
  }
  final runtime = inspectNativeRuntimeIdentity();
  if (runtime['colocatedMetalExists'] != true) {
    throw StateError('qwen_smoke_metal_missing');
  }
  final hashes = <String, String>{};
  for (final path in [
    '$snapshot/config.json',
    '$snapshot/tokenizer.json',
    '$snapshot/tokenizer_config.json',
    '$snapshot/model.safetensors',
    runtime['nativeImage']! as String,
    runtime['colocatedMetal']! as String,
    Platform.resolvedExecutable,
  ]) {
    hashes[path] = await digest(File(path));
  }
  stdout.writeln(
    jsonEncode({
      'phase': 'prepared',
      'runtime': runtime,
      'snapshot': snapshot,
      'hashes': hashes,
    }),
  );
  const limit = 16;
  final client = MlxNativeTextClient.lazyQwen(
    snapshotDir: snapshot,
    thinking: false,
    model: 'Qwen3-1.7B-4bit',
    defaultMaxTokens: limit,
  );
  final watch = Stopwatch()..start();
  try {
    await client.load();
    if (!client.isAvailable) {
      throw StateError('qwen_smoke_load_failed:${client.loadError}');
    }
    final loadedMs = watch.elapsedMilliseconds;
    stdout.writeln(jsonEncode({'phase': 'loaded', 'elapsedMs': loadedMs}));
    final result = await client.infer(
      InferenceRequest(
        prompt: 'Reply with one word: the sky color on a clear day?',
        maxTokens: limit,
        temperature: 0,
        thinking: false,
      ),
    );
    if (!result.success) {
      throw StateError(
        'qwen_smoke_infer_failed:'
        '${result.error!.code}:${result.error!.message}',
      );
    }
    final response = result.data!;
    final usage = response.meta['usage'] as Map;
    if (response.toolCalls.isNotEmpty ||
        response.rawOutput?.isNotEmpty != true ||
        (usage['completion_tokens'] as int) > limit) {
      throw StateError('qwen_smoke_output_contract_failed');
    }
    for (final entry in hashes.entries) {
      if (await digest(File(entry.key)) != entry.value) {
        throw StateError('qwen_smoke_artifact_changed:${entry.key}');
      }
    }
    stdout.writeln(
      jsonEncode({
        'phase': 'completed',
        'loadedMs': loadedMs,
        'elapsedMs': watch.elapsedMilliseconds,
        'maxTokens': limit,
        'temperature': 0,
        'thinking': false,
        'response': response.toJson(),
        'codingAcceptance': false,
        'toolsInvoked': false,
        'artifactsUnchanged': true,
      }),
    );
  } finally {
    client.unloadEngine();
    client.dispose();
  }
}
