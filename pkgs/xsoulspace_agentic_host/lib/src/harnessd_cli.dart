// ignore_for_file: lines_longer_as_80_chars

/// Stage N3 + R7c — `harnessd`: the agentic harness as a long-lived ACP agent.
///
/// ```sh
/// dart run <composition-root>/bin/harnessd.dart [--backend <name>]
///     [--model <id>] [--profile meaning] [--scripted] [--remote-mover]
///     [--workspace <path>] [--idle-exit-minutes <n>]
/// ```
///
/// The CLI lives here (ADR 0025 — the ONE canonical host surface, reusable
/// as CLI, SDK or pi extension); the composition root supplies the backend
/// `bindings` (e.g. `apple_foundation_afm` from the AFM bridge package,
/// `open_router` from the OpenRouter client) and may pin the default.
///
/// `--profile meaning` runs every delegated task through the R7
/// meaning-profile surface (repo_etl / meaning_zoom / meaning_impact /
/// edit_symbol / run) — zero `read`, zero `write` moves; the meaning tree
/// is the only code interface (ADR 0023).
///
/// `--scripted` (LLM-free gates): the mover is a directive interpreter.
/// `--remote-mover` (R7 production #4): the daemon runs the harness loop
/// MODEL-LESS — pi's own model decides, round-tripping every decision as
/// `session/propose_move` (typed tool calls back). The two flags are the
/// same pluggable seam: the surface gate never depends on a mover model.
///
/// `--workspace <path>` (R7 production #5 — the persistent daemon):
/// - SINGLE INSTANCE PER WORKSPACE (mandatory — two daemons = two worlds =
///   single-writer broken at process level): an exclusive file lock at
///   `<workspace>/.dart_tool/harnessd/harnessd.lock`; a second daemon for
///   the same workspace exits non-zero immediately;
/// - a Unix-socket ACP listener at `<workspace>/.dart_tool/harnessd/
///   harnessd.sock` speaks the SAME newline-delimited JSON-RPC as stdio —
///   a second client (another pi session) ATTACHES to the warm daemon and
///   continues the per-workspace world (zero re-scan — the tree is world
///   state, a mechanical mtime tick is all a new prompt pays);
/// - `--idle-exit-minutes <n>` (default 10 with `--workspace`): exit when
///   no session has been active for n minutes (keep-warm between pi
///   sessions, no zombie daemons).
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

import 'dart:async';
import 'dart:io';

import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';

import 'harness_acp_backend.dart';

