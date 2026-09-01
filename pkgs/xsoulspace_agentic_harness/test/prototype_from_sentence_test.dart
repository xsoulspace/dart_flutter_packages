// ignore_for_file: lines_longer_than_80_chars

/// ADR 0014/0015 composition proof, CI-gated: a single product brief can be
/// carried through (FlowSpec → jailed world → discovery tools → harness →
/// tiered verdict) with ZERO core changes. Mirrors the LLM-free prototype
/// demo (`bin/prototype_from_sentence.dart`) but as a deterministic test so
/// the composition path cannot silently regress.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'support/agent_harness_support.dart';

Future<({DatasetResultSummary summary, bool hasStore})> _compose(
  String idea,
) async {
  final spec = FlowSpec.fromYaml('''
name: prototype_builder
archetype: app_prototype
tools:
  allow_all: false
  allowed: [write, list_dir, glob, read]
stages:
  - kind: decide
    trigger: tool_result
    prompt: Keep building toward the idea.
''');
  final rendered = renderFlow(spec);
  final jail = await Directory.systemTemp.createTemp('proto_test_');

  final world = World()..addPlugin(AgentPlugin());
  final router = ModelRouter(inferenceClientsBuilders: {});
  router.models[const ModelId('m')] = const Model(
    id: ModelId('m'),
  );
  world
    ..upsertResource(ModelRouterResource(router))
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(AgencyPolicy(maxConcurrent: 1, maxToolRounds: 8))
    ..upsertResource(DecisionFlowResource(rendered.flow))
    ..flush();

  final reg = ToolRegistry();
  for (final t in applyToolSurface(fsTools(FsToolsRoot(jail.path)), spec.toolSurface)) {
    reg.register(t);
  }
  world.getResource<ToolRegistryResource>().register('default', reg);

  world.getResource<GenerationHandlerResource>().registerDefault(
    ScriptedGenerationHandler([
      const ScriptedTurn(
        text: 'saved',
        toolCalls: [
          ToolCall(
            name: ToolName('write'),
            arguments: {
              'path': 'bookmarks.json',
              'content': '{"items":[]}',
            },
          ),
        ],
      ),
    ]),
  );

  final setup = AgentWorldSetup(world: world);
  final scene = setup.spawnScene();
  final actor = setup.spawnActors(
    [ActorSpec(name: 'builder', systemPrompt: 'Build.')],
    scene,
  ).single;
  world.upsertComponent(actor.entity, OpenDecision(prompt: 'Build: $idea'));
  world.flush();

  await HarnessLoop(world: world).runUntilIdle();
  expectIdle(world);

  final hasStore = File('${jail.path}/bookmarks.json').existsSync();
  final summary = DatasetResultSummary([
    DatasetRow(
      task: 'store',
      backend: EvalBackend.scripted,
      tokens: 100,
      calls: 1,
      passed: hasStore,
    ),
    DatasetRow(
      task: 'readme',
      backend: EvalBackend.scripted,
      tokens: 60,
      calls: 0,
      evidence: hasStore ? 'scaffolded' : 'missing store',
    ),
  ]);

  await jail.delete(recursive: true);
  return (summary: summary, hasStore: hasStore);
}

void main() {
  test('one sentence → FlowSpec → jailed world → tiered verdict', () async {
    final out = await _compose(
      'a bookmark manager that saves the current URL and lists saved ones',
    );
    expect(out.hasStore, isTrue);
    expect(out.summary.passableCount, 1);
    expect(out.summary.evidenceCount, 1);
    expect(out.summary.passedCount, 1);
    expect(out.summary.passRate, 1.0);
  });

  test('declared tool surface gates out unwanted tools even on the real profile', () {
    final spec = FlowSpec.fromYaml('''
name: x
archetype: prose_draft
tools:
  allow_all: false
  allowed: [write, read, glob]
stages:
  - kind: decide
    trigger: tool_result
    prompt: continue
''');
    expect(spec.archetype, 'prose_draft'); // free-form label, host-owned
    expect(spec.toolSurface.allows(const ToolName('write')), isTrue);
    expect(spec.toolSurface.allows(const ToolName('grep')), isFalse);
  });
}