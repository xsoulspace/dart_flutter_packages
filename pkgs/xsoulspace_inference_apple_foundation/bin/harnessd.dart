// ignore_for_file: lines_longer_as_80_chars

/// Stage N3 + R7c — `harnessd`: the agentic harness as a long-lived ACP agent.
///
/// ```sh
/// dart run bin/harnessd.dart [--backend apple_foundation_afm|open_router]
///                            [--model <or/model>] [--profile meaning]
/// ```
///
/// Default backend (R7c item 6, AFM-first North Star): `apple_foundation_afm`
/// on macOS; hosted OpenRouter is the EXPLICIT escalation choice
/// (`--backend open_router`, needs OPENROUTER_API_KEY).
///
/// `--profile meaning` runs every delegated task through the R7
/// meaning-profile surface (repo_etl / meaning_zoom / meaning_impact /
/// edit_symbol / run) — zero `read`, zero `write` moves; the meaning tree
/// is the only code interface (ADR 0023).
///
/// Any ACP client (Zed, pi via stdio JSON-RPC, last_answer) can then:
/// 1. `initialize` → capability negotiation (loadSession: true);
/// 2. `session/new` with `cwd` = the delegated workspace — per-workspace
///    persistence: the world (and the code tree) stay warm; a snapshot
///    store under `.dart_tool/harnessd_store` resumes beats/verdicts/
///    budgets across daemon restarts;
/// 3. `session/prompt` with a free task sentence — D8 workspace-convention
///    oracle, no hardcoded checkers; a mechanical tree-refresh tick runs
///    before every prompt;
/// 4. stream `session/update`s while the squad works; verdict chunk at end;
/// 5. `session/cancel` — real cancellation (loop flag + `xs_fm_cancel`).
///
/// The daemon is transport + host policy (D5): the core learns no ACP.
library;

import 'dart:io';

import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';

import 'package:xsoulspace_inference_apple_foundation/src/harness_acp_backend.dart';

Future<void> main(List<String> args) async {
  String? backend;
  String? model;
  var meaningProfile = false;
  var scripted = false;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--backend' && i + 1 < args.length) backend = args[++i];
    if (args[i] == '--model' && i + 1 < args.length) model = args[++i];
    if (args[i] == '--profile' && i + 1 < args.length) {
      meaningProfile = args[++i] == 'meaning';
    }
    if (args[i] == '--scripted') scripted = true;
  }
  // R7c item 6: AFM-first on macOS; hosted OpenRouter is the explicit
  // escalation flag.
  final resolvedBackend = backend ??
      (Platform.isMacOS ? 'apple_foundation_afm' : 'open_router');
  stderr.writeln(
    '[harnessd] starting (backend $resolvedBackend'
    '${model == null ? "" : ", model $model"}'
    '${meaningProfile ? ", profile meaning" : ""}'
    '${scripted ? ", scripted mover" : ""}) — ACP v1 over stdio',
  );
  final server = AcpStdioServer(
    backend: HarnessAcpBackend(
      backend: resolvedBackend,
      model: model ?? 'deepseek/deepseek-v4-flash-0731',
      meaningProfile: meaningProfile,
      scripted: scripted,
    ),
  );
  await server.run();
}
