// ignore_for_file: lines_longer_than_80_chars

/// Stage I3/J1 — real-AFM intent closure: the bookmark-manager end-to-end
/// loop. The runner core (prompts, tool surface, oracle) lives in
/// `lib/src/intent_closure_runner.dart` so it is measurable and benchmarkable;
/// this driver owns only the process plumbing: native client load, meter,
/// verifier loop, stdout report.
///
/// The tiny 2–4k model SHAPES the executor logic through meaning moves
/// (one `act_with_project` tool with macros, closed enum) + `intent_define`
/// + `intent_call`. It never writes a code token: the host materializer
/// compiles the op chains into the suite's `program.dart` contract, and the
/// INTENT-graded oracle replays real intent calls (`dart run
/// intent_runner.dart`).
library;

import 'dart:io';

import 'package:xsoulspace_agentic_harness/benchmark_api.dart'
    show openFreshDecision;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_inference_apple_foundation/src/intent_closure_runner.dart';
import 'package:xsoulspace_inference_apple_foundation/src/native_bridge/native_client.dart';

// Meter + SIGINT wiring are SHARED with bin/coding_agent.dart (B3: one
// implementation lives in the runner lib — DecisionMeter + wireSigintDump).

final ProcessResult _notRun = ProcessResult(0, -1, '', 'not run');

Future<void> main(List<String> args) async {
  final client = AppleFoundationNativeClient();
  await client.load();
  if (!await client.refreshAvailability()) {
    stderr.writeln('Apple Foundation Model unavailable.');
    exit(2);
  }

  final world = World()..addPlugin(AgentPlugin());
  // J1.5.3: the flight recorder is wired BEFORE any decisions so even a
  // hang leaves a post-mortem (dumped on maxTicks StateError / at exit).
  final recorder = FlightRecorder();
  final router = ModelRouter(
    inferenceClientsBuilders: {
      DefaultModelNames.appleFoundation: () => AppleFoundationNativeClient(),
    },
  );
  final modelId = ModelId('intent_closure');
  router.models[modelId] = Model(
    id: modelId,
    name: DefaultModelNames.appleFoundation,
  );
  world
    ..upsertResource(ModelRouterResource(router))
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(recorder)
    // J2 (ADR 0018 follow-up): the bridge is session-per-decision (a new
    // LanguageModelSession per generate call), so native-side accumulation
    // is bounded by THIS round cap × per-round ack size. Macros make builds
    // round-light (~5 moves) — the cap is a harness-owned context bound,
    // not headroom. The verifier loop provides cross-decision continuity.
    ..upsertResource(AgencyPolicy(maxConcurrent: 1, maxToolRounds: 12))
    ..flush();

  final meter = DecisionMeter(DefaultGenerationHandler(router: router));
  world.getResource<GenerationHandlerResource>().registerDefault(meter);

  // J1.5.5: Ctrl-C during an on-device run still leaves a post-mortem.
  wireSigintDump(recorder);

  final jail = await Directory.systemTemp.createTemp('intent_closure_');
  final tools = registerIntentClosureTools(world, jail);
  final overhead = overheadTokens(
    systemPrompt: afmSystemPrompt,
    tools: tools,
  );

  final scene = world.spawnComponents([Scene(), SceneFrame()]);
  final actor = world.spawnComponents([
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: modelId),
    ActorSystemPrompt(text: afmSystemPrompt),
    ActorThreads(threads: []),
    ActorTools(registryName: 'default'),
    PresentInScene(sceneEntity: scene),
    OpenDecision(prompt: afmTaskPrompt),
  ]);
  final thread = spawnThread(world, actor, scene);
  world.upsertComponent(actor, ActorThreads(threads: [thread]));
  world.flush();

  // Verifier-in-the-loop (same mechanical pattern as the coding suite):
  // run → intent-graded oracle → on failure feed the failure back as a new
  // OpenDecision (NO LLM in the retry loop itself — each retry is an honest
  // generation). Bounded by maxRetries. Premature-completion and drift are
  // recovered mechanically; a model that can't recover is an honest FAIL.
  const maxRetries = 3;
  var oracle = _notRun; // never-run sentinel; replaced on first oracle pass
  var retries = 0;
  while (true) {
    await HarnessLoop(world: world).runUntilIdle();
    oracle = await runIntentOracle(jail);
    if (oracle.exitCode == 0 || retries >= maxRetries) break;
    retries++;
    // J1.5.2: the retry is a FRESH decision — openFreshDecision resets the
    // per-decision ReAct round budget (a bare upsert left the previous
    // attempt's exhausted round count in place → retries started with a
    // silently shrunken budget and died after one tool round).
    openFreshDecision(
      world,
      actor,
      prompt: 'Your previous attempt did not satisfy the intent '
          'verification. Failing check: intents checker — '
          '${(oracle.stdout as String).trim()}\n\n'
          'Fix the meaning tree (check your op chains with action list — '
          'every intent needs an impl edge to a FIRST op and a then-chain '
          'to a return op; if an op is missing props a or b, fix it with '
          'set_prop using the op id from the error; intent_define define '
          'replaces one intent\u2019s whole logic in one move), '
          're-materialize, and call the intents to verify. '
          'Original task:\n$afmTaskPrompt',
    );
  }

  final view = meaningView(world);
  // Moves from the durable thread record: every internal tool round is a
  // beat — the response object only carries the final round's calls.
  final moves = <String, int>{};
  final beatIndex = world.getResource<FacetIndex>();
  for (final beat in beatIndex.beatsOfThread(thread).toList()) {
    final we = world.getEntity(beat).$1;
    final call = we.get<BeatToolCall>();
    if (call == null) continue;
    final action = call.args['action'];
    moves.update(
      action is String ? '${call.name}.$action' : call.name,
      (v) => v + 1,
      ifAbsent: () => 1,
    );
  }
  final program = File('${jail.path}/program.dart');
  // J1.5.5: publish the pulse + flight recorder even on FAILURE (standing
  // rule: failures are data). The dump names the last prompts, round/attempt
  // budgets, and any loop warnings — no more bisecting a silent hang.
  final pulse = sampleHarness(world, tick: retries);
  stdout
    ..writeln('intent_closure (AFM):')
    ..writeln('  overhead tokens (system+schemas): $overhead')
    ..writeln('  decisions: ${meter.decisions}')
    ..writeln('  tool rounds (from thread beats): '
        '${moves.values.fold(0, (a, b) => a + b)}')
    ..writeln('  moves: $moves')
    ..writeln('  projection tokens (honest spend): ${meter.projectionTokens}')
    ..writeln('  nodes: ${view.nodeCount}, edges: ${view.edgeCount}')
    ..writeln('  program.dart exists: ${program.existsSync()}')
    ..writeln('  oracle exit: ${oracle.exitCode} (retries: $retries)')
    ..writeln('  oracle stdout: ${(oracle.stdout as String).trim()}')
    ..writeln('--- harness pulse (J1.5.3) ---')
    ..writeln(pulse.toText())
    ..writeln('--- flight recorder ---')
    ..writeln(recorder.dump());
  exit(oracle.exitCode == 0 ? 0 : 1);
}
