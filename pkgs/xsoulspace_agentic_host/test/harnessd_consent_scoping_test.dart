// ignore_for_file: lines_longer_as_80_chars

/// Consent-scoping INTEGRATION gate, host side (follow-up 3): the daemon's
/// consent paths answer through the session's `ConsentLedger` —
/// actor-keyed audit, v1 backward compatibility, explicit-beats-fallback
/// precedence. LLM-free (scripted mover), same pattern as
/// `consent_plan_test.dart`.
///
/// Claims under test:
/// 1. A legacy v1 workspace `consent.json` still answers mechanically —
///    the write lands with ZERO permission round-trips, and the audit row
///    is ACTOR-KEYED (`harnessd@<cwd>`, the documented derivation) and
///    carries the structured row in the session consent log.
/// 2. A v2 document with an explicit plan for the session actor grants
///    THAT session and NOT another workspace's session (actor isolation
///    across workspaces).
/// 3. Explicit beats fallback: an explicit actor plan that does NOT cover
///    a path stands as a deny even when the `*` fallback covers it — the
///    client is asked (the fallback never widens an explicit deny).
/// 4. Deny-on-timeout is unchanged: the bounded round-trip still resolves
///    DENY at the deadline (and the out-of-band answer lands in the
///    ledger audit too).
library;

import 'dart:io';

import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/src/tooling/consent_scoping.dart' as consent;
import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';

