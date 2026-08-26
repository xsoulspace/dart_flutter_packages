// ignore_for_file: avoid_print, lines_longer_than_80_chars

/// Interactive agent CLI over Apple Foundation Models — the everyday,
/// battle-test vehicle for the harness, hosted on core's [CliHost].
///
/// ```sh
/// dart run bin/agent.dart --root /tmp/agent_ws
/// ```
///
/// The binary owns only provider wiring and presentation; the turn lifecycle
/// (input-as-decisions, cancellation, idle detection, streaming fan-out,
/// tool confirmation) lives in `CliHost`, so everything battle-tested here
/// transfers to Flutter/ACP hosts unchanged.
///
/// REPL commands:
/// - any text → sent to the actor as a decision; response streams live
/// - `/situation` → human-readable projection state per acting actor
/// - `/cancel`    → cancel in-flight generation + release agency (or Ctrl-C)
/// - `/exit`      → stop the harness and tear down
/// - `_stats`     → channel watermarks + thread/token metrics
/// - `_trace`     → dump the execution ledger (last turn)
/// - `_spawn <p>` → additional actor with its own thread of work
/// - `_save <p>` / `_load <p>` → world snapshot to/from JSON
///
/// Flags:
/// - `--root <dir>`  tool jail root (default: system temp)
/// - `--trace`       dump ledger after every settled turn
/// - `--no-debug`    silence native debug traces
library;

import 'dart:async';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'dart:convert';
import 'dart:io';

import 'package:ecsly_serialization/ecsly_serialization.dart';
import 'package:xsoulspace_inference_apple_foundation/src/native_bridge/native_client.dart';
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// Exclusive single-user stdin reader: each pulled line is consumed exactly
/// once, whether it answers a tool-confirmation prompt or feeds the REPL.
class _StdinLines {
  _StdinLines() {
    stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            final waiter = _waiter;
            if (waiter != null && !waiter.isCompleted) {
              _waiter = null;
              waiter.complete(line);
            } else {
              _buffer.add(line);
            }
          },
          onDone: () {
            _closed = true;
            final waiter = _waiter;
            if (waiter != null && !waiter.isCompleted) {
              _waiter = null;
              waiter.complete(null);
            }
          },
        );
  }

  final _buffer = <String>[];
  Completer<String?>? _waiter;
  var _closed = false;

  /// Next buffered line, or null on EOF (Ctrl-D).
  Future<String?> next() {
    if (_buffer.isNotEmpty) return Future.value(_buffer.removeAt(0));
    if (_closed) return Future.value(null);
    return (_waiter ??= Completer<String?>()).future;
  }
}

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
    // AFM serializes generation requests on-device (~8s TTFT cold).
    // grantAgencySystem reads this to gate per-model concurrency; the
    // global policy stays generous so hosted models could parallelize.
    maxInFlight: 1,
  );

  final world = World()
    ..addPlugin(AgentPlugin())
    ..addPlugin(SerializationPlugin());
  world
    ..upsertResource(ModelRouterResource(router))
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(AgencyPolicy(maxConcurrent: 4)) // real cap = Σ maxInFlight
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

  // ── Observability ────────────────────────────────────────────────────────
  final ledger = HarnessExecutionLedger(world);
  world.executionObserver = ledger;

  var streaming = false;

  // Late actors are not covered by CliHost's start-time subscriptions, so
  // each spawn attaches its own labeled tap ([a0], [a1], …).
  var nextActorOrdinal = 0;
  final spawnedSubscriptions = <StreamSubscription<String>>[];
  Entity spawnActor(final String prompt) {
    final ordinal = nextActorOrdinal++;
    final spawned = world.spawnComponents([
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
    spawnedSubscriptions.add(
      world.getResource<StreamingTapResource>().subscribe(spawned).listen((
        delta,
      ) {
        stdout.write('\x1b[2m[a$ordinal]\x1b[0m $delta');
      }),
    );
    world.upsertComponent(spawned, OpenDecision(prompt: prompt));
    world.flush();
    print('spawned a$ordinal');
    return spawned;
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

  // ── Host (turn lifecycle owned by core) ──────────────────────────────────
  // Single-user stdin: a line answers a pending confirmation prompt if one is
  // open, otherwise it reaches the REPL loop — never both.
  Completer<String>? pendingConfirmation;

  final host = CliHost(
    world: world,
    config: CliHostConfig(
      confirmationRequiredTools: {'write'},
      onIdleTurnEnd: () async {
        // Settled turn: close the dim-wrapped stream window, drain the
        // fire-and-forget dispatch watermark so _stats stays honest, and
        // optionally dump the trace. Autosave hooks belong here too.
        if (streaming) {
          stdout.writeln('\x1b[0m');
          streaming = false;
        }
        world.events.reader<ActorGenerateRequest>().drain();
        world.events.channel<ActorGenerateRequest>().clear();
        if (traceEveryTurn) print(ledger.dump());
        ledger.reset();
      },
    ),
    requestToolConfirmation: (name, arguments) async {
      String target;
      if (arguments case {'path': final path}) {
        target = '$path';
      } else {
        target = '$arguments';
      }
      stderr.write('approve write to $target? [y/N] ');
      pendingConfirmation = Completer<String>();
      final answer = (await pendingConfirmation!.future).trim().toLowerCase();
      return answer == 'y' || answer == 'yes';
    },
  );

  // ── REPL ────────────────────────────────────────────────────────────────
  stdout.writeln(
    'xs_agent ready. jail=$root\n'
    'type a task, or /situation | /cancel | /exit | '
    '_stats | _trace | _spawn <p> | _save <p> | _load <p>',
  );
  unawaited(host.start());

  host.output.listen((delta) {
    if (!streaming) {
      stdout.write('\x1b[2m');
      streaming = true;
    }
    stdout.write(delta);
  });

  ProcessSignal.sigint.watch().listen((_) {
    host.cancel();
    stdout.writeln('\n(cancelled — type /exit to quit)');
  });

  final stdinLines = _StdinLines();
  while (true) {
    final line = await stdinLines.next();
    if (line == null) break; // EOF (Ctrl-D)

    final pending = pendingConfirmation;
    if (pending != null) {
      pendingConfirmation = null;
      pending.complete(line);
      continue;
    }

    final input = line.trim();
    if (input.isEmpty) continue;

    if (input == '/exit') break;
    if (input == '/cancel') {
      host.cancel();
      continue;
    }
    if (input == '/situation') {
      print(host.renderSituation());
      continue;
    }
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
    if (input.startsWith('_spawn ')) {
      final prompt = input.substring('_spawn '.length).trim();
      if (prompt.isNotEmpty) {
        spawnActor(prompt);
        host.wakeup(); // sleeping loop must pick up the new decision
      }
      continue;
    }

    if (!host.feed(input)) {
      stdout.writeln('(all actors busy — /cancel to interrupt, or wait)');
    }
  }

  for (final sub in spawnedSubscriptions) {
    await sub.cancel();
  }
  await host.stop();
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
