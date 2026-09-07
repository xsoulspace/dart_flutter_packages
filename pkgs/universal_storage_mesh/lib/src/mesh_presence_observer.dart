import 'dart:async';

import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

import 'ephemeral_frame_auth.dart';
import 'mesh_presence_session.dart'
    show MeshFrameRejection, MeshFrameRejectionReason, PresenceClock;
import 'mesh_presence_tracker.dart';

/// Passive presence observation for doc channels THIS device has no
/// local session on (ADR 0031 §1–2, measured two-device gate: a host
/// whose doc opened before its mesh replica existed never calls
/// `joinDoc`, so it has no [MeshPresenceSession] on the channel — and
/// the peers' join/ping frames were buffered forever by the link fan-in
/// instead of being folded. The tracker fold is OBSERVATION, never
/// announcement: folding what verified peers announce about THEMSELVES
/// makes `presence(doc)` agent-queryable for every channel the relay
/// carries, while this device still announces on the docs IT joined —
/// "a background sync must not make a device visible as present in a
/// document it never opened" stays true because nothing here ever sends.
///
/// Frame ownership is decided SYNCHRONOUSLY at arrival: frames for docs
/// a local [MeshPresenceSession] already owns are skipped (the session
/// verifies + folds them; skipping keeps rejection counts
/// single-counted); every other verified frame is folded here. This
/// closes the fan-in replay window: a frame that arrives BEFORE the
/// session subscribes is folded by this observer instead of being
/// buffered for a session that will never replay it. Frames a session
/// would reject are rejected here with the same named-data discipline
/// (ADR 0031 §3): counted in [rejections], never folded.
///
/// Expired entries are swept opportunistically on every fold — a device
/// with no open sessions has no session ping cycle to sweep for it, so
/// the ttl crash backstop (ADR 0031 §1) rides the observer. Readers
/// sweep on read (`MeshPresenceTracker.presence(now:)`).
///
/// ```dart
/// final observer = MeshPresenceObserver(
///   tracker: tracker,
///   authenticator: authenticator,
///   selfId: selfId,
///   hasLocalSession: presenceSessions.containsKey,
/// )..attach(link.frames);
/// ```
final class MeshPresenceObserver {
  MeshPresenceObserver({
    required this.tracker,
    required this.authenticator,
    required this.selfId,
    this.hasLocalSession,
    PresenceClock? clock,
  }) : _clock = clock ?? _systemClock;

  static DateTime _systemClock() => DateTime.now();

  /// The kernel fold inbound frames are absorbed into.
  final MeshPresenceTracker tracker;

  /// Verifies inbound frames before any fold (ADR 0031 §3) — the same
  /// authenticator the local sessions use, so TOFU binds learned keys
  /// exactly once and pins are shared with the sessions.
  final EphemeralFrameAuthenticator authenticator;

  /// Local peer id — frames claiming it are local echoes, never folded.
  final String selfId;

  /// Whether a local session already owns [docId]'s fold, consulted
  /// SYNCHRONOUSLY when the frame ARRIVES (not when its async
  /// verification chain runs — the session map may grow in between).
  /// `null` means "no local sessions": every verified frame is folded.
  final bool Function(String docId)? hasLocalSession;

  final PresenceClock _clock;

  StreamSubscription<MeshEphemeralFrame>? _framesSub;
  Future<void> _inbound = Future<void>.value();
  var _disposed = false;
  final List<MeshFrameRejection> _rejections = [];

  /// Starts consuming [frames]. Returns the subscription (also cancelled
  /// by [dispose]); safe to call once per observer.
  StreamSubscription<MeshEphemeralFrame> attach(
    final Stream<MeshEphemeralFrame> frames,
  ) => frames.listen(_onFrame);

  /// How many inbound frames were dropped as named data (ADR 0031 §3).
  int get rejectedFrameCount => _rejections.length;

  /// Every dropped frame with its rejection reason, oldest first.
  List<MeshFrameRejection> get rejections => List.unmodifiable(_rejections);

  /// Drops expired entries from the tracker; also run before every fold.
  int sweep({final DateTime? now}) => tracker.sweep(now ?? _clock());

  /// Stops consuming; queued frames are ignored.
  Future<void> dispose() async {
    _disposed = true;
    await _framesSub?.cancel();
    _framesSub = null;
  }

  void _onFrame(final MeshEphemeralFrame frame) {
    // Ownership is decided NOW, synchronously: the verification chain
    // below runs in a later microtask, by which time a local session may
    // have opened for this doc — and a frame delivered here was NEVER
    // seen by that session (it subscribed after this broadcast event).
    final owned = hasLocalSession?.call(frame.docId) ?? false;
    // Serialize so verification + fold order matches arrival; one bad
    // frame never kills the pipeline (mirrors the session's inbound
    // chain — that frame is simply not folded, the next one is).
    _inbound = _inbound
        .then((_) => _processFrame(frame, owned))
        .catchError((final Object _) {});
  }

  Future<void> _processFrame(
    final MeshEphemeralFrame frame,
    final bool owned,
  ) async {
    if (_disposed || owned) return;
    if (frame.fromPeerId == selfId) return; // local echo
    final authentic = await authenticator.verify(frame);
    if (!authentic) {
      _rejections.add(
        MeshFrameRejection(
          frame: frame,
          reason: frame.signature == null
              ? MeshFrameRejectionReason.unsigned
              : MeshFrameRejectionReason.unauthenticated,
        ),
      );
      return; // dropped as named data — never folded (ADR 0031 §3)
    }
    // Expiry rides the fold: no session ping cycle sweeps for a device
    // with no open sessions, so this is the ttl backstop here.
    tracker.sweep(_clock());
    tracker.handleFrame(frame, now: _clock());
  }
}