Future<Directory> _fixture(String name) async {
  final dir = await Directory.systemTemp.createTemp('consent_scope_$name');
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
    ws = await _fixture('ws');
  });
  tearDown(() {
    try {
      ws.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  });

  test('v1 workspace consent.json answers mechanically; the audit row is '
      'actor-keyed and the consent log carries the structured row',
      () async {
    final configDir = Directory('${ws.path}/.harnessd')..createSync();
    File('${configDir.path}/consent.json').writeAsStringSync(
      r'{"pathGlob": "notes\\.md", "verbs": ["write"], "maxUses": 3}',
    );

    final backend = HarnessAcpBackend(
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
      r'# Notes\n\nv1 plan write landed\n',
    );
    expect(stop, AcpStopReason.endTurn, reason: 'output: $out');
    expect(
      File('${ws.path}/notes.md').readAsStringSync(),
      contains('v1 plan write landed'),
    );
    expect(
      permissionCalls,
      isEmpty,
      reason: 'the v1 plan answers in-scope writes before the client '
          'is asked — behavior unchanged',
    );

    // The ledger is the authority: the session actor is the documented
    // derivation, and the decision is audited under it.
    final ledger = backend.sessionsDebugConsentLedger(sid);
    expect(ledger, isNotNull);
    final actor = consent.sessionConsentActor(ws.path);
    expect(actor, 'harnessd@${ws.path}');
    final rows = ledger!.auditFor(actor);
    expect(rows, hasLength(1), reason: 'audit: ${ledger.audit}');
    expect(rows.single.verb, 'write');
    expect(rows.single.path, 'notes.md');
    expect(rows.single.decision.allowed, isTrue);
    expect(rows.single.planId, consent.ConsentPlan.legacyActor);
    // The structured row rides the session consent log.
    final audit = backend.consentAudit(sid);
    expect(audit, hasLength(1));
    expect(audit.single, contains('plan-allowed write: notes.md'));
    expect(audit.single, contains('uses: 1/3'));
    expect(audit.single, contains('"actor":"harnessd@${ws.path}"'));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('a v2 document: the explicit session-actor plan grants THIS '
      'session and NOT another workspace session', () async {
    final backend = HarnessAcpBackend(
      meaningProfile: true,
      scripted: true,
    );
    backend.attachPermissionRequester(
      (request) async => AcpPermissionOutcome.reject,
    );
    final sidA = await backend.createSession(
      AcpSessionNewRequest(cwd: ws.path),
    );
    backend.setSessionConsentDocument(sidA, {
      'plans': [
        {
          'planId': 'p-a',
          'actor': consent.sessionConsentActor(ws.path),
          'scopePathGlob': r'^notes\.md$',
          'verbs': ['write'],
          'maxUses': 3,
          'grantedAt': '2026-09-08T10:00:00Z',
        },
      ],
    });

    final (stopA, outA) = await _writeNotes(
      backend,
      sidA,
      r'# Notes\n\nexplicit actor plan write landed\n',
    );
    expect(stopA, AcpStopReason.endTurn, reason: 'output: $outA');
    expect(
      File('${ws.path}/notes.md').readAsStringSync(),
      contains('explicit actor plan write landed'),
      reason: 'the explicit plan answers THIS session',
    );

    // A DIFFERENT workspace's session has a DIFFERENT actor id — the same
    // relative path is NOT covered by actor A's grant (one actor's grant
    // never covers another). No `*` fallback registered → noPlan → the
    // (rejecting) client is asked; the write never lands.
    final wsB = await _fixture('wsb');
    try {
      final sidB = await backend.createSession(
        AcpSessionNewRequest(cwd: wsB.path),
      );
      final (stopB, outB) = await _writeNotes(
        backend,
        sidB,
        r'# Notes\n\nmust not land\n',
      );
      expect(stopB, AcpStopReason.endTurn, reason: 'output: $outB');
      expect(
        File('${wsB.path}/notes.md').readAsStringSync(),
        isNot(contains('must not land')),
        reason: 'actor isolation: B is denied on the same relative path',
      );
      final ledgerB = backend.sessionsDebugConsentLedger(sidB)!;
      final rowsB = ledgerB.auditFor(consent.sessionConsentActor(wsB.path));
      expect(
        rowsB.where((e) => e.decision.reason == consent.ConsentReason.noPlan),
        isNotEmpty,
        reason: 'the deny is NAMED (noPlan), never silent',
      );
    } finally {
      try {
        wsB.deleteSync(recursive: true);
      } on Object {
        // best effort
      }
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('explicit beats fallback: an explicit actor plan that misses the '
      'path stands as a deny even when the * fallback covers it',
      () async {
    final configDir = Directory('${ws.path}/.harnessd')..createSync();
    // A v2 document: the `*` fallback covers everything, but the session
    // actor's EXPLICIT plan covers only report.md — notes.md stays with
    // the client (the fallback never widens an explicit deny).
    File('${configDir.path}/consent.json').writeAsStringSync(
      '{"plans": [ '
      '{"planId": "fallback", "actor": "*", "scopePathGlob": ".*", '
      '"verbs": ["write"], "maxUses": 9, "grantedAt": '
      '"2026-09-08T10:00:00Z"}, '
      '{"planId": "p-a", "actor": "${consent.sessionConsentActor(ws.path)}", '
      r'"scopePathGlob": "^report\.md\$", "verbs": ["write"], '
      '"maxUses": 9, "grantedAt": "2026-09-08T10:00:00Z"} '
      ']}',
    );

    final backend = HarnessAcpBackend(
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
      reason: 'the explicit plan does not cover notes.md — the deny stands '
          'and the client is asked, despite the * fallback covering it',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('deny-on-timeout is unchanged and the out-of-band answer lands in '
      'the ledger audit', () async {
    final backend = HarnessAcpBackend(
      meaningProfile: true,
      scripted: true,
      permissionDeadline: const Duration(milliseconds: 250),
    );
    backend.attachPermissionRequester(
      (request) => Future.delayed(
        const Duration(milliseconds: 600),
        () => AcpPermissionOutcome.allow, // arrives AFTER the deadline
      ),
    );
    final sid = await backend.createSession(
      AcpSessionNewRequest(cwd: ws.path),
    );
    final (stop, out) = await _writeNotes(backend, sid, 'TIMEOUT WRITE');
    expect(stop, AcpStopReason.endTurn, reason: 'output: $out');
    expect(
      File('${ws.path}/notes.md').readAsStringSync(),
      isNot(contains('TIMEOUT WRITE')),
      reason: 'deny-on-timeout holds: $out',
    );
    final ledger = backend.sessionsDebugConsentLedger(sid)!;
    final actor = consent.sessionConsentActor(ws.path);
    final rows = ledger.auditFor(actor);
    expect(
      rows.where(
        (e) => e.decision.reason == consent.ConsentReason.approverDenied,
      ),
      isNotEmpty,
      reason: 'the timeout deny is in the ledger audit, actor-keyed',
    );
    expect(
      backend.consentAudit(sid).where(
            (l) =>
                l.contains('DENIED via timeout') &&
                l.contains('consent-row'),
          ),
      isNotEmpty,
    );
  }, timeout: const Timeout(Duration(seconds: 60)));
}
