// ignore_for_file: avoid_print, lines_longer_than_80_chars

/// "Scale one sentence into a full prototype" — harness + AE composition demo.
///
/// Composes the generic shapes (ADR 0014/0015) to go from one product brief
/// to a tiered verdict + a populated prototype workspace, all LLM-free:
///
/// ```text
///   "a bookmark manager that saves the current tab and lists saved ones"
///   │  1. host → FlowSpec (declarative loop: stages + tool surface + archetype)
///   │  2. world → AgentWorldSetup + HarnessLoop (embedding surface)
///   │  3. jail + discovery tools (grep/glob) for the agent to work
///   │  4. verify gate → DatasetSpec tier (passable vs evidence)
///   ▼
///   prototype workspace + verdict row
/// ```
///
/// The exact seams a real product pulls: declare the loop as data, host it,
/// let the agent build into a jail, gate the result. Nothing forks the core.
library;

import 'dart:io';

import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

/// Run one sentence through the composition stack; return the summary.
Future<DatasetResultSummary> prototypeFrom(String idea) async {
  // 1. Declare the loop as data (free-form archetype, host-owned).
  final spec = FlowSpec.fromYaml('''
name: prototype_builder
archetype: app_prototype
tools:
  allow_all: false
  allowed: [write, list_dir, glob, read]
stages:
  - kind: decide
    trigger: tool_result
    prompt: Keep building the prototype toward the idea the user gave.
''');
  final rendered = renderFlow(spec);

  // 2. Embed the world through the public host surface, with a tool jail.
  final jail = await Directory.systemTemp.createTemp('proto_');
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

  final registry = ToolRegistry();
  for (final tool
      in applyToolSurface(fsTools(FsToolsRoot(jail.path)), spec.toolSurface)) {
    registry.register(tool);
  }
  world.getResource<ToolRegistryResource>().register('default', registry);

  // 3. LLM-free host: deterministic builder (swap for AFM/OR to "vibe").
  world.getResource<GenerationHandlerResource>().registerDefault(
        ScriptedGenerationHandler([
          ScriptedTurn(
            text: 'I saved the first bookmark.',
            toolCalls: [
              const ToolCall(
                name: ToolName('write'),
                arguments: {'path': 'bookmarks.json', 'content': '{"items":[]}'},
              ),
              ToolCall(
                name: const ToolName('write'),
                arguments: {
                  'path': 'README.md',
                  'content': 'Bookmark manager — from: "$idea"',
                },
              ),
            ],
          ),
        ]),
      );

  world.flush();

  final setup = AgentWorldSetup(world: world);
  final scene = setup.spawnScene();
  final actors = setup.spawnActors([
    ActorSpec(name: 'builder', systemPrompt: 'Build the idea.'),
  ], scene);
  world.upsertComponent(
    actors.single.entity,
    OpenDecision(prompt: 'Build a prototype for: $idea'),
  );
  world.flush();

  await HarnessLoop(world: world).runUntilIdle();

  // 4. Verify gate on the produced workspace → DatasetResultSummary.
  final hasStore = File('${jail.path}/bookmarks.json').existsSync();
  final summary = DatasetResultSummary([
    DatasetRow(
      task: 'bookmark_manager_store',
      backend: EvalBackend.scripted,
      tokens: 140,
      calls: 2,
      passed: hasStore,
    ),
    DatasetRow(
      task: 'bookmark_manager_readme',
      backend: EvalBackend.scripted,
      tokens: 60,
      calls: 1,
      evidence: hasStore
          ? 'prototype scaffolded; store present'
          : 'partial — missing bookmarks.json',
    ),
  ]);

  try {
    await jail.delete(recursive: true);
  } on Object {
    // best-effort temp cleanup
  }
  return summary;
}

Future<void> main(List<String> args) async {
  final idea = args.isNotEmpty
      ? args.join(' ')
      : 'a bookmark manager that saves the current URL and lists saved ones';
  final summary = await prototypeFrom(idea);
  print('brief : $idea');
  print(summary.toMarkdown());
}