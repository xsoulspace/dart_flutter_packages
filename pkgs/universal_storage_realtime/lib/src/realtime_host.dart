import 'dart:async';

import 'package:meta/meta.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

import 'realtime_envelope.dart';
import 'realtime_link.dart';

/// The authority policy seam (ADR 0050 §4): given the current claim state,
/// decide who drives after [candidate] produced an event.
///
/// The default ([FirstClaimArbiter]) is the gesture-keyboard semantics:
/// the first sender to produce an app event claims; the claim holds while
/// the active sender keeps producing (within [FirstClaimArbiter
/// .handoffIdle]); an idle or gone sender yields to the next. Richer
/// policies (vosges's per-frame pointer fusion — a non-authoritative
/// view takes the continuous stream over when it is BETTER, not just
/// newer) implement this interface and use the host's non-authoritative
/// event surfacing; the library never hard-codes fusion.
abstract interface class RealtimeArbiter {
  /// The active sender after [candidate]'s event: [active] (kept), the
  /// [candidate] (handoff/claim), or null (release).
  String? arbitrate({
    required final String? active,
    required final String candidate,
    required final DateTime? activeLastEventAt,
    required final DateTime now,
  });
}

/// The default policy: first claimant wins; idle past [handoffIdle] or a
/// release hands authority to the candidate.
final class FirstClaimArbiter implements RealtimeArbiter {
  const FirstClaimArbiter({this.handoffIdle = const Duration(seconds: 3)});

  /// Must be positive (a zero idle makes every event a handoff race);
  /// not asserted in the const constructor — Duration comparison is not
  /// const-evaluable.
  final Duration handoffIdle;

  @override
  String? arbitrate({
    required final String? active,
    required final String candidate,
    required final DateTime? activeLastEventAt,
    required final DateTime now,
  }) {
    if (active == null || active == candidate) return candidate;
    final last = activeLastEventAt;
    if (last == null) return candidate;
    return now.difference(last) >= handoffIdle ? candidate : active;
  }
}

/// One adopted sender's UI snapshot.
@immutable
final class RealtimeSenderView {
  const RealtimeSenderView({
    required this.peerId,
    required this.lastActiveAt,
    required this.active,
  });

  final String peerId;
  final DateTime? lastActiveAt;
  final bool active;
}

/// The multi-sender realtime host (ADR 0050 §4): adopts sessions from a
/// CLAIMED plane ([ClaimingMeshTransport] with [looksLikeRealtimeFrame]),
/// keeps exactly one authoritative sender under [arbiter], and surfaces
/// EVERY app event with its authority flag — richer policies (per-frame
/// fusion) consume non-authoritative streams directly instead of
/// re-implementing session plumbing.
///
/// Release semantics (the safety law): a `release-all` from the active
/// sender, a stale sender, or a lost session fires [onReleaseAll] BEFORE
/// the claim clears, so whatever the sender was driving (held pinch, key,
/// pause) is let go before anyone else may drive.
final class RealtimeHost {
  RealtimeHost({
    required final MeshTransport claimedPlane,
    required this.selfId,
    this.arbiter = const FirstClaimArbiter(),
    this.onEvent,
    this.onReleaseAll,
    this.onSenderChanged,
    this.log,
    this.heartbeatInterval = const Duration(seconds: 2),
    this.staleAfter = const Duration(seconds: 8),
    this.clock = DateTime.now,
    this.tickDriven = false,
    this.adoptSession,
    this.onAdopted,
    this.isClaimable,
  }) : _plane = claimedPlane;

  final MeshTransport _plane;
  final String selfId;
  final RealtimeArbiter arbiter;

  /// Every decoded app event, from every sender. [RealtimeEvent] carries
  /// no authority flag by itself — check [eventIsAuthoritative] or the
  /// [activeSender].
  final void Function(RealtimeEvent event, {required bool authoritative})?
  onEvent;

  /// Fired whenever held input must be released: handoffs, sender loss,
  /// stale links, and sender-initiated release-alls.
  final void Function(String reason)? onReleaseAll;

  /// The active sender changed; null means no active sender.
  final void Function(String? sender, String reason)? onSenderChanged;

  /// Optional diagnostic sink (adoptions, drops, handoffs).
  final void Function(String message)? log;

  final Duration heartbeatInterval;
  final Duration staleAfter;
  final DateTime Function() clock;

  /// Pulse-law mode (ADR 0047 §4): links are created without internal
  /// timers and [tick] drives heartbeats/staleness from the consumer's
  /// own loop — required by hosts whose tests inject a clock and by apps
  /// that already run a watchdog.
  final bool tickDriven;

  /// The adoption gate (ADR 0050 §4): called with every inbound session
  /// BEFORE a link is created; returning false closes the session
  /// untouched. This is the AUTH seam — the plane may authenticate the
  /// transport, but the host decides which peers may drive. Null accepts
  /// every session (the transport is fully trusted).
  final bool Function(MeshSession session)? adoptSession;

  /// Fired after a session is adopted as a live sender link (after the
  /// gate). Policies that reclaim on reconnect (the gesture host's law: a
  /// returning controller resumes its slot without waiting to speak)
  /// hook this and call [claimSender].
  final void Function(String peerId)? onAdopted;

  /// Whether an event may MOVE authority (an announce/hello the app
  /// surfaces for classification or bookkeeping must not steal the claim
  /// or hand it off). Null: every app event is claimable (the default).
  final bool Function(RealtimeEvent event)? isClaimable;

  final Map<String, RealtimeLink> _links = {};
  final Map<String, DateTime?> _lastActiveAt = {};
  StreamSubscription<MeshSession>? _subscription;
  String? _activeSenderId;
  var _started = false;

