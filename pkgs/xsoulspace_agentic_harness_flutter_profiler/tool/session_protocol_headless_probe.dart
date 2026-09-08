// ignore_for_file: lines_longer_than_80_chars

/// ADR 0009 — the HEADLESS GATE probe (§Gates 2): a plain-VM script (no
/// flutter_tester, no widget tree, no Flutter in the process) that runs
/// the profiler protocol layer over a scripted daemon handle.
///
/// Run with the plain Dart VM:
/// ```
/// dart run tool/session_protocol_headless_probe.dart
/// ```
///
/// Exits 0 when the registry + protocol answer state/beats/spend for the
/// scripted session; any gate failure throws. This probe imports the
/// protocol sub-barrel ONLY (`session_protocol.dart`) — never the widget
/// barrel — so its entire import graph is pure Dart.
library;

import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';
import 'package:xsoulspace_agentic_harness_flutter_profiler/session_protocol.dart';

void main() {
  // A scripted daemon handle — the seam a harnessd runner registers at
  // spawn (no UI, no widget tree, no Flutter anywhere in this process).
  final registry = HarnessSessionRegistry();
  registry.register(
    'agent-doc-1',
    _ScriptedDaemonHandle(
      const SessionSnapshot(
        sessionId: 'daemon-1',
        kind: 'daemon',
        pendingPermissionTitle: 'write lib/main.dart',
        verdict: 'verdict: PASS (decisions 2, rounds 5, tokens 1200, '
            'wall 3000)',
        turnCount: 1,
        beats: [
          SessionBeat(name: 'read', detail: 'lib/main.dart'),
          SessionBeat(name: 'edit', detail: 'lib/main.dart'),
        ],
        contextSummary: 'meaning cut: 12 nodes, zoom on lib/main.dart',
        transcriptTail: '[read] lib/main.dart\n[edit] lib/main.dart\n',
      ),
    ),
  );

  final report = SessionProtocolReader(registry: registry).read();

  // state:
  _gate(report.state.kind == 'daemon', 'state.kind');
  _gate(report.state.turnCount == 1, 'state.turnCount');
  // what beats ran:
  _gate(report.beats.length == 2, 'beats.length');
  _gate(report.beats[0].name == 'read', 'beats[0].name');
  _gate(report.beats[1].detail == 'lib/main.dart', 'beats[1].detail');
  // what context was assembled:
  _gate(report.contextSummary.contains('meaning cut'), 'contextSummary');
  // spend:
  _gate(report.spend != null, 'spend');
  _gate(report.spend!.tokens == 1200, 'spend.tokens');
  _gate(report.spend!.wallMs == 3000, 'spend.wallMs');
  _gate(report.verdictPassed == true, 'verdictPassed');
  // intent seam state:
  _gate(report.pendingPermission == 'write lib/main.dart', 'permission');

  // One honest line, headless:
  print(report.summary());
  print('HEADLESS GATE PASS — state/beats/spend answered with no Flutter '
      'in the process.');
}

/// The scripted daemon handle: state as data, intent actions recorded.
final class _ScriptedDaemonHandle implements SessionHandle {
  const _ScriptedDaemonHandle(this.snapshot);

  final SessionSnapshot snapshot;

  @override
  SessionSnapshot get state => snapshot;

  @override
  SessionIntentResult delegateTask(final String task) =>
      (ok: true, message: 'delegated: $task');

  @override
  SessionIntentResult answerPermission({required final bool allow}) =>
      (ok: true, message: allow ? 'allowed' : 'rejected');
}

/// One gate assertion — a failure throws (exit non-zero, named).
void _gate(final bool condition, final String name) {
  if (!condition) {
    throw StateError('HEADLESS GATE FAIL: $name');
  }
}
