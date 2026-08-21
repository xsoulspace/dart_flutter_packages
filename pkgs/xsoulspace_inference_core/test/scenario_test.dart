// ignore_for_file: lines_longer_than_80_chars

/// Scenario stress-runner tests (LLM-agnostic).
///
/// Drives [ScenarioRunner] against a [MockGenerationHandler] end to end and
/// verifies the metrics we rely on to find weak spots: per-decision metrics,
/// aggregate LLM-call counts, thread behavior, and tool registry wiring
/// (including the dynamic tool hook). Runs with no real model.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'support/agent_harness_support.dart';

void main() {
  test(
    'runs a multi-actor scenario and records per-decision metrics',
    () async {
      final world = await buildTestWorld();
      final handler = MockGenerationHandler(responseText: 'ok');
      final runner = ScenarioRunner(world: world, handler: handler);

      final scenario = Scenario(
        name: 'multi',
        actors: [
          ScenarioActor(
            name: 'a',
            systemPrompt: 'p',
            decisions: ['one', 'two'],
          ),
          ScenarioActor(name: 'b', systemPrompt: 'p', decisions: ['three']),
        ],
      );
      final metrics = await runner.run(scenario);

      expect(metrics.name, 'multi');
      expect(metrics.decisions, hasLength(3));
      expect(metrics.decisions.map((d) => d.actor).toSet(), {'a', 'b'});
      expect(metrics.totalLlmCalls, 3);
      // Each decision produced a projection; none should be truncated here.
      expect(metrics.decisions.every((d) => !d.truncated), isTrue);
    },
  );

  test('registers both static and dynamically added tools', () async {
    final tResource = ToolRegistryResource();
    final world = await buildTestWorld(toolRegistryResource: tResource);
    final handler = MockGenerationHandler(responseText: 'ok');
    final runner = ScenarioRunner(
      world: world,
      handler: handler,
      toolRegistryResource: tResource,
    );

    final scenario = Scenario(
      name: 'tools',
      tools: [
        ToolDef(
          name: const ToolName('static_tool'),
          description: 'd',
          execute: (args) async => 'static',
        ),
      ],
      toolHook: () async => [
        ToolDef(
          name: const ToolName('dynamic_tool'),
          description: 'd',
          execute: (args) async => 'dynamic',
        ),
      ],
      actors: [
        ScenarioActor(name: 'a', systemPrompt: 'p', decisions: ['go']),
      ],
    );

    await runner.run(scenario);

    final registry = tResource.get('default');
    expect(registry, isNotNull);
    expect(registry!.get(const ToolName('static_tool')), isNotNull);
    expect(registry.get(const ToolName('dynamic_tool')), isNotNull);
  });

  test('reporter renders a human-readable report', () async {
    final world = await buildTestWorld();
    final handler = MockGenerationHandler(responseText: 'ok');
    final runner = ScenarioRunner(world: world, handler: handler);

    final scenario = Scenario(
      name: 'single',
      actors: [
        ScenarioActor(name: 'a', systemPrompt: 'p', decisions: ['go']),
      ],
    );

    final metrics = await runner.run(scenario);
    final report = const ScenarioMetricsReporter().render(metrics);

    expect(report, contains('Scenario: single'));
    expect(report, contains('[a]'));
  });
}
