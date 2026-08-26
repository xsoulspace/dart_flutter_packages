// ignore_for_file: lines_longer_than_80_chars

/// The production stress CLI — argument parsing, subcommands, and output.
///
/// This is the "real" CLI the user reaches for, distinct from the dev
/// `flutter run -t` hack. It builds into a macOS binary and exposes
/// subcommands with flags and machine-readable output:
///
/// ```sh
/// stress_cli list
/// stress_cli run --scenario=multi_actor [--json] [--budget=4000]
/// stress_cli benchmark [--json]
/// ```
///
/// It is a Flutter-hosted CLI (Apple Foundation is a platform plugin, so it
/// needs a Flutter engine), but the parsing/selection/output logic here is
/// pure and testable without a model or engine.
library;

import 'dart:convert';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import '../scenario_definitions.dart';

/// Exit codes — stable contract for scripts/CI.
class ExitCode {
  static const ok = 0;
  static const engineUnavailable = 1;
  static const badArgs = 2;
  static const budgetExceeded = 3;
}

/// The scenarios this CLI knows about.
Map<String, Scenario> builtInScenarios() => <String, Scenario>{
  'multi_actor': multiActorTopicScenario(),
};

/// Parse [args] (excluding the program name) into a command + options.
///
/// Throws [ArgException] on bad usage.
({String command, String? scenario, bool json, int? budget}) parseArgs(
  List<String> args,
) {
  var command = '';
  String? scenario;
  var json = false;
  int? budget;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--')) {
      final eq = arg.indexOf('=');
      final key = eq == -1 ? arg.substring(2) : arg.substring(2, eq);
      String? value = eq == -1 ? null : arg.substring(eq + 1);
      switch (key) {
        case 'json':
          json = true;
        case 'scenario':
          // Support both `--scenario=x` and `--scenario x`.
          if (value == null && i + 1 < args.length) {
            value = args[i + 1];
            i++;
          }
          scenario = value;
          if (scenario == null) {
            throw ArgException('--scenario requires a value');
          }
        case 'budget':
          if (value == null && i + 1 < args.length) {
            value = args[i + 1];
            i++;
          }
          budget = value == null ? null : int.tryParse(value);
          if (budget == null) {
            throw ArgException('--budget requires an int');
          }
        default:
          throw ArgException('Unknown flag: --$key');
      }
    } else {
      command = arg;
    }
  }

  if (command.isEmpty) {
    throw ArgException('Expected a command: list|run|benchmark');
  }
  return (command: command, scenario: scenario, json: json, budget: budget);
}

class ArgException implements Exception {
  ArgException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Enumerate the built-in scenarios as human/JSON text.
String listScenarios({required bool json}) {
  final scenarios = builtInScenarios();
  if (json) {
    return jsonEncode({'scenarios': scenarios.keys.toList()});
  }
  return scenarios.keys.map((s) => '  - $s').join('\n');
}

/// Render a [ScenarioMetrics] report as JSON for machine consumption.
String metricsToJson(ScenarioMetrics metrics) => jsonEncode({
  'scenario': metrics.name,
  'decisions': metrics.decisions
      .map(
        (d) => {
          'actor': d.actor,
          'prompt': d.prompt,
          'tokensUsed': d.tokensUsed,
          'projectedBeats': d.projectedBeats,
          'truncated': d.truncated,
          'absences': d.explicitAbsences,
        },
      )
      .toList(),
  'totalLlmCalls': metrics.totalLlmCalls,
  'totalTokens': metrics.totalTokens,
  'prunedThreads': metrics.prunedThreads,
  'mergedThreads': metrics.mergedThreads,
  'telemetry': {
    'toolCalls': metrics.telemetry.totalToolCalls,
    'toolResults': metrics.telemetry.totalToolResults,
    'pendingTools': metrics.telemetry.pendingTools,
    'toolFrequency': metrics.telemetry.toolFrequency,
  },
});
