// ignore_for_file: lines_longer_than_80_chars

/// P1 consent UX hardening gate (LLM-free — the remote-mover mechanical
/// write path, the production pi consent surface; no mover model, no
/// task, no grade).
///
/// Locks the three Phase 1.5 GUI-dogfood findings:
/// 1. **short deadline + deny-on-timeout** — an unanswered
///    `session/request_permission` resolves DENIED at the permission
///    deadline (`permission_timeout`, audited) instead of stalling the
///    tool round for the client's full 5-minute silence;
/// 2. **late answers are logged and IGNORED** — the wait already resolved
///    deny; deny-by-default is monotonic in time (a later allow requires
///    a NEW round-trip — the deadline is a loop-breaker, not a policy
///    change);
/// 3. **cancel interrupts permission waits** — `session/cancel` resolves
///    every pending wait as DENY promptly; the tool returns, the loop
///    idles, no dangling Future (the Phase 1.5 bridge-crash class);
/// 4. **F3 attribution** — every decision path (plan-allow /
///    approver-allow / deny / timeout / cancel-deny) logs WHICH path
///    answered, so a silent allow is detectable in the audit.
library;

import 'dart:async';
import 'dart:io';

import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';

void main() {
  late Directory ws;

  setUp(() async {
    ws = await Directory.systemTemp.createTemp('consent_ux_');
    File('${ws.path}/notes.md').writeAsStringSync('# Notes\n\nscratch\n');
  });
  tearDown(() {
    try {
      ws.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  });

  Future<({AcpStopReason stop, String updates, String sessionId})> prompt(
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
          updates.write(
            u.content is AcpTextBlock ? (u.content as AcpTextBlock).text : '',
          );
        }
      },
    );
    return (stop: stop, updates: updates.toString(), sessionId: sid);
  }

  test(
    'gate 1 — no approver answers: the wait resolves DENIED at the '
    'deadline, failure_class permission_timeout rides the tool result, '
    'the deny is audited',
    () async {
      final backend = HarnessAcpBackend(
        meaningProfile: true,
        remoteMover: true,
        permissionDeadline: const Duration(milliseconds: 250),
      );
      final never = Completer<AcpPermissionOutcome>();
      backend.attachPermissionRequester((request) {
        expect(request.title, startsWith('write '));
        return never.future; // NEVER answers — the Phase 1.5 stall
      });
      final r = await prompt(
        backend,
        'harness_fs_write {"path": "notes.md", "content": "TIMEOUT WRITE"}',
      );
      never.complete(AcpPermissionOutcome.reject); // tidy: end the dangling
      expect(r.stop, AcpStopReason.endTurn, reason: r.updates);
      expect(
        File('${ws.path}/notes.md').readAsStringSync(),
        isNot(contains('TIMEOUT WRITE')),
        reason: 'deny-by-default holds on timeout: ${r.updates}',
      );
      // The named failure class rides the TOOL RESULT — the client sees
      // WHY without re-reading the audit.
      expect(
        r.updates,
        contains('failure_class: permission_timeout'),
        reason: r.updates,
      );
      // …and the deny is audited like every other answer.
      final audit = backend.consentAudit(r.sessionId);
      expect(
        audit.where(
          (l) => l.contains('DENIED via timeout (permission_timeout)'),
        ),
        isNotEmpty,
        reason: 'audit: ${audit.join(" | ")}',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'gate 2 — approver answers LATE (after the deadline): still denied; '
    'the late answer is LOGGED and IGNORED',
    () async {
      // SEMANTIC (named): a late answer is logged and ignored. The wait
      // already resolved DENY at the deadline; a permission that outlives
      // its deadline can never retroactively allow (deny-by-default is
      // monotonic in time) — a later allow requires a NEW round-trip. The
      // deadline is a loop-breaker, not a policy change.
      final backend = HarnessAcpBackend(
        meaningProfile: true,
        remoteMover: true,
        permissionDeadline: const Duration(milliseconds: 250),
      );
      backend.attachPermissionRequester((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        return AcpPermissionOutcome.allow; // arrives AFTER the deadline
      });
      final r = await prompt(
        backend,
        'harness_fs_write {"path": "notes.md", "content": "LATE ALLOW"}',
      );
      expect(r.stop, AcpStopReason.endTurn, reason: r.updates);
      expect(
        File('${ws.path}/notes.md').readAsStringSync(),
        isNot(contains('LATE ALLOW')),
        reason: 'the timeout deny held: ${r.updates}',
      );
      final audit = backend.consentAudit(r.sessionId);
      expect(
        audit.where((l) => l.contains('DENIED via timeout')),
        isNotEmpty,
        reason: 'audit: ${audit.join(" | ")}',
      );
      // The late answer lands in the audit as IGNORED — logged, never
      // applied.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final auditAfterLate = backend.consentAudit(r.sessionId);
      expect(
        auditAfterLate.where(
          (l) => l.contains('LATE APPROVED via approver (IGNORED'),
        ),
        isNotEmpty,
        reason: 'audit: ${auditAfterLate.join(" | ")}',
      );
      expect(
        File('${ws.path}/notes.md').readAsStringSync(),
        isNot(contains('LATE ALLOW')),
        reason: 'the ignored late answer never applies the write',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'gate 3 — session/cancel during an open permission wait: prompt deny, '
    'the tool returns, the loop idles (stop=cancelled)',
    () async {
      final backend = HarnessAcpBackend(
        meaningProfile: true,
        remoteMover: true,
        // The deadline is deliberately LONG: the cancel must interrupt
        // the wait, never race the deadline.
        permissionDeadline: const Duration(minutes: 5),
      );
      final asked = Completer<void>();
      backend.attachPermissionRequester((request) async {
        asked.complete();
        return Completer<AcpPermissionOutcome>().future; // never answers
      });
      final sid = await backend.createSession(
        AcpSessionNewRequest(cwd: ws.path),
      );
      final updates = StringBuffer();
      final done = Completer<AcpStopReason>();
      unawaited(
        backend
            .prompt(
              AcpPromptRequest(
                sessionId: sid,
                prompt: [
                  AcpTextBlock(
                    'harness_fs_write {"path": "notes.md", "content": '
                    '"CANCELLED WRITE"}',
                  ),
                ],
              ),
              isCancelled: () => false,
              emit: (u) {
                if (u is AgentMessageChunk) {
                  updates.write(
                    u.content is AcpTextBlock
                        ? (u.content as AcpTextBlock).text
                        : '',
                  );
                }
              },
            )
            .then(done.complete),
      );
      await asked.future; // the permission wait is OPEN
      backend.cancelSession(sid); // session/cancel interrupts the wait
      // The prompt resolves PROMPTLY (no dangling Future — the Phase 1.5
      // bridge-crash class); its return IS the loop idling.
      final stop = await done.future.timeout(const Duration(seconds: 10));
      expect(stop, AcpStopReason.cancelled, reason: '$updates');
      expect(
        File('${ws.path}/notes.md').readAsStringSync(),
        isNot(contains('CANCELLED WRITE')),
        reason: 'the cancel-deny never applies the write: $updates',
      );
      final audit = backend.consentAudit(sid);
      expect(
        audit.where((l) => l.contains('DENIED via cancel-deny')),
        isNotEmpty,
        reason: 'audit: ${audit.join(" | ")}',
      );
      expect(
        '$updates',
        contains('failure_class: permission_cancelled'),
        reason: '$updates',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'gate 4 — F3 attribution: every decision path logs WHICH path '
    'answered (plan-allow / approver-allow / deny / timeout / cancel-deny)',
    () async {
      final backend = HarnessAcpBackend(
        meaningProfile: true,
        remoteMover: true,
        permissionDeadline: const Duration(milliseconds: 250),
      );
      var behavior = (_) async => AcpPermissionOutcome.allow;
      final requesterCalls = <void>[];
      backend.attachPermissionRequester((request) {
        requesterCalls.add(null);
        return behavior(request);
      });
      final sid = await backend.createSession(
        AcpSessionNewRequest(cwd: ws.path),
      );

      Future<void> write(String content) async {
        await backend.prompt(
          AcpPromptRequest(
            sessionId: sid,
            prompt: [
              AcpTextBlock(
                'harness_fs_write {"path": "notes.md", "content": "$content"}',
              ),
            ],
          ),
          isCancelled: () => false,
          emit: (u) {},
        );
      }

      // 1. plan-allow: the plan answers BEFORE the client is asked.
      backend.setConsentPlan(
        sid,
        const ConsentPlan(
          pathGlob: 'notes\\.md',
          verbs: {'write'},
          maxUses: 1,
        ),
      );
      final callsBeforePlan = requesterCalls.length;
      await write('PLAN WRITE');
      expect(requesterCalls.length, callsBeforePlan,
          reason: 'the plan answers in-scope writes mechanically');
      expect(
        File('${ws.path}/notes.md').readAsStringSync(),
        contains('PLAN WRITE'),
        reason: 'the plan-allowed write landed (behavior unchanged)',
      );

      // 2. approver-allow: the plan is exhausted (maxUses 1) → the client
      //    allows.
      behavior = (_) async => AcpPermissionOutcome.allow;
      await write('APPROVER ALLOW');
      expect(
        File('${ws.path}/notes.md').readAsStringSync(),
        contains('APPROVER ALLOW'),
        reason: 'the approver-allowed write landed',
      );

      // 3. deny: the client rejects.
      behavior = (_) async => AcpPermissionOutcome.reject;
      await write('APPROVER DENY');

      // 4. timeout: the client never answers.
      behavior = (_) => Completer<AcpPermissionOutcome>().future;
      await write('TIMEOUT DENY');

      // 5. cancel-deny: the client never answers; the session cancels.
      behavior = (_) => Completer<AcpPermissionOutcome>().future;
      final cancelDone = Completer<void>();
      unawaited(
        backend
            .prompt(
              AcpPromptRequest(
                sessionId: sid,
                prompt: [
                  AcpTextBlock(
                    'harness_fs_write {"path": "notes.md", "content": '
                    '"CANCEL DENY"}',
                  ),
                ],
              ),
              isCancelled: () => false,
              emit: (u) {},
            )
            .then((_) => cancelDone.complete()),
      );
      // Wait until THIS call's permission wait is open, then cancel.
      while (requesterCalls.length < 4) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      backend.cancelSession(sid);
      await cancelDone.future.timeout(const Duration(seconds: 10));

      final audit = backend.consentAudit(sid);
      String single(String needle) => audit.singleWhere(
            (l) => l.contains(needle),
            orElse: () => 'MISSING "$needle" in [${audit.join(" | ")}]',
          );
      expect(
        single('plan-allowed mechanical write'),
        contains('plan-allowed mechanical write'),
        reason: audit.join(' | '),
      );
      expect(
        single('APPROVED via approver'),
        contains('APPROVED via approver'),
        reason: audit.join(' | '),
      );
      expect(
        single('DENIED via approver'),
        contains('DENIED via approver'),
        reason: audit.join(' | '),
      );
      expect(
        single('DENIED via timeout (permission_timeout)'),
        contains('DENIED via timeout (permission_timeout)'),
        reason: audit.join(' | '),
      );
      expect(
        single('DENIED via cancel-deny (permission_cancelled)'),
        contains('DENIED via cancel-deny (permission_cancelled)'),
        reason: audit.join(' | '),
      );
      // F3's point: a silent allow is DETECTABLE — every allow names its
      // path, so an allow with no audit line cannot happen.
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
