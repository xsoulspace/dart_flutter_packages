// ignore_for_file: lines_longer_than_80_chars

/// P1 GATE — per-package verify derivation (LLM-free, recorded runner).
///
/// The measured pain: the delegated `harness_verify` graded the ROOT
/// convention (`flutter test` over the whole monorepo — 156.9 s wall vs
/// the 90 s dart-turn budget) even when the session touched files in ONE
/// package. The fix derives the ACTIVE packages from the session's own
/// touched-file beats and grades THOSE packages in their own directories:
///
/// 1. a scripted session touches ONE file in a fixture package → the
///    verify runs THAT package's convention in that dir (command + cwd
///    asserted via a recorded runner) and NOT the root;
/// 2. a multi-package touch (2 packages) runs both, bounded;
/// 3. 3+ packages or no touched files → the ROOT fallback (never a
///    skipped gate);
/// 4. `verify_wall_ms` is present in the `goal_verify` verify beat.
///
/// The runner is RECORDED (no real subprocess): the gate is about the
/// DERIVATION — which command runs, in which directory — not about dart.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/benchmark_api.dart'
    show
        RunGoalCommand,
        VerifyTierPlanner,
        dartVerifyConvention,
        derivePerPackageVerify,
        runGoalVerifier,
        wireRunGradedGoal;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

/// One recorded run execution (the derivation's observable output).
class RecordedRun {
  RecordedRun({required this.command, required this.cwd});
  final List<String> command;
  final String cwd;
}

