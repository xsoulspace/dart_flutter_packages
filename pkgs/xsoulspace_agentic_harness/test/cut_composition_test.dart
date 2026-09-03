// ignore_for_file: lines_longer_than_80_chars

/// ADR 0020 — Cut Composition API conformance suite (LLM-free).
///
/// A composition that cannot state its invariant does not ship. Every test
/// here is a stated invariant of the `coder` composition:
/// slot order, dedup, drop-empty, required-slot input gate, working-set
/// survival under eviction pressure.
library;

import 'dart:io';

import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'package:xsoulspace_agentic_harness/src/agent.dart';
import 'package:xsoulspace_agentic_harness/src/events.dart';
import 'package:xsoulspace_agentic_harness/src/handler.dart';
import 'package:xsoulspace_agentic_harness/src/schedules.dart';
import 'package:xsoulspace_agentic_harness/src/systems/projection/cut_composition.dart';
import 'package:xsoulspace_agentic_harness/src/tooling/build_gates.dart';

import 'support/agent_harness_support.dart';

Entity _beat(String text) => Entity.create(0);
String _textOf(Entity e) => _texts[e] ?? '';
final _texts = <Entity, String>{};
final _index = <Entity, int>{};

/// Pure composeCut conformance — no world needed.
void pureConformance() {
  group('composeCut: slot order', () {
    test('working set renders in declared slot order', () {
      final cut = composeCut(
        composition: CutComposition.coder(),
        candidates: const [],
        textOf: _textOf,
        originalIndex: (e) => _index[e] ?? 0,
        goalText: 'fix the test',
        mapText: 'lib/, test/',
        verdictText: 'dart test exit=1: expected hello',
        totalCandidates: 0,
      );
      expect(cut.workingSet, hasLength(3));
      expect(cut.workingSet[0], startsWith('task:'));
      expect(cut.workingSet[1], startsWith('workspace map:'));
      expect(cut.workingSet[2], startsWith('last check:'));
      expect(cut.violations, isEmpty);
    });

    test('required goal missing → INPUT GATE violation', () {
      final cut = composeCut(
        composition: CutComposition.coder(),
        candidates: const [],
        textOf: _textOf,
        originalIndex: (_) => 0,
        goalText: '',
        totalCandidates: 0,
      );
      expect(cut.violations, hasLength(1));
      expect(cut.violations.single.slot, 'goal');
      expect(cut.violations.single.reason, contains('input gate'));
    });

    test('map without provider → explicit absence, never a violation', () {
      final cut = composeCut(
        composition: CutComposition.coder(),
        candidates: const [],
        textOf: _textOf,
        originalIndex: (_) => 0,
        goalText: 'g',
        mapText: null,
        totalCandidates: 0,
      );
      expect(cut.violations, isEmpty);
      expect(cut.absences.where((a) => a.contains('map')), isNotEmpty);
    });
  });

  group('composeCut: observations slot policies', () {
    List<Entity> candidates(List<String> texts) {
      final out = <Entity>[];
      for (var i = 0; i < texts.length; i++) {
        final e = Entity.create(i + 1);
        _texts[e] = texts[i];
        _index[e] = i;
        out.add(e);
      }
      return out;
    }

    int index(Entity e) => _index[e] ?? 0;

    test('DEDUP: identical tool results admitted once', () {
      final cut = composeCut(
        composition: CutComposition.coder(),
        candidates: candidates([
          'tool:read {greet_test import greet}',
          'tool:read {greet_test import greet}',
          'tool:read {greet_test import greet}',
        ]),
        textOf: _textOf,
        originalIndex: index,
        goalText: 'g',
        totalCandidates: 3,
      );
      expect(
        cut.orderedBeats.map(_textOf).where(
              (t) => t.contains('greet_test import greet'),
            ),
        hasLength(1),
      );
      expect(cut.duplicatesDropped, 2);
    });

    test('DROP-EMPTY: empty fragments never admitted', () {
      final cut = composeCut(
        composition: CutComposition.coder(),
        candidates: candidates(['', '   ', 'tool:read {content}']),
        textOf: _textOf,
        originalIndex: index,
        goalText: 'g',
        totalCandidates: 3,
      );
      expect(cut.emptyDropped, 2);
      expect(cut.orderedBeats.map(_textOf), ['tool:read {content}']);
    });

    test('CAPACITY + working-set survival: oldest observations evicted, '
        'render order stays chronological within the slot', () {
      final texts = [
        for (var i = 0; i < 12; i++) 'observation beat number $i',
      ];
      // Candidates arrive RELEVANCE-RANKED (as rankFragments produces: recency
      // tie-break means newest first under equal relevance).
      final cut = composeCut(
        composition: CutComposition.coder(),
        candidates: candidates(texts).reversed.toList(),
        textOf: _textOf,
        originalIndex: index,
        goalText: 'the goal',
        totalCandidates: 12,
      );
      expect(cut.orderedBeats, hasLength(8));
      // Chronological WITHIN the slot: newest last.
      final rendered = [for (final b in cut.orderedBeats) _textOf(b)];
      expect(rendered.first, 'observation beat number 4');
      expect(rendered.last, 'observation beat number 11');
      // The goal survived eviction pressure (non-evictable slot).
      expect(cut.workingSet.first, contains('the goal'));
    });
  });
}

