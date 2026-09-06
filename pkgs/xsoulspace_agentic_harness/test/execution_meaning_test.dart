// ignore_for_file: lines_longer_than_80_chars

/// Execution-as-meaning gate (PLAN §NOW P2, Directions item 2 — LLM-free).
///
/// Claims under test:
/// 1. An allowlisted run creates the run intent node + outcome beat +
///    output span.
/// 2. A budgeted span cut returns bounded output (the chars cap is
///    mechanical — write-time AND cut-time).
/// 3. A second identical run RE-USES the declaration node (idempotent) and
///    appends a NEW beat.
/// 4. A NON-allowlisted command is refused BEFORE any node/beat/span
///    exists — the allowlist law stands, zero bypass.
/// 5. Tree re-derivation is UNCHANGED by outcomes: scan never sees exit
///    codes — outcomes are beats, the tree stays re-derivable.
/// 6. A call-edge chain (run node → follow-up intent) is data-visible with
///    no execution (the composability seam).
library;

import 'dart:convert';
import 'dart:io';

import 'package:ecsly/ecsly.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xsoulspace_agentic_harness/src/agent.dart' show AgentPlugin;
import 'package:xsoulspace_agentic_harness/src/data_models/components.dart'
    show ToolResultContent;
import 'package:xsoulspace_agentic_harness/src/meaning/execution_meaning.dart';
import 'package:xsoulspace_agentic_harness/src/meaning/meaning_tree.dart';
import 'package:xsoulspace_agentic_harness/src/narrative/components.dart'
    show BeatToolCall, TextContent;
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart';

World _world() => World()..addPlugin(AgentPlugin());

/// Count `run` outcome beats (BeatToolCall name == 'run') in the world.
int _runBeatCount(World world) => world
    .query<BeatToolCall>()
    .toList()
    .where((row) => row.$2.name == 'run')
    .length;

/// First output map of a beat named `run` (for span_key linkage asserts).
Map<String, dynamic>? _firstRunBeatOutput(World world) {
  for (final (facade, call) in world.query<BeatToolCall>().toList()) {
    if (call.name != 'run') continue;
    final we = world.getEntity(facade.entity).$1;
    final result = we.get<ToolResultContent>();
    if (result == null) continue;
    return (result.output as Map).cast<String, dynamic>();
  }
  return null;
}

/// The short summary text of the first `run` beat (must never be output).
String? _beatTextOf(World world) {
  for (final (facade, call) in world.query<BeatToolCall>().toList()) {
    if (call.name != 'run') continue;
    final we = world.getEntity(facade.entity).$1;
    return we.get<TextContent>()?.text;
  }
  return null;
}

/// Stored span count, or 0 when the store was never created (the strongest
/// "no spans exist" signal — a refused run must never even allocate it).
int _spanCount(World world) {
  try {
    return world.getResource<RunSpanStore>().length;
  } on StateError {
    return 0;
  }
}

