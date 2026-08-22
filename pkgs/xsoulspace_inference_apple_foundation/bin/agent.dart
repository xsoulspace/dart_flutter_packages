// ignore_for_file: avoid_print, lines_longer_than_80_chars

/// Interactive agent CLI over Apple Foundation Models — the battle-test
/// vehicle for the harness.
///
/// ```sh
/// dart run bin/agent.dart --root /tmp/agent_ws
/// ```
///
/// REPL commands:
/// - any text → sent to the actor as a decision; response streams live
/// - `_stats`   → channel watermarks + thread/token metrics
/// - `_trace`   → dump the execution ledger (last turn)
/// - `_save` / `_load <path>` → world snapshot to/from JSON
/// - `_exit`
///
/// Flags:
/// - `--root <dir>`  tool jail root (default: system temp)
/// - `--trace`       dump ledger after every turn
/// - `--no-debug`    silence native debug traces
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ecsly_serialization/ecsly_serialization.dart';
import 'package:xsoulspace_inference_apple_foundation/src/native_bridge/native_client.dart';
import 'package:xsoulspace_inference_core/src/agent/tools/fs_tools.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

Future<void> main(List<String> args) async {
  var root = Directory.systemTemp.path;
  var traceEveryTurn = false;
  final debug = !args.contains('--no-debug');
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--root' && i + 1 < args.length) root = args[++i];
    if (args[i] == '--trace') traceEveryTurn = true;
  }

  AppleFoundationNativeClient.setDebug(enabled: debug);

  // ── World setup (production path) ────────────────────────────────────────
  final client = AppleFoundationNativeClient();
  await client.load();
  if (!await client.refreshAvailability()) {
    stderr.writeln('Apple Foundation Model unavailable.');
    exit(2);
  }

  const modelId = ModelId('afm');
  final router = ModelRouter(
    inferenceClientsBuilders: {DefaultModelNames.appleFoundation: () => client},
  );
  router.models[modelId] = Model(
    id: modelId,
    name: DefaultModelNames.appleFoundation,
    tier: 0,
  );

  final world = World()
    ..addPlugin(AgentPlugin())
    ..addPlugin(SerializationPlugin());
  world
    ..upsertResource(ModelRouterResource(router))
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(AgencyPolicy(maxConcurrent: 1)) // AFM is serial on-device
    ..flush();

  final handler = DefaultGenerationHandler()..router = router;
  world.getResource<GenerationHandlerResource>().registerDefault(handler);

  final registry = ToolRegistry();
  fsTools(FsToolsRoot(root)).forEach(registry.register);
  world.getResource<ToolRegistryResource>().register('default', registry);

  final scene = world.spawnComponents([const Scene(), SceneFrame()]);
  final actor = world.spawnComponents([
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: modelId),
    ActorSystemPrompt(
      text:
          'You are a coding agent working inside a sandboxed directory. '
          'Use the provided tools to read, write, list, and search files. '
          'Complete tasks fully; be concise.',
    ),
    ActorThreads(threads: []),
    const ActorTools(registryName: 'default'),
    PresentInScene(sceneEntity: scene),
  ]);
  world.flush();

  // ── Loop + observability ─────────────────────────────────────────────────
  final loop = HarnessLoop(world: world);
  unawaited(loop.start());
  final ledger = HarnessExecutionLedger(world);
  world.executionObserver = ledger;
  final tap = world.getResource<StreamingTapResource>();

  var streaming = false;
  final tapSub = tap
      .subscribe(actor)
      .listen(
        (delta) {
          if (!streaming) {
            stdout.write('\x1b[2m');
            streaming = true;
          }
          stdout.write(delta);
        },
        onDone: () {
          if (streaming) {
            stdout.writeln('\x1b[0m');
            streaming = false;
          }
        },
      );

  String latestResponse() {
    String? last;
    for (final (_, _, content) in world.query2<BeatModality, TextContent>()) {
      if (content.text.isNotEmpty) last = content.text;
    }
    return last ?? '';
  }

  void saveSession(String path) {
    registerPersistentId(world);
    world.upsertComponent(actor, PersistentId(0));
    world.flush();
    final snapshot = captureWorldSnapshot(world);
    File(path).writeAsStringSync(encodeWorldSnapshot(snapshot));
    print('saved → $path');
  }

  void loadSession(String path) {
    final json = File(path).readAsStringSync();
    decodeWorldSnapshot(json); // restore into a fresh world is Phase 8+
    print(
      'loaded (restore-into-world lands with Phase 8) — bytes: ${json.length}',
    );
  }

  // ── REPL ─────────────────────────────────────────────────────────────────
  stdout.writeln(
    'xs_agent ready. jail=$root\n'
    'type a task, or _stats | _trace | _save <p> | _load <p> | _exit',
  );
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final input = line.trim();
    if (input.isEmpty) continue;

    if (input == '_exit') break;
    if (input == '_stats') {
      _printStats(world);
      continue;
    }
    if (input == '_trace') {
      print(ledger.dump());
      ledger.reset();
      continue;
    }
    if (input.startsWith('_save')) {
      saveSession(_argOf(input, '/tmp/xs_agent_session.json'));
      continue;
    }
    if (input.startsWith('_load')) {
      loadSession(_argOf(input, '/tmp/xs_agent_session.json'));
      continue;
    }

    ledger.reset();
    world.upsertComponent(actor, OpenDecision(prompt: input));
    world.flush();
    loop.wakeup();

    // Wait until this decision resolves (actor idle again).
    while (!loop.canSleep()) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final reply = latestResponse();
    if (!streaming && reply.isNotEmpty) print(reply);
    if (traceEveryTurn) print(ledger.dump());
    stdout.write('> ');
  }

  await tapSub.cancel();
  loop.stop();
  world.clear();
}

String _argOf(final String input, final String fallback) {
  final parts = input.split(' ');
  return parts.length > 1 ? parts[1] : fallback;
}

void _printStats(final World world) {
  final b = StringBuffer('── stats ──\n');

  void chan<T extends EcsEvent>(final String name) {
    if (!world.events.hasRegistered<T>()) return;
    final s = world.events.stats<T>();
    b.writeln(
      '$name: sent=${s.sent} consumed=${s.consumed} '
      'dropped=${s.dropped} cleared=${s.cleared} buffered=${s.length}'
      '${s.isConsistent ? '' : ' ⚠️ INVARIANT VIOLATION'}',
    );
  }

  chan<ActorGenerateRequest>('request ');
  chan<ActorGenerateResponse>('response');
  chan<ActorGenerateStreamEvent>('stream  ');
  chan<ToolCallEvent>('toolCall');
  chan<ToolResultEvent>('toolRes ');

  var threads = 0;
  var pruned = 0;
  for (final (_, _, status) in world.query2<Thread, ThreadStatus>()) {
    threads++;
    if (status.value == ThreadStatusEnum.pruned) pruned++;
  }
  var beats = 0;
  for (final _ in world.query2<BeatModality, TextContent>()) {
    beats++;
  }
  var tokens = 0;
  for (final (_, _, situation) in world.query2<Actor, Situation>()) {
    tokens += situation.tokensUsed;
  }
  b
    ..writeln('threads: $threads ($pruned pruned)')
    ..writeln('beats: $beats')
    ..writeln('tokens used (last projection): $tokens');
  print(b);
}
