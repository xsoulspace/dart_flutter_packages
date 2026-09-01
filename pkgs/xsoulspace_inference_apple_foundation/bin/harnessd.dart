// ignore_for_file: lines_longer_than_80_chars

/// Stage N3 — `harnessd`: the agentic harness as a long-lived ACP agent.
///
/// ```sh
/// dart run bin/harnessd.dart [--backend open_router] [--model <or/model>]
/// ```
///
/// Any ACP client (Zed, pi via stdio JSON-RPC, last_answer) can then:
/// 1. `initialize` → capability negotiation;
/// 2. `session/new` with `cwd` = the delegated workspace;
/// 3. `session/prompt` with a free task sentence — D8 workspace-convention
///    oracle, no hardcoded checkers;
/// 4. stream `session/update`s while the squad works; verdict chunk at end.
///
/// The daemon is transport + host policy (D5): the core learns no ACP.
library;

import 'dart:io';

import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';

import 'package:xsoulspace_inference_apple_foundation/src/harness_acp_backend.dart';

Future<void> main(List<String> args) async {
  String? backend;
  String? model;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--backend' && i + 1 < args.length) backend = args[++i];
    if (args[i] == '--model' && i + 1 < args.length) model = args[++i];
  }
  stderr.writeln(
    '[harnessd] starting (backend ${backend ?? "open_router"}'
    '${model == null ? "" : ", model $model"}) — ACP v1 over stdio',
  );
  final server = AcpStdioServer(
    backend: HarnessAcpBackend(
      backend: backend ?? 'open_router',
      model: model ?? 'deepseek/deepseek-v4-flash-0731',
    ),
  );
  await server.run();
}
