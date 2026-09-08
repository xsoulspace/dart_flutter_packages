// ignore_for_file: lines_longer_than_80_chars

/// ADR 0009 — the session registry gates (scripted, no LLM, no Flutter).
///
/// 1. **Two-surface gate**: two handles registered; `resolve(id)` targets
///    each correctly; the ambiguous no-id resolve errors NAMING both; the
///    focused resolve lands on the focused handle; explicit intent actions
///    land on the addressed handle, never silently on the other.
/// 2. **Register/unregister lifecycle** incl. the identical-guard
///    semantics: a stale unregister must not clobber a newer registration.
///
/// The headless gate lives beside the protocol layer
/// (`xsoulspace_agentic_harness_flutter_profiler`).
library;

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';

/// A scripted [SessionHandle]: state as data, intent actions recorded.
final class _ScriptedHandle implements SessionHandle {
  _ScriptedHandle(this.snapshot, {this.onDelegate, this.onAnswer});

  SessionSnapshot snapshot;
  final SessionIntentResult Function(String task)? onDelegate;
  final SessionIntentResult Function({required bool allow})? onAnswer;

  @override
  SessionSnapshot get state => snapshot;

  @override
  SessionIntentResult delegateTask(final String task) =>
      onDelegate?.call(task) ?? (ok: true, message: 'delegated: $task');

  @override
  SessionIntentResult answerPermission({required final bool allow}) =>
      onAnswer?.call(allow: allow) ??
      (ok: true, message: allow ? 'allowed' : 'rejected');
}

SessionSnapshot _snapshot(
  final String sessionId, {
  final String kind = 'surface',
  final bool running = false,
  final String? pendingPermissionTitle,
  final String? verdict,
  final List<SessionBeat> beats = const [],
}) => SessionSnapshot(
  sessionId: sessionId,
  kind: kind,
  running: running,
  pendingPermissionTitle: pendingPermissionTitle,
  verdict: verdict,
  beats: beats,
);

