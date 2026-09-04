// ignore_for_file: lines_longer_than_80_chars

/// R7 PRODUCTION #3 GATE (ADR 0021 capture loop × ADR 0023 §3): a NOVEL
/// model-composed resolution — a `replace_member_body` that passed all
/// three fences and the free oracles — becomes a PROJECT-PACK entry
/// (`EditExecutableWire` + op-chain, persisted under
/// `.dart_tool/harnessd/edit_pack.json`), and a SECOND task consumes it at
/// ZERO authored tokens (`apply_executable {executableId, symbolId}` — no
/// op rows in the call).
///
/// LLM-free: scripted movers over the real registry; the same two-task
/// shape as the R7b gate. Two INDEPENDENT worlds/sessions over one
/// workspace prove the pack persists across tasks (the second task's
/// materializer realizes the pack automatically — no extra wiring).
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/benchmark_api.dart'
    show defaultGoalFlow;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'package:xsoulspace_agentic_dart_meaning/xsoulspace_agentic_dart_meaning.dart';

// The fixture: TWO members with the SAME repair class (params w, h):
// `area` is the novel resolution target; `product` is what the SECOND
// task fixes pack-fed. The suite covers both (fence b).
Future<Directory> _jail() async {
  final dir = await Directory.systemTemp.createTemp('edit_pack_jail_');
  File('${dir.path}/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      'name: pack_capture\nenvironment:\n  sdk: ^3.0.0\ndev_dependencies:\n  test: any\n',
    );
  File('${dir.path}/lib/geometry.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
int area(int w, int h) {
  return 0;
}

int product(int w, int h) {
  return 0;
}
''');
  File('${dir.path}/test/geometry_test.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
import 'package:test/test.dart';
import 'package:pack_capture/geometry.dart';

void main() {
  test('area', () {
    expect(area(2, 3), 6);
  });
}
''');
  return dir;
}

/// The SECOND task needs product covered only when it runs — the suite
/// stays green for task 1 (area-only) so the composed move grades FULLY
/// green (capture requires a proven resolution, not a kept one).
void _coverProduct(Directory jail) {
  File('${jail.path}/test/geometry_test.dart').writeAsStringSync('''
import 'package:test/test.dart';
import 'package:pack_capture/geometry.dart';

void main() {
  test('area', () {
    expect(area(2, 3), 6);
  });
  test('product', () {
    expect(product(2, 3), 6);
  });
}
''');
}

World _world(Directory jail, GenerationHandler handler) {
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
  world.getResource<GenerationHandlerResource>().registerDefault(handler);
  return world;
}

/// The R7 registry exactly as the daemon wires it — edit_symbol carries
/// the capture loop (auto-realizes the project pack).
void _registerSurface(World world, Directory jail) {
  final registry = ToolRegistry();
  registry.register(repoEtlTool(world, jail));
  registry.register(meaningZoomTool(world));
  registry.register(meaningImpactTool(world));
  registry.register(editSymbolTool(world, jail));
  world.getResource<ToolRegistryResource>().register('default', registry);
}

