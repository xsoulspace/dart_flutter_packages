// ignore_for_file: do_not_use_environment, lines_longer_than_80_chars

/// Headless Apple Foundation stress harness.
///
/// Runs a [Scenario] against the real `AppleFoundationInferenceClient` and
/// prints a metrics report, with no UI. This is the tool we use to stress the
/// harness end to end: multi-actor, multi-topic, tool-using, against a real
/// model, so we can find and fix weak spots.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:xsoulspace_inference_apple_foundation/xsoulspace_inference_apple_foundation.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'scenario_definitions.dart';

/// Entry point run via `flutter run -t lib/stress_cli.dart`.
///
/// Usage:
///   flutter run -t lib/stress_cli.dart --release --dart-define=SCENARIO=multi_actor
///
/// Prints the [ScenarioMetrics] report to stdout and exits 0 on success,
/// 1 on failure (e.g. engine unavailable, a projection blew the budget).
Future<void> main(List<String> args) async {
  // Platform channels (the Apple Foundation plugin) require the binding.
  WidgetsFlutterBinding.ensureInitialized();

  const scenarioName = String.fromEnvironment(
    'SCENARIO',
    defaultValue: 'multi_actor',
  );

  // Pick a scenario. The built-in set lives in scenario_definitions.dart;
  // a real CLI would load these from a config file, but for the first stress
  // pass we ship a couple of focused built-ins.
  final scenario = _scenarios()[scenarioName];
  if (scenario == null) {
    stderr.writeln('Unknown scenario: $scenarioName');
    exit(1);
  }

  // Wire up the real Apple Foundation model.
  final client = AppleFoundationInferenceClient(
    api: AppleFoundationInferenceClient.initApi(),
  );
  final available = await client.refreshAvailability();
  if (!available) {
    stderr.writeln('Apple Foundation Model unavailable.');
    exit(1);
  }

  final router = ModelRouter(
    inferenceClientsBuilders: {DefaultModelNames.appleFoundation: () => client},
  );
  final world = World()..addPlugin(AgentPlugin());
  world
    ..upsertResource(ModelRouterResource(router))
    ..upsertResource(ToolRegistryResource());
  world.flush();

  final handler = DefaultGenerationHandler()..router = router;
  world.getResource<GenerationHandlerResource>().registerDefault(handler);

  final runner = ScenarioRunner(world: world, handler: handler);

  stdout.writeln('Running scenario: ${scenario.name}');
  final metrics = await runner.run(scenario);
  final report = const ScenarioMetricsReporter().render(metrics);
  stdout.writeln(report);

  final budgetMiss = metrics.decisions.any((d) => d.truncated);
  exit(budgetMiss ? 1 : 0);
}

Map<String, Scenario> _scenarios() => <String, Scenario>{
  'multi_actor': multiActorTopicScenario(),
};
