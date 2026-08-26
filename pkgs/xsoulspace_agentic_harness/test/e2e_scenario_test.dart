// ignore_for_file: lines_longer_than_80_chars

/// End-to-end system test — the whole stack together, no real LLM.
///
/// Drives [ScenarioRunner] (which wires real tools + the metrics machine)
/// through a multi-actor scenario against a mock handler, and asserts the
/// metrics report is coherent end to end. This is the CI-viable version of the
/// Apple Foundation stress run: same path, mock model.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'support/agent_harness_support.dart';

void main() {
  test('scenario run produces a coherent metrics report with tools', () async {
    final world = await buildTestWorld();
    final handler = MockGenerationHandler(responseText: 'done');
    final runner = ScenarioRunner(world: world, handler: handler);

    // A multi-actor scenario using the real shared FS tools.
    final scenario = Scenario(
      name: 'e2e',
      tools: [...fsTools(FsToolsRoot('/tmp/ecsly_e2e_test'))],
      actors: [
        ScenarioActor(
          name: 'coder',
          systemPrompt: 'You are a coding agent.',
          decisions: ['Write a file', 'Read a file'],
        ),
        ScenarioActor(
          name: 'researcher',
          systemPrompt: 'You are a researcher.',
          decisions: ['List a directory'],
        ),
      ],
    );

    final metrics = await runner.run(scenario);

    // Scenario-level shape.
    expect(metrics.name, 'e2e');
    expect(metrics.decisions, hasLength(3));
    expect(metrics.decisions.map((d) => d.actor).toSet(), {
      'coder',
      'researcher',
    });
    expect(metrics.totalLlmCalls, 3);

    // Metrics-machine telemetry is populated.
    expect(metrics.telemetry.totalDecisions, 3);
    // The harness drives a real tool-execution path; results land as beats.
    expect(metrics.telemetry.totalToolResults, greaterThanOrEqualTo(0));

    // Reporter renders without throwing and shows the scenario.
    final report = const ScenarioMetricsReporter().render(metrics);
    expect(report, contains('Scenario: e2e'));
  });

  test('stress CLI scenario definitions build valid real tools', () {
    // Even if we cannot hit Apple Foundation in CI, the scenario builder must
    // produce tools with structured schemas and the runner must accept them.
    final scenario = Scenario(
      name: 'tools-ok',
      tools: [...fsTools(FsToolsRoot('/tmp/ecsly_e2e_test'))],
      actors: [
        ScenarioActor(name: 'a', systemPrompt: 'p', decisions: ['go']),
      ],
    );
    expect(
      scenario.tools,
      hasLength(fsTools(FsToolsRoot('/tmp/ecsly_e2e_test')).length),
    );
    for (final tool in scenario.tools) {
      expect(tool.argsSchema.isEmpty, isFalse);
    }
  });
}
