// ignore_for_file: lines_longer_than_80_chars

/// PLAN Stage H — intent closure (LLM-free): the agent defines intents of
/// the program it is building, calls them, and the goal is graded by intent
/// results — the closed feedback loop, deterministic.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:xsoulspace_agentic_harness/src/tooling/build_gates.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_harness/src/meaning/meaning_tree.dart' as mt;

World _world() => World()..addPlugin(AgentPlugin());
Map<String, dynamic> _dec(Object? raw) {
  final r = raw is String ? jsonDecode(raw) : raw;
  return (r as Map).cast<String, dynamic>();
}

/// Host materializer semantics for a bookmark manager: intents are pure
/// functions over the meaning view — `save_url` adds a feature node,
/// `list_saved` reads them back. The HOST owns behavior; the model only
/// defines contracts + makes meaning moves.
void registerBookmarkIntents(World world) {
  final runtime = world.getResource<IntentRuntime>();
  runtime.register('save_url', (args, program) async {
    final url = args['url'];
    if (url is! String || !url.startsWith('http')) {
      return {'saved': false, 'reason': 'invalid url'};
    }
    addMeaningNode(world, kind: 'bookmark', label: '$url', props: {'url': url});
    return {'saved': true, 'url': url};
  });
  runtime.register('list_saved', (args, program) async {
    final urls = program.propValues('url', kind: 'bookmark');
    return {'count': urls.length, 'urls': urls};
  });
}

