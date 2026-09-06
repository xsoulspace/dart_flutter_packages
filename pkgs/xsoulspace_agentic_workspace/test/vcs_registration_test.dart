// ignore_for_file: lines_longer_than_80_chars

/// VCS REGISTRATION SEAM GATE (PLAN §NOW P3): `vcs.repo` nodes enter the
/// LIVE daemon world — the NORMAL `repoEtlTool` scan/refresh/tick pass
/// (the same zero-model-token pass that reconciles fs/dart/md) projects
/// the VCS state via `projectVcsMeaning` + `GitVcsAdapter`. No test
/// bootstrap: any world that builds the tool carries VCS nodes. Gates:
///
/// - a normal scan over a temp git repo projects vcs.repo / branch /
///   head / change nodes (findable through the index API);
/// - a second commit + the INCREMENTAL tick updates head and drops the
///   committed change node; the persistent-tree refresh path updates too;
/// - a non-repo workspace scans CLEAN with zero vcs nodes (named
///   `not_a_repo`, never a crash — the failure-honest wiring law).
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'package:xsoulspace_agentic_workspace/xsoulspace_agentic_workspace.dart';

Map<String, dynamic> _decoded(Object? raw) => raw is String
    ? jsonDecode(raw) as Map<String, dynamic>
    : raw! as Map<String, dynamic>;

World _world() {
  final world = World()..addPlugin(AgentPlugin());
  world.upsertResource(ToolRegistryResource());
  return world;
}

/// A deterministic fixture repo (git init + one commit + one untracked
/// file). The test DRIVES git (fixture setup only) — the ADAPTER stays
/// read-only by law.
class _FixtureRepo {
  late Directory dir;

  Future<void> _git(List<String> args) async {
    final r = await Process.run('git', args, workingDirectory: dir.path);
    if (r.exitCode != 0) fail('git $args failed: ${r.stderr}');
  }

  Future<void> seed() async {
    dir = await Directory.systemTemp.createTemp('vcs_registration_test_');
    await _git(['init', '-q', '-b', 'main']);
    await _git(['config', 'user.email', 'test@example.dev']);
    await _git(['config', 'user.name', 'test']);
    File('${dir.path}/tracked.txt').writeAsStringSync('seed\n');
    await _git(['add', '.']);
    await _git(['commit', '-q', '-m', 'seed commit']);
    File('${dir.path}/dirty.txt').writeAsStringSync('uncommitted\n');
  }

  /// Second state: a second commit (head moves), dirty.txt committed-away
  /// (its change node must drop), a new untracked file.
  Future<void> evolve() async {
    File('${dir.path}/tracked.txt').writeAsStringSync('evolved\n');
    await _git(['add', 'tracked.txt']);
    await _git(['commit', '-q', '-m', 'second commit']);
    File('${dir.path}/dirty.txt').deleteSync();
    File('${dir.path}/new.txt').writeAsStringSync('fresh\n');
  }

  void dispose() {
    try {
      dir.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  }
}

Map<String, dynamic> _propsOf(World world, String id) {
  final index = world.getResource<MeaningIndex>();
  return meaningComponentOf<MeaningProps>(world, index.byId[id]!)?.props ??
      const {};
}

void main() {
  late _FixtureRepo repo;
  late World world;

  setUp(() async {
    repo = _FixtureRepo();
    await repo.seed();
    world = _world();
  });
  tearDown(() => repo.dispose());

  test('a NORMAL scan projects vcs.repo/branch/head/change into the live '
      'world — no bootstrap', () async {
    final etl = repoEtlTool(world, repo.dir);
    final scan = _decoded(await etl.execute({'action': 'scan'}));
    expect(scan['ok'], true, reason: '$scan');
    final vcs = scan['vcs'] as Map;
    expect(vcs['status'], 'projected');
    expect(vcs['nodes'], greaterThanOrEqualTo(4));

    // Findable through the index API (the ray matches the same nodes).
    final index = world.getResource<MeaningIndex>();
    expect(index.byId['vcs.repo'], isNotNull);
    expect(index.byId['vcs.branch.main'], isNotNull,
        reason: 'the current branch is a node');
    expect(_propsOf(world, 'vcs.branch.main')['is_current'], true);
    expect(_propsOf(world, 'vcs.repo')['current_branch'], 'main');
    expect(_propsOf(world, 'vcs.repo')['backend'], 'git');
    expect(_propsOf(world, 'vcs.head')['subject'], 'seed commit');
    expect(index.byId['vcs.change.dirty.txt'], isNotNull,
        reason: 'the untracked file is a change node');
    expect(_propsOf(world, 'vcs.change.dirty.txt')['status'], '??');
  });

  test('a second commit + the INCREMENTAL tick updates head and drops the '
      'committed change node', () async {
    final etl = repoEtlTool(world, repo.dir);
    await etl.execute({'action': 'scan'});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await repo.evolve();

    // SAME tool instance → the tree-driven tick path (cutoff-gated).
    final tick = _decoded(await etl.execute({'action': 'refresh'}));
    expect(tick['ok'], true, reason: '$tick');
    expect((tick['vcs'] as Map)['status'], 'projected');
    expect(_propsOf(world, 'vcs.head')['subject'], 'second commit',
        reason: 'head follows the new commit');
    expect(_propsOf(world, 'vcs.repo')['recent_commits'].toString(),
        contains('second commit'));
    expect(world.getResource<MeaningIndex>().byId['vcs.change.dirty.txt'],
        isNull,
        reason: 'a committed-away change node drops (the tree stays '
            're-derivable from the VCS state alone)');
    expect(world.getResource<MeaningIndex>().byId['vcs.change.new.txt'],
        isNotNull);
  });

  test('the persistent-tree refresh path re-projects the VCS state too',
      () async {
    await _decoded(
        await repoEtlTool(world, repo.dir).execute({'action': 'scan'}));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await repo.evolve();
    // A FRESH tool instance over the carried tree → the persistent path.
    final raw =
        await repoEtlTool(world, repo.dir).execute({'action': 'refresh'});
    final refresh = _decoded(raw);
    expect(refresh['ok'], true, reason: '$refresh');
    expect((refresh['vcs'] as Map)['status'], 'projected');
    expect(_propsOf(world, 'vcs.head')['subject'], 'second commit');
  });

  test('a non-repo workspace scans CLEAN — zero vcs nodes, named status',
      () async {
    final plain = await Directory.systemTemp.createTemp('vcs_plain_test_');
    addTearDown(() {
      try {
        plain.deleteSync(recursive: true);
      } on Object {
        // best effort
      }
    });
    File('${plain.path}/note.txt').writeAsStringSync('no git here\n');
    final plainWorld = _world();
    final scan = _decoded(
        await repoEtlTool(plainWorld, plain).execute({'action': 'scan'}));
    expect(scan['ok'], true, reason: '$scan');
    expect((scan['vcs'] as Map)['status'], 'not_a_repo');
    expect(
      plainWorld
          .getResource<MeaningIndex>()
          .byId.keys
          .where((id) => id.startsWith('vcs.'))
          .length,
      0,
      reason: 'the not-a-repo degradation is a named EMPTY projection',
    );
  });
}
