// ignore_for_file: lines_longer_than_80_chars

/// ADR 0009 (D1) — the session registry: the ONE index of live sessions,
/// owned by the host layer, pure Dart — no Flutter, no widget tree.
///
/// Replaces the widget statics (`AgentDocSurface.debugState`/`debugSurface`)
/// as the substrate for the inspector, the MCP/intent verbs and headless
/// drivers: UI surfaces, daemon runners, shadow viewers and tests all
/// register here and are EQUAL CITIZENS (a daemon session with no UI at
/// all is the harnessd daemon's normal mode).
///
/// **Registration is presence, not authority** (ADR 0007 §3 analogy):
/// registering a handle grants no ownership of the session — only
/// observability (the typed state snapshot) and intent routing (delegate,
/// permission answer). A registered surface cannot block, veto or claim a
/// session; unregistering only removes its own presence.
///
/// Resolve semantics (ADR 0009 D2 — never a silent wrong-target answer):
/// explicit id → exact; absent id → the only session; several → the
/// focused one; still ambiguous → a [SessionResolutionException] that
/// NAMES the live sessions.
///
/// Consumers: `xsoulspace_agentic_harness_flutter_profiler` (the pure-Dart
/// protocol layer — D3: the registry is the inspector's headless
/// substrate), the coding-agent runner, and the last_answer surface
/// adapters (D4 — widget statics become thin read/write-through adapters;
/// that side is out of scope here).
library;

import 'dart:collection';

/// The id a handle registers under.
///
/// For agent docs this is the deterministic replica id the mesh wiring
/// already uses (`agent-<docId>`); daemon runners key by their session id;
/// tests use any stable key. The id is the ADDRESS of the session for
/// every intent verb and profiler reader — naming it must land on exactly
/// one handle.
typedef SessionId = String;

/// The intent-action result: byte for byte the shape today's
/// `debugSurface` intent methods return (`({bool ok, String message})` —
/// the `agent_task_delegate` / `agent_permission_answer` verb contract in
/// last_answer's `agent_mcp_tools.dart`), so an existing surface can
/// implement [SessionHandle] without wrapping.
typedef SessionIntentResult = ({bool ok, String message});

/// One tool beat as data — the dim monospace row the surfaces render
/// (`[tool_name] payload`), kept structured so headless readers never
/// re-parse transcript strings.
final class SessionBeat {
  const SessionBeat({required this.name, required this.detail});

  /// The beat's tool/actor name (the `[…]` gutter label).
  final String name;

  /// The payload as the handle saw it (truncation is the renderer's job).
  final String detail;

  Map<String, Object?> toJson() => {'name': name, 'detail': detail};

  @override
  String toString() => '[$name] $detail';
}

/// Spend as data — the backend verdict chunk's four figures (the same
/// `(decisions, rounds, tokens, wallMs)` tuple today's controller parses
/// from the verdict line). Carried structured when the handle owns it.
final class SessionSpend {
  const SessionSpend({
    required this.decisions,
    required this.rounds,
    required this.tokens,
    required this.wallMs,
  });

  final int decisions;
  final int rounds;
  final int tokens;
  final int wallMs;

  Map<String, Object?> toJson() => {
    'decisions': decisions,
    'rounds': rounds,
    'tokens': tokens,
    'wallMs': wallMs,
  };

  @override
  String toString() =>
      'd$decisions r$rounds ${tokens}tok ${wallMs}ms';
}

/// The typed state snapshot a [SessionHandle] exposes — the same state
/// today's `debugState` carries (doc/session id, running flag, pending
/// permission, verdict, transcript tail, turn count), kept minimal and
/// host-owned. Projection-only fields (mesh status, roster labels) stay on
/// the projecting side; a reader that needs them extends its OWN
/// projection, not this registry contract.
final class SessionSnapshot {
  const SessionSnapshot({
    required this.sessionId,
    this.kind = 'session',
    this.running = false,
    this.pendingPermissionTitle,
    this.verdict,
    this.spend,
    this.transcriptTail = '',
    this.turnCount = 0,
    this.beats = const [],
    this.contextSummary = '',
  });

