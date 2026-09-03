// ignore_for_file: lines_longer_than_80_chars

/// R7b GATE (ADR 0023 §2): a scripted actor performs a multi-file code
/// change through `edit_symbol` moves ONLY — rename one symbol across the
/// refs frontier AND insert one member in another file — on a workspace
/// scanned via `repo_etl`, with the run-graded goal loop wired exactly like
/// the workspace-meaning runner. LLM-free.
///
/// Assertions:
/// - `dart analyze` exit 0 + workspace convention (`dart test`) green after
///   the moves (the mechanical verify tier);
/// - ZERO `read` and ZERO `write` tool calls in the registry AND in the
///   thread beats;
/// - every intermediate invalid move bounced as structured data (exact
///   repair move, B2 dialect);
/// - auto-revert: a deliberately-failing scripted move (wrong body under a
///   COVERED member) restores bytes and reports `reverted: true`;
/// - the three fences gate-asserted with dedicated variants:
///   (a) a state-op chain bounces (expressiveness),
///   (b) a replacement of an uncovered legacy member bounces (coverage),
///   (c) a signature-mismatched chain bounces BEFORE generation
///       (integration).
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/benchmark_api.dart'
    show defaultGoalFlow, openFreshDecision;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'package:xsoulspace_agentic_dart_meaning/xsoulspace_agentic_dart_meaning.dart';

// ---------------------------------------------------------------------------
// Fixture jail — a multi-file Dart package whose FAILING suite IS the spec:
// `surfaceArea` and `Box.doubled` do not exist yet; the scripted actor must
// produce them via edit_symbol moves only (rename area + insert doubled).
// ---------------------------------------------------------------------------

