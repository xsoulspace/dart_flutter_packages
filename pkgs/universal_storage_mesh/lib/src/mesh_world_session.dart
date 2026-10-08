import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';
import 'package:universal_storage_world/universal_storage_world.dart';

import 'ephemeral_frame_transport.dart';
import 'mesh_frame_auth.dart';
import 'mesh_presence_observer.dart';
import 'mesh_presence_session.dart';
import 'mesh_presence_tracker.dart';
import 'mesh_storage_provider.dart';
import 'mesh_sync_participant.dart';
import 'pairing_service.dart';
import 'presence_config.dart';
import 'relay_ephemeral_transport.dart';

/// The sync brain of one mesh replica, extracted from the app layer
/// (ADR 0047 §3): attached [MeshSyncParticipant]s, the host-driven pulse
/// cycle, presence over an ephemeral link, and interest publication.
///
/// Scheduling law (ADR 0047 §4): the session NEVER owns a loop. Hosts pull
/// [pulse] from whatever they already run — a game's ecsly schedule, a
/// Flutter ticker, a harness event loop. The only exception is the
/// [startPeriodicPulse] convenience adapter (a plain `Timer.periodic`),
/// provided for apps that want the old behavior verbatim; production hosts
/// are expected to drive the pulse themselves.
///
/// The user-facing flow stays tiny: attach participants, attach a presence
/// link when the transport comes up, let the host pulse. Pairing and relay
/// hosting stay ABOVE this class (app policy); the session consumes their
/// outcomes ([registerPeerIdentityKey], peers, attached transports).
final class MeshWorldSession implements Pulseable {
  MeshWorldSession({
    required this.storage,
    required this.selfId,
  });

  /// The storage this session syncs (its provider runs the anti-entropy
  /// exchange; mesh-backed providers also serve [peers] and interest).
  final StorageService storage;

  /// This replica's pairing peer id.
  final String selfId;

  /// The identity keypair source for presence-frame signing. Settable
  /// BEFORE first use: hosts funnel pairing and presence through ONE
  /// keypair (an app registers peers by their pairing identity key, so
  /// presence frames must be signed by that same identity). Default:
  /// generate on first use.
  Future<SimpleKeyPair> Function() identityKeyPairProvider =
      PairingService.newIdentityKeyPair;

  SimpleKeyPair? _identityKeyPair;
  Future<SimpleKeyPair>? _identityFuture;

  final List<MeshSyncParticipant> _participants = [];

  /// Registers [participant] in the sync cycle (registration only —
  /// nothing is written until the next [pulse]/[sync]). The caller keeps
  /// ownership (lifecycle, dispose); this session never disposes it.
  void attachParticipant(final MeshSyncParticipant participant) {
    _participants.add(participant);
  }

  /// Participants attached via [attachParticipant] (read-only view).
  List<MeshSyncParticipant> get participants =>
      List.unmodifiable(_participants);

  /// Invoked after every pulse (success or failure) — the embedding host
  /// refreshes its projections from the fold here. Without it a periodic
  /// absorb would never reach an open surface.
  void Function()? onCycle;

  /// Publishes what this replica wants DELIVERED (ADR 0048 §2), resolved
  /// immediately; re-set before every pulse for per-cycle re-evaluation.
  /// Null clears back to the wildcard.
  void setInterest(final InterestPolicy? policy) {
    final provider = storage.provider;
    if (provider is MeshStorageProvider) provider.setInterest(policy);
  }

  /// Receiver-expressed delivery preference (ADR 0048 §3).
  void setDeliveryPriority(final Map<String, int> priority) {
    final provider = storage.provider;
    if (provider is MeshStorageProvider) provider.setDeliveryPriority(priority);
  }

  /// Asks peers to cap their delta (backpressure-lite, ADR 0048 §3).
  void setIncomingBudget(final int? maxOps) {
    final provider = storage.provider;
    if (provider is MeshStorageProvider) provider.setIncomingBudget(maxOps);
  }