  /// The handle's own session id (the daemon session), which may differ
  /// from the registry key (the doc replica id) when the registry indexes
  /// one projection of a shared doc session.
  final String sessionId;

  /// What registered this handle — presence data only (never authority):
  /// `'surface'` (a UI doc surface), `'daemon'` (a harnessd runner),
  /// `'shadow'` (a peer viewer), `'test'` (a scripted seam). Free-form on
  /// purpose; readers render it, they never branch authority on it.
  final String kind;

  /// Whether a turn is running right now.
  final bool running;

  /// Title of the pending permission round-trip, if one awaits an answer.
  final String? pendingPermissionTitle;

  /// The latest verdict line, if any turn has ended.
  final String? verdict;

  /// Structured spend when the handle owns it as data; readers fall back
  /// to parsing [verdict] (same labels as today's controller).
  final SessionSpend? spend;

  /// The transcript tail (the streamed text projection).
  final String transcriptTail;

  /// Number of turns so far.
  final int turnCount;

  /// The tool beats that ran (what the dim mono rows render).
  final List<SessionBeat> beats;

  /// The context cut the model currently sees (the meaning profile /
  /// derived-context row, as data). Empty when the handle exposes none —
  /// honest absence, never a fabricated cut.
  final String contextSummary;

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'kind': kind,
    'running': running,
    'pendingPermissionTitle': ?pendingPermissionTitle,
    'verdict': ?verdict,
    'spend': ?spend?.toJson(),
    'turnCount': turnCount,
    'beats': [for (final beat in beats) beat.toJson()],
    'contextSummary': contextSummary,
    'transcriptTail': transcriptTail.length > 4000
        ? '${transcriptTail.substring(0, 4000)}…'
        : transcriptTail,
  };
}

/// The minimal seam the existing runner/session objects implement (ADR
/// 0009 D1): the typed state snapshot plus the intent actions today's
/// `debugSurface` seam carries — delegate a task sentence, answer the
/// pending permission. Deliberately ONE interface: a UI surface, a daemon
/// runner and a scripted test handle implement the same three members.
abstract interface class SessionHandle {
  /// The current typed state snapshot (re-read on every access — the
  /// projection must be live, never a cached copy).
  SessionSnapshot get state;

  /// Intent action: delegate a task sentence (host-injected decision).
  /// Returns immediately; the verdict lands in [SessionSnapshot].
  SessionIntentResult delegateTask(final String task);

  /// Intent action: answer the pending permission round-trip
  /// (allow = the write proceeds; reject = it never lands).
  SessionIntentResult answerPermission({required final bool allow});
}

/// The resolve failure that NAMES the live sessions (ADR 0009 D2 — honest
/// surfaces: never a silent wrong-target answer). The typed error carries
/// the live ids so a driver can list and retry with an explicit id.
final class SessionResolutionException implements Exception {
  SessionResolutionException(this.message, {required this.liveSessions});

  final String message;

  /// The currently live session ids at resolve time (named, ordered).
  final List<SessionId> liveSessions;

  @override
  String toString() => 'SessionResolutionException: $message';
}

/// ADR 0009 (D1) — the one index of live sessions on this device. See the
/// library docs for the presence-not-authority law and resolve semantics.
final class HarnessSessionRegistry {
  HarnessSessionRegistry();

  /// The shared registry — the one index the host, surfaces, daemon
  /// runners and profiler protocol readers converge on. Tests construct
  /// fresh instances for isolation.
  static final HarnessSessionRegistry instance = HarnessSessionRegistry();

  final Map<SessionId, SessionHandle> _sessions = {};

  /// Device-local focus marker ("last interaction"). Never synced — the
  /// OPEN QUESTION of ADR 0009 §Open questions 1 (what makes a session
  /// "focused" across windows and mesh peers is undecided; last UI
  /// interaction, device-local, is the current candidate and stays a
  /// local heuristic until that decision lands).
  SessionId? _focused;