  String? get activeSender => _activeSenderId;

  /// Connected while at least one sender session is alive.
  bool get hasSenders => _links.isNotEmpty;

  /// UI snapshot of the live senders.
  List<RealtimeSenderView> get senders => _links.keys
      .map(
        (final peerId) => RealtimeSenderView(
          peerId: peerId,
          lastActiveAt: _lastActiveAt[peerId],
          active: peerId == _activeSenderId,
        ),
      )
      .toList(growable: false);

  /// Whether [event] came from the current authority.
  bool eventIsAuthoritative(final RealtimeEvent event) =>
      event.senderPeerId == _activeSenderId;

  /// Starts accepting sender sessions from the claimed plane.
  void start() {
    if (_started) return;
    _started = true;
    _subscription = _plane.incoming.listen((final session) {
      final peerId = session.remotePeerId;
      if (peerId.isEmpty) {
        session.close();
        return;
      }
      final gate = adoptSession;
      if (gate != null && !gate(session)) {
        log?.call('sender $peerId rejected by the adoption gate');
        session.close();
        return;
      }
      _links[peerId]?.close();
      final link = RealtimeLink(
        session: session,
        heartbeatInterval: heartbeatInterval,
        staleAfter: staleAfter,
        clock: clock,
        tickDriven: tickDriven,
        onStale: (final reason) => _drop(peerId, reason),
      );
      _links[peerId] = link;
      _lastActiveAt[peerId] = null;
      log?.call('sender $peerId adopted (${_links.length} live)');
      onAdopted?.call(peerId);
      link.inbound.listen((final event) => _onEvent(peerId, event));
    });
  }

  /// Claims [peerId] when nobody holds authority; returns whether the
  /// claim was made. The reconnect law's primitive (see [onAdopted]):
  /// the claim is stamped as of NOW so another sender's next event does
  /// not immediately steal it via the idle-handoff path.
  bool claimSender(final String peerId, final String reason) {
    if (_activeSenderId != null) return false;
    if (!_links.containsKey(peerId)) return false;
    _activeSenderId = peerId;
    _lastActiveAt[peerId] = clock();
    onSenderChanged?.call(peerId, reason);
    log?.call('sender $peerId is active ($reason)');
    return true;
  }

  /// Pulse-law drive (tickDriven hosts): heartbeats every live link and
  /// drops the stale ones. A copy: [RealtimeLink.tick] may drop its own
  /// link mid-iteration.
  Future<void> tick() async {
    for (final link in List<RealtimeLink>.from(_links.values)) {
      await link.tick();
    }
  }

  /// Sends a droppable app frame to one sender over its link (the
  /// host-to-sender direction for app payloads — rebroadcasts, pushes).
  /// Returns false when the sender has no live link.
  Future<bool> sendTo(
    final String peerId,
    final String type,
    final Map<String, Object?> payload,
  ) async {
    final link = _links[peerId];
    if (link == null) return false;
    await link.sendDroppable(type, payload);
    return true;
  }

  /// Clears the claim as if the sender asked to stop.
  Future<void> releaseSender(final String peerId, final String reason) async {
    if (_activeSenderId != peerId) return;
    onReleaseAll?.call(reason);
    _activeSenderId = null;
    onSenderChanged?.call(null, reason);
  }

  void _onEvent(final String peerId, final RealtimeEvent event) {
    if (_links[peerId] == null) return; // A replaced link's late event.
    final claimable = isClaimable?.call(event) ?? true;
    if (claimable) _lastActiveAt[peerId] = clock();
    switch (event.type) {
      case RealtimeTypes.releaseAll:
        releaseSender(peerId, 'sender $peerId released control');
        return;
      case RealtimeTypes.heartbeat:
      case RealtimeTypes.heartbeatAck:
        return; // Link control: never surfaced, never authoritative.
      default:
        final authoritative = claimable
            ? _claimAfter(peerId)
            : peerId == _activeSenderId;
        onEvent?.call(event, authoritative: authoritative);
    }
  }

  /// Runs the arbiter and fires the change callbacks; returns whether
  /// [peerId] holds authority after this event.
  bool _claimAfter(final String peerId) {
    final next = arbiter.arbitrate(
      active: _activeSenderId,
      candidate: peerId,
      activeLastEventAt:
          _activeSenderId == null ? null : _lastActiveAt[_activeSenderId],
      now: clock(),
    );
    if (next == peerId && _activeSenderId != peerId) {
      final previous = _activeSenderId;
      if (previous != null) {
        onReleaseAll?.call('authority handed from $previous to $peerId');
      }
      _activeSenderId = peerId;
      onSenderChanged?.call(
        peerId,
        previous == null ? 'sender joined' : 'handoff from $previous',
      );
    } else if (next == null && _activeSenderId != null) {
      _activeSenderId = null;
      onSenderChanged?.call(null, 'arbiter released the claim');
    } else {
      _activeSenderId = next;
    }
    return _activeSenderId == peerId;
  }

  void _drop(final String peerId, final String reason) {
    final link = _links.remove(peerId);
    _lastActiveAt.remove(peerId);
    unawaited(link?.close());
    log?.call('sender $peerId dropped ($reason)');
    if (_activeSenderId == peerId) {
      onReleaseAll?.call('sender $peerId lost ($reason)');
      _activeSenderId = null;
      onSenderChanged?.call(null, 'sender $peerId $reason');
    }
  }

  Future<void> close() async {
    await _subscription?.cancel();
    for (final link in _links.values) {
      await link.close();
    }
    _links.clear();
    _activeSenderId = null;
  }
}
