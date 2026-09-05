// ignore_for_file: avoid_print, lines_longer_as_80_chars

/// Stress CLI — scenarios over the harness `ScenarioRunner` (ADR 0026 §4).
///
/// Provider-agnostic: the caller injects the router factory (a composition
/// root builds it from its backend — e.g. the AFM bridge or a hosted
/// client). `list` works without any router.
///
/// ```sh
/// dart run bin/stress_cli.dart list [--json]
/// dart run bin/stress_cli.dart run --scenario=multi_actor [--json]
/// ```
library;

import 'dart:io';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'package:xsoulspace_agentic_harness/src/benchmark/stress/stress_cli_app.dart';
/// Runs the stress CLI with a router factory supplied by the composition
/// root ([buildRouter] returns null when the backend is unavailable — the
/// CLI then exits with the honest `engineUnavailable` code).
Future<void> runStressCli(
  List<String> args, {
  required Future<ModelRouter?> Function() buildRouter,
}) async {
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
      stdout.writeln(listScenarios(json: opts.json));
      return;
    case 'run':
    case 'benchmark':
      final router = await buildRouter();
      if (router == null) {
        stderr.writeln('backend unavailable on this device/environment.');
        exit(2);
      }
      final scenarios = builtInScenarios();
      final scenario = scenarios[opts.scenario ?? 'multi_actor'];
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
