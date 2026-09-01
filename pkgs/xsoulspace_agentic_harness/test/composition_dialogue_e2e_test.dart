// ignore_for_file: lines_longer_than_80_chars

/// End-to-end ADR 0014 "A": a prose/dialogue `FlowSpec` wired THROUGH the real
/// harness loop (`HarnessLoop.runUntilIdle`), LLM-free with a scripted
/// handler and a tool surface that gates OUT structural discovery.
///
/// This is the concrete proof that a general agent is *different loops, not
/// different models*: the dialogue loop is declared in YAML, `renderFlow`-ed
/// onto the existing [DecisionFlow], and driven by the SAME machinery that
/// runs coding agents.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'support/agent_harness_support.dart';

/// A minimal surface: the prose agent may `patch_file` (create/append a beat)
/// and `read` — but NOT `grep`/`glob` (no structural discovery for prose).
ToolRegistry _proseRegistry() {
  final registry = ToolRegistry();
  registry.register(
    ToolDef.encode(
      name: const ToolName('write_beat'),
      description: 'Append a beat to the draft.',
      execute: (args) async {
        final text = (args as Map? ?? const {})['text']?.toString() ?? '';
        return {
          'ok': true,
          'beat': text,
        };
      },
    ),
  );
  return registry;
}

void main() {
  test('dialogue flow (YAML) renders + drives the loop; surface gates tools', () async {
    // 1. Declare the dialogue loop as data.
    final spec = FlowSpec.fromYaml('''
name: dialogue_writer
archetype: dialogue
tools:
  allow_all: false
  allowed: [write_beat]
stages:
  - kind: decide
    trigger: tool_result
    prompt: Continue the dialogue. Draft the next turn as one beat.
  - kind: decide
    trigger: idle_every_n_ticks
    every_n_ticks: 3
    prompt: Reflect on pacing, then write the next turn.
''');
    expect(spec.archetype, 'dialogue');
    expect(spec.toolSurface.allows(const ToolName('write_beat')), isTrue);
    expect(spec.toolSurface.allows(const ToolName('grep')), isFalse);

    // 2) Render onto the existing DecisionFlow; wire + go.
    final rendered = renderFlow(spec);
    expect(rendered.flow.policies.length, 2); // tool_result + idle_tick
    final world = await buildTestWorld(
      decisionFlow: rendered.flow,
      toolRegistry: _proseRegistry(),
    );

    // Scripted single-turn generator: fires the model-facing policies.
    final handler = ScriptedGenerationHandler([
      const ScriptedTurn(text: 'HERO: "So this is where the story starts."'),
      const ScriptedTurn(text: 'VILLAIN: "Starts? No. It ends here."'),
    ]);
    world.getResource<GenerationHandlerResource>().registerDefault(handler);

    final scene = world.spawnComponents([const Scene(), SceneFrame()]);
    world.spawnComponents([
      Actor(agentId: AgentId.create()),
      const ActorModel(modelId: ModelId('suite-model')),
      const ActorSystemPrompt(text: 'You are a screenwriter. One beat per turn.'),
      const ActorTools(registryName: 'default'),
      PresentInScene(sceneEntity: scene),
      const OpenDecision(prompt: 'Open on the scene.'),
    ]);
    world.flush();

    await HarnessLoop(world: world).runUntilIdle();

    // 3) Deterministic oracle: the composition surface drove the loop; the
    //    actor is genuinely idle and empty (nothing stranded).
    expect(handler.requests, isNotEmpty);
    expectIdle(world);
  });
}