  /// Paired peers, when the storage provider is mesh-backed.
  Iterable<MeshPeerRecord> get peers {
    final provider = storage.provider;
    return provider is MeshStorageProvider ? provider.peers : const [];
  }

  // -- Sync cycle -----------------------------------------------------------

  /// Anti-entropy with every known peer, wrapped in the participant seam:
  /// flush every participant before the exchange, absorb after, compact
  /// last. Wrapped in a timeout because an addressed relay silently drops
  /// frames addressed to offline peers; without it manual sync hangs.
  Future<void> sync({
    final Duration timeout = const Duration(minutes: 1),
  }) async {
    await _syncCycle().timeout(timeout);
  }

  Future<void> _syncCycle() async {
    for (final participant in _participants) {
      await participant.flush(storage);
    }
    await storage.syncRemote();
    for (final participant in _participants) {
      await participant.absorb(storage);
    }
    for (final participant in _participants) {
      await participant.compact(storage);
    }
  }

  // -- Host-driven pulse (ADR 0047 §4) ---------------------------------------

  Future<void>? _pulseInFlight;
  Timer? _pulseTimer;

  /// Runs at most one sync cycle (coalescing: a pulse landing while a
  /// cycle is in flight is skipped, never queued). Errors are
  /// swallowed-and-recorded: a failed background cycle surfaces via the
  /// host's status or the next pulse, never by throwing into the host's
  /// loop. [onCycle] fires even after a failed cycle — the fold may still
  /// have moved.
  @override
  Future<void> pulse() {
    final inFlight = _pulseInFlight;
    if (inFlight != null) return inFlight;
    final cycle = sync()
        .catchError((final Object error) {
          // Background cycle: never break the host's loop on a relay drop
          // or timeout.
        })
        .whenComplete(() {
          _pulseInFlight = null;
          onCycle?.call();
        });
    _pulseInFlight = cycle;
    return cycle;
  }

  /// CONVENIENCE adapter driving [pulse] every [interval] (the pre-0047
  /// app behavior, kept for parity). A pulse landing while a cycle is
  /// still running is skipped — the next tick picks the work up.
  /// Production hosts drive [pulse] from their own scheduler instead.
  void startPeriodicPulse({
    final Duration interval = const Duration(seconds: 30),
  }) {
    stopPeriodicPulse();
    _pulseTimer = Timer.periodic(interval, (final _) {
      unawaited(pulse());
    });
  }

  void stopPeriodicPulse() {
    _pulseTimer?.cancel();
    _pulseTimer = null;
  }

  /// Whether the periodic pulse adapter is armed
  /// ([stopPeriodicPulse] and [dispose] disarm it).
  bool get isPeriodicPulseRunning => _pulseTimer?.isActive ?? false;

  // -- Presence over an ephemeral link (ADR 0031 §1–2) -----------------------

  /// Cadence policy for the presence sessions this session opens
  /// (ADR 0031 §5: policy-with-bounds, chosen by the embedding host).
  PresenceConfig presenceConfig = PresenceConfig.background;

  final Map<String, MeshPresenceSession> _presenceSessions = {};

  /// Docs the CALLER asked to join (ADR 0031 §1: presence is doc-scoped;
  /// the session never decides which docs are open). Re-opened whenever
  /// the presence link (re)connects.
  final Set<String> _presenceDocs = {};
  MeshPresenceTracker? _presenceTracker;
  MeshFrameAuthenticator? _presenceAuthenticator;
  _PresenceLink? _presenceLink;
  AddressedRelayEphemeralTransport? _ownedRelayPresenceTransport;
  StreamSubscription<EphemeralLinkState>? _presenceLinkSub;
  Future<void>? _presenceOpening;
  var _ownsPresenceTransport = false;

  /// Passive presence observation (ADR 0031 §1–2): folds verified peer
  /// frames for docs with no local session, so a doc that opened before
  /// this replica existed still SEES peers — observation only, never
  /// announcement.
  MeshPresenceObserver? _presenceObserver;

