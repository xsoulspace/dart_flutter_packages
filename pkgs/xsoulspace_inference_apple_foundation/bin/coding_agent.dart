// ignore_for_file: lines_longer_than_80_chars

/// B3 — ONE entry point for AFM Dart coding.
///
/// ```sh
/// dart run bin/coding_agent.dart "<task sentence>" [--jail <dir>] [--task <suite-id>] [--runs 3] [--scripted]
///                      [--diff-gate] [--auto-approve] [--session <store-path>] [--resume <store-path>]
/// ```
///
/// - `--task intent_03_bookmark_macros` — the J1.4 gate (intent oracle).
/// - `--task bugfix_01_off_by_one` — run-graded bugfix (runs-checker).
/// - a bare sentence + `--jail <dir>` — the workspace convention decides the
///   check (D8/M0: `dart test` / `dart analyze` / `dart run main.dart`);
///   `--check <command>` overrides it explicitly. A workspace with no
///   resolvable convention is an honest exit(64) — pass `--check`.
/// - `--runs N` (default 3) — pass@k protocol: fresh jail per run, per-run
///   logs + summary row to `benchmark/runs/` (K4). No single-run claims.
/// - `--scripted` — LLM-free proof: the scripted suite handler through the
///   SAME driver (same surface, same verifier, same budgets). On-device
///   claims require the real AFM client; scripted runs are labeled as such.
///
/// B7: the verifier (intent-graded or run-graded) is wired INSIDE the loop —
/// ONE `runUntilIdle`, retries consume `AttemptCount` (maxGoalAttempts: 3),
/// the outer oracle runs once as the final gate. B6/B1: teaching lives in
/// tool descriptions + the system prompt only.
library;

import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_harness/benchmark_api.dart'
    show ScriptedSuiteHandler;
import 'package:xsoulspace_agentic_harness/src/snapshot_store.dart'
    show SnapshotStore;
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show WriteGateMode;
import 'package:xsoulspace_inference_apple_foundation/src/coding_agent_runner.dart';
import 'package:xsoulspace_inference_apple_foundation/src/intent_closure_runner.dart'
    show wireSigintDump;
import 'package:xsoulspace_inference_apple_foundation/src/native_bridge/native_client.dart';
import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart'
    show OpenRouterInferenceClient, OpenRouterModelNames;

const _backendAfm = 'apple_foundation_afm';
const _backendScripted = 'scripted_llm_free';
const _defaultOpenRouterModel = 'deepseek/deepseek-v4-flash-0731';

