// ignore_for_file: lines_longer_than_80_chars

/// B3 — ONE entry point for AFM Dart coding.
///
/// ```sh
/// dart run bin/coding_agent.dart "<task sentence>" [--jail <dir>] [--task <suite-id>] [--runs 3] [--scripted]
///                      [--diff-gate] [--auto-approve]
/// ```
///
/// - `--task intent_03_bookmark_macros` — the J1.4 gate (intent oracle).
/// - `--task bugfix_01_off_by_one` — run-graded bugfix (runs-checker).
/// - a bare sentence — run-graded build (`dart run main.dart` terminal proof).
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

import 'dart:io';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_harness/benchmark_api.dart'
    show ScriptedSuiteHandler;
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
const _defaultOpenRouterModel = 'poolside/laguna-xs-2.1:free';

Future<void> main(List<String> args) async {
  final cli = parseCliArgs(args);
  final runs = int.tryParse(cli['runs'] ?? '') ?? 3;
  final taskId = cli['task'];
  final jailArg = cli['jail'];
  final scripted = cli.containsKey('scripted');
  final sentence = cli['_positional'];
  // P1 dogfooding: `--backend open_router --model <or/model>` runs the SAME
  // loop with an OpenRouter model (native tool_calls, session-per-decision
  // codec). The backend label names the model (K discipline).
  final backendArg = cli['backend'] ?? (scripted ? _backendScripted : _backendAfm);
  final openRouter = backendArg == 'open_router';
  final orModel = cli['model'] ?? _defaultOpenRouterModel;

  if (taskId == null && sentence == null) {
    stderr.writeln(
      'usage: dart run bin/coding_agent.dart "<task sentence>" '
      '[--task <suite-id>] [--jail <dir>] [--runs 3] [--scripted]',
    );
    exit(64);
  }

  final backend =
      openRouter ? 'open_router:$orModel' : backendArg;
  final task = taskId != null
      ? (codingAgentTasks[taskId] ??
            (throw ArgumentError.value(
              taskId,
              'task',
              'unknown task; available: ${codingAgentTasks.keys.join(", ")}',
            )))
      : taskFromSentence(sentence!);

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
            : Directory('${jailArg}_run$i')..createSync(recursive: true));
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
            OpenRouterModelNames.openRouter: () =>
                OpenRouterInferenceClient(apiKey: apiKey, defaultModel: orModel),
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
      final result = await runCodingAgentOnce(
        task: task,
        jail: jail,
        handler: scripted
            ? ScriptedSuiteHandler(taskId: task.id)
            : DefaultGenerationHandler(router: router!),
        backend: backend,
        // J1.5.5: Ctrl-C during an on-device run still leaves a post-mortem.
        onRecorder: wireSigintDump,
        // P3 (revised): host write gate — diff/review before bytes land.
        // Default (no flag): apply immediately, zero behavior change.
        writeGateMode: cli.containsKey('diff-gate')
            ? WriteGateMode.review
            : null,
        autoApprove: cli.containsKey('auto-approve'),
      );
      results.add(result);
      final logFile = writeRunLog(
        runsDir,
        'coding_agent${scripted ? "_scripted" : "_afm"}_run$i.log',
        formatRunLog(result),
      );
      stdout
        ..writeln(
          '[$backend] ${task.id} run $i/$runs: '
          '${result.passed ? "PASS" : "FAIL"} '
          '(decisions ${result.decisions}, rounds ${result.toolRounds}, '
          'tokens ${result.projectionTokens}, '
          'moves ${result.moves.values.fold(0, (a, b) => a + b)}) '
          '→ ${logFile.path}',
        )
        ..writeln('  final gate: '
            '${[for (final c in result.finalGate) c.detail].join(" | ")}');
    } finally {
      if (jailArg == null) {
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
  stdout
    ..writeln(summary)
    ..writeln('(logs in ${runsDir.path}/)');
  exit(results.any((r) => r.passed) ? 0 : 1);
}
