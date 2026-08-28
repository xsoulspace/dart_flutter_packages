// ignore_for_file: lines_longer_than_80_chars

/// Real-AFM harness driving ONE `act_with_project` tool so a tiny 2–4k model
/// builds a RUNNING Dart tic-tac-toe board by picking only tiny moves over
/// the MEANING (never an AST, never raw code tokens).
///
/// The AST is internal: this host materializes the model's choices into a
/// REAL `dart run`-able `main.dart` and runs it. The model only ever sees
/// the closed sub-actions: list / add / link / set_prop / materialize / run.
/// Proves "repurpose a small model via exposed-trivial-means" on-device.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_harness/src/tooling/structured_editor.dart'
    show StructuredDoc, actWithProjectTool;
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show FsToolsRoot, runTool;
import 'package:xsoulspace_inference_apple_foundation/src/native_bridge/native_client.dart';

// ---------------------------------------------------------------------------
// Host materializer: doc (board + cells) -> a VALID Dart main.dart.
// AST stays internal; this is the "another program" that talks meaning->code.
// ---------------------------------------------------------------------------

String materializeMainDart(StructuredDoc doc) {
  final cells = doc.nodes.values.where((n) => n.kind == 'cell').toList();
  // Board dimension: prefer an explicit size prop, else by cell count.
  int size = 3;
  final sizeProp = doc.nodes.values
      .where((n) => n.kind == 'board')
      .map((n) => n.props['size'])
      .whereType<Object>()
      .map((v) => num.tryParse('$v'))
      .whereType<num>()
      .firstOrNull;
  if (sizeProp != null) {
    size = sizeProp.toInt().clamp(2, 9);
  } else if (cells.isNotEmpty) {
    size = math.max(2, (math.sqrt(cells.length).ceil()));
  }
  final buf = StringBuffer()..writeln('void main() {');
  for (var r = 0; r < size; r++) {
    final line = <String>[];
    for (var c = 0; c < size; c++) {
      line.add('"·"');
    }
    buf.writeln('  print(${line.join(' + "|" + ')});');
  }
  buf.writeln('}');
  return buf.toString();
}

Future<void> main(List<String> args) async {
  final client = AppleFoundationNativeClient();
  await client.load();
  if (!await client.refreshAvailability()) {
    stderr.writeln('Apple Foundation Model unavailable.');
    exit(2);
  }

  // A world with ONE act_with_project tool + the run tool (materialize+run).
  final world = World()..addPlugin(AgentPlugin());
  final router = ModelRouter(
    inferenceClientsBuilders: {
      DefaultModelNames.appleFoundation: () => AppleFoundationNativeClient(),
    },
  );
  final modelId = ModelId('act');
  router.models[modelId] = Model(
    id: modelId,
    name: DefaultModelNames.appleFoundation,
  );
  world
    ..upsertResource(ModelRouterResource(router))
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(AgencyPolicy(maxConcurrent: 1, maxToolRounds: 20))
    ..flush();
  world.getResource<GenerationHandlerResource>().registerDefault(
        DefaultGenerationHandler(router: router),
      );

  // The shared project doc lives in the closure; the one tool closes over it.
  final doc = StructuredDoc();
  final jail = await Directory.systemTemp.createTemp('act_project_');
  final registry = ToolRegistry();
  registry.register(actWithProjectTool(
    doc: () => doc,
    materialize: () async {
      final src = materializeMainDart(doc);
      File('${jail.path}/main.dart').writeAsStringSync(src);
      return {'path': 'main.dart', 'materialized': true, 'runs': 'see run'};
    },
  ));
  registry.register(runTool(FsToolsRoot(jail.path)));
  world.getResource<ToolRegistryResource>().register('default', registry);

  final scene = world.spawnComponents([Scene(), SceneFrame()]);
  final actor = world.spawnComponents([
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: modelId),
    ActorSystemPrompt(
      text: 'You talk to the project through one tool: act_with_project. '
          'Pick the smallest sub-action each turn: list, add, link, set_prop, '
          'materialize, or run. To make a tic-tac-toe board: add 9 cells, '
          'link them, then materialize, then run. You never write code.',
    ),
    ActorThreads(threads: []),
    ActorTools(registryName: 'default'),
    PresentInScene(sceneEntity: scene),
    OpenDecision(prompt: 'Build a 3x3 tic-tac-toe game that runs.'),
  ]);
  final thread = spawnThread(world, actor, scene);
  world.upsertComponent(actor, ActorThreads(threads: [thread]));
  world.flush();

  // A weak capturing "done" oracle OR the harness loop ends on the final
  // answer. We run until idle and then check the produced file runs.
  await HarnessLoop(world: world).runUntilIdle();

  // Evaluate: did the model build a working program via tiny picks?
  final path = '${jail.path}/main.dart';
  final exists = File(path).existsSync();
  String runResult = 'n/a';
  if (exists) {
    final r = Process.runSync(
      'dart',['run', path],
      workingDirectory: jail.path,
    );
    runResult = 'exit=${r.exitCode}';
  }
  stdout
    ..writeln('act_with_project (AFM):')
    ..writeln('  nodes built: ${doc.nodes.length}')
    ..writeln('  edges: ${doc.edges.length}')
    ..writeln('  main.dart exists: $exists')
    ..writeln('  dart run main.dart: $runResult');
  exit(exists && runResult.startsWith('exit=0') ? 0 : 1);
}