Future<void> main(List<String> args) async {
  final cli = parseCliArgs(args);
  final taskId = cli['task'];
  final jailArg = cli['jail'];
  final scripted = cli.containsKey('scripted');
  final sentence = cli['_positional'];
  // P5: `--resume <store-path>` continues a saved session (task + jail come
  // from the envelope meta; the world is restored idle-resumable and a fresh
  // snapshot persists after every loop session). `--session <store-path>`
  // persists WITHOUT resuming — the first half of a save/resume pair.
  final resumePath = cli['resume'];
  final sessionPath = resumePath ?? cli['session'];
  SnapshotStore? store;
  World? restoredWorld;
  String? resumeJail;
  if (sessionPath != null) {
    store = SnapshotStore();
    await store.open(sessionPath);
  }
  if (resumePath != null) {
    final envelope = await store!.loadEnvelope('current');
    final meta = (envelope['meta'] as Map?) ?? const {};
    final restoredTask = meta['task'] as String?;
    resumeJail = meta['jail'] as String?;
    if (restoredTask == null || resumeJail == null) {
      stderr.writeln(
        'resume: the session envelope carries no task/jail meta — '
        'cannot resume.',
      );
      exit(66);
    }
    restoredWorld = await store.load('current');
    stderr.writeln(
      '[resume] session loaded from $resumePath '
      '(task $restoredTask, jail $resumeJail)',
    );
  }
  final runs = resumePath != null
      ? 1 // one continuation per resume invocation
      : int.tryParse(cli['runs'] ?? '') ?? 3;
  // M0/D8 — the free-sentence oracle: --check overrides, else the workspace
  // convention resolved in the delegated jail (--jail). No jail → the legacy
  // bare-file fallback (dart run main.dart); nothing resolvable in a
  // provided workspace is an honest exit(64), never an invented criterion.
  final check = cli['check'] == null
      ? null
      : splitCheckCommand(cli['check']!);
  final workspaceDir = jailArg != null
      ? (Directory(jailArg)..createSync(recursive: true))
      : (resumeJail != null ? Directory(resumeJail) : null);
  final CodingAgentTask task;
  try {
    task = taskId != null
        ? (codingAgentTasks[taskId] ??
              (throw ArgumentError.value(
                taskId,
                'task',
                'unknown task; available: ${codingAgentTasks.keys.join(", ")}',
              )))
        : taskFromSentence(
            sentence!,
            check: check,
            workspace: workspaceDir,
          );
  } on StateError catch (e) {
    stderr.writeln('task: ${e.message}');
    exit(64);
  }
  // P1 dogfooding: `--backend open_router --model <or/model>` runs the SAME
  // loop with an OpenRouter model (native tool_calls, session-per-decision
  // codec). The backend label names the model (K discipline).
  final backendArg =
      cli['backend'] ?? (scripted ? _backendScripted : _backendAfm);
  final openRouter = backendArg == 'open_router';
  final orModel = cli['model'] ?? _defaultOpenRouterModel;

  if (taskId == null && sentence == null) {
    stderr.writeln(
      'usage: dart run bin/coding_agent.dart "<task sentence>" '
      '[--jail <dir>] [--check <command>] [--task <suite-id>] [--runs 3] '
      '[--scripted]',
    );
    exit(64);
  }

  final backend = openRouter ? 'open_router:$orModel' : backendArg;

  // P6 — NDJSON transport (--json): stdout streams one JSON object per line
  // (run_start / decision / pulse / run_end / summary). The harness core
  // learns no transport (D5): telemetry wraps the HANDLER here in the host.
  final jsonOut = cli.containsKey('json');
  void emit(Map<String, Object?> event) {
    if (jsonOut) stdout.writeln(jsonEncode(event));
  }

  if (!scripted && !openRouter) {
    final client = AppleFoundationNativeClient();
    await client.load();
    if (!await client.refreshAvailability()) {
      stderr.writeln(
        'Apple Foundation Model unavailable. '
        'Re-run with --scripted or --backend open_router for the LLM proofs '
        '(on-device claims stay UNTESTED, never PASS).',
      );
      exit(2);
    }
  }

  final runsDir = resolveRunsDirectory();

  final results = <CodingAgentRunResult>[];
  for (var i = 1; i <= runs; i++) {
    final jail = jailArg == null
        ? await Directory.systemTemp.createTemp('coding_agent_')
        : (runs == 1
                ? (Directory(jailArg)..createSync(recursive: true))
                : Directory('${jailArg}_run$i')
            ..createSync(recursive: true));
    try {
      ModelRouter? router;
      if (openRouter) {
        final apiKey = Platform.environment['OPENROUTER_API_KEY'];
        if (apiKey == null || apiKey.isEmpty) {
          stderr.writeln('OPENROUTER_API_KEY not set.');
          exit(2);
        }
        router = ModelRouter(
          inferenceClientsBuilders: {
            OpenRouterModelNames.openRouter: () => OpenRouterInferenceClient(
              apiKey: apiKey,
              defaultModel: orModel,
            ),
          },
        );
        final modelId = ModelId('coding_agent');
        router.models[modelId] = Model(
          id: modelId,
          name: OpenRouterModelNames.openRouter,
        );
      } else if (!scripted) {
        router = ModelRouter(
          inferenceClientsBuilders: {
            DefaultModelNames.appleFoundation: () =>
                AppleFoundationNativeClient(),
          },
        );
        final modelId = ModelId('coding_agent');
        router.models[modelId] = Model(
          id: modelId,
          name: DefaultModelNames.appleFoundation,
        );
      }
      emit({
        'type': 'run_start',
        'run': i,
        'task': task.id,
        'backend': backend,
        'jail': jail.path,
        'resumed': restoredWorld != null,
      });
      final result = await runCodingAgentOnce(
        task: task,
        jail: jail,
        handler: _wrapTelemetry(
          scripted
              ? ScriptedSuiteHandler(taskId: task.id)
              : DefaultGenerationHandler(router: router!),
          jsonOut: jsonOut,
          run: i,
          emit: emit,
        ),
        backend: backend,
        // J1.5.5: Ctrl-C during an on-device run still leaves a post-mortem.
        onRecorder: wireSigintDump,
        // P3 (revised): host write gate — diff/review before bytes land.
        // Default (no flag): apply immediately, zero behavior change.
        writeGateMode: cli.containsKey('diff-gate')
            ? WriteGateMode.review
            : null,
        autoApprove: cli.containsKey('auto-approve'),
        // P5: restore + persist the session around every loop session.
        restoredWorld: restoredWorld,
        onSnapshot: store == null
            ? null
            : (liveWorld) async => store!.save(
                liveWorld,
                name: 'current',
                meta: {'task': task.id, 'jail': jail.path},
              ),
      );
      results.add(result);
      final logFile = writeRunLog(
        runsDir,
        'coding_agent${scripted ? "_scripted" : "_afm"}_run$i.log',
        formatRunLog(result),
      );
      final humanLine =
          '[$backend] ${task.id} run $i/$runs: '
          '${result.passed ? "PASS" : "FAIL"} '
          '(decisions ${result.decisions}, rounds ${result.toolRounds}, '
          'tokens ${result.projectionTokens}, '
          'moves ${result.moves.values.fold(0, (a, b) => a + b)}) '
          '→ ${logFile.path}';
      // P6: in NDJSON mode stdout IS the transport — human lines go to stderr.
      jsonOut ? stderr.writeln(humanLine) : stdout.writeln(humanLine);
      (jsonOut ? stderr : stdout).writeln(
        '  final gate: '
        '${[for (final c in result.finalGate) c.detail].join(" | ")}',
      );
      if (jsonOut) {
        emit({
          'type': 'pulse',
          'run': i,
          'text': result.pulseText,
        });
        emit({
          'type': 'run_end',
          'run': i,
          'task': task.id,
          'backend': backend,
          'verdict': result.passed ? 'PASS' : 'FAIL',
          'decisions': result.decisions,
          'tool_rounds': result.toolRounds,
          'tokens': result.projectionTokens,
          'moves': result.moves,
          'gate': [for (final c in result.finalGate) c.detail],
          'failure_class': result.failureClass,
          'wall_clock_ms': result.wallClock.inMilliseconds,
        });
      }
    } finally {
      if (jailArg == null && resumeJail == null) {
        jail.deleteSync(recursive: true);
      }
    }
  }

  // Summary row (B8) — appended to the evidence dir + printed.
  final summary = formatSummary(
    backend: backend,
    taskId: task.id,
    runs: runs,
    passes: results.where((r) => r.passed).length,
    results: results,
  );
  writeRunLog(runsDir, 'coding_agent_afm_summary.log', '$summary\n');
  if (jsonOut) {
    emit({
      'type': 'summary',
      'row': summary,
      'passed': results.where((r) => r.passed).length,
      'runs': runs,
    });
  } else {
    stdout
      ..writeln(summary)
      ..writeln('(logs in ${runsDir.path}/)');
  }
  exit(results.any((r) => r.passed) ? 0 : 1);
}

