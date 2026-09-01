// ignore_for_file: lines_longer_than_80_chars

/// ADR 0019 — long-horizon tier CI gate: tokens/decision stay flat ACROSS
/// session boundaries (snapshot → kill → restore → continue), not just
/// within one run. Complements the Phase 2 within-run gate
/// (`long_horizon_test.dart`): the beat graph grows every session, the cut
/// must not. LLM-free (scripted handler); ends every session idle.
library;

import 'dart:io';

import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/src/agent.dart';

import 'support/agent_harness_support.dart';

const _sessions = 3;
const _beatsPerSession = 40;
const _decisionsPerSession = 6;

/// Flatness bound across session boundaries. The within-run Phase 2 gate is
/// 1.40 over 300 decisions; a restored session re-derives the facet index
/// from beats, so a modest allowance absorbs rebuild noise. Growth beyond
/// this means session state is leaking into the cut — a bug class (D7).
const _flatnessBound = 1.5;

double _avg(List<num> xs) {
  if (xs.isEmpty) return 0;
  var sum = 0.0;
  for (final x in xs) {
    sum += x.toDouble();
  }
  return sum / xs.length;
}

String _keyword(int session, int i) =>
    'topic-s$session-${i.toString().padLeft(3, '0')}';

/// One session: index [_beatsPerSession] fresh beats (growing the graph),
/// then drive [_decisionsPerSession] decisions — each ray-cast targets only
/// a keyword indexed THIS session, so older material must stay dark.
/// Returns avg tokens/decision for the session.
Future<double> _runSession(
  World world,
  Entity actor,
  Entity thread,
  int session,
) async {
  for (var i = 0; i < _beatsPerSession; i++) {
    addIndexedBeat(
      world,
      thread,
      actor,
      'status ${_keyword(session, i)} nominal',
      [_keyword(session, i)],
    );
  }

  final tokens = <num>[];
  for (var i = 0; i < _decisionsPerSession; i++) {
    final kw = _keyword(session, i + _beatsPerSession);
    addIndexedBeat(world, thread, actor, 'status $kw nominal', [kw]);
    final metrics = await driveOneDecision(world, actor, 'report on $kw');
    expect(metrics.decisions, hasLength(1));
    final d = metrics.decisions.single;
    expect(
      d.truncated,
      isFalse,
      reason: 'cut truncated in session $session — the cut grew with the '
          'graph (D7 violation)',
    );
    tokens.add(d.tokensUsed);
  }
  expectIdle(world);
  return _avg(tokens);
}

void main() {
  late Directory tempDir;
  late SnapshotStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('multi-session-test');
    store = SnapshotStore();
    await store.open('${tempDir.path}/store');
  });

  tearDown(() => tempDir.delete(recursive: true));

  test(
    'long-horizon: tokens/decision stay flat across '
    '$_sessions snapshot/restore session boundaries',
    () async {
      final handler = MockGenerationHandler(responseText: 'ack');

      // ---- session 1: original world ----
      var world = await buildTestWorld(handler: handler);
      final setup = AgentWorldSetup(world: world);
      final scene = setup.spawnScene();
      final spawned = setup.spawnActors([
        ActorSpec(name: 'a', systemPrompt: 'p'),
      ], scene);
      var actor = spawned.first.entity;
      var thread = spawned.first.thread;

      final avgs = <double>[];
      avgs.add(await _runSession(world, actor, thread, 1));

      for (var s = 2; s <= _sessions; s++) {
        // ---- snapshot → kill (drop the world handle) → restore ----
        await store.save(world, meta: {'session': s - 1});
        world = await store.load('current');

        // Re-wire host seams (closures never cross a process boundary).
        world
          ..upsertResource(ModelRouterResource(ModelRouter()))
          ..upsertResource(GenerationHandlerResource())
          ..flush();
        world.getResource<GenerationHandlerResource>().registerDefault(
              handler,
            );

        final we = world
            .query2<Actor, ActorThreads>()
            .toList()
            .single
            .$1;
        actor = we.entity;
        thread = we.get<ActorThreads>()!.threads.single;

        avgs.add(await _runSession(world, actor, thread, s));
      }

      const beatsTotal = _sessions * (_beatsPerSession + _decisionsPerSession);
      expect(beatsTotal, greaterThanOrEqualTo(120));
      for (var s = 1; s < avgs.length; s++) {
        final ratio = avgs[s] / avgs[0];
        expect(
          ratio,
          lessThan(_flatnessBound),
          reason: 'tokens/decision drifted across the session boundary: '
              'session 1 avg=${avgs[0].toStringAsFixed(1)} vs session '
              '${s + 1} avg=${avgs[s].toStringAsFixed(1)} — session state '
              'leaked into the cut',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