  /// Joins [docId]'s presence channel. Doc-scoped join is the CALLER's
  /// job (ADR 0031 §1). When the presence link is up, the join frame goes
  /// out immediately; otherwise the doc stays queued and joins on the
  /// next (re)connect.
  Future<void> joinDoc(final String docId) async {
    _presenceDocs.add(docId);
    final link = _presenceLink;
    if (link != null &&
        link.connectionState == EphemeralLinkState.connected) {
      await _openPresenceSessions();
    }
  }

  /// Leaves [docId]'s presence channel: a signed leave frame goes out so
  /// peers drop this peer immediately (ADR 0031 §1).
  Future<void> leaveDoc(final String docId) async {
    _presenceDocs.remove(docId);
    final session = _presenceSessions.remove(docId);
    if (session != null) await _closePresenceSession(session);
  }

  /// Liveness refresh on the doc's channel (ADR 0031 §5: ping on
  /// activity). Best-effort: a dead link swallows the ping — peers' ttl
  /// sweeps are the crash backstop.
  Future<void> notifyPresenceActivity(final String docId) async {
    final session = _presenceSessions[docId];
    if (session == null) return;
    try {
      await session.notifyActivity();
    } on Object {
      // Link down mid-ping: presence is observation, never durability.
    }
  }

  /// Live presence for [docId] — the tracker fold over unexpired
  /// ephemeral ops (ADR 0029 §1, ADR 0031 §2). Sweeps on read (expiry is
  /// the crash backstop).
  List<MeshPresenceEntry> presence(
    final String docId, {
    final DateTime? now,
  }) =>
      _presenceTracker?.presence(docId, now: now ?? DateTime.now()) ??
      const [];

  /// How many inbound presence frames were dropped as named data
  /// (ADR 0031 §3) across every open doc session and the passive observer.
  int get rejectedPresenceFrameCount =>
      (_presenceObserver?.rejectedFrameCount ?? 0) +
      _presenceSessions.values.fold(
        0,
        (final n, final session) => n + session.rejectedFrameCount,
      );

  /// Every dropped presence frame with its rejection reason, oldest
  /// first, across every open doc session and the passive observer.
  List<MeshFrameRejection> get presenceFrameRejections => [
    ...?_presenceObserver?.rejections,
    for (final session in _presenceSessions.values) ...session.rejections,
  ];

  /// Owns the presence channel over a relay client's connection: the
  /// session constructs the relay transport and disposes it at teardown.
  void attachRelayPresenceLink(final AddressedRelayClient client) {
    _startPresenceLink(
      AddressedRelayEphemeralTransport(client: client),
      ownedBySession: true,
    );
  }

  /// Attaches a caller-owned ephemeral link (any transport plugs in,
  /// ADR 0031 §2). The session never disposes caller-owned transports.
  void attachPresenceLink(
    final EphemeralFrameTransport transport, {
    final bool ownedBySession = false,
  }) => _startPresenceLink(transport, ownedBySession: ownedBySession);

  /// Test seam kept from the app service: same as [attachPresenceLink]
  /// with the caller keeping ownership.
  @visibleForTesting
  void attachPresenceTransport(final EphemeralFrameTransport transport) =>
      attachPresenceLink(transport);

  void _startPresenceLink(
    final EphemeralFrameTransport inner, {
    required final bool ownedBySession,
  }) {
    unawaited(_stopPresenceLink(sendLeaves: false));
    _presenceTracker ??= MeshPresenceTracker(actorId: selfId);
    _presenceAuthenticator ??= MeshFrameAuthenticator();
    _seedAuthenticatorFromPeers();
    final link = _PresenceLink(inner);
    _presenceLink = link;
    _ownsPresenceTransport = ownedBySession;
    _ownedRelayPresenceTransport =
        ownedBySession && inner is AddressedRelayEphemeralTransport
        ? inner
        : null;
    _presenceLinkSub = link.connectionChanges.listen(_onPresenceLinkChanged);
    // Observe every channel the link carries (ADR 0031 §2): docs with a
    // local session are skipped (the session verifies + folds them);
    // everything else still folds so presence(doc) answers for docs this
    // device never announced on.
    unawaited(_presenceObserver?.dispose());
    _presenceObserver =
        MeshPresenceObserver(
            tracker: _presenceTracker!,
            authenticator: _presenceAuthenticator!,
            selfId: selfId,
            hasLocalSession: _presenceSessions.containsKey,
          );
    _presenceObserver!.attach(link.frames);
    if (link.connectionState == EphemeralLinkState.connected) {
      unawaited(_openPresenceSessions());
    }
  }

