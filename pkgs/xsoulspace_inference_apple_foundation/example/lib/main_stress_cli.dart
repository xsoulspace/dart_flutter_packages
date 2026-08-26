// ignore_for_file: lines_longer_than_80_chars

/// Production stress CLI entrypoint (Flutter macOS host).
///
/// Apple Foundation is a platform plugin, so the CLI must run inside the
/// Flutter engine. This is the entrypoint to build/run:
///
/// ```sh
/// # dev (interactive)
/// flutter run -t lib/main_stress_cli.dart --debug \
///   --dart-entrypoint-args=run --dart-entrypoint-args=--scenario \
///   --dart-entrypoint-args=multi_actor
///
/// # build a real binary, then run the .app
/// flutter build macos -t lib/main_stress_cli.dart --release
/// open build/macos/Build/Products/Release/*.app --args run --scenario=multi_actor
/// ```
///
/// Subcommands: `list`, `run`. Parsing + output logic live in
/// `lib/cli/stress_cli_app.dart` and are testable without the engine.
library;

import 'dart:io';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'package:flutter/widgets.dart';

import 'package:xsoulspace_inference_apple_foundation/xsoulspace_inference_apple_foundation_flutter.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'cli/stress_cli_app.dart';

Future<void> main(List<String> args) async {
  // Platform channels (Apple Foundation plugin) require the binding.
  WidgetsFlutterBinding.ensureInitialized();

  final parsed = _tryParse(args);
  if (parsed.error != null) {
    stderr.writeln(parsed.error);
    exit(ExitCode.badArgs);
  }
  final opts = parsed.opts!;

  switch (opts.command) {
    case 'list':
      stdout.writeln(listScenarios(json: opts.json));
      exit(ExitCode.ok);
    case 'run':
      await _run(opts);
    default:
      stderr.writeln('Unknown command: ${opts.command}');
      exit(ExitCode.badArgs);
  }
}

({
  String? error,
  ({String command, String? scenario, bool json, int? budget})? opts,
})
_tryParse(List<String> args) {
  try {
    return (error: null, opts: parseArgs(args));
  } on ArgException catch (e) {
    return (error: e.toString(), opts: null);
  }
}

Future<void> _run(
  ({String command, String? scenario, bool json, int? budget}) opts,
) async {
  final scenario = builtInScenarios()[opts.scenario ?? 'multi_actor'];
  if (scenario == null) {
    stderr.writeln('Unknown scenario: ${opts.scenario}');
    exit(ExitCode.badArgs);
  }

  final client = AppleFoundationInferenceClient(
    api: AppleFoundationInferenceClient.initApi(),
  );
  final available = await client.refreshAvailability();
  if (!available) {
    stderr.writeln('Apple Foundation Model unavailable.');
    exit(ExitCode.engineUnavailable);
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
  final metrics = await runner.run(scenario);

  if (opts.json) {
    stdout.writeln(metricsToJson(metrics));
  } else {
    stdout.writeln(const ScenarioMetricsReporter().render(metrics));
  }

  final budgetMiss = metrics.decisions.any((d) => d.truncated);
  exit(budgetMiss ? ExitCode.budgetExceeded : ExitCode.ok);
}