/// One task cycle: scan → the mover's scripted edit calls — graded by the
/// workspace convention through the run-graded goal loop.
Future<void> _runTask(World world, String taskPrompt) async {
  final scene = world.spawnComponents([Scene(), SceneFrame()]);
  final actor = world.spawnComponents([
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: ModelId.create()),
    ActorSystemPrompt(text: 'You edit code through meaning moves only.'),
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
}

/// The same pack filename the capture loop persists to.
File packFile(Directory jail) =>
    File('${jail.path}/.dart_tool/harnessd/edit_pack.json');

void main() {
  test('R7 production #3: scripted novel resolution → pack entry → a second '
      'task consumes it at ZERO authored tokens', () async {
    final jail = await _jail();
    addTearDown(() => jail.deleteSync(recursive: true));
    await Process.run('dart', ['pub', 'get'], workingDirectory: jail.path);

    // Pre-scan to resolve ids for the scripted movers (host-side
    // accommodation, zero model tokens — same as the R7b gate).
    final pre = _world(jail, _Noop());
    _registerSurface(pre, jail);
    await pre
        .getResource<ToolRegistryResource>()
        .get('default')!
        .tools
        .values
        .firstWhere((t) => t.name.value == 'repo_etl')
        .execute({'action': 'scan'});
    final index = pre.getResource<MeaningIndex>();
    final areaId = index.byId.keys.where((id) => id.endsWith('_area')).first;
    final productId = index.byId.keys
        .where((id) => id.endsWith('_product'))
        .first;

    // ---- TASK 1: the NOVEL resolution (model-composed op-chain) ----
    final chain = [
      {'label': 'load_arg', 'a': 'w'},
      {'label': 'load_arg', 'a': 'h'},
      {'label': 'mul'},
      {'label': 'return'},
    ];
    final world1 = _world(
      jail,
      _ScriptedEditor([
        ToolCall(
          name: const ToolName('repo_etl'),
          arguments: {'action': 'scan'},
        ),
        ToolCall(
          name: const ToolName('edit_symbol'),
          arguments: {
            'action': 'replace_member_body',
            'symbolId': areaId,
            'opChain': chain,
          },
        ),
      ]),
    );
    _registerSurface(world1, jail);
    await _runTask(world1, 'Fix area: it must return w*h.');

    // The move LANDED and the suite went green (dart test exit 0).
    final test1 = await Process.run('dart', [
      'test',
    ], workingDirectory: jail.path);
    expect(test1.exitCode, 0, reason: '${test1.stdout}${test1.stderr}');
    final geometry1 = File('${jail.path}/lib/geometry.dart').readAsStringSync();
    expect(geometry1, contains('return (w * h);'));

    // THE CAPTURE: a pack entry exists with a mechanical fingerprint id
    // and the chain as data.
    final pack = packFile(jail);
    expect(
      pack.existsSync(),
      isTrue,
      reason: 'the novel resolution must be captured',
    );
    final decoded = jsonDecode(pack.readAsStringSync()) as Map;
    final entries = (decoded['executables'] as List).cast<Map>();
    expect(entries, hasLength(1));
    final entry = entries.single;
    expect(entry['id'], startsWith('dart/captured/'));
    expect(entry['kind'], 'replace_member_body');
    expect(entry['params'], ['symbolId']);
    final capturedChain = (entry['opChain'] as List).cast<Map>();
    expect(capturedChain.map((r) => r['label']).toList(), [
      'load_arg',
      'load_arg',
      'mul',
      'return',
    ]);
    final capturedId = entry['id'] as String;

    // ---- TASK 2: the SAME repair class, consumed PACK-FED ----
    _coverProduct(jail);
    final world2 = _world(
      jail,
      _ScriptedEditor([
        ToolCall(
          name: const ToolName('repo_etl'),
          arguments: {'action': 'scan'},
        ),
        // ZERO authored tokens: NO opChain in the call — the chain travels
        // with the pack; the model supplies only id + symbolId.
        ToolCall(
          name: const ToolName('edit_symbol'),
          arguments: {
            'action': 'apply_executable',
            'executableId': capturedId,
            'symbolId': productId,
          },
        ),
      ]),
    );
    _registerSurface(world2, jail);
    await _runTask(world2, 'Fix product the same way area was fixed.');

    // The pack-fed move landed and the convention is green.
    final test2 = await Process.run('dart', [
      'test',
    ], workingDirectory: jail.path);
    expect(test2.exitCode, 0, reason: '${test2.stdout}${test2.stderr}');
    final geometry2 = File('${jail.path}/lib/geometry.dart').readAsStringSync();
    expect(
      geometry2,
      stringContainsInOrder(['int product(int w, int h) {', 'return (w * h);']),
      reason: 'the captured chain must apply to the second symbol',
    );

    // Idempotence: re-capturing the same class does not duplicate.
    final capture = EditPackCapture(jail);
    final again = capture.captureVerified(
      action: 'replace_member_body',
      opChain: chain,
      description: 'duplicate capture attempt',
    );
    expect(again, capturedId);
    expect(
      (jsonDecode(pack.readAsStringSync()) as Map)['executables'],
      hasLength(1),
    );

    // Non-capturable actions bounce out of the loop as null.
    expect(
      capture.captureVerified(
        action: 'insert_member',
        opChain: chain,
        description: 'not a body replacement',
      ),
      isNull,
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('capture requires a PROVEN resolution: a kept move under a pre-existing '
      'red baseline is NOT captured', () async {
    final jail = await _jail();
    addTearDown(() => jail.deleteSync(recursive: true));
    await Process.run('dart', ['pub', 'get'], workingDirectory: jail.path);
    // The suite is RED from the start (product uncovered expectation on
    // a broken body) — the composed move keeps, but the oracles never
    // graded it green.
    File('${jail.path}/test/geometry_test.dart').writeAsStringSync('''
import 'package:test/test.dart';
import 'package:pack_capture/geometry.dart';

void main() {
  test('area', () {
    expect(area(2, 3), 6);
  });
  test('product', () {
    expect(product(2, 3), 6);
  });
}
''');

    final pre = _world(jail, _Noop());
    _registerSurface(pre, jail);
    await pre
        .getResource<ToolRegistryResource>()
        .get('default')!
        .tools
        .values
        .firstWhere((t) => t.name.value == 'repo_etl')
        .execute({'action': 'scan'});
    final areaId = pre
        .getResource<MeaningIndex>()
        .byId
        .keys
        .where((id) => id.endsWith('_area'))
        .first;

    final world = _world(
      jail,
      _ScriptedEditor([
        ToolCall(
          name: const ToolName('repo_etl'),
          arguments: {'action': 'scan'},
        ),
        ToolCall(
          name: const ToolName('edit_symbol'),
          arguments: {
            'action': 'replace_member_body',
            'symbolId': areaId,
            'opChain': [
              {'label': 'load_arg', 'a': 'w'},
              {'label': 'load_arg', 'a': 'h'},
              {'label': 'mul'},
              {'label': 'return'},
            ],
          },
        ),
      ]),
    );
    _registerSurface(world, jail);
    await _runTask(world, 'Fix area.');

    // The move landed (area is correct now) but product is STILL red —
    // the oracles never graded the move green, so NOTHING is captured.
    final geometry = File('${jail.path}/lib/geometry.dart').readAsStringSync();
    expect(geometry, contains('return (w * h);'));
    expect(
      packFile(jail).existsSync(),
      isFalse,
      reason: 'a kept-but-unproven resolution must not enter the pack',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// Registers the surface without acting (pre-scan accommodation).
class _Noop implements GenerationHandler {
  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final r = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: const {'text': 'idle'},
      rawOutput: 'idle',
      toolCalls: const [],
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(r);
    return r;
  }
}

/// Emits the scripted steps in order, then goes quiet (the goal loop
/// grades the workspace convention).
class _ScriptedEditor implements GenerationHandler {
  _ScriptedEditor(this.steps);
  final List<ToolCall> steps;
  var emitted = false;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final calls = emitted ? const <ToolCall>[] : steps;
    emitted = true;
    final r = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': calls.isEmpty ? 'done' : 'editing'},
      rawOutput: calls.isEmpty ? 'done' : 'editing',
      toolCalls: calls,
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(r);
    return r;
  }
}
