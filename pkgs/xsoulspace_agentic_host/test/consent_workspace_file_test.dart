// ignore_for_file: lines_longer_as_80_chars

/// R9.1 (last_answer redefined plan) — the WORKSPACE-LEVEL consent policy:
/// `<workspace>/.harnessd/consent.json` applies to every new session
/// automatically (host-side, invisible to the model). Absent/malformed →
/// deny-by-default unchanged. LLM-free (scripted mover), same pattern as
/// `consent_plan_test.dart`.
library;

import 'dart:io';

import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';

Future<Directory> _fixture() async {
  final dir = await Directory.systemTemp.createTemp('consent_ws_');
  File('${dir.path}/notes.md').writeAsStringSync('# Notes\n\nscratch\n');
  File('${dir.path}/main.dart')
    .writeAsStringSync("void main() { print('ok'); }\n");
  return dir;
}

Future<(AcpStopReason, String)> _writeNotes(
  HarnessAcpBackend backend,
  String sid,
  String content,
) async {
  final updates = StringBuffer();
  final stop = await backend.prompt(
    AcpPromptRequest(
      sessionId: sid,
      prompt: [
        AcpTextBlock(
          '[scan] '
          'harness_fs_write {"path": "notes.md", "content": "$content"}',
        ),
      ],
    ),
    emit: (u) {
      if (u is AgentMessageChunk) {
        updates.write(
          u.content is AcpTextBlock ? (u.content as AcpTextBlock).text : '',
        );
      }
    },
    isCancelled: () => false,
  );
  return (stop, updates.toString());
}

void main() {
  late Directory ws;

  setUp(() async {
    ws = await _fixture();
  });
  tearDown(() {
    try {
      ws.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  });

  test('a workspace consent file auto-applies: in-scope write lands with '
      'ZERO permission round-trips, audited', () async {
    // Workspace-level policy data — written by the operator/UI, honored by
    // the daemon at session creation.
    final configDir = Directory('${ws.path}/.harnessd')..createSync();
    File('${configDir.path}/consent.json').writeAsStringSync(
      '{"pathGlob": "notes\\\\.md", "verbs": ["write"], "maxUses": 3}',
    );

    final backend = HarnessAcpBackend(
      backend: 'open_router',
      meaningProfile: true,
      scripted: true,
    );
    final permissionCalls = <AcpPermissionRequest>[];
    backend.attachPermissionRequester((request) async {
      permissionCalls.add(request);
      return AcpPermissionOutcome.reject; // the plan must answer FIRST
    });
    final sid = await backend.createSession(
      AcpSessionNewRequest(cwd: ws.path),
    );

    final (stop, out) = await _writeNotes(
      backend,
      sid,
      r'# Notes\n\nworkspace-plan write landed\n',
    );
    expect(stop, AcpStopReason.endTurn, reason: 'output: $out');
    expect(
      File('${ws.path}/notes.md').readAsStringSync(),
      contains('workspace-plan write landed'),
    );
    expect(
      permissionCalls,
      isEmpty,
      reason: 'the workspace plan answers in-scope writes '
          'before the client is asked',
    );
    expect(backend.consentAudit(sid), hasLength(1));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('no consent file: deny-by-default unchanged (the client is asked)',
      () async {
    final backend = HarnessAcpBackend(
      backend: 'open_router',
      meaningProfile: true,
      scripted: true,
    );
    var asked = 0;
    backend.attachPermissionRequester((request) async {
      asked++;
      return AcpPermissionOutcome.allow;
    });
    final sid = await backend.createSession(
      AcpSessionNewRequest(cwd: ws.path),
    );
    await _writeNotes(backend, sid, r'# Notes\n\nclient-allowed\n');
    expect(
      asked,
      1,
      reason: 'without a workspace plan every write round-trips',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('a malformed consent file is honest: no plan, no crash', () async {
    final configDir = Directory('${ws.path}/.harnessd')..createSync();
    File('${configDir.path}/consent.json').writeAsStringSync('{broken');
    expect(ConsentPlan.forWorkspace(ws), isNull);
  });
}
