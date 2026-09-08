// ignore_for_file: lines_longer_than_80_chars

/// ADR 0009 (D3) — the profiler PROTOCOL layer: pure Dart, NO Flutter
/// imports. This module is the headless reader seam beside the Flutter
/// panes: grid panes and headless consumers (daemon drivers, MCP verbs,
/// agents debugging the harness without UI) are EQUAL READERS of the
/// session registry.
///
/// It answers, for one session and with no UI in the process:
///
/// - **state** — the typed [SessionSnapshot] the handle exposes;
/// - **beats** — what beats ran ([SessionProtocolReport.beats]);
/// - **context** — what context was assembled
///   ([SessionProtocolReport.contextSummary]);
/// - **spend** — the verdict/spend tuple ([SessionProtocolReport.spend],
///   structured when the handle owns it, parsed from the verdict line
///   otherwise — the same labels today's controller parses);
/// - **pending permission / transcript tail** — the intent seams' state.
///
/// Resolution is REGISTRY-BACKED and rides the registry's semantics
/// (explicit id → exact; absent id → the only session; several → the
/// focused one; ambiguous → an error that NAMES the live sessions — never
/// a silent wrong-target answer).
library;

import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart'
    show
        HarnessSessionRegistry,
        SessionBeat,
        SessionHandle,
        SessionId,
        SessionSnapshot,
        SessionSpend;

/// Verdict pass/fail from the verdict line — the SAME parse the surface
/// colors by today (`HarnessTurn.verdictPassed`: contains `PASS` → true).
/// Null when there is no verdict or it names neither outcome.
bool? verdictPassedOf(final String? verdict) {
  if (verdict == null) return null;
  if (verdict.contains('PASS')) return true;
  if (verdict.contains('FAIL')) return false;
  return null;
}

/// Spend parsed from the verdict line — the same four labels today's
/// controller parses (`decisions`, `rounds`, `tokens`, `wall`); null when
/// the line carries none. The structured [SessionSpend] a handle owns
/// always wins over this fallback.
SessionSpend? spendFromVerdict(final String? verdict) {
  if (verdict == null) return null;
  int? figure(final String label) {
    final match = RegExp('$label (\\d+)').firstMatch(verdict);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  final decisions = figure('decisions');
  final rounds = figure('rounds');
  final tokens = figure('tokens');
  final wallMs = figure('wall');
  if (decisions == null && rounds == null && tokens == null && wallMs == null) {
    return null;
  }
  return SessionSpend(
    decisions: decisions ?? 0,
    rounds: rounds ?? 0,
    tokens: tokens ?? 0,
    wallMs: wallMs ?? 0,
  );
}

/// The headless reader's answer for ONE session — the protocol projection
/// of a live [SessionHandle]. Everything here is read from the handle's
/// typed state; nothing is scraped from a widget, nothing is guessed.
final class SessionProtocolReport {
  const SessionProtocolReport({
    required this.sessionId,
    required this.state,
    required this.beats,
    required this.spend,
    required this.verdictPassed,
    required this.pendingPermission,
    required this.transcriptTail,
    required this.contextSummary,
  });

  /// The session id the report was resolved under (the registry key when
  /// read through the registry; the snapshot's own id otherwise).
  final SessionId sessionId;

  /// The typed state snapshot (the full projection lives here).
  final SessionSnapshot state;

  /// What beats ran, as data (the `[tool] payload` rows, structured).
  final List<SessionBeat> beats;

  /// Spend: structured when the handle owns it, parsed from the verdict
  /// line otherwise, null when the turn has not ended.
  final SessionSpend? spend;

  /// Verdict outcome (`PASS`/`FAIL`), null before the first verdict.
  final bool? verdictPassed;

  /// Title of the pending permission round-trip, if one awaits an answer.
  final String? pendingPermission;

  /// The transcript tail (the streamed text projection).
  final String transcriptTail;

  /// What context was assembled for the model (the meaning cut /
  /// derived-context row as data; empty when the handle exposes none).
  final String contextSummary;

  Map<String, Object?> toJson() => {
    // The state projection first — report-level keys (the registry key,
    // the parsed beats/spend/verdict) override the snapshot's inner ones.
    ...state.toJson(),
    'sessionId': sessionId,
    'beats': [for (final beat in beats) beat.toJson()],
    'spend': ?spend?.toJson(),
    'verdictPassed': ?verdictPassed,
    'pendingPermission': ?pendingPermission,
    'transcriptTail': transcriptTail,
    'contextSummary': contextSummary,
  };

  /// One honest line — the headless equivalent of the state verb's
  /// message (state · beats · context · spend, never a guess).
  String summary() {
    final verdict = state.verdict == null ? '' : ' · ${state.verdict}';
    final permission = pendingPermission == null
        ? ''
        : ' — permission "${pendingPermission}" awaits an answer';
    final spendText = spend == null
        ? ''
        : ' · d${spend!.decisions} r${spend!.rounds} '
              '${spend!.tokens}tok ${spend!.wallMs}ms';
    final context = contextSummary.isEmpty
        ? ''
        : ' · context: $contextSummary';
    return '$sessionId: ${state.kind}, '
        '${state.running ? 'RUNNING' : 'idle'}, '
        '${beats.length} beats$spendText$context$verdict$permission';
  }
}

/// The registry-backed headless reader (ADR 0009 D3): answers "what beats
/// ran / what context was assembled / spend" for a session with NO UI.
/// Consumes the registry — never a widget static; the Flutter profiler
/// panes are one reader among equals.
final class SessionProtocolReader {
  const SessionProtocolReader({final HarnessSessionRegistry? registry})
    : _registryOverride = registry;

  final HarnessSessionRegistry? _registryOverride;

  /// The registry this reader resolves through: the injected one, else the
  /// shared [HarnessSessionRegistry.instance] (the one index, ADR 0009 D1).
  HarnessSessionRegistry get registry =>
      _registryOverride ?? HarnessSessionRegistry.instance;

  /// Resolves a session through the registry (explicit id → exact; absent
  /// id → only/focused; ambiguous → the registry's error NAMING the live
  /// sessions) and returns its protocol report. The report names the
  /// REGISTRY KEY the handle lives under (the addressable id).
  SessionProtocolReport read({final SessionId? id}) {
    final handle = registry.resolve(id: id);
    return readHandle(handle, id: id ?? _keyOf(handle));
  }

  /// The registry key [handle] lives under (identity lookup over the
  /// live sessions — the reader reads the index, never re-resolves).
  SessionId? _keyOf(final SessionHandle handle) {
    for (final entry in registry.sessions.entries) {
      if (identical(entry.value, handle)) return entry.key;
    }
    return null;
  }

  /// Builds the report for an already-resolved [handle]; pass the
  /// registry [id] when known so the report names the addressable key.
  SessionProtocolReport readHandle(
    final SessionHandle handle, {
    final SessionId? id,
  }) {
    final state = handle.state;
    return SessionProtocolReport(
      sessionId: id ?? state.sessionId,
      state: state,
      beats: List.unmodifiable(state.beats),
      spend: state.spend ?? spendFromVerdict(state.verdict),
      verdictPassed: verdictPassedOf(state.verdict),
      pendingPermission: state.pendingPermissionTitle,
      transcriptTail: state.transcriptTail,
      contextSummary: state.contextSummary,
    );
  }
}
