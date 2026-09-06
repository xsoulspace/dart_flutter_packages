// ignore_for_file: lines_longer_than_80_chars

/// P3 first slice — VCS-as-meaning projection gate (LLM-free).
///
/// Claim under test: VCS state (branches / HEAD / changed files) projects
/// as MeaningNode/MeaningProps/MeaningEdge DATA over a read-only VCS
/// abstraction — git one impl, jailed to {status, branch, log, rev-parse},
/// bounded output, honest named degradation (not-a-repo → named empty,
/// never a crash), idempotent re-projection (no duplicates, updated props),
/// deterministic (same repo state → same projection) — and the projected
/// nodes are findable through the EXISTING discovery ray
/// (`meaning_locate`), class-agnostic as the law requires.
library;

import 'dart:convert' show jsonDecode;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_agentic_harness/src/tools/meaning_locate_tool.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

/// A deterministic fixture repo in a system temp dir (git init + one
/// commit + one untracked file). Dates pinned via env so the projection
/// is byte-stable across runs.
class _FixtureRepo {
  late Directory dir;
  Future<void> _git(List<String> args) async {
    final r = await Process.run(
      'git',
      args,
      workingDirectory: dir.path,
      environment: {
        ...Platform.environment,
        'GIT_AUTHOR_DATE': '2026-09-06T00:00:00+00:00',
        'GIT_COMMITTER_DATE': '2026-09-06T00:00:00+00:00',
      },
    );
    if (r.exitCode != 0) fail('git $args failed: ${r.stderr}');
  }

  Future<void> seed() async {
    dir = await Directory.systemTemp.createTemp('vcs_meaning_test_');
    await _git(['init', '-q', '-b', 'main']);
    await _git(['config', 'user.email', 'test@example.dev']);
    await _git(['config', 'user.name', 'test']);
    File('${dir.path}/tracked.txt').writeAsStringSync('seed\n');
    await _git(['add', '.']);
    await _git(['commit', '-q', '-m', 'seed commit']);
    // An untracked file → one change node with porcelain status `??`.
    File('${dir.path}/dirty.txt').writeAsStringSync('uncommitted\n');
  }

  /// Second repo state: tracked.txt amended in a second commit, dirty.txt
  /// removed (its change node must drop), a new untracked file added, and
  /// tracked.txt left modified-unstaged again (porcelain status ` M`).
  Future<void> evolve() async {
    File('${dir.path}/tracked.txt').writeAsStringSync('evolved\n');
    await _git(['add', 'tracked.txt']);
    await _git(['commit', '-q', '-m', 'second commit']);
    File('${dir.path}/dirty.txt').deleteSync();
    File('${dir.path}/new.txt').writeAsStringSync('fresh\n');
    File('${dir.path}/tracked.txt').writeAsStringSync('evolved+dirty\n');
  }

  void dispose() {
    dir.deleteSync(recursive: true);
  }
}

World _world() => World()..addPlugin(AgentPlugin());

/// Typed accessor over a projected node's props — keeps the gate free of
/// dynamic calls (the repo lint treats them as errors).
Map<String, dynamic> _props(Map<String, dynamic> node) =>
    node['props'] as Map<String, dynamic>;

