// ignore_for_file: avoid_print, lines_longer_than_80_chars

/// AFM stress CLI — scenarios over the harness `ScenarioRunner`, FFI-only.
///
/// ```sh
/// dart run bin/stress_cli.dart list [--json]
/// dart run bin/stress_cli.dart run --scenario=multi_actor [--json]
/// ```
library;

import 'dart:io';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_inference_apple_foundation/src/native_bridge/native_client.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'stress/stress_cli_app.dart';

Future<void> main(List<String> args) async {
  final ({String? error, ({String command, String? scenario, bool json, int? budget})? opts}) parsed;
  try {
    parsed = (error: null, opts: parseArgs(args));
  } on ArgException catch (e) {
    stderr.writeln(e.toString());
    exit(64);
  }
  final opts = parsed.opts!;
  switch (opts.command) {
    case 'list':
      print(listScenarios(json: opts.json));
      return;
    case 'run':
    case 'benchmark':
      final client = AppleFoundationNativeClient();
      await client.load();
      if (!await client.refreshAvailability()) {
        stderr.writeln('Apple Foundation Model unavailable on this device.');
        exit(2);
      }
      final router = ModelRouter(
        inferenceClientsBuilders: {
          DefaultModelNames.appleFoundation: () => client,
        },
      );
      final scenarios = builtInScenarios();
      final scenario =
          scenarios[opts.scenario ?? 'multi_actor'];
      if (scenario == null) {
        stderr.writeln(
          'unknown scenario ${opts.scenario}; known: ${scenarios.keys.toList()}',
        );
        exit(64);
      }
      final world = World()..addPlugin(AgentPlugin());
      world
        ..upsertResource(ModelRouterResource(router))
        ..upsertResource(ToolRegistryResource());
      world.flush();
      final handler = DefaultGenerationHandler()..router = router;
      world.getResource<GenerationHandlerResource>().registerDefault(handler);

      final runner = ScenarioRunner(world: world, handler: handler);
      final metrics = await runner.run(scenario);
      stdout.writeln(
        opts.json
            ? metricsToJson(metrics)
            : const ScenarioMetricsReporter().render(metrics),
      );
      final budgetMiss = metrics.decisions.any((d) => d.truncated);
      exit(budgetMiss ? 3 : 0);
    default:
      stderr.writeln('usage: stress_cli list | run --scenario=<id> [--json]');
      exit(64);
  }
}