void main() {
  late Directory jail;
  late World world;
  late FsToolsRoot root;
  late RunMeaningRecorder meaning;

  setUp(() async {
    jail = await Directory.systemTemp.createTemp('execution_meaning_');
    Directory('${jail.path}/lib').createSync();
    File(
      '${jail.path}/pubspec.yaml',
    ).writeAsStringSync('name: jail_probe\nenvironment:\n  sdk: ^3.0.0\n');
    world = _world();
    root = FsToolsRoot(jail.path);
    meaning = RunMeaningRecorder(world);
  });
  tearDown(() {
    try {
      jail.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  });

  Future<Map<String, dynamic>> callRunTool(
    Object args, {
    required List<List<String>> allowlist,
  }) async {
    final run = runTool(root, allowlist: allowlist, meaning: meaning);
    return ((jsonDecode('${await run.execute(args)}') as Map))
        .cast<String, dynamic>();
  }

  test('gate 1: allowlisted run creates run intent node + outcome beat + '
      'output span', () async {
    const cmd = ['dart', 'analyze', '.'];
    final result = await callRunTool({'command': cmd}, allowlist: const [
      ['dart', 'analyze'],
    ]);
    // The allowlist did NOT refuse it (no command_not_allowed) — whatever
    // the analyzer's verdict on the empty jail, the run EXECUTED.
    expect(result['code'], isNull, reason: '${result['code']}');

    // (a) the run DECLARATION is a tree node: kind 'intent', props
    //     {run_command, allowlist_scope} — re-derivable state.
    final id = runDeclarationId(cmd);
    expect(hasMeaningNode(world, id), isTrue);
    expect(isRunDeclaration(world, id), isTrue);
    final view = meaningView(world);
    final node = view.nodes.single;
    expect(node['kind'], 'intent');
    final props = node['props'] as Map;
    expect(props['run_command'], cmd);
    expect(props['allowlist_scope'], 'dart analyze');

    // (b) the OUTCOME is a beat (existing beat channel), NOT a node.
    expect(_runBeatCount(world), 1);
    final output = _firstRunBeatOutput(world)!;
    expect(output.keys, containsAll(['exit_code', 'duration_ms', 'span_key']));
    expect(output['run_node'], id);

    // (c) the OUTPUT is a bounded span keyed by the run beat — and the
    //     span key on the beat resolves to the stored span.
    final store = world.getResource<RunSpanStore>();
    final span = store.spans[output['span_key']];
    expect(span, isNotNull);
    expect(span!.runNodeId, id);
    expect(span.exitCode, result['exit_code']);
    expect(store.latestFor(id)!.spanKey, span.spanKey);
  });

  test('gate 2: budgeted span cut returns bounded output (mechanical cap)',
      () async {
    // Tiny argv, big OUTPUT (~13.9k chars): the command argument stays
    // small so the tree (which legitimately holds the declaration's
    // run_command) can never be confused with the output span.
    const cmd = ['seq', '1', '3000'];
    final result = await callRunTool(
      {'command': cmd},
      allowlist: const [
        ['seq'],
      ],
    );
    expect(result['ok'], isTrue);

    final id = runDeclarationId(cmd);
    // Write-time cap: the stored span holds at most the budget chars.
    const budget = defaultRunSpanCharBudget;
    final span = world.getResource<RunSpanStore>().latestFor(id)!;
    expect(span.stdoutTail.length, lessThanOrEqualTo(budget));
    expect(span.stdoutTotalChars, greaterThan(budget));
    expect(span.truncated, isTrue);

    // Cut-time: the cut can only NARROW the budget, never widen it.
    final cut = runSpanCut(world, id)!;
    expect((cut['stdout'] as String).length, lessThanOrEqualTo(budget));
    expect(cut['truncated'], isTrue);
    final narrow = runSpanCut(world, id, maxChars: 50)!;
    expect((narrow['stdout'] as String).length, lessThanOrEqualTo(50));
    // Output NEVER entered the tree or the beat: no node prop carries
    // output content, and the beat's text is a short summary line only.
    for (final n in meaningView(world).nodes) {
      expect(
        jsonEncode(n['props']),
        isNot(contains('2998')),
        reason: 'output must live only in the span store',
      );
      expect((n['props'] as Map).keys.where((k) => '$k'.contains('stdout')),
          isEmpty);
    }
    final beatText = _beatTextOf(world);
    expect(beatText, isNotNull);
    expect(beatText!.length, lessThan(100));
  });

  test('gate 3: second identical run RE-USES the declaration node '
      '(idempotent, new beat)', () async {
    const cmd = ['dart', 'analyze', '.'];
    const allowlist = [
      ['dart', 'analyze'],
    ];
    await callRunTool({'command': cmd}, allowlist: allowlist);
    final nodeId = runDeclarationId(cmd);
    final nodeCountBefore = meaningView(world).nodeCount;
    final beatsBefore = _runBeatCount(world);
    final spanCountBefore = world.getResource<RunSpanStore>().length;

    await callRunTool({'command': cmd}, allowlist: allowlist);

    final view = meaningView(world);
    // SAME node (idempotent declaration) — no fork, no duplicate.
    expect(view.nodeCount, nodeCountBefore);
    expect(view.nodes.where((n) => n['id'] == nodeId).length, 1);
    // NEW outcome beat + NEW span (append-only).
    expect(_runBeatCount(world), beatsBefore + 1);
    expect(world.getResource<RunSpanStore>().length, spanCountBefore + 1);
    final keys = world.getResource<RunSpanStore>().keysFor(nodeId);
    expect(keys.length, 2);
  });

  test('gate 4: NON-allowlisted command refused BEFORE any node/beat/span '
      'exists (allowlist law intact)', () async {
    // The exact write path the pi row found (run_allowlist_test.dart).
    final result = await callRunTool({
      'command': ['perl', '-pi', '-e', 's/a/b/', 'lib/x.dart'],
    }, allowlist: const [
      ['dart', 'analyze'],
    ]);
    expect(result['code'], 'command_not_allowed');

    // The world is UNTOUCHED: zero nodes, zero edges, zero beats, zero
    // spans. The allowlist check precedes every execution-meaning write.
    final view = meaningView(world);
    expect(view.nodeCount, 0);
    expect(view.edgeCount, 0);
    expect(_runBeatCount(world), 0);
    expect(_spanCount(world), 0);
  });

  test('gate 5: tree re-derivation is UNCHANGED by outcomes — scan never '
      'sees exit codes (outcomes are beats, the tree stays clean)', () async {
    const cmd = ['dart', 'analyze', '.'];
    const allowlist = [
      ['dart', 'analyze'],
    ];
    await callRunTool({'command': cmd}, allowlist: allowlist);
    // Tree state after the DECLARATION landed (before any further outcome):
    final before = meaningView(world);
    expect(before.nodeCount, 1);

    // More outcomes accumulate (failures, successes — irrelevant to the
    // tree): beats append, tree state must not move.
    await callRunTool({'command': cmd}, allowlist: allowlist);
    await callRunTool({'command': cmd}, allowlist: allowlist);
    expect(_runBeatCount(world), 3);

    final after = meaningView(world);
    expect(jsonEncode(after.nodes), jsonEncode(before.nodes));
    expect(jsonEncode(after.edges), jsonEncode(before.edges));
    // Exit codes are NOT tree props — re-derivation can never see them.
    for (final n in after.nodes) {
      expect((n['props'] as Map).keys.where((k) => '$k'.contains('exit')),
          isEmpty);
    }
  });

  test('gate 6: call-edge chain — run node → follow-up intent is '
      'data-visible with NO execution', () {
    const cmd = ['dart', 'test'];
    final runId = meaning.ensureDeclaration(
      command: cmd,
      allowlistScope: 'dart test',
    );
    // The follow-up intent exists as a declaration (data), not an executor.
    addMeaningNode(
      world,
      kind: 'intent',
      label: 'verify after test',
      props: {'intent_kind': 'verify'},
      id: 'intent_verify_after_test',
    );
    expect(
      linkRunFollowUp(
        world,
        runNodeId: runId,
        followUpIntentId: 'intent_verify_after_test',
      ),
      isTrue,
    );

    final view = meaningView(world);
    expect(
      view.edges.map(jsonEncode),
      contains(
        jsonEncode({
          'from': runId,
          'relation': 'call',
          'to': 'intent_verify_after_test',
        }),
      ),
    );
    final runNode = view.nodes.singleWhere((n) => n['id'] == runId);
    final runProps = runNode['props'] as Map;
    expect(runProps['follow_up_intent'], 'intent_verify_after_test');
    // Dangling follow-up names are refused — no dangling edges, ever.
    expect(
      linkRunFollowUp(
        world,
        runNodeId: runId,
        followUpIntentId: 'intent_missing',
      ),
      isFalse,
    );
  });
}
