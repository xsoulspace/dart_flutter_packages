import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/benchmark_api.dart'
    show defaultGoalFlow, wireRunGradedGoal;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_dart_meaning/xsoulspace_agentic_dart_meaning.dart';

class _Scripted implements GenerationHandler {
  var step = 0;
  final String areaId;
  final String boxId;
  _Scripted(this.areaId, this.boxId);
  @override
  Future<ActorGenerateResponse> generate(
    World world, ActorGenerateRequest request) async {
    step++;
    stderr.writeln('--- decision $step');
    final calls = switch (step) {
      1 => [
          ToolCall(name: const ToolName('repo_etl'), arguments: {'action': 'scan'}),
        ],
      2 => [
          ToolCall(name: const ToolName('edit_symbol'), arguments: {
            'action': 'apply_executable',
            'executableId': 'rename_symbol',
            'symbolId': areaId,
            'executableParams': {'newName': 'surfaceArea'},
          }),
        ],
      3 => [
          ToolCall(name: const ToolName('edit_symbol'), arguments: {
            'action': 'insert_member',
            'classSymbolId': boxId,
            'name': 'doubled',
            'returns': 'int',
            'params': ['f:int'],
            'opChain': [
              {'label': 'load_arg', 'a': 'f'},
              {'label': 'literal', 'b': '2'},
              {'label': 'mul'},
              {'label': 'return'},
            ],
          }),
        ],
      _ => const <ToolCall>[],
    };
    final r = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': 'step $step'},
      rawOutput: 'step $step',
      toolCalls: calls,
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(r);
    return r;
  }
}

class _Noop implements GenerationHandler {
  @override
  Future<ActorGenerateResponse> generate(
    World world, ActorGenerateRequest request) async {
    final r = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: const {'text': ''},
      rawOutput: '',
      toolCalls: const [],
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(r);
    return r;
  }
}

void main() {
  test('debug gate flow', () async {
    final jail = await Directory.systemTemp.createTemp('dbg_jail_');
    addTearDown(() => jail.delete(recursive: true));
    File('${jail.path}/pubspec.yaml').writeAsStringSync(
      'name: span_jail\nenvironment:\n  sdk: ^3.0.0\ndev_dependencies:\n  test: any\n');
    Directory('${jail.path}/lib').createSync();
    Directory('${jail.path}/test').createSync();
    File('${jail.path}/lib/geometry.dart').writeAsStringSync(
      'int area(int w, int h) {\n  return w * h;\n}\n');
    File('${jail.path}/lib/boxes.dart').writeAsStringSync(
      'class Box {\n  int volume(int w, int h, int d) {\n    return w * h * d;\n  }\n}\n');
    File('${jail.path}/test/geometry_test.dart').writeAsStringSync('''
import 'package:test/test.dart';
import 'package:span_jail/geometry.dart';
import 'package:span_jail/boxes.dart';
void main() {
  test('surfaceArea', () { expect(surfaceArea(2, 3), 6); });
  test('doubled', () { expect(Box().doubled(21), 42); });
}
''');
    await Process.run('dart', ['pub', 'get'], workingDirectory: jail.path);

    // pre-scan to resolve ids
    final pre = World()..addPlugin(AgentPlugin());
    pre..upsertResource(ToolRegistryResource())..upsertResource(FlightRecorder())
      ..upsertResource(GenerationHandlerResource())..upsertResource(ModelRouterResource(ModelRouter()))
      ..flush();
    pre.getResource<GenerationHandlerResource>().registerDefault(_Noop());
    final preScan = repoEtlTool(pre, jail);
    await preScan.execute({'action': 'scan'});
    final idx = pre.getResource<MeaningIndex>();
    final areaId = idx.byId.keys.where((i) => i.endsWith('_area')).first;
    final boxId = idx.byId.keys.where((i) => i.endsWith('_Box')).first;
    stderr.writeln('areaId=$areaId boxId=$boxId');

    final world = World()..addPlugin(AgentPlugin());
    world
      ..upsertResource(ToolRegistryResource())
      ..upsertResource(FlightRecorder())
      ..upsertResource(DecisionFlowResource(defaultGoalFlow()))
      ..upsertResource(AgencyPolicy(maxConcurrent: 1, maxToolRounds: 12))
      ..upsertResource(CutCompositionResource(CutComposition.coderLean()))
      ..upsertResource(ProjectionBudget(tokens: 4000))
      ..upsertResource(GenerationHandlerResource())
      ..upsertResource(ModelRouterResource(ModelRouter()))
      ..flush();
    world.getResource<GenerationHandlerResource>().registerDefault(_Scripted(areaId, boxId));
    final registry = ToolRegistry();
    registry.register(repoEtlTool(world, jail));
    registry.register(editSymbolTool(world, jail));
    world.getResource<ToolRegistryResource>().register('default', registry);
    wireRunGradedGoal(world, command: ['dart', 'test'], cwd: jail.path);

    const taskPrompt = 'Make the failing suite pass.';
    final scene = world.spawnComponents([Scene(), SceneFrame()]);
    final actor = world.spawnComponents([
      Actor(agentId: AgentId.create()),
      ActorModel(modelId: ModelId.create()),
      ActorSystemPrompt(text: 'edit through meaning moves'),
      ActorThreads(threads: []),
      ActorTools(registryName: 'default'),
      PresentInScene(sceneEntity: scene),
      Goal(text: taskPrompt),
      OpenDecision(prompt: taskPrompt),
    ]);
    final thread = spawnThread(world, actor, scene);
    world.upsertComponent(actor, ActorThreads(threads: [thread]));
    world.flush();

    await HarnessLoop(world: world).runUntilIdle();

    for (final b in world.getResource<FacetIndex>().beatsOfThread(thread).toList()) {
      final we = world.getEntity(b).$1;
      final call = we.get<BeatToolCall>();
      final res = we.get<ToolResultContent>();
      final ver = we.get<GoalVerified>();
      final outStr = '${res?.output}';
      stderr.writeln('BEAT call=${call?.name} verified=${ver?.passed} out=' + outStr.substring(0, outStr.length > 180 ? 180 : outStr.length));
    }
    final geo = File('${jail.path}/lib/geometry.dart').readAsStringSync();
    stderr.writeln('geometry now: $geo');
    stderr.writeln('attempt=${world.getEntity(actor).$1.get<AttemptCount>()?.value}');
    stderr.writeln('exhausted=${world.query2<Actor, GoalAttemptsExhausted>().toList().isNotEmpty}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