  void _onPresenceLinkChanged(final EphemeralLinkState state) {
    switch (state) {
      case EphemeralLinkState.connected:
        // Re-join the docs the caller asked for; the link came back.
        unawaited(_openPresenceSessions());
      case EphemeralLinkState.disconnected:
        // Stop join/ping/leave lifecycle with the link; pings stop
        // immediately and peers expire this peer via their ttl sweep.
        _closeAllPresenceSessions();
    }
  }

  /// Serialized: concurrent triggers (attach-time connect, link
  /// recovery, [joinDoc]) share ONE open cycle — a caller must never
  /// observe a half-opened session. The cycle never throws: presence is
  /// best-effort observation, and a cycle killed by a link replacement is
  /// simply re-run by the next connect event.
  Future<void> _openPresenceSessions() {
    final inFlight = _presenceOpening;
    if (inFlight != null) return inFlight;
    final cycle = _openPresenceSessionsNow()
        .catchError((final Object _) {
          // Link replaced or transport gone mid-cycle.
        })
        .whenComplete(() => _presenceOpening = null);
    _presenceOpening = cycle;
    return cycle;
  }

  Future<void> _openPresenceSessionsNow() async {
    final link = _presenceLink;
    final authenticator = _presenceAuthenticator;
    if (link == null || authenticator == null) return;
    final transport = link;
    final signer = MeshFrameSigner(
      identityKeyPair: await _ensureIdentity(),
    );
    for (final docId in _presenceDocs) {
      if (!identical(_presenceLink, link)) {
        return; // Link replaced mid-cycle — the next connect event reruns.
      }
      if (_presenceSessions.containsKey(docId)) continue;
      final session = MeshPresenceSession(
        transport: transport,
        tracker: _presenceTracker!,
        docId: docId,
        presenceConfig: presenceConfig,
        signer: signer,
        authenticator: authenticator,
      );
      _presenceSessions[docId] = session;
      await session.open();
    }
  }

  void _closeAllPresenceSessions() {
    final sessions = List.of(_presenceSessions.values);
    _presenceSessions.clear();
    for (final session in sessions) {
      unawaited(_closePresenceSession(session));
    }
  }

  Future<void> _closePresenceSession(final MeshPresenceSession session) async {
    try {
      await session.close(); // leave frame; best-effort
    } on Object {
      // Link died mid-leave: peers' ttl sweeps are the backstop
      // (ADR 0031 §1).
    }
  }

  Future<void> _stopPresenceLink({required final bool sendLeaves}) async {
    // Tear the link down SYNCHRONOUSLY first: a replacement link may
    // already be attaching by the time the awaits below settle, so every
    // old-link resource is captured into locals up front and only those
    // locals are touched afterwards.
    unawaited(_presenceLinkSub?.cancel());
    _presenceLinkSub = null;
    unawaited(_presenceObserver?.dispose());
    _presenceObserver = null;
    final sessions = List.of(_presenceSessions.values);
    _presenceSessions.clear();
    final oldLink = _presenceLink;
    _presenceLink = null;
    final oldRelayTransport = _ownedRelayPresenceTransport;
    _ownedRelayPresenceTransport = null;
    final owned = _ownsPresenceTransport;
    _ownsPresenceTransport = false;
    if (sendLeaves) {
      for (final session in sessions) {
        await _closePresenceSession(session);
      }
    }
    await oldLink?.dispose();
    if (owned && oldRelayTransport != null) {
      unawaited(oldRelayTransport.dispose());
    }
  }

  // -- Peer frame authentication (ADR 0031 §3) ----------------------------

