// ignore_for_file: lines_longer_than_80_chars

/// Tests for the production stress CLI's pure parsing/output logic.
///
/// These are engine-free: they validate argument parsing, scenario listing,
/// and metrics-to-JSON without needing Apple Foundation or a Flutter engine.
library;

import 'package:apple_foundation_example/cli/stress_cli_app.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  group('parseArgs', () {
    test('parses a plain command', () {
      final opts = parseArgs(['list']);
      expect(opts.command, 'list');
      expect(opts.json, isFalse);
    });

    test('parses flags', () {
      final opts = parseArgs([
        'run',
        '--scenario=multi_actor',
        '--json',
        '--budget=2000',
      ]);
      expect(opts.command, 'run');
      expect(opts.scenario, 'multi_actor');
      expect(opts.json, isTrue);
      expect(opts.budget, 2000);
    });

    test('rejects unknown flags', () {
      expect(() => parseArgs(['run', '--nope']), throwsA(isA<ArgException>()));
    });

    test('rejects missing command', () {
      expect(() => parseArgs(['--json']), throwsA(isA<ArgException>()));
    });
  });

  group('scenarios + output', () {
    test('lists built-in scenarios', () {
      final scenarios = builtInScenarios();
      expect(scenarios, contains('multi_actor'));
    });

    test('renders metrics as JSON with telemetry', () {
      final metrics = ScenarioMetrics(
        name: 'multi_actor',
        decisions: [
          DecisionMetrics(
            actor: 'coder',
            prompt: 'fix parser',
            tokensUsed: 14,
            projectedBeats: 3,
            explicitAbsences: const [],
            llmCalls: 1,
            truncated: false,
          ),
        ],
        totalLlmCalls: 1,
        totalTokens: 14,
        prunedThreads: 0,
        mergedThreads: 0,
        telemetry: MetricsReport(
          decisions: [
            DecisionTelemetry(
              actor: 'coder',
              prompt: 'fix parser',
              tokensUsed: 14,
              projectedBeats: 3,
              explicitAbsences: const [],
              truncated: false,
              toolCalls: const ['read'],
              toolResults: const ['read'],
              llmCalls: 1,
            ),
          ],
        ),
      );
      final json = metricsToJson(metrics);
      expect(json, contains('"scenario":"multi_actor"'));
      expect(json, contains('"toolCalls":1'));
    });
  });
}