  /// The live sessions, keyed by [SessionId] — UI surfaces, daemon
  /// runners, shadow viewers, tests: equal citizens. Unmodifiable view;
  /// mutate through [register]/[unregister] only.
  Map<SessionId, SessionHandle> get sessions =>
      UnmodifiableMapView(_sessions);

  /// The live session ids at read time (what an ambiguity error names).
  List<SessionId> get liveSessions => List.unmodifiable(_sessions.keys);

  /// The device-local focused session id, or null when nothing is marked.
  /// Unregistering the focused session clears the marker (a closed session
  /// never stays the answer); [resolve]'s stale-marker guard is defensive
  /// (an id marked before its session registers, or a future registrant
  /// that forgets to unregister). See the open question this field defers
  /// (ADR 0009 §Open questions 1) on the [focused] setter.
  SessionId? get focused => _focused;

  /// Marks [id] as the device-local focused session (the "last
  /// interaction" heuristic; ADR 0009 §Open questions 1). Device-local,
  /// never synced; callers mark on interaction, not on presence.
  set focused(final SessionId id) => _focused = id;

  /// Registers [handle] under [id]: PRESENCE, not authority (ADR 0007 §3
  /// analogy) — this grants observability and intent routing, never
  /// ownership of the session.
  ///
  /// Re-registering a live id REPLACES the previous handle (a new
  /// projection of the same session took over the slot — the same shape
  /// the widget statics had, but keyed and guarded, see [unregister]).
  /// Registration does not move focus; mark it explicitly via [focus].
  void register(final SessionId id, final SessionHandle handle) {
    _sessions[id] = handle;
  }

  /// Unregisters [handle] from [id] — with the IDENTICAL GUARD: the
  /// removal lands only when the live handle for [id] is identical to
  /// [handle] (the dispose-ordering law the widget statics carried,
  /// migrated to keyed slots). A STALE unregister — one whose slot was
  /// since replaced by a newer registration — is a no-op: it must never
  /// clobber the newer registration.
  ///
  /// Returns the removed handle, or null when nothing was removed
  /// (guard held, or [id] was not live).
  SessionHandle? unregister(final SessionId id, final SessionHandle handle) {
    final current = _sessions[id];
    if (current == null || !identical(current, handle)) return null;
    _sessions.remove(id);
    if (_focused == id) _focused = null;
    return handle;
  }

  /// Resolves a handle (ADR 0009 D2 — never a silent wrong-target answer):
  ///
  /// - explicit [id] → that exact session (unknown id → error naming the
  ///   live sessions);
  /// - absent id and exactly one live session → that session;
  /// - absent id and several live → the focused one ([focus]);
  /// - absent id, several live, no (live) focus →
  ///   [SessionResolutionException] NAMING the live sessions.
  ///
  /// Throws [SessionResolutionException] on every ambiguous or empty
  /// case — the error always names the live sessions.
  SessionHandle resolve({final SessionId? id}) {
    if (id != null) {
      final handle = _sessions[id];
      if (handle == null) {
        throw SessionResolutionException(
          'no live session "$id" — live sessions: '
          '[${_sessions.keys.join(', ')}]',
          liveSessions: liveSessions,
        );
      }
      return handle;
    }
    if (_sessions.isEmpty) {
      throw SessionResolutionException(
        'no live sessions are registered',
        liveSessions: const [],
      );
    }
    if (_sessions.length == 1) return _sessions.values.single;
    final focused = _focused;
    final focusedHandle = focused == null ? null : _sessions[focused];
    if (focusedHandle == null) {
      throw SessionResolutionException(
        'several sessions are live and none is focused — name one of: '
        '[${_sessions.keys.join(', ')}]',
        liveSessions: liveSessions,
      );
    }
    return focusedHandle;
  }
}
