// ignore_for_file: lines_longer_as_80_chars

/// ADR 0027 amendment — CONSENT PLANS: one bounded grant covering a class
/// of writes/edits, host-side policy INVISIBLE to the model. Deny-by-
/// default outside the plan is untouched; every plan answer is audited.
/// LLM-free (scripted mover).
library;

import 'dart:io';

import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';

Future<Directory> _fixture() async {
  final dir = await Directory.systemTemp.createTemp('consent_plan_');
  // Bare-file workspace: the convention resolves to `dart run main.dart`.
  File('${dir.path}/notes.md').writeAsStringSync('# Notes\n\nscratch\n');
  File('${dir.path}/report.md').writeAsStringSync('# Report\n\nbody\n');
  File('${dir.path}/main.dart')
    .writeAsStringSync("void main() { print('ok'); }\n");
  return dir;
}

Future<(AcpStopReason, String)> _writeNotes(HarnessAcpBackend backend,
    String sid, String content) async {
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

  test('consent plan: an in-scope write lands with ZERO permission '
      'round-trips, audited', () async {
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
    final sid = await backend.createSession(AcpSessionNewRequest(cwd: ws.path));
    backend.setConsentPlan(
      sid,
      const ConsentPlan(pathGlob: 'notes\\.md', verbs: {'write'}, maxUses: 3),
    );

    final (stop, out) = await _writeNotes(
      backend,
      sid,
      r'# Notes\n\nplan-allowed write landed\n',
    );
    expect(stop, AcpStopReason.endTurn, reason: 'output: $out');
    expect(
      File('${ws.path}/notes.md').readAsStringSync(),
      contains('plan-allowed write landed'),
    );
    expect(
      permissionCalls,
      isEmpty,
      reason: 'the plan answers in-scope writes BEFORE the client is asked',
    );
    expect(backend.consentAudit(sid), hasLength(1));
    expect(backend.consentAudit(sid).single, contains('plan-allowed write'));
    expect(out, contains('[write_review]'));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('consent plan: out-of-scope paths still round-trip to the client '
      '(deny-by-default outside the plan)', () async {
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
    final sid = await backend.createSession(AcpSessionNewRequest(cwd: ws.path));
    // The plan covers only notes.md — lib/greet.dart is OUTSIDE it.
    backend.setConsentPlan(
      sid,
      const ConsentPlan(pathGlob: 'notes\\.md', verbs: {'write'}, maxUses: 3),
    );
    final updates = StringBuffer();
    await backend.prompt(
      AcpPromptRequest(
        sessionId: sid,
        prompt: [
          AcpTextBlock(
            '[scan] '
            'harness_fs_write {"path": "report.md", "content": '
            '"# Report\\n\\nout-of-scope write\\n"}',
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
    expect(asked, 1, reason: 'out-of-scope writes still ask the client');
    expect(
      File('${ws.path}/report.md').readAsStringSync(),
      contains('out-of-scope write'),
      reason: 'the client allowed, so it lands — the plan never blocks, '
          'it only answers in place of the prompt',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('consent plan: maxUses is a HARD cap — the grant exhausts', () async {
    final backend = HarnessAcpBackend(
      backend: 'open_router',
      meaningProfile: true,
      scripted: true,
    );
    final permissionCalls = <AcpPermissionRequest>[];
    backend.attachPermissionRequester((request) async {
      permissionCalls.add(request);
      return AcpPermissionOutcome.allow;
    });
    final sid = await backend.createSession(AcpSessionNewRequest(cwd: ws.path));
    backend.setConsentPlan(
      sid,
      const ConsentPlan(pathGlob: 'notes\\.md', verbs: {'write'}, maxUses: 1),
    );
    await _writeNotes(backend, sid, '# one\\n');
    expect(permissionCalls, isEmpty);
    await _writeNotes(backend, sid, '# two\\n');
    expect(
      permissionCalls,
      hasLength(1),
      reason: 'after maxUses the plan is exhausted — the client decides '
          'again (a plan is NOT an unbounded grant)',
    );
    expect(File('${ws.path}/notes.md').readAsStringSync(), contains('# two'));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
