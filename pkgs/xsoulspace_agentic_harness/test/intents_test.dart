// ignore_for_file: lines_longer_than_80_chars

/// PLAN Stage H — intent closure (LLM-free): the agent defines intents of
/// the program it is building, calls them, and the goal is graded by intent
/// results — the closed feedback loop, deterministic.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:xsoulspace_agentic_harness/src/tooling/build_gates.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

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
}
