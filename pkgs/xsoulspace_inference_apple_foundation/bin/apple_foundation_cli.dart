import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_inference_apple_foundation/src/native_bridge/native_client.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// Native CLI smoke test — no Flutter engine required.
///
/// ```sh
/// sh tool/build_bridge.sh
/// dart run bin/apple_foundation_cli.dart probe
/// dart run bin/apple_foundation_cli.dart ask "Say hello in one word"
/// ```
Future<void> main(List<String> args) async {
  final command = args.isEmpty ? 'probe' : args.first;
  final client = AppleFoundationNativeClient();

  switch (command) {
    case 'probe':
      await client.load();
      final available = await client.refreshAvailability();
      stdout.writeln(
        jsonEncode({'provider': client.id, 'available': available}),
      );
      exit(available ? 0 : 1);
    case 'ask':
      if (args.length < 2) {
        stderr.writeln('Usage: ask <prompt>');
        exit(2);
      }
      final result = await client.infer(
        InferenceRequest(prompt: args.sublist(1).join(' ')),
      );
      if (result.success) {
        stdout.writeln(result.data!.rawOutput);
        exit(0);
      }
      stderr.writeln(
        jsonEncode({
          'code': result.error?.code,
          'message': result.error?.message,
        }),
      );
      exit(1);
    case 'tool':
      // Tool round-trip: model must call the clock tool to answer.
      final registry = ToolRegistry()
        ..register(
          ToolDef.encode(
            name: const ToolName('clock'),
            description: 'Returns the current time in ISO-8601.',
            argsSchema: SchemaBundle(
              root: FM.object(
                'ClockResult',
                properties: () => [FM.prop('iso', FM.string())],
              ),
            ),
            execute: (args) async => <String, dynamic>{
              'iso': DateTime.now().toIso8601String(),
            },
          ),
        );
      final toolResult = await client.infer(
        InferenceRequest(
          prompt:
              'Use the clock tool, then answer with just the hour number. What time is it? '
              '',
          task: InferenceTask.text,
        ),
        toolRegistry: registry,
      );
      if (toolResult.success) {
        stdout.writeln(toolResult.data!.rawOutput);
        exit(0);
      }
      stderr.writeln(
        jsonEncode({
          'code': toolResult.error?.code,
          'message': toolResult.error?.message,
        }),
      );
      exit(1);
    default:
      stderr.writeln('Unknown command: $command (expected probe|ask|tool)');
      exit(2);
  }
}