void main() {
  group('two-surface gate (ADR 0009 §Gates 1)', () {
    test('resolve(id) targets each registered handle exactly', () {
      final registry = HarnessSessionRegistry();
      final docA = _ScriptedHandle(_snapshot('daemon-a'));
      final docB = _ScriptedHandle(_snapshot('daemon-b'));
      registry
        ..register('agent-doc-a', docA)
        ..register('agent-doc-b', docB);

      expect(registry.liveSessions, ['agent-doc-a', 'agent-doc-b']);
      expect(identical(registry.resolve(id: 'agent-doc-a'), docA), isTrue);
      expect(identical(registry.resolve(id: 'agent-doc-b'), docB), isTrue);
      // The resolved handles carry their own state — no cross-talk.
      expect(
        registry.resolve(id: 'agent-doc-a').state.sessionId,
        'daemon-a',
      );
      expect(
        registry.resolve(id: 'agent-doc-b').state.sessionId,
        'daemon-b',
      );
    });

    test('ambiguous no-id resolve errors NAMING both live sessions', () {
      final registry = HarnessSessionRegistry();
      registry
        ..register(
          'agent-doc-a',
          _ScriptedHandle(_snapshot('daemon-a')),
        )
        ..register(
          'agent-doc-b',
          _ScriptedHandle(_snapshot('daemon-b')),
        );

      expect(
        registry.resolve,
        throwsA(
          isA<SessionResolutionException>()
              .having(
                (e) => e.message,
                'message',
                contains('agent-doc-a'),
              )
              .having((e) => e.message, 'message', contains('agent-doc-b'))
              .having(
                (e) => e.liveSessions,
                'liveSessions',
                ['agent-doc-a', 'agent-doc-b'],
              ),
        ),
      );
    });

    test('the focused handle wins the no-id resolve (device-local focus)', () {
      final registry = HarnessSessionRegistry();
      final docA = _ScriptedHandle(_snapshot('daemon-a'));
      final docB = _ScriptedHandle(_snapshot('daemon-b'));
      registry
        ..register('agent-doc-a', docA)
        ..register('agent-doc-b', docB)
        ..focused = 'agent-doc-b';

      expect(registry.focused, 'agent-doc-b');
      expect(identical(registry.resolve(), docB), isTrue);
    });

    test('explicit intent actions land on the ADDRESSED handle', () {
      final registry = HarnessSessionRegistry();
      final aTasks = <String>[];
      final bTasks = <String>[];
      final bAnswers = <bool>[];
      registry
        ..register(
          'agent-doc-a',
          _ScriptedHandle(
            _snapshot('daemon-a'),
            onDelegate: (task) {
              aTasks.add(task);
              return (ok: true, message: 'delegated: $task');
            },
          ),
        )
        ..register(
          'agent-doc-b',
          _ScriptedHandle(
            _snapshot('daemon-b'),
            onDelegate: (task) {
              bTasks.add(task);
              return (ok: true, message: 'delegated: $task');
            },
            onAnswer: ({required allow}) {
              bAnswers.add(allow);
              return (ok: true, message: allow ? 'allowed' : 'rejected');
            },
          ),
        );

      // Delegate to A by id — never silently to B (the wrong-target law).
      final a = registry.resolve(id: 'agent-doc-a');
      expect(
        a.delegateTask('fix the import'),
        (ok: true, message: 'delegated: fix the import'),
      );
      expect(aTasks, ['fix the import']);
      expect(bTasks, isEmpty);
      expect(bAnswers, isEmpty);

      // And answer B's permission by id — A's intent seams stay silent.
      final b = registry.resolve(id: 'agent-doc-b');
      expect(b.answerPermission(allow: false), (ok: true, message: 'rejected'));
      expect(bAnswers, [false]);
    });

    test('explicit unknown id errors naming the live sessions', () {
      final registry = HarnessSessionRegistry();
      registry
        ..register(
          'agent-doc-a',
          _ScriptedHandle(_snapshot('daemon-a')),
        )
        ..register(
          'agent-doc-b',
          _ScriptedHandle(_snapshot('daemon-b')),
        );

      expect(
        () => registry.resolve(id: 'agent-doc-zzz'),
        throwsA(
          isA<SessionResolutionException>()
              .having(
                (e) => e.message,
                'message',
                allOf(contains('agent-doc-zzz'), contains('agent-doc-a'), contains('agent-doc-b')),
              )
              .having((e) => e.liveSessions.length, 'liveSessions', 2),
        ),
      );
    });

    test(
        'the focused session closes → resolve degrades to the named error, '
        'never a target', () {
      final registry = HarnessSessionRegistry();
      final docA = _ScriptedHandle(_snapshot('daemon-a'));
      final docB = _ScriptedHandle(_snapshot('daemon-b'));
      final docC = _ScriptedHandle(_snapshot('daemon-c'));
      registry
        ..register('agent-doc-a', docA)
        ..register('agent-doc-b', docB)
        ..register('agent-doc-c', docC)
        ..focused = 'agent-doc-a';

      // The focused session closed; TWO sessions stay live. Resolve must
      // NOT silently land on either — it errors NAMING them.
      registry.unregister('agent-doc-a', docA);

      expect(registry.focused, isNull); // marker cleared on unregister
      expect(
        registry.resolve,
        throwsA(
          isA<SessionResolutionException>()
              .having((e) => e.message, 'message', contains('agent-doc-b'))
              .having((e) => e.message, 'message', contains('agent-doc-c')),
        ),
      );
      // Naming one lands exactly — the error names, it never guesses.
      expect(identical(registry.resolve(id: 'agent-doc-b'), docB), isTrue);
    });
  });

  group('register/unregister lifecycle (identical guard)', () {
    test('unregister removes only the identical handle', () {
      final registry = HarnessSessionRegistry();
      final docA = _ScriptedHandle(_snapshot('daemon-a'));
      registry.register('agent-doc-a', docA);

      expect(identical(registry.unregister('agent-doc-a', docA), docA),
          isTrue);
      expect(registry.sessions, isEmpty);
      // Nothing live → resolve names the emptiness honestly.
      expect(
        registry.resolve,
        throwsA(isA<SessionResolutionException>()),
      );
    });

    test('a STALE unregister never clobbers a newer registration', () {
      final registry = HarnessSessionRegistry();
      final docA = _ScriptedHandle(_snapshot('daemon-a'));
      final docB = _ScriptedHandle(_snapshot('daemon-b'));

      // A surface registered; a newer projection (headless driver, rebuilt
      // surface) took over the slot; the STALE teardown arrives late.
      registry
        ..register('agent-doc-a', docA)
        ..register('agent-doc-a', docB)
        ..unregister('agent-doc-a', docA); // stale — must be a no-op

      expect(registry.liveSessions, ['agent-doc-a']);
      expect(identical(registry.resolve(id: 'agent-doc-a'), docB), isTrue);
    });

    test('unregistering the focused handle clears the focus marker', () {
      final registry = HarnessSessionRegistry();
      final docA = _ScriptedHandle(_snapshot('daemon-a'));
      registry
        ..register('agent-doc-a', docA)
        ..focused = 'agent-doc-a'
        ..unregister('agent-doc-a', docA);

      expect(registry.focused, isNull);
    });

    test('the only live session resolves without any focus mark', () {
      final registry = HarnessSessionRegistry();
      final docA = _ScriptedHandle(_snapshot('daemon-a'));
      registry.register('agent-doc-a', docA);

      // Backward compatible with today's single-open-doc behavior (ADR
      // 0009 D2): no id, no focus mark — the only session answers.
      expect(identical(registry.resolve(), docA), isTrue);
    });

    test('re-registering replaces the slot (presence, not authority)', () {
      final registry = HarnessSessionRegistry();
      final headless = _ScriptedHandle(
        _snapshot('daemon-a', kind: 'daemon'),
      );
      final rebuilt = _ScriptedHandle(
        // The default kind IS the surface kind (a rebuilt UI projection).
        _snapshot('daemon-a'),
      );
      registry
        ..register('agent-doc-a', headless)
        ..register('agent-doc-a', rebuilt);

      expect(registry.liveSessions, ['agent-doc-a']);
      expect(registry.resolve(id: 'agent-doc-a').state.kind, 'surface');
    });
  });

  group('presence-not-authority (ADR 0007 §3 analogy)', () {
    test('registered handles carry equal-citizen state snapshots', () {
      final registry = HarnessSessionRegistry();
      registry
        ..register(
          'agent-doc-a',
          _ScriptedHandle(
            _snapshot(
              'daemon-a',
              running: true,
              pendingPermissionTitle: 'write lib/main.dart',
              verdict: 'verdict: PASS (decisions 2, rounds 5, tokens 1200)',
              beats: const [
                SessionBeat(name: 'read', detail: 'lib/main.dart'),
                SessionBeat(name: 'edit', detail: 'lib/main.dart'),
              ],
            ),
          ),
        )
        ..register(
          'agent-doc-b',
          _ScriptedHandle(
            _snapshot('daemon-b', kind: 'daemon'),
          ),
        );

      final a = registry.resolve(id: 'agent-doc-a');
      final b = registry.resolve(id: 'agent-doc-b');
      expect(a.state.running, isTrue);
      expect(a.state.pendingPermissionTitle, 'write lib/main.dart');
      expect(a.state.beats.length, 2);
      expect(a.state.beats[0].name, 'read');
      expect(b.state.kind, 'daemon');
      expect(b.state.running, isFalse);
      // The registry renders presence — it never ranks authority.
      expect(registry.sessions, hasLength(2));
    });
  });
}