void main() {
  test('define → list → call: the model builds the program surface', () async {
    final world = _world();
    registerBookmarkIntents(world);
    final define = intentDefineTool(world);
    final call = intentCallTool(world);

    // define two intents (the model's contract moves — no code tokens)
    final r = _dec(await define.execute({
      'action': 'define',
      'name': 'save_url',
      'params': ['url:string'],
      'returns': 'bool',
      'description': 'Saves the current URL.',
    }));
    expect(r['ok'], true);
    expect((r['defined'] as Map)['name'], 'save_url');
    await define.execute({
      'action': 'define',
      'name': 'list_saved',
      'returns': 'list',
      'description': 'Lists saved URLs.',
    });

    // list shows both
    final listed = _dec(await define.execute({'action': 'list'}));
    expect(
      (listed['intents'] as List).map((i) => (i as Map)['name']),
      containsAll(['save_url', 'list_saved']),
    );

    // intents live in the meaning tree as nodes → appear in the cut
    final cut = meaningCut(world, query: 'list_saved', maxNodes: 8);
    expect(
      (cut['nodes'] as List).cast<Map>().map((n) => n['id']),
      contains('list_saved'),
    );

    // call → typed result, defined-and-observable behavior
    final saved = _dec(await call.execute({
      'intent': 'save_url',
      'args': ['url=https://example.com'],
    }));
    expect(saved['ok'], true);
    expect(((saved['result'] as Map)['saved']), true);

    final listed2 = _dec(await call.execute({'intent': 'list_saved'}));
    expect((listed2['result'] as Map)['count'], 1);
    expect(
      ((listed2['result'] as Map)['urls'] as List),
      contains('https://example.com'),
    );
  });

  test('modify = re-define over the same name (a meaning-tree edit)', () async {
    final world = _world();
    final define = intentDefineTool(world);
    await define.execute({
      'action': 'define',
      'name': 'save_url',
      'params': ['url:string'],
      'description': 'v1',
    });
    await define.execute({
      'action': 'define',
      'name': 'save_url',
      'params': ['url:string', 'title:string'],
      'description': 'v2 accepts a title',
    });
    final intents = listIntents(world);
    expect(intents, hasLength(1)); // no duplicate node
    expect(intents.single['params'], contains('title:string'));
    expect(intents.single['description'], 'v2 accepts a title');
  });

  test('calling an unimplemented intent fails with the defined set', () async {
    final world = _world();
    await intentDefineTool(world).execute({
      'action': 'define',
      'name': 'future_intent',
    });
    final r = await callIntent(world, name: 'future_intent');
    expect(r['ok'], false);
    expect((r['defined'] as List), contains('future_intent'));
  });

  test('intent-graded goal: the loop terminates when scripted calls verify',
      () async {
    final world = _world();
    registerBookmarkIntents(world);

    // Goal + actor, exactly the Gate-B shape.
    final goal = world.spawnComponents([Goal(text: 'bookmark manager works')]);
    final scene = world.spawnComponents([const Scene(), SceneFrame()]);
    final actor = world.spawnComponents([
      Actor(agentId: AgentId.create()),
      ActorModel(modelId: ModelId.create()),
      ActorSystemPrompt(text: 'build'),
      ActorGoalRef(goal),
      PresentInScene(sceneEntity: scene),
    ]);
    world.flush();

    wireIntentGradedGoal(world, sequence: [
      const IntentExpectation('save_url', args: {'url': 'https://x.dev'}),
      const IntentExpectation('list_saved', expect: {'count': 1}),
    ]);

    // A tool result lands ON the actor (the trigger) → the verifier replays
    // the scripted sequence and stamps GoalVerified.
    world.upsertComponent(actor, OpenDecision(prompt: 'continue'));
    world.upsertComponent(actor, const ToolResultPendingMarker());
    world.flush();

    await intentGoalVerifier(world);

    final verified = world.query2<Actor, GoalVerified>().toList().single;
    expect(verified.$3.passed, isTrue);
    expect(verified.$3.detail, 'intents: all 2 calls verified');

    // The run-graded policy consumes the same stamp → no next decision.
    final ctx = DecisionContext(actor: verified.$1.entity, world: world, tick: 1);
    expect(const RunGradedGoalPolicy().evaluate(ctx), isNull);
  });

  // ---- J1 macro on the intent surface: redefine_chain (ADR 0018) ----
  test('redefine_chain macro: atomic drop + rebuild repairs accretion',
      () async {
    final world = _world();
    final define = intentDefineTool(world);

    // A BROKEN chain first: impl wired to a dead-end chain (no return op).
    await define.execute({'action': 'define', 'name': 'save_url'});
    addMeaningNode(world, kind: 'op', label: 'load_state', props: {'a': 'bookmarks'});
    addMeaningNode(world, kind: 'op', label: 'list_len');
    linkMeaning(world, from: 'save_url', relation: 'impl', to: 'op_1');
    linkMeaning(world, from: 'op_1', relation: 'then', to: 'op_2');
    expect(validateMeaningProgram(world), isNotEmpty);

    // ONE move replaces the whole logic — declarative spec rows with
    // `next` (default i+1) and `#row` jump targets; host tracks every id.
    final r = _dec(await define.execute({
      'action': 'redefine_chain',
      'name': 'save_url',
      'params': ['url:string'],
      'returns': 'bool',
      'specs': [
        {'label': 'load_arg', 'a': 'url'}, // 0
        {'label': 'starts_with', 'b': 'http'}, // 1
        {'label': 'jump_if_false', 'b': '#5'}, // 2 → false branch
        {'label': 'push_state', 'a': 'bookmarks'}, // 3
        {'label': 'literal', 'b': '{"saved": true}', 'next': 6}, // 4
        {'label': 'literal', 'b': '{"saved": false}'}, // 5
        {'label': 'return'}, // 6
      ],
    }));
    expect(r['ok'], true, reason: '${r['problems']}');
    expect(r['dropped'], 2, reason: 'old 2-op chain dropped');
    expect(r['ids'], [
      'op_3', 'op_4', 'op_5', 'op_6', 'op_7', 'op_8', 'op_9',
    ]);
    expect((r['problems'] as List), isEmpty);

    // The rebuilt chain branches correctly via the interpreter.
    final ok = interpretMeaningProgram(
      world,
      'save_url',
      {'bookmarks': <String>[]},
      {'url': 'https://x.dev'},
    );
    expect((ok['_result'] as Map)['saved'], true);
    final bad = interpretMeaningProgram(
      world,
      'save_url',
      {'bookmarks': <String>[]},
      {'url': 'nope'},
    );
    expect((bad['_result'] as Map)['saved'], false);
    // Accretion absorbed: only intent + new chain remain.
    expect(meaningView(world).nodeCount, 8);
  });

  test('redefine_chain rejects unresolvable #refs BEFORE any state change',
      () async {
    final world = _world();
    final define = intentDefineTool(world);
    // AFM run2: the model echoed the prompt's literal "#row" as a jump
    // target. The macro must reject it as malformed — not let it into the
    // tree where it becomes "unknown op: #row" at oracle time.
    final r = _dec(await define.execute({
      'action': 'redefine_chain',
      'name': 'save_url',
      'specs': [
        {'label': 'load_arg', 'a': 'url'},
        {'label': 'jump_if_false', 'b': '#row'},
        {'label': 'return'},
      ],
    }));
    expect(r['error'], isNotNull,
        reason: 'unresolvable #ref must fail at spec validation');
    expect(mt.hasMeaningNode(world, 'save_url'), isFalse,
        reason: 'nothing spawned on a malformed request');
    // A valid #ref still resolves.
    final ok = _dec(await define.execute({
      'action': 'redefine_chain',
      'name': 'save_url',
      'specs': [
        {'label': 'literal', 'b': '1'},
        {'label': 'return'},
      ],
    }));
    expect(ok['ok'], true, reason: '${ok['problems']}');
  });

  test('redefine_chain topology gate: cyclic chains rejected at spec time '
      '(AFM run4 finding — step limit exceeded at oracle time)', () async {
    final world = _world();
    final define = intentDefineTool(world);
    // A self-loop: row 0 jumps to itself.
    final r = _dec(await define.execute({
      'action': 'redefine_chain',
      'name': 'looped',
      'specs': [
        {'label': 'load_state', 'a': 'x', 'next': 0},
        {'label': 'return'},
      ],
    }));
    expect(r['error'], contains('cycle'));
    expect(mt.hasMeaningNode(world, 'looped'), isFalse);

    // No return reachable.
    final r2 = _dec(await define.execute({
      'action': 'redefine_chain',
      'name': 'no_return',
      'specs': [
        {'label': 'load_state', 'a': 'x'},
        {'label': 'list_len'},
      ],
    }));
    expect(r2['error'], contains('no return op is reachable'));
    expect(mt.hasMeaningNode(world, 'no_return'), isFalse);
  });

  test('redefine_chain dedup guard: identical spec is a cheap no-op '
      '(thrash damping)', () async {
    final world = _world();
    final define = intentDefineTool(world);
    final specs = {
      'action': 'redefine_chain',
      'name': 'save_url',
      'specs': [
        {'label': 'load_arg', 'a': 'url'},
        {'label': 'return'},
      ],
    };
    final first = _dec(await define.execute(specs));
    expect(first['ok'], true);
    final nodesAfterFirst = meaningView(world).nodeCount;
    // Same call again: thrash pattern from the AFM runs. No drop/rebuild.
    final again = _dec(await define.execute(specs));
    expect(again['ok'], true);
    expect(again['unchanged'], true);
    expect(meaningView(world).nodeCount, nodesAfterFirst,
        reason: 'dedup must not churn the tree');
    // A DIFFERENT spec still rebuilds.
    final changed = _dec(await define.execute({
      ...specs,
      'specs': [
        {'label': 'load_arg', 'a': 'url'},
        {'label': 'list_len'},
        {'label': 'return'},
      ],
    }));
    expect(changed['ok'], true);
    expect(changed['unchanged'], isNull);
    expect(meaningView(world).nodeCount, nodesAfterFirst + 1);
  });

  test('redefine_chain vocabulary guard: invalid op rejected with the '
      'closed list (AFM run3 finding)', () async {
    final world = _world();
    final r = _dec(await intentDefineTool(world).execute({
      'action': 'redefine_chain',
      'name': 'save_url',
      'specs': [
        {'label': 'load'},
        {'label': 'return'},
      ],
    }));
    expect(r['error'], contains('outside the closed vocabulary'));
    expect(r['error'], contains('load_arg'));
    expect((r['valid_ops'] as List), contains('return'));
    expect(mt.hasMeaningNode(world, 'save_url'), isFalse);
  });

  test('redefine_chain macro is atomic: malformed request keeps the chain',
      () async {
    final world = _world();
    final define = intentDefineTool(world);
    await define.execute({
      'action': 'redefine_chain',
      'name': 'good',
      'specs': [
        {'label': 'literal', 'b': '1'},
        {'label': 'return'},
      ],
    });
    expect(validateMeaningProgram(world), isEmpty);
    final r = _dec(await define.execute({
      'action': 'redefine_chain',
      'name': 'good',
      'specs': [{'a': 'x'}],
    }));
    expect(r['error'], isNotNull);
    expect(validateMeaningProgram(world), isEmpty,
        reason: 'atomicity: the working chain must survive a bad request');
  });
}
