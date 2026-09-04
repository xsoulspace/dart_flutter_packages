// ignore_for_file: lines_longer_than_80_chars

/// R7 PRODUCTION #4 GATE — the remote mover (pi joins as the session
/// actor's brain) + PRODUCTION #5 — the persistent daemon lifecycle.
///
/// #4 (LLM-free): the daemon runs the harness loop with NO mover model;
/// every decision round-trips to the CLIENT as `session/propose_move`
/// (bounded cut + tool schemas out, typed tool calls back). Gates:
/// - ONE decision = ONE propose_move round-trip;
/// - budgets are consumed IN-WORLD (the proposal carries the live
///   ToolRoundCount/AttemptCount — the loop, its budgets and oracles are
///   unchanged; only WHO decides is pluggable);
/// - cancel works MID-decision (a decision blocked awaiting the client's
///   response unblocks and the turn ends cancelled — never a hang);
/// - the bounded protocol: the proposal carries the cut + schemas only —
///   no file text ever leaves the daemon.
///
/// #5 (in-process socket wiring): a second ACP connection attaches to the
/// SAME backend over a unix socket and continues the per-workspace world.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_inference_apple_foundation/src/harness_acp_backend.dart';

import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';

/// A fixture workspace with a GREEN convention (D8: pubspec + tests →
/// `dart test`) so a scan-only remote-mover session grades PASS.
Future<Directory> _greenWorkspace() async {
  final dir = await Directory.systemTemp.createTemp('r7_remote_mover_');
  File('${dir.path}/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      'name: remote_mover\nenvironment:\n  sdk: ^3.0.0\ndev_dependencies:\n  test: any\n',
    );
  File('${dir.path}/lib/greet.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync("String greet(String name) => 'hello ' + name;\n");
  File('${dir.path}/test/greet_test.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      "import 'package:test/test.dart';\n"
      "import 'package:remote_mover/greet.dart';\n"
      "void main() { test('greet', () { expect(greet('x'), 'hello x'); }); }\n",
    );
  await Process.run('dart', ['pub', 'get'], workingDirectory: dir.path);
  return dir;
}

/// The scripted CLIENT-as-mover (LLM-free): answers one propose_move per
/// decision — first the scan move, then done. Records every proposal for
/// the gate assertions.
class _ScriptedClientMover {
  final proposals = <AcpMoveProposal>[];
  final Completer<void> scanned = Completer<void>();
  var done = false;

  Future<AcpMoveResponse> respond(AcpMoveProposal proposal) async {
    proposals.add(proposal);
    if (proposals.length == 1) {
      return AcpMoveResponse(
        toolCalls: [
          const AcpMoveToolCall(
            name: 'repo_etl',
            arguments: {'action': 'scan'},
          ),
        ],
        text: 'scanning the workspace',
      );
    }
    // Second decision onward: done — the goal gate grades the workspace.
    done = true;
    if (!scanned.isCompleted) scanned.complete();
    return const AcpMoveResponse(text: 'scanned; the suite is green');
  }
}

void main() {
  late Directory ws;

  setUp(() async {
    ws = await _greenWorkspace();
  });
  tearDown(() {
    try {
      ws.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  });

  test('remote mover: one decision = one propose_move round-trip; budgets '
      'consumed in-world; bounded protocol only', () async {
    final backend = HarnessAcpBackend(
      backend: 'open_router',
      meaningProfile: true,
      remoteMover: true,
    );
    final mover = _ScriptedClientMover();
    backend.attachMoveProposer(mover.respond);
    final sid = await backend.createSession(AcpSessionNewRequest(cwd: ws.path));
    final updates = <String>[];
    final stop = await backend.prompt(
      AcpPromptRequest(
        sessionId: sid,
        prompt: const [
          AcpTextBlock(
            'Scan the workspace and confirm it is '
            'green.',
          ),
        ],
      ),
      emit: (u) {
        final c = switch (u) {
          AgentMessageChunk(:final content) => content,
          _ => null,
        };
        if (c is AcpTextBlock) updates.add(c.text);
      },
      isCancelled: () => false,
    );
    expect(stop, AcpStopReason.endTurn);
    // THE DECISION ECONOMY: exactly ONE decision per propose_move — the
    // two scripted responses were two decisions, and the verdict chunk
    // must count the same (one truth: the meter over the loop).
    expect(mover.proposals, hasLength(2));
    expect(
      updates.join(),
      contains('decisions 2'),
      reason:
          'the in-world decision meter must equal the number of '
          'propose_move round-trips',
    );
    // Budgets consumed IN-WORLD: the SECOND proposal carries the live
    // round count from the world's components (the scan consumed one
    // tool round) — the client never owns the budget.
    final first = mover.proposals.first.budgets;
    final second = mover.proposals.last.budgets;
    expect(first['max_tool_rounds'], 12);
    expect(
      (second['tool_rounds'] as num) >= (first['tool_rounds'] as num),
      isTrue,
      reason: 'round budget advances in the world between decisions',
    );
    // The bounded protocol: cut + schemas + budgets — NO file text.
    for (final p in mover.proposals) {
      expect(p.prompt, isNotEmpty);
      expect(
        p.prompt.contains('hello x'),
        isFalse,
        reason:
            'no file text may reach the client — the cut is a '
            'projection',
      );
      expect(
        p.toolSchemas.map((t) => t['name']),
        containsAll(['repo_etl', 'edit_symbol']),
      );
    }
    // The verdict lands with the in-world decision count.
    // (DecisionMeter counts generate() calls == proposer calls.)
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('remote mover: cancelSession unblocks a decision blocked awaiting the '
      'client — the turn ends cancelled', () async {
    final backend = HarnessAcpBackend(
      backend: 'open_router',
      meaningProfile: true,
      remoteMover: true,
    );
    // The client never answers (a hung model / a hung network): the
    // proposal waits on a never-completed future.
    var blocked = Completer<AcpMoveResponse>();
    backend.attachMoveProposer((proposal) => blocked.future);
    final sid = await backend.createSession(AcpSessionNewRequest(cwd: ws.path));
    final promptFuture = backend.prompt(
      AcpPromptRequest(sessionId: sid, prompt: const [AcpTextBlock('scan')]),
      emit: (u) {},
      isCancelled: () => false,
    );
    // Let the FIRST decision go out and block inside it.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    backend.cancelSession(sid);
    final stop = await promptFuture.timeout(const Duration(minutes: 2));
    expect(
      stop,
      AcpStopReason.cancelled,
      reason:
          'cancel must work MID-decision — the pending propose_move '
          'round-trip unblocks and the turn ends cancelled',
    );
    // The pending proposal was drained (no leaked awaits).
    expect(
      backend.sessionsDebugPendingMoves(sid),
      isEmpty,
      reason: 'cancelSession drains every pending propose_move',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('production #5 socket wiring: a SECOND connection attaches to the '
      'same backend and continues the per-workspace world', () async {
    final backend = HarnessAcpBackend(
      backend: 'open_router',
      meaningProfile: true,
      scripted: true,
    );
    // macOS caps unix-socket paths at ~104 chars — real workspaces exceed
    // that, so the production binary uses a short hashed /tmp socket (see
    // bin/harnessd.dart); the gate uses a short path directly.
    final socketPath = '/tmp/hd_gate_${pid}.sock';
    final socketServer = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    socketServer.listen((client) {
      unawaited(
        AcpStdioServer(
          backend: backend,
          inputStream: client,
          outputSink: client,
        ).run(),
      );
    });
    addTearDown(socketServer.close);

    // Client A over the socket: session + scan prompt (the tree warms).
    final clientA = _SocketAcpClient();
    await clientA.connect(socketPath);
    final createdA = await clientA.call('session/new', {'cwd': ws.path});
    final sidA = createdA['sessionId'] as String;
    final turnA = await clientA.call('session/prompt', {
      'sessionId': sidA,
      'prompt': [
        {'type': 'text', 'text': '[scan]'},
      ],
    });
    expect(turnA['stopReason'], 'end_turn');

    // Client B attaches: SAME session id (per-workspace keying) — the
    // world (and the tree) continue without a re-scan.
    final clientB = _SocketAcpClient();
    await clientB.connect(socketPath);
    final createdB = await clientB.call('session/new', {'cwd': ws.path});
    expect(
      createdB['sessionId'],
      sidA,
      reason: 'the warm daemon continues ONE world per workspace',
    );
    final turnB = await clientB.call('session/prompt', {
      'sessionId': sidA,
      'prompt': [
        {'type': 'text', 'text': '[zoom greet]'},
      ],
    });
    expect(turnB['stopReason'], 'end_turn');
    await clientA.close();
    await clientB.close();
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// A minimal newline-delimited JSON-RPC CLIENT over a unix socket — the
/// same framing the daemon's socket listener speaks.
class _SocketAcpClient {
  Socket? _socket;
  var _buffer = '';
  final _pending = <int, Completer<Map<String, Object?>>>{};
  var _nextId = 1;
  final _updates = <Map<String, Object?>>[];

  Future<void> connect(String path) async {
    final task = await Socket.startConnect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    _socket = await task.socket;
    _socket!.listen((data) {
      _buffer += utf8.decode(data);
      int idx;
      while ((idx = _buffer.indexOf('\n')) >= 0) {
        final line = _buffer.substring(0, idx).trim();
        _buffer = _buffer.substring(idx + 1);
        if (line.isEmpty) continue;
        final msg = jsonDecode(line) as Map<String, Object?>;
        if (msg['id'] != null &&
            (msg['result'] != null || msg['error'] != null)) {
          final pending = _pending.remove(msg['id']);
          if (pending != null) {
            pending.complete(
              (msg['result'] as Map<String, Object?>?) ?? const {},
            );
          }
        } else if (msg['method'] == 'session/request_permission') {
          // The gate client allows (deny-by-default otherwise).
          _socket!.writeln(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': msg['id'],
              'result': {
                'outcome': {'outcome': 'allow', 'optionId': 'allow'},
              },
            }),
          );
        } else if (msg['method'] == 'session/update') {
          _updates.add(msg);
        }
      }
    }, onDone: () {});
    await call('initialize', {'protocolVersion': 1, 'clientCapabilities': {}});
  }

  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> params,
  ) async {
    final id = _nextId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _socket!.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    return completer.future.timeout(const Duration(minutes: 2));
  }

  Future<void> close() async {
    await _socket?.close();
  }
}