/// Runs the `harnessd` daemon (ACP v1 over stdio, plus a unix socket in
/// workspace mode). [bindings] are the backends the composition root
/// offers via `--backend`; [defaultBackend] is used when `--backend` is
/// absent (falling back to the single registered backend, or
/// `open_router` when several are registered).
Future<void> runHarnessdCli(
  List<String> args, {
  required Map<String, HarnessBackendBinding> bindings,
  String? defaultBackend,
}) async {
  String? backend;
  String? model;
  String? workspace;
  var meaningProfile = false;
  var scripted = false;
  var remoteMover = false;
  int? idleExitMinutes;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--backend' && i + 1 < args.length) backend = args[++i];
    if (args[i] == '--model' && i + 1 < args.length) model = args[++i];
    if (args[i] == '--profile' && i + 1 < args.length) {
      meaningProfile = args[++i] == 'meaning';
    }
    if (args[i] == '--workspace' && i + 1 < args.length) workspace = args[++i];
    if (args[i] == '--idle-exit-minutes' && i + 1 < args.length) {
      idleExitMinutes = int.tryParse(args[++i]);
    }
    if (args[i] == '--scripted') scripted = true;
    if (args[i] == '--remote-mover') remoteMover = true;
  }
  // AFM-first on macOS when the composition root registers the AFM
  // binding; otherwise the single registered backend wins.
  final resolvedBackend =
      backend ??
      defaultBackend ??
      (bindings.containsKey('apple_foundation_afm')
          ? 'apple_foundation_afm'
          : bindings.keys.firstOrNull ?? 'open_router');

  // R7 production #5 — SINGLE-INSTANCE PER WORKSPACE (mandatory): an
  // exclusive lock file; a second daemon for the same workspace exits
  // non-zero BEFORE touching any state (two worlds = single-writer broken).
  RandomAccessFile? lock;
  if (workspace != null) {
    final dir = Directory('$workspace/.dart_tool/harnessd')
      ..createSync(recursive: true);
    try {
      lock = File('${dir.path}/harnessd.lock').openSync(mode: FileMode.write);
      lock.lockSync(FileLock.exclusive); // throws when a peer holds it
      lock
        ..writeStringSync('$pid\n')
        ..flushSync();
    } on Object {
      lock?.closeSync();
      stderr.writeln(
        '[harnessd] REFUSED: a daemon is already running for workspace '
        '$workspace (single-instance is mandatory — two daemons = two '
        'worlds = single-writer broken). Connect to the running one '
        '(${dir.path}/harnessd.sock).',
      );
      exit(2);
    }
  }

  stderr.writeln(
    '[harnessd] starting (backend $resolvedBackend'
    '${model == null ? "" : ", model $model"}'
    '${meaningProfile ? ", profile meaning" : ""}'
    '${scripted ? ", scripted mover" : ""}'
    '${remoteMover ? ", REMOTE MOVER (pi decides)" : ""}'
    '${workspace == null ? "" : ", workspace $workspace"}'
    ') — ACP v1 over stdio'
    '${workspace == null ? "" : " + unix socket"}',
  );

  final backendInstance = HarnessAcpBackend(
    backend: resolvedBackend,
    bindings: bindings,
    model: model ?? bindings[resolvedBackend]?.defaultModel ?? '',
    meaningProfile: meaningProfile,
    scripted: scripted,
    remoteMover: remoteMover,
  );

  // R7 production #5 — keep-warm + idle-exit: the daemon survives session
  // ends (the WORLD stays in this process; the snapshot store is crash
  // recovery only) and exits when nobody has used it for N minutes.
  Timer? idleTimer;
  final idleLimit = idleExitMinutes ?? 10;
  void bumpIdle() {
    if (workspace == null) return;
    idleTimer?.cancel();
    idleTimer = Timer(Duration(minutes: idleLimit), () {
      stderr.writeln(
        '[harnessd] idle-exit (no session activity for $idleLimit minutes)',
      );
      exit(0);
    });
  }

  backendInstance.onActivity = bumpIdle;
  bumpIdle();

  // R7 production #5 — the socket ACP listener: a second client (another
  // pi session) ATTACHES to the warm daemon over the SAME JSON-RPC
  // framing; sessions are keyed per workspace, so the second session
  // continues the live world (zero re-scan). macOS caps unix-socket
  // paths at ~104 chars, so the socket lives at a SHORT hashed path
  // under the temp dir; the workspace keeps a POINTER file for discovery.
  File? socketPointer;
  ServerSocket? socketServer;
  if (workspace != null) {
    final socketPath = '/tmp/harnessd-${_workspaceHash(workspace)}.sock';
    final socketFile = File(socketPath);
    if (socketFile.existsSync()) socketFile.deleteSync(); // stale peer
    socketServer = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    socketPointer = File('$workspace/.dart_tool/harnessd/harnessd.sock')
      ..writeAsStringSync('$socketPath\n');
    stderr.writeln(
      '[harnessd] socket listening: $socketPath (pointer '
      '${socketPointer.path})',
    );
    socketServer.listen((client) {
      stderr.writeln('[harnessd] client attached over socket');
      // Each connection is a FULL ACP server over the shared backend —
      // sessions are keyed per workspace, so a second client continues
      // the live world instead of re-deriving it. The socket chunk type
      // is cast to List<int>: Stream<Uint8List>.transform(utf8.decoder)
      // fails a runtime generic check (measured — the mapped stream is
      // the fix).
      final connection = AcpStdioServer(
        backend: backendInstance,
        inputStream: client.map<List<int>>((d) => d),
        outputSink: client,
      );
      unawaited(
        connection.run().then(
          (_) => stderr.writeln('[harnessd] socket client detached'),
        ),
      );
    });
  }

  final server = AcpStdioServer(backend: backendInstance);
  try {
    await server.run();
  } finally {
    // R7 production #5 — keep-warm: in workspace mode the stdio transport
    // ending (the spawning pi exited) does NOT terminate the daemon — the
    // socket keeps serving and the idle-exit timer owns shutdown.
    if (workspace == null) {
      idleTimer?.cancel();
      await socketServer?.close();
      lock?.closeSync();
      socketPointer?.deleteSync();
    }
  }
  if (workspace != null) {
    stderr.writeln(
      '[harnessd] stdio transport ended — keeping warm for socket clients '
      '(idle-exit after $idleLimit minutes)',
    );
    await Completer<void>().future; // the idle timer exit(0)s
  }
}

/// Stable short socket name per workspace (unix sockets cap at ~104
/// chars — workspaces exceed that; the workspace path itself is hashed
/// with FNV-1a, never stored in the name).
String _workspaceHash(String workspace) {
  var hash = 0xcbf29ce484222325;
  for (final code in workspace.codeUnits) {
    hash ^= code;
    hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0').substring(0, 12);
}
