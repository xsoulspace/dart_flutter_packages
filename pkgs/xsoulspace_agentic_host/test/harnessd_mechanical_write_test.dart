// ignore_for_file: lines_longer_than_80_chars

/// ADR 0027 amendment — MECHANICAL WRITES gate: a directive-only
/// `harness_fs_write {…}` prompt in REMOTE-MOVER mode (the production pi
/// path) executes through the review gate — consent round-trip, write,
/// tree reconcile — with ZERO mover involvement.
///
/// Measured failure this locks out: routing the whole-file write through
/// the mover as a graded task ended `mover_refusal: empty move` after a
/// 9-minute wall (547,979 ms) — the mover model refused the huge payload
/// it was never supposed to judge. The content is DATA; the human is the
/// approver; the mover has nothing to decide.
library;

import 'dart:async';
import 'dart:io';

import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';

void main() {
  late Directory ws;

  setUp(() async {
    ws = await Directory.systemTemp.createTemp('mech_write_');
    File('${ws.path}/notes.md').writeAsStringSync('# Notes\n\nscratch\n');
  });
  tearDown(() {
    try {
      ws.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  });

  Future<BackendPromptOutcome> delegate(
    HarnessAcpBackend backend,
    String text,
  ) async {
    final sid = await backend.createSession(
      AcpSessionNewRequest(cwd: ws.path),
    );
    final updates = StringBuffer();
    final stop = await backend.prompt(
      AcpPromptRequest(sessionId: sid, prompt: [AcpTextBlock(text)]),
      isCancelled: () => false,
      emit: (u) {
        if (u is AgentMessageChunk) {
          updates.write(u.content is AcpTextBlock ? (u.content as AcpTextBlock).text : '');
        }
      },
    );
    return (stop: stop, updates: updates.toString());
  }

  test('classifier: pure write payload → mechanical; mixed → never', () {
    expect(
      isMechanicalWriteDirective(
        'harness_fs_write {"path": "a.md", "content": "x"}',
      ),
      isTrue,
    );
    expect(
      isMechanicalWriteDirective(
        'harness_fs_write {"path": "a.md", "content": "x"} '
        'and also verify the workspace',
      ),
      isFalse,
      reason: 'leftover prose = a task — deny-by-default on ambiguity',
    );
    expect(
      isMechanicalWriteDirective(
        'harness_edit {"action": "replace_member_body"} '
        'harness_fs_write {"path": "a.md", "content": "x"}',
      ),
      isFalse,
      reason: 'edit is a mover decision — never mixed into the write path',
    );
    expect(isMechanicalWriteDirective('[scan]'), isFalse);
  });

  test('remote mover + ALLOW: write lands through the review gate, tree reconciles',
      () async {
    final backend = HarnessAcpBackend(
      meaningProfile: true,
      remoteMover: true,
    );
    backend.attachPermissionRequester(
      (request) async {
        expect(request.title, startsWith('write '));
        expect(request.details, contains('+++ b/docs/new_note.md'));
        return AcpPermissionOutcome.allow;
      },
    );
    final r = await delegate(
      backend,
      'harness_fs_write {"path": "docs/new_note.md", "content": '
      '"# New Note\\n\\nmechanical write landed\\n"}',
    );
    expect(r.stop, AcpStopReason.endTurn, reason: r.updates);
    expect(
      File('${ws.path}/docs/new_note.md').readAsStringSync(),
      contains('mechanical write landed'),
    );
    expect(r.updates, contains('[mechanical write path] 1 applied'));
    // The tree must not lie: the reconcile ran — the new file is zoomable.
    final zoom = await delegate(
      backend,
      'harness_meaning_program {"ops":[{"op":"locate","query":"New '
          'Note"}]}',
    );
    expect(zoom.updates, contains('new_note'), reason: zoom.updates);
  });

  test('remote mover + REJECT: the write NEVER lands', () async {
    final backend = HarnessAcpBackend(
      meaningProfile: true,
      remoteMover: true,
    );
    backend.attachPermissionRequester(
      (request) async => AcpPermissionOutcome.reject,
    );
    final r = await delegate(
      backend,
      'harness_fs_write {"path": "notes.md", "content": "OVERWRITTEN"}',
    );
    expect(r.stop, AcpStopReason.endTurn, reason: r.updates);
    expect(
      File('${ws.path}/notes.md').readAsStringSync(),
      isNot(contains('OVERWRITTEN')),
    );
    expect(r.updates, contains('[mechanical write path] 0 applied'));
  });

  test('no consent approver wired → refusal (deny-by-default is structural)',
      () async {
    final backend = HarnessAcpBackend(meaningProfile: true, remoteMover: true);
    final r = await delegate(
      backend,
      'harness_fs_write {"path": "notes.md", "content": "x"}',
    );
    expect(r.stop, AcpStopReason.refusal);
    expect(File('${ws.path}/notes.md').readAsStringSync(), contains('scratch'));
    expect(r.updates, contains('no consent approver wired'));
  });
}

typedef BackendPromptOutcome = ({AcpStopReason stop, String updates});