/// Integration: the composition flows through the real projection → actorAct
/// → request fragments, in slot order, with dedup applied.
void integrationConformance() {
  test('ADR 0020: the emitted cut conforms to its composition', () async {
    final world = await buildTestWorld();
    world.upsertResource(CutCompositionResource(CutComposition.coder()));
    world.flush();
    final scene = spawnScene(world);
    final actor = spawnActor(world, scene, openDecisionPrompt: 'do the task');
    world.flush();

    // Seed observations: a duplicate read, an empty narration, and the
    // observation that matters (keyword 'parser').
    final thread = spawnThread(world, actor, scene);
    world.upsertComponent(actor, ActorThreads(threads: [thread]));
    addIndexedBeat(world, thread, actor, '', ['empty']);
    addIndexedBeat(world, thread, actor, 'tool:read greet_test body', ['greet']);
    addIndexedBeat(world, thread, actor, 'tool:read greet_test body', ['greet']);
    addIndexedBeat(world, thread, actor, 'the parser needs fixing', ['parser']);
    world.getResource<GenerationHandlerResource>().registerDefault(
          _CapturingHandler(),
        );

    world.upsertComponent(actor, OpenDecision(prompt: 'fix the parser'));
    world.flush();
    await HarnessLoop(world: world).runUntilIdle();

    final capture = _CapturingHandler.last!;
    // Working set first: the goal is the leading fragment (non-evictable).
    expect(capture[0], startsWith('task:'));
    expect(capture[0], contains('fix the parser'));
    // DEDUP across the cut: 'tool:read greet_test body' appears once.
    expect(capture.where((f) => f.contains('greet_test body')), hasLength(1));
    // DROP-EMPTY: no empty assistant fragments in the emitted cut.
    expect(capture.where((f) => f.trim().isEmpty), isEmpty);
    // Slot order: goal (working set) precedes observations; the relevant
    // observation is present (selection by relevance within the slot).
    expect(
      capture.indexWhere((f) => f.startsWith('task:')),
      lessThan(capture.indexWhere((f) => f.contains('parser needs fixing'))),
    );
    expectIdle(world);
  });
}

class _CapturingHandler implements GenerationHandler {
  static List<String>? last;
  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    last = [for (final f in request.contextFragments) f.toString()];
    final r = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': 'ok'},
      rawOutput: 'ok',
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(r);
    return r;
  }
}

Future<void> main() async {
  pureConformance();
  integrationConformance();
}