void main() {
  const adapter = GitVcsAdapter();
  final repo = _FixtureRepo();

  setUpAll(repo.seed);
  tearDownAll(repo.dispose);

  test('node shape: vcs root, branch, head, change — with props', () async {
    final world = _world();
    final result = await projectVcsMeaning(world, adapter, repo.dir.path);

    expect(result.status, 'projected');
    expect(result.projected, isTrue);
    expect(result.nodeIds, containsAll(['vcs.repo', 'vcs.head']));

    final view = meaningView(world);
    final byId = {for (final n in view.nodes) n['id'] as String: n};

    // Root: kind 'vcs', backend + current branch projected as props.
    final root = byId['vcs.repo']!;
    expect(root['kind'], 'vcs');
    final rootProps = _props(root);
    expect(rootProps['backend'], 'git');
    expect(rootProps['current_branch'], 'main');
    final firstCommit =
        (rootProps['recent_commits'] as List).first as Map<String, dynamic>;
    expect(firstCommit['subject'], 'seed commit');

    // Branch node: name + is_current.
    final branch = byId['vcs.branch.main']!;
    expect(branch['kind'], 'vcs_branch');
    expect(branch['label'], 'main');
    final branchProps = _props(branch);
    expect(branchProps['name'], 'main');
    expect(branchProps['is_current'], isTrue);

    // Head node: short sha, subject, author date — all present, bounded.
    final head = byId['vcs.head']!;
    expect(head['kind'], 'vcs_head');
    expect(head['label'], 'seed commit');
    final headProps = _props(head);
    expect(headProps['subject'], 'seed commit');
    final sha = headProps['sha'] as String;
    expect(sha.length, inInclusiveRange(7, 40));
    expect(headProps['author_date'], contains('2026-09-06'));

    // Change node per changed file with porcelain status.
    final change = byId['vcs.change.dirty.txt']!;
    expect(change['kind'], 'vcs_change');
    final changeProps = _props(change);
    expect(changeProps['path'], 'dirty.txt');
    expect(changeProps['status'], '??');

    // Edges hang off the root: branch / head / change relations.
    final triples = view.edges
        .map((e) => '${e['from']} --${e['relation']}--> ${e['to']}')
        .toSet();
    expect(triples, containsAll(<String>[
      'vcs.repo --branch--> vcs.branch.main',
      'vcs.repo --head--> vcs.head',
      'vcs.repo --change--> vcs.change.dirty.txt',
    ]));
  });

  test('locatable through the EXISTING discovery ray (meaning_locate)',
      () async {
    final world = _world();
    await projectVcsMeaning(world, adapter, repo.dir.path);

    // Locate is class-agnostic: it matches ANY meaning node label — a vcs
    // node is just another meaning. The branch label and the head subject
    // must surface through the same ray the model uses for symbols.
    for (final entry in [
      // 'main' exact-matches the branch label.
      ('main', 'vcs_branch'),
      // 'seed' prefix-matches the head node's label (the subject).
      ('seed', 'vcs_head'),
    ]) {
      final (query, expectedKind) = entry;
      final raw = await meaningLocateTool(world).execute({'query': query});
      final out = raw == null
          ? const <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
      expect(out['ok'], isTrue, reason: 'query: $query');
      final rows = (out['rows'] as List).cast<Map>();
      expect(rows.map((r) => r['kind']), contains(expectedKind),
          reason: 'query "$query" should surface vcs nodes through the ray');
    }
    // The head node is addressable by the id the ray yields — the same
    // handle zoom/impact would take.
    final raw = await meaningLocateTool(world).execute({'query': 'seed'});
    final out =
        raw == null ? const <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
    expect((out['rows'] as List).cast<Map>().map((r) => r['id']),
        contains('vcs.head'));
  });

  test('re-projection is idempotent: no duplicates, updated props, stale drops',
      () async {
    final world = _world();
    await projectVcsMeaning(world, adapter, repo.dir.path);
    final first = meaningView(world);
    final firstNodeCount = first.nodeCount;

    await repo.evolve();
    final result = await projectVcsMeaning(world, adapter, repo.dir.path);
    expect(result.status, 'projected');

    final second = meaningView(world);
    final byId = {for (final n in second.nodes) n['id'] as String: n};

    // No duplicates: node count grows only by the one NEW change node.
    expect(second.nodeCount, firstNodeCount + 1);
    // Stable identity: same head/branch ids, never an auto `vcs_N` id,
    // never a duplicated `vcs_head_2`.
    expect(byId.containsKey('vcs.head'), isTrue);
    expect(byId.containsKey('vcs.branch.main'), isTrue);
    expect(
      byId.keys.where((k) => RegExp(r'^vcs_\d+$').hasMatch(k)),
      isEmpty,
      reason: 'no auto-generated kind_N ids may leak into the vcs projection',
    );

    // Updated props: HEAD moved to the second commit.
    final headProps = _props(byId['vcs.head']!);
    expect(headProps['subject'], 'second commit');
    expect(byId['vcs.head']!['label'], 'second commit');

    // Stale change node dropped (dirty.txt was never committed and is
    // gone); the new change node is in; tracked.txt is modified-unstaged.
    expect(byId.containsKey('vcs.change.dirty.txt'), isFalse);
    expect(_props(byId['vcs.change.new.txt']!)['status'], '??');
    expect(_props(byId['vcs.change.tracked.txt']!)['status'], ' M');

    // The second pass over the SAME state changes nothing (true idempotence).
    final snapshot = await projectVcsMeaning(world, adapter, repo.dir.path);
    expect(snapshot.status, 'projected');
    final third = meaningView(world);
    expect(third.nodeCount, second.nodeCount);
    expect(third.edgeCount, second.edgeCount);
  });

  test('deterministic: same repo state → identical projection', () async {
    final a = _world();
    final b = _world();
    await projectVcsMeaning(a, adapter, repo.dir.path);
    await projectVcsMeaning(b, adapter, repo.dir.path);

    final va = meaningView(a);
    final vb = meaningView(b);
    final nodesA = [...va.nodes]..sort(
        (x, y) => (x['id'] as String).compareTo(y['id'] as String));
    final nodesB = [...vb.nodes]..sort(
        (x, y) => (x['id'] as String).compareTo(y['id'] as String));
    final edgesA = [...va.edges]..sort(
        (x, y) => '${x['from']}${x['relation']}${x['to']}'
            .compareTo('${y['from']}${y['relation']}${y['to']}'));
    final edgesB = [...vb.edges]..sort(
        (x, y) => '${x['from']}${x['relation']}${x['to']}'
            .compareTo('${y['from']}${y['relation']}${y['to']}'));
    expect(nodesA, nodesB);
    expect(edgesA, edgesB);
  });

  test('not-a-repo degrades to a NAMED EMPTY result, never a crash',
      () async {
    final emptyDir =
        await Directory.systemTemp.createTemp('vcs_meaning_empty_');
    addTearDown(() => emptyDir.deleteSync(recursive: true));

    final world = _world();
    final result = await projectVcsMeaning(world, adapter, emptyDir.path);

    expect(result.status, 'not_a_repo');
    expect(result.projected, isFalse);
    expect(result.nodeIds, isEmpty);
    // Nothing leaked into the tree.
    expect(meaningView(world).nodeCount, 0);
  });

  test('read-only law: the command set is exactly the jailed four', () {
    expect(gitReadOnlyCommands, <String>{'status', 'branch', 'log', 'rev-parse'});

    // Every allowed subcommand passes the jail assertion.
    for (final command in gitReadOnlyCommands) {
      expect(() => ensureReadOnlyGitCommand(command), returnsNormally);
    }
    // Write / mutating / state-changing commands are NAMED refusals —
    // writes stay with the edit tier.
    for (final command in ['commit', 'push', 'reset', 'checkout', 'add']) {
      expect(
        () => ensureReadOnlyGitCommand(command),
        throwsA(
          isA<VcsCommandRefusal>().having(
            (e) => e.toString(),
            'message',
            contains(command),
          ),
        ),
        reason: 'git $command must be a named refusal',
      );
    }
  });
}