Future<Directory> _jail() async {
  final dir = await Directory.systemTemp.createTemp('span_edit_jail_');
  File('${dir.path}/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
name: span_jail
environment:
  sdk: ^3.0.0
dev_dependencies:
  test: any
''');
  File('${dir.path}/lib/geometry.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
int area(int w, int h) {
  return w * h;
}

String label(String name) {
  return 'shape: \$name';
}
''');
  File('${dir.path}/lib/report.dart').writeAsStringSync('''
import 'geometry.dart';

String report() {
  return 'area=\${area(2, 3)}';
}
''');
  File('${dir.path}/lib/boxes.dart').writeAsStringSync('''
class Box {
  int volume(int w, int h, int d) {
    return w * h * d;
  }
}
''');
  File('${dir.path}/test/geometry_test.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
import 'package:test/test.dart';
import 'package:span_jail/geometry.dart';
import 'package:span_jail/boxes.dart';

void main() {
  test('surfaceArea', () {
    expect(surfaceArea(2, 3), 6);
  });
  test('doubled', () {
    expect(Box().doubled(21), 42);
  });
}
''');
  return dir;
}

Future<Directory> _coveredJail() async {
  // Variant fixture: the suite PASSES for `area` (covered) and says nothing
  // about `label` (uncovered) — the fence-b and auto-revert fixtures.
  final dir = await _jail();
  File('${dir.path}/test/geometry_test.dart').writeAsStringSync('''
import 'package:test/test.dart';
import 'package:span_jail/geometry.dart';

void main() {
  test('area', () {
    expect(area(2, 3), 6);
  });
}
''');
  return dir;
}

/// Host pre-pass: resolve the package before the loop runs (mechanical,
/// zero model tokens).
Future<void> _pubGet(Directory jail) async {
  await Process.run('dart', ['pub', 'get'], workingDirectory: jail.path);
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

/// Local idle assertion (same contract as the harness package's
/// expectIdle): no pending decisions, grants, awaits, or stranded events.
void _expectIdle(World world) {
  final problems = <String>[];
  if (world.query2<Actor, OpenDecision>().toList().isNotEmpty) {
    problems.add('OpenDecision still pending');
  }
  if (world.query2<Actor, Agency>().toList().isNotEmpty) {
    problems.add('Agency still granted');
  }
  if (world.query2<Actor, AwaitingResponse>().toList().isNotEmpty) {
    problems.add('AwaitingResponse still set');
  }
  expect(problems, isEmpty, reason: 'harness not idle: ${problems.join("; ")}');
}

class _Meter implements GenerationHandler {
  _Meter(this.inner);
  final GenerationHandler inner;
  int decisions = 0;
  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final r = await inner.generate(world, request);
    decisions++;
    return r;
  }
}

/// The scripted editor: scan → (invalid rename attempt → structured
/// bounce) → insert member → rename — with ONE deliberate pause after the
/// scan so the DRIVER-graded goal loop (the workspace_meaning_runner
/// pattern) must re-open a decision and consume AttemptCount monotonically.
/// Every move is exactly what a small model emits (ids + op rows, no code).
class _ScriptedEditor implements GenerationHandler {
  _ScriptedEditor(this.areaId, this.labelId, this.boxId);
  var step = 0;
  var paused = false;
  final String areaId;
  final String labelId;
  final String boxId;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    step++;
    if (step == 2 && !paused) {
      // Pause once: close the chain after the scan. The driver's grade
      // fails (surfaceArea undefined) and it must re-open a decision —
      // AttemptCount 1, monotonic, never a reset.
      paused = true;
      return _respond(world, request, 'pausing after scan', const []);
    }
    final calls = switch (step) {
      1 => [
          ToolCall(
            name: const ToolName('repo_etl'),
            arguments: {'action': 'scan'},
          ),
        ],
      2 => [
          // The intermediate INVALID move: illegal identifier — must bounce
          // as structured data.
          ToolCall(
            name: const ToolName('edit_symbol'),
            arguments: {
              'action': 'apply_executable',
              'executableId': 'rename_symbol',
              'symbolId': areaId,
              'executableParams': {'newName': '9surface-area'},
            },
          ),
        ],
      3 => [
          ToolCall(
            name: const ToolName('edit_symbol'),
            arguments: {
              'action': 'apply_executable',
              'executableId': 'rename_symbol',
              'symbolId': areaId,
              'executableParams': {'newName': 'surfaceArea'},
            },
          ),
        ],
      4 => [
          ToolCall(
            name: const ToolName('edit_symbol'),
            arguments: {
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
            },
          ),
        ],
      _ => const <ToolCall>[],
    };
    return _respond(world, request, 'edit step $step', calls);
  }

  ActorGenerateResponse _respond(
    World world,
    ActorGenerateRequest request,
    String text,
    List<ToolCall> calls,
  ) {
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': text},
      rawOutput: text,
      toolCalls: calls,
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

void main() {
  test(
    'R7b MAIN GATE: scripted actor renames a symbol across files and '
    'inserts a member via edit_symbol only — analyze + test green, zero '
    'read/write moves, invalid move bounced as data, budgets monotonic',
    () async {
      final jail = await _jail();
      addTearDown(() => jail.delete(recursive: true).catchError((_) => jail));
      await _pubGet(jail);

      // Pre-scan (host-side) only to RESOLVE ids for the script — the same
      // accommodation the R7a gate makes for its zoom target.
      final pre = _world(jail, _Meter(_ScriptedEditor('', '', '')));
      final preScan = repoEtlTool(pre, jail);
      await preScan.execute({'action': 'scan'});
      final index = pre.getResource<MeaningIndex>();
      final areaId = index.byId.keys
          .where((id) => id.endsWith('_area'))
          .first;
      final boxId = index.byId.keys.where((id) => id.endsWith('_Box')).first;

      final world = _world(jail, _Meter(_ScriptedEditor(areaId, '', boxId)));

      // The R7 actor surface: NO read, NO write, NO patch. edit_symbol is
      // the only ACT verb.
      final registry = ToolRegistry();
      registry.register(repoEtlTool(world, jail));
      registry.register(meaningZoomTool(world));
      registry.register(meaningImpactTool(world));
      registry.register(editSymbolTool(world, jail));
      world.getResource<ToolRegistryResource>().register('default', registry);

      // The goal loop, wired exactly like the workspace-meaning runner:
      // the DRIVER grades the workspace convention after the loop idles and
      // re-opens decisions (openFreshDecision) while it fails, consuming
      // the monotonic AttemptCount against maxGoalAttempts (3).
      const taskPrompt =
          'Make the failing suite pass: surfaceArea must exist (rename '
          'area), Box must gain doubled. Work only through repo_etl, '
          'meaning_zoom, meaning_impact and edit_symbol — never file '
          'reads or writes.';
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

      // Driver-graded goal loop (the workspace_meaning_runner pattern).
      var attempt = 0;
      const maxGoalAttempts = 3;
      Future<({bool passed, String detail})> grade() async {
        final run = await Process.run(
          'dart',
          ['test'],
          workingDirectory: jail.path,
        );
        return (
          passed: run.exitCode == 0,
          detail: 'dart test exit=${run.exitCode}\n'
              '${run.stdout}${run.stderr}',
        );
      }

      var gate = await grade();
      while (!gate.passed && attempt < maxGoalAttempts) {
        attempt++;
        world.getEntity(actor).$1.insert(AttemptCount(attempt));
        world.flush();
        openFreshDecision(
          world,
          actor,
          prompt: 'Your previous attempt did not satisfy verification '
              '(attempt $attempt/$maxGoalAttempts).\nFailing:\n'
              '${gate.detail}\n\nOriginal task:\n$taskPrompt',
        );
        await HarnessLoop(world: world).runUntilIdle();
        gate = await grade();
      }
      expect(gate.passed, isTrue, reason: gate.detail);
      // The pause cost exactly one monotonic attempt (never a reset).
      expect(
        world.getEntity(actor).$1.get<AttemptCount>()?.value,
        greaterThanOrEqualTo(1),
      );

      _expectIdle(world);

      // The moves landed: multi-file rename + insert, verified by the
      // mechanical tier (the in-loop verifier already graded dart test;
      // assert the bytes directly).
      final geometry = File('${jail.path}/lib/geometry.dart').readAsStringSync();
      final report = File('${jail.path}/lib/report.dart').readAsStringSync();
      final boxes = File('${jail.path}/lib/boxes.dart').readAsStringSync();
      expect(geometry, contains('int surfaceArea(int w, int h)'));
      expect(geometry, isNot(contains('int area(')));
      expect(report, contains('surfaceArea(2, 3)'));
      expect(
        boxes,
        stringContainsInOrder([
          'int doubled(int f) {',
          'return (f * 2);',
        ]),
      );
      final analyze = await Process.run(
        'dart',
        ['analyze'],
        workingDirectory: jail.path,
      );
      expect(analyze.exitCode, 0, reason: '${analyze.stdout}${analyze.stderr}');
      final testRun = await Process.run(
        'dart',
        ['test'],
        workingDirectory: jail.path,
      );
      expect(testRun.exitCode, 0, reason: '${testRun.stdout}${testRun.stderr}');

      // ZERO read/write in the registry…
      final tools = world
          .getResource<ToolRegistryResource>()
          .get('default')!
          .tools
          .keys
          .map((t) => t.value)
          .toSet();
      expect(tools, isNot(contains('read')));
      expect(tools, isNot(contains('write')));
      expect(
        tools,
        containsAll(['repo_etl', 'meaning_zoom', 'meaning_impact',
            'edit_symbol']),
      );
      // …AND in the thread beats (the actor could not have cheated even by
      // emitting the moves blind).
      final beats = world
          .getResource<FacetIndex>()
          .beatsOfThread(thread)
          .toList();
      expect(beats, isNotEmpty);
      final beatTools = <String>[];
      for (final b in beats) {
        final call = world.getEntity(b).$1.get<BeatToolCall>();
        if (call != null) beatTools.add(call.name);
      }
      expect(beatTools, everyElement(isNot('read')));
      expect(beatTools, everyElement(isNot('write')));
      expect(beatTools.where((t) => t == 'edit_symbol').length, greaterThanOrEqualTo(2));

      // The invalid intermediate move bounced as structured data:
      // its beat result carries the bounce + the exact repair move.
      final bounceBeats = <String>[];
      for (final b in beats) {
        final we = world.getEntity(b).$1;
        final result = we.get<ToolResultContent>();
        if (result != null && '${result.output}'.contains('bounce')) {
          bounceBeats.add('${result.output}');
        }
      }
      expect(bounceBeats, isNotEmpty,
          reason: 'the invalid intermediate move must leave a bounce beat');
      expect(
        bounceBeats.join(' '),
        contains('newName'),
        reason: 'the invalid rename must bounce with the exact repair move',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  test(
    'R7b fence (a) expressiveness: a state-op chain bounces as named data '
    '— never a silent downgrade',
    () async {
      final jail = await _coveredJail();
      addTearDown(() => jail.delete(recursive: true).catchError((_) => jail));
      await _pubGet(jail);
      final world = _world(jail, _Meter(_Noop()));
      registryFor(world, jail);
      final scan = repoEtlTool(world, jail);
      await scan.execute({'action': 'scan'});
      final index = world.getResource<MeaningIndex>();
      final areaId = index.byId.keys.where((id) => id.endsWith('_area')).first;

      final out = await runTool(world, 'edit_symbol', {
        'action': 'replace_member_body',
        'symbolId': areaId,
        'opChain': [
          {'label': 'load_state', 'a': 'total'},
          {'label': 'return'},
        ],
      });
      expect(out['ok'], false);
      expect(out['fence'], 'expressiveness');
      expect(
        '${out['error']}', contains('load_state'),
      );
      // Bytes untouched.
      expect(
        File('${jail.path}/lib/geometry.dart').readAsStringSync(),
        contains('int area('),
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'R7b fence (b) oracle coverage: replacing an UNCOVERED legacy member '
    'bounces — add coverage first',
    () async {
      final jail = await _coveredJail();
      addTearDown(() => jail.delete(recursive: true).catchError((_) => jail));
      await _pubGet(jail);
      final world = _world(jail, _Meter(_Noop()));
      registryFor(world, jail);
      await repoEtlTool(world, jail).execute({'action': 'scan'});
      final index = world.getResource<MeaningIndex>();
      final labelId = index.byId.keys.where((id) => id.endsWith('_label')).first;

      // A perfectly valid pure chain — it STILL bounces: the suite derives
      // no expectations for `label`, so replacing it would destroy
      // untested behavior with nothing in the pipeline noticing.
      final out = await runTool(world, 'edit_symbol', {
        'action': 'replace_member_body',
        'symbolId': labelId,
        'opChain': [
          {'label': 'load_arg', 'a': 'name'},
          {'label': 'starts_with', 'b': 'shape'},
          {'label': 'return'},
        ],
      });
      expect(out['ok'], false);
      expect(out['fence'], 'coverage');
      expect('${out['error']}', contains('coverage'));
      expect(
        File('${jail.path}/lib/geometry.dart').readAsStringSync(),
        contains("'shape: "),
        reason: 'uncovered member must be byte-identical after the bounce',
      );
      // And the COVERED member passes the same fence by construction
      // (sanity: area is covered in this fixture).
      final mat = SpanEditMaterializer(world: world, workspace: jail);
      expect(mat.coverageSet(), contains('area'));
      expect(mat.coverageSet(), isNot(contains('label')));
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'R7b fence (c) integration: a signature-mismatched chain bounces '
    'BEFORE generation',
    () async {
      final jail = await _coveredJail();
      addTearDown(() => jail.delete(recursive: true).catchError((_) => jail));
      await _pubGet(jail);
      final world = _world(jail, _Meter(_Noop()));
      registryFor(world, jail);
      await repoEtlTool(world, jail).execute({'action': 'scan'});
      final index = world.getResource<MeaningIndex>();
      final areaId = index.byId.keys.where((id) => id.endsWith('_area')).first;

      final out = await runTool(world, 'edit_symbol', {
        'action': 'replace_member_body',
        'symbolId': areaId,
        'opChain': [
          {'label': 'load_arg', 'a': 'z'},
          {'label': 'return'},
        ],
      });
      expect(out['ok'], false);
      expect(out['fence'], 'integration');
      expect('${out['error']}', contains('z'));
      // No generation happened: the bytes are untouched and no body was
      // compiled in.
      expect(
        File('${jail.path}/lib/geometry.dart').readAsStringSync(),
        contains('return w * h;'),
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'R7b auto-revert: a deliberately-failing scripted move (wrong body '
    'under a COVERED member) is applied, fails dart test, and every byte '
    'is restored',
    () async {
      final jail = await _coveredJail();
      addTearDown(() => jail.delete(recursive: true).catchError((_) => jail));
      await _pubGet(jail);
      final world = _world(jail, _Meter(_Noop()));
      registryFor(world, jail);
      await repoEtlTool(world, jail).execute({'action': 'scan'});
      final index = world.getResource<MeaningIndex>();
      final areaId = index.byId.keys.where((id) => id.endsWith('_area')).first;

      final before = File(
        '${jail.path}/lib/geometry.dart',
      ).readAsStringSync();
      // Compiles cleanly, analyze-clean — but WRONG (2+3 != 6): the
      // workspace convention must catch it and the host must revert.
      final out = await runTool(world, 'edit_symbol', {
        'action': 'replace_member_body',
        'symbolId': areaId,
        'opChain': [
          {'label': 'load_arg', 'a': 'w'},
          {'label': 'load_arg', 'a': 'h'},
          {'label': 'add'},
          {'label': 'return'},
        ],
      });
      expect(out['ok'], false, reason: '$out');
      expect(out['reverted'], true, reason: '$out');
      expect(out['failure_class'], 'workspace_check_failed');
      expect(out['check_exit'], isNot(0));
      final after = File('${jail.path}/lib/geometry.dart').readAsStringSync();
      expect(after, before, reason: 'auto-revert must restore exact bytes');
      // The tree does NOT track the reverted body as changed state — the
      // next scan re-derives truth (projection target, never snapshot).
      final analyze = await Process.run(
        'dart',
        ['analyze'],
        workingDirectory: jail.path,
      );
      expect(analyze.exitCode, 0);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'R7b repo-scale plan: the lexical rename executable expands over the '
    'refs frontier of the REAL harness package (plan-only, zero writes)',
    () async {
      var dir = Directory.current;
      for (var i = 0; i < 6; i++) {
        final pubspec = File('${dir.path}/pubspec.yaml');
        if (pubspec.existsSync() &&
            pubspec.readAsStringSync().contains('workspace:')) {
          break;
        }
        dir = dir.parent;
      }
      final workspace = Directory('${dir.path}/pkgs/xsoulspace_agentic_harness');
      final world = _world(workspace, _Meter(_Noop()));
      await repoEtlTool(world, workspace).execute({'action': 'scan'});
      final index = world.getResource<MeaningIndex>();
      final loopId = index.byId.keys
          .where((id) => id.endsWith('_HarnessLoop'))
          .first;
      final mat = SpanEditMaterializer(world: world, workspace: workspace);
      final plan = mat.plan(
        action: 'apply_executable',
        executableId: 'rename_symbol',
        symbolId: loopId,
        executableParams: {'newName': 'HarnessLoopRenamed'},
      );
      expect(plan.isAtomic, true, reason: plan.description);
      final files = plan.patches.map((p) => p.file).toSet();
      expect(files.length, greaterThan(1),
          reason: 'HarnessLoop is referenced across files: ${plan.description}');
      // Plan-only: zero bytes touched.
      expect(
        File(
          '${workspace.path}/lib/src/harness_loop.dart',
        ).readAsStringSync(),
        contains('class HarnessLoop'),
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

class _Noop implements GenerationHandler {
  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
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

/// Executes a registered tool and decodes its JSON result (the registry
/// transport is JSON strings — the actor reads the same shape).
Future<Map<String, dynamic>> runTool(
  World world,
  String name,
  Map<String, dynamic> args,
) async {
  final raw = await world
      .getResource<ToolRegistryResource>()
      .get('default')!
      .execute(ToolName(name), args);
  return (jsonDecode(raw ?? '{}') as Map).cast<String, dynamic>();
}

void registryFor(World world, Directory jail) {
  final registry = ToolRegistry();
  registry.register(repoEtlTool(world, jail));
  registry.register(editSymbolTool(world, jail));
  world.getResource<ToolRegistryResource>().register('default', registry);
}