  /// Registers [peerId]'s public identity key in the frame authenticator.
  /// Peers recorded WITHOUT key bytes stay sync-only: their frames are
  /// rejected as unauthenticated named data, never folded.
  void registerPeerIdentityKey({
    required final String peerId,
    required final List<int> identityKey,
  }) {
    if (identityKey.isEmpty) return;
    _presenceAuthenticator ??= MeshFrameAuthenticator();
    _presenceAuthenticator!.registerIdentityKey(
      peerId: peerId,
      identityKey: identityKey,
    );
  }

  void _seedAuthenticatorFromPeers() {
    final authenticator = _presenceAuthenticator;
    if (authenticator == null) return;
    for (final peer in peers) {
      registerPeerIdentityKey(
        peerId: peer.peerId,
        identityKey: peer.identityKey,
      );
    }
  }

  // -- Lifecycle ------------------------------------------------------------

  Future<void> dispose() async {
    // Leave frames BEFORE the link dies (ADR 0031 §1: leave on close; a
    // crash that skips this is covered by peers' ttl sweeps).
    stopPeriodicPulse();
    await _stopPresenceLink(sendLeaves: true);
  }

  /// Race-safe: concurrent callers share one key-generation future
  /// instead of each starting their own (and racing the assignment).
  Future<SimpleKeyPair> _ensureIdentity() {
    final existing = _identityKeyPair;
    if (existing != null) return Future<SimpleKeyPair>.value(existing);
    return _identityFuture ??= identityKeyPairProvider().then(
      (final keyPair) {
        _identityKeyPair = keyPair;
        return keyPair;
      },
    );
  }
}

/// The relay-client seam [attachRelayPresenceLink] needs. Structural (not
/// an import) so the session stays decoupled from relay specifics.
/// Internal fan-in over the presence link's transport (ADR 0031 §2):
/// gives every doc session a BROADCAST view of the transport's
/// one-shot frame stream, so sessions can be closed on connection loss
/// and re-opened on recovery without exhausting the underlying
/// transport's single listen.
final class _PresenceLink implements EphemeralFrameTransport {
  _PresenceLink(this._inner) {
    _framesSub = _inner.frames.listen(_onInnerFrame);
    _changesSub = _inner.connectionChanges.listen(_changes.add);
  }

  final EphemeralFrameTransport _inner;

  /// Frames that arrived while NO session was listening (between doc
  /// sessions, or across a disconnect). Replayed on the next listen —
  /// the transport contract is "buffered until listened, never dropped"
  /// and the kernel's op-id dedupe makes replaying stale frames
  /// harmless.
  final List<MeshEphemeralFrame> _pending = [];

  late final _frames = StreamController<MeshEphemeralFrame>.broadcast(
    onListen: _flushPending,
  );
  final _changes = StreamController<EphemeralLinkState>.broadcast();
  StreamSubscription<MeshEphemeralFrame>? _framesSub;
  StreamSubscription<EphemeralLinkState>? _changesSub;

  void _flushPending() {
    if (_pending.isEmpty) return;
    final buffered = List.of(_pending);
    _pending.clear();
    buffered.forEach(_frames.add);
  }

  void _onInnerFrame(final MeshEphemeralFrame frame) {
    if (_frames.hasListener) {
      _frames.add(frame);
    } else {
      _pending.add(frame);
    }
  }

  @override
  Stream<MeshEphemeralFrame> get frames => _frames.stream;

  @override
  EphemeralLinkState get connectionState => _inner.connectionState;

  @override
  Stream<EphemeralLinkState> get connectionChanges => _changes.stream;

  @override
  Future<void> send(final MeshEphemeralFrame frame) => _inner.send(frame);

  /// Stops consuming the inner transport and closes the broadcast
  /// streams. Never awaited from teardown paths that must stay
  /// synchronous-first.
  Future<void> dispose() async {
    await _framesSub?.cancel();
    await _changesSub?.cancel();
    unawaited(_frames.close());
    unawaited(_changes.close());
  }
}