void main() {
  late Directory root;
  late World world;
  late Entity actor;
  late Entity thread;
  late List<RecordedRun> recorded;

  /// Builds a fixture MONOREPO: a workspace-root pubspec + named
  /// sub-packages, each a plain dart package with tests (convention:
  /// `dart test`).
  void makePackage(String name) {
    File('${root.path}/pkgs/$name/pubspec.yaml')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('name: $name\nenvironment:\n  sdk: ^3.0.0\n');
    File('${root.path}/pkgs/$name/lib/$name.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('bool flag_$name() => true;\n');
    File('${root.path}/pkgs/$name/test/${name}_test.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        "import 'package:test/test.dart';\n"
        "import 'package:$name/$name.dart';\n"
        "void main() { test('flag', () { expect(flag_$name(), isTrue); }); }\n",
      );
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('per_package_verify_');
    File('${root.path}/pubspec.yaml')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        'name: fixture_workspace\nenvironment:\n  sdk: ^3.0.0\nworkspace:\n  packages:\n',
      );
    for (final name in ['alpha', 'beta', 'gamma']) {
      makePackage(name);
    }
    world = World()..addPlugin(AgentPlugin());
    world
      ..upsertResource(ToolRegistryResource())
      // The planner's legacy full-fallback path reads the meaning tree;
      // these gates exercise the derivation, so an EMPTY index is honest.
      ..upsertResource(MeaningIndex());
    recorded = <RecordedRun>[];

    final scene = world.spawnComponents([Scene(), SceneFrame()]);
    actor = world.spawnComponents([
      Actor(agentId: AgentId.create()),
      ActorModel(modelId: ModelId.create()),
      ActorThreads(threads: []),
      ActorTools(registryName: 'default'),
      PresentInScene(sceneEntity: scene),
      Goal(text: 'per-package verify fixture'),
    ]);
    thread = spawnThread(world, actor, scene);
    world.upsertComponent(actor, ActorThreads(threads: [thread]));
    world.flush();
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  });

  /// Fabricates one edit_symbol beat with [files] touched (the shape the
  /// real span editor leaves on the thread).
  void addEditBeat(List<String> files) {
    final beat = world.reserveEmptyEntity().entity;
    final we = world.getEntity(beat).$1;
    we
      ..insert(BeatToolCall('edit_symbol', const {}))
      ..insert(
        ToolResultContent(
          name: 'edit_symbol',
          output: {'ok': true, 'files': files},
        ),
      )
      ..insert(Speaker(actor));
    indexBeat(world, beat, const <String>[], thread: thread);
  }

  /// Wires the run-graded verifier with the ROOT convention (what the
  /// delegated verify used to grade over the whole monorepo) and a
  /// RECORDED run tool, then grades once and returns the executions.
  Future<List<RecordedRun>> drive() async {
    wireRunGradedGoal(
      world,
      command: const ['flutter', 'test'], // the root convention (fallback)
      cwd: root.path,
      planProvider: const VerifyTierPlanner(),
    );
    final registry = ToolRegistry();
    registry.register(
      ToolDef.encode(
        name: const ToolName('run'),
        description: 'recorded runner (LLM-free gate)',
        execute: (args) async {
          final map = args is Map ? args : const <String, Object?>{};
          recorded.add(
            RecordedRun(
              command: [
                for (final c in (map['command'] as List).cast<String>()) c,
              ],
              cwd: '${map['cwd']}',
            ),
          );
          return {'ok': true, 'exit_code': 0, 'stdout': '', 'stderr': ''};
        },
      ),
    );
    world.getResource<ToolRegistryResource>().register('default', registry);
    world.upsertComponent(actor, ToolResultPendingMarker());
    await runGoalVerifier(world);
    return recorded;
  }

  test(
    'ONE touched file in a fixture package → THAT package\'s convention in '
    'its directory, never the root',
    () async {
      addEditBeat(['pkgs/alpha/lib/alpha.dart']);
      final runs = await drive();
      expect(runs, hasLength(1), reason: 'one active package → one step');
      expect(runs.single.command, ['dart', 'test']);
      expect(
        runs.single.cwd,
        'pkgs/alpha',
        reason: 'the step runs in the PACKAGE dir (root-relative), '
            'not the workspace root',
      );
    },
  );

  test('multi-package touch (2 packages) runs BOTH, bounded', () async {
    addEditBeat(['pkgs/alpha/lib/alpha.dart', 'pkgs/beta/lib/beta.dart']);
    final runs = await drive();
    expect(runs, hasLength(2));
    expect(
      runs.map((r) => r.cwd).toSet(),
      {'pkgs/alpha', 'pkgs/beta'},
      reason: 'each touched package grades in its own directory',
    );
    for (final r in runs) {
      expect(r.command, ['dart', 'test']);
    }
  });

  test('3+ packages → ROOT fallback (the root convention runs)', () async {
    addEditBeat([
      'pkgs/alpha/lib/alpha.dart',
      'pkgs/beta/lib/beta.dart',
      'pkgs/gamma/lib/gamma.dart',
    ]);
    final runs = await drive();
    expect(runs, hasLength(1));
    expect(runs.single.command, ['flutter', 'test']);
    expect(runs.single.cwd, root.path, reason: 'the honest root fallback');
  });

  test('no touched files → derivation declines (root fallback)', () {
    // The read-only-session shape: the derivation must return null so the
    // caller runs the ROOT convention — never a silently skipped gate.
    final steps = derivePerPackageVerify(
      workspaceRoot: root.path,
      touchedFiles: const [],
      convention: dartVerifyConvention,
    );
    expect(steps, isNull);
  });

  test('root-level touched files → derivation declines (root fallback)', () {
    // A file whose nearest pubspec IS the workspace root maps to the root
    // pseudo-package — a partial map would silently under-verify.
    final steps = derivePerPackageVerify(
      workspaceRoot: root.path,
      touchedFiles: const ['README.md', 'pkgs/alpha/lib/alpha.dart'],
      convention: dartVerifyConvention,
    );
    expect(steps, isNull);
    final rootOnly = derivePerPackageVerify(
      workspaceRoot: root.path,
      touchedFiles: const ['pubspec.yaml'],
      convention: dartVerifyConvention,
    );
    expect(rootOnly, isNull);
  });

  test('package without a resolvable convention → root fallback', () {
    // pkgs/gamma has tests, but a package WITHOUT tests resolves to null
    // (honest failure) — the derivation must fall back to the root.
    Directory('${root.path}/pkgs/beta/test').deleteSync(recursive: true);
    final steps = derivePerPackageVerify(
      workspaceRoot: root.path,
      touchedFiles: const ['pkgs/alpha/lib/alpha.dart', 'pkgs/beta/b.dart'],
      convention: dartVerifyConvention,
    );
    expect(steps, isNull);
  });

  test('verify_wall_ms is stamped on the goal_verify beat', () async {
    addEditBeat(['pkgs/alpha/lib/alpha.dart']);
    await drive();
    final beatOutputs = <Map<String, Object?>>[];
    for (final beat
        in world.getResource<FacetIndex>().beatsOfThread(thread).toList()) {
      final result = world.getEntity(beat).$1.get<ToolResultContent>();
      if (result != null && result.name == 'goal_verify') {
        final output = result.output;
        if (output is Map) {
          beatOutputs.add({
            for (final e in output.entries) '${e.key}': e.value,
          });
        }
      }
    }
    expect(beatOutputs, hasLength(1), reason: 'the grade stamped one beat');
    final wall = beatOutputs.single['verify_wall_ms'];
    expect(wall, isA<int>(), reason: 'the verify wall is graph data');
    expect(wall as int, greaterThanOrEqualTo(0));
    // The per-package tier is visible in the beat, too.
    expect(beatOutputs.single['command'], ['dart', 'test']);
  });

  test('derivation data: steps carry the resolved package convention', () {
    final steps = derivePerPackageVerify(
      workspaceRoot: root.path,
      touchedFiles: const [
        'pkgs/alpha/lib/alpha.dart',
        'pkgs/beta/test/beta_test.dart',
      ],
      convention: dartVerifyConvention,
    );
    expect(steps, isNotNull);
    expect(steps!, hasLength(2));
    expect(
      {for (final s in steps) s.cwd},
      {'pkgs/alpha', 'pkgs/beta'},
    );
    expect(steps.every((s) => s.command.join(' ') == 'dart test'), isTrue);
    // RunGoalCommand.cwd is workspace-root-RELATIVE (jail-resolved).
    expect(
      steps.every((s) => !s.cwd!.startsWith('/') && !s.cwd!.contains(':')),
      isTrue,
    );
  });
}
