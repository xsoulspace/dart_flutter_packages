// ignore_for_file: lines_longer_than_80_chars

/// ADR 0009 — the headless gate (§Gates 2) over the profiler PROTOCOL
/// layer (scripted, no LLM).
///
/// The protocol module (`src/session_protocol.dart`) imports NO Flutter —
/// the registry + protocol answer state/beats/spend for a scripted handle
/// with no widget, no bindings, no BuildContext in the reader path. The
/// two-surface resolve law is re-asserted from the protocol side: an
/// ambiguous read errors NAMING the live sessions.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';
import 'package:xsoulspace_agentic_harness_flutter_profiler/session_protocol.dart';

/// A scripted [SessionHandle] — the seam a daemon runner or a test
/// registers (state as data; intent actions recorded).
final class _ScriptedHandle implements SessionHandle {
  _ScriptedHandle(this.snapshot, {this.onAnswer});

  SessionSnapshot snapshot;
  final SessionIntentResult Function(bool allow)? onAnswer;

  @override
  SessionSnapshot get state => snapshot;

  @override
  SessionIntentResult delegateTask(final String task) =>
      (ok: true, message: 'delegated: $task');

  @override
  SessionIntentResult answerPermission({required final bool allow}) =>
      onAnswer?.call(allow) ??
      (ok: true, message: allow ? 'allowed' : 'rejected');
}

void main() {
  group('headless gate (ADR 0009 §Gates 2)', () {
    test(
      'registry + protocol answer state/beats/spend with no UI in the path',
      () {
        final registry = HarnessSessionRegistry();
        final daemon = _ScriptedHandle(
          SessionSnapshot(
            sessionId: 'daemon-1',
            kind: 'daemon',
            running: false,
            pendingPermissionTitle: 'write lib/main.dart',
            verdict:
                'verdict: PASS (decisions 2, rounds 5, tokens 1200, wall 3000)',
            turnCount: 1,
            beats: const [
              SessionBeat(name: 'read', detail: 'lib/main.dart'),
              SessionBeat(name: 'edit', detail: 'lib/main.dart'),
            ],
            contextSummary: 'meaning cut: 12 nodes, zoom on lib/main.dart',
            transcriptTail: '[read] lib/main.dart\n[edit] lib/main.dart\n'
                'verdict: PASS\n',
          ),
        );
        registry.register('agent-doc-1', daemon);

        // The reader rides the registry's resolve law (only session →
        // answers with no id, no focus mark, no UI).
        final report = SessionProtocolReader(registry: registry).read();
        expect(report.sessionId, 'agent-doc-1');
        // state:
        expect(report.state.kind, 'daemon');
        expect(report.state.running, isFalse);
        expect(report.state.turnCount, 1);
        // what beats ran:
        expect(report.beats.length, 2);
        expect(report.beats[0].name, 'read');
        expect(report.beats[1].detail, 'lib/main.dart');
        // what context was assembled:
        expect(report.contextSummary, contains('meaning cut'));
        // spend (structured figures, verdict outcome):
        expect(report.spend, isNotNull);
        expect(report.spend!.tokens, 1200);
        expect(report.spend!.wallMs, 3000);
        expect(report.verdictPassed, isTrue);
        // intent seams' state:
        expect(report.pendingPermission, 'write lib/main.dart');
        expect(report.transcriptTail, contains('[edit] lib/main.dart'));
      },
    );

    test('spend falls back to parsing the verdict line (same labels)', () {
      final registry = HarnessSessionRegistry();
      registry.register(
        'agent-doc-1',
        _ScriptedHandle(
          SessionSnapshot(
            sessionId: 'daemon-1',
            verdict: 'verdict: FAIL (decisions 3, rounds 9, tokens 4200, '
                'wall 8000)',
          ),
        ),
      );

      final report = SessionProtocolReader(registry: registry).read();
      expect(report.spend!.decisions, 3);
      expect(report.spend!.rounds, 9);
      expect(report.spend!.tokens, 4200);
      expect(report.spend!.wallMs, 8000);
      expect(report.verdictPassed, isFalse);
    });

    test('report projects to JSON and one honest summary line', () {
      final registry = HarnessSessionRegistry();
      registry.register(
        'agent-doc-1',
        _ScriptedHandle(
          SessionSnapshot(
            sessionId: 'daemon-1',
            kind: 'surface',
            running: true,
            beats: const [SessionBeat(name: 'grep', detail: 'session')],
            contextSummary: 'derived context row 4/4000',
          ),
        ),
      );

      final reader = SessionProtocolReader(registry: registry);
      final report = reader.read();
      final json = report.toJson();
      expect(json['sessionId'], 'agent-doc-1');
      expect(json['running'], isTrue);
      expect((json['beats'] as List).length, 1);
      expect(json['spend'], isNull);
      expect(json['verdictPassed'], isNull);
      expect(
        report.summary(),
        'agent-doc-1: surface, RUNNING, 1 beats '
            '· context: derived context row 4/4000',
      );
    });

    test('intent actions ride the resolved handle (delegate, permission)',
        () {
        var allowed = false;
        final registry = HarnessSessionRegistry();
        registry.register(
          'agent-doc-1',
          _ScriptedHandle(
            SessionSnapshot(sessionId: 'daemon-1'),
            onAnswer: (allow) {
              allowed = allow;
              return (ok: true, message: allow ? 'allowed' : 'rejected');
            },
          ),
        );

        final reader = SessionProtocolReader(registry: registry);
        // The report names the addressable id; the driver acts on the
        // handle it names (delegate/permission ride the SAME handle the
        // state was read from).
        final report = reader.read();
        final handle = registry.resolve(id: report.sessionId);
        expect(
          handle.answerPermission(allow: false),
          (ok: true, message: 'rejected'),
        );
        expect(allowed, isFalse);
        expect(report.summary(), 'agent-doc-1: session, idle, 0 beats');
      });
  });

  group('two-surface law from the protocol side (ADR 0009 §Gates 1)', () {
    test('an ambiguous read errors NAMING the live sessions', () {
      final registry = HarnessSessionRegistry();
      registry
        ..register(
          'agent-doc-a',
          _ScriptedHandle(SessionSnapshot(sessionId: 'daemon-a')),
        )
        ..register(
          'agent-doc-b',
          _ScriptedHandle(SessionSnapshot(sessionId: 'daemon-b')),
        );

      final reader = SessionProtocolReader(registry: registry);
      expect(
        () => reader.read(),
        throwsA(
          isA<SessionResolutionException>()
              .having((e) => e.message, 'message', contains('agent-doc-a'))
              .having((e) => e.message, 'message', contains('agent-doc-b')),
        ),
      );
      // Naming one id lands on exactly that session — never wrong-target.
      expect(reader.read(id: 'agent-doc-b').state.sessionId, 'daemon-b');
    });

    test('the shared registry is the default substrate (one index)', () {
      final reader = SessionProtocolReader();
      expect(identical(reader.registry, HarnessSessionRegistry.instance),
          isTrue);
    });
  });
}
