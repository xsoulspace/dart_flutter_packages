/// Phases of a zone journey — the double-buffered border crossing
/// (ADR 0047 §5).
///
/// The defining property of a game-grade seamless journey: the OLD zone
/// stays live through [JourneyPhase.subscribing] and
/// [JourneyPhase.warming]; the switch itself is the atomic
/// [JourneyPhase.switching] re-point; [JourneyPhase.catchingUp] converges
/// the deltas that arrived during the overlap. NO phase is ever a loader —
/// surfaces render placeholders from catalog metadata, never spinners.
library;

/// The phases, in canonical order.
enum JourneyPhase {
  /// No journey in flight.
  idle,

  /// Publishing/refreshing the subscription for the destination zone.
  subscribing,

  /// Warming destination members behind the back of the live surface.
  warming,

  /// The atomic re-point: surfaces flip to the destination.
  switching,

  /// Converging deltas that arrived during the overlap.
  catchingUp,

  /// Destination settled; the journey is done (back to [JourneyPhase.idle]).
  settled,
}

/// Thrown on an out-of-order phase move — the state machine's way of
/// keeping orchestration honest.
final class JourneyTransitionError extends Error {
  JourneyTransitionError(this.from, this.to);

  final JourneyPhase from;
  final JourneyPhase to;

  @override
  String toString() =>
      'JourneyTransitionError: illegal $from -> $to '
      '(allowed: ${_allowed[from]?.map((final p) => p.name).join(", ")})';
}

const _allowed = <JourneyPhase, Set<JourneyPhase>>{
  JourneyPhase.idle: {JourneyPhase.subscribing, JourneyPhase.switching},
  // A cold journey (no census available to warm) may skip straight to the
  // switch — still seamless, just without prefetch.
  JourneyPhase.subscribing: {JourneyPhase.warming, JourneyPhase.switching},
  JourneyPhase.warming: {JourneyPhase.switching},
  // Nothing to catch up? switching -> settled directly.
  JourneyPhase.switching: {JourneyPhase.catchingUp, JourneyPhase.settled},
  JourneyPhase.catchingUp: {JourneyPhase.settled},
  JourneyPhase.settled: {JourneyPhase.idle},
};

/// Pure state machine for one journey (ADR 0047 §5).
///
/// Orchestration — driving warm IO, choosing when the overlap is deep
/// enough to switch — is the HOST's job; this type validates the ORDER and
/// carries the target. Abort is always legal from any non-idle phase.
final class JourneyState {
  JourneyState() : _phase = JourneyPhase.idle;

  JourneyPhase _phase;
  String? _targetDocId;

  JourneyPhase get phase => _phase;

  /// The destination member (usually the zone's catalog doc), set when the
  /// journey leaves idle.
  String? get targetDocId => _targetDocId;

  bool get isIdle => _phase == JourneyPhase.idle;

  bool canTransitionTo(final JourneyPhase next) =>
      next == JourneyPhase.idle || _allowed[_phase]!.contains(next);

  /// Moves to [next], optionally naming the destination on departure from
  /// idle. Throws [JourneyTransitionError] on an illegal move — an
  /// orchestration bug, deliberately loud.
  void transitionTo(final JourneyPhase next, {final String? targetDocId}) {
    if (!canTransitionTo(next)) {
      throw JourneyTransitionError(_phase, next);
    }
    if (_phase == JourneyPhase.idle) _targetDocId = targetDocId;
    _phase = next;
    if (next == JourneyPhase.idle) _targetDocId = null;
  }

  /// Abort from any phase (always legal).
  void abort() {
    _phase = JourneyPhase.idle;
    _targetDocId = null;
  }

  @override
  String toString() =>
      'JourneyState(${_phase.name}${_targetDocId == null ? "" : " -> $_targetDocId"})';
}