/// P6 — decision-level telemetry: observes every generation the handler
/// returns and emits one NDJSON `decision` event per tool-call turn. Pure
/// observation: the response flows to the world unchanged (the handler never
/// executes tools).
class _NdjsonTelemetryHandler implements GenerationHandler {
  _NdjsonTelemetryHandler(this._inner, {required this.run, required this.emit});
  final GenerationHandler _inner;
  final int run;
  final void Function(Map<String, Object?> event) emit;
  int _seq = 0;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final response = await _inner.generate(world, request);
    // One `decision` event per generation turn. The tool calls ride on the
    // RETURNED response (ADR 0002: the actorAct wrapper re-sends it onto the
    // channel) — the native AFM path carries every tool call there. Channel
    // observation is racy (processResponsesSystem drains concurrently), so
    // telemetry never depends on channel contents.
    _seq++;
    emit({
      'type': 'decision',
      'run': run,
      'seq': _seq,
      'actor': response.actorEntity.toString(),
      if (response.error.isNotEmpty) 'error': response.error,
      'responses_sent_delta':
          world.events.stats<ActorGenerateResponse>().sent - _lastSent,
      'tool_calls': [
        for (final call in response.toolCalls)
          {'name': call.name.value, 'args': call.arguments},
      ],
    });
    _lastSent = world.events.stats<ActorGenerateResponse>().sent;
    return response;
  }

  int _lastSent = 0;
}

GenerationHandler _wrapTelemetry(
  GenerationHandler inner, {
  required bool jsonOut,
  required int run,
  required void Function(Map<String, Object?> event) emit,
}) => jsonOut
    ? _NdjsonTelemetryHandler(inner, run: run, emit: emit)
    : inner;
