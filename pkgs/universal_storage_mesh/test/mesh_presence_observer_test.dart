import 'dart:async';

import 'package:test/test.dart';
import 'package:universal_storage_mesh/universal_storage_mesh.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

/// Task N — passive presence observation (the two-device gate): the
/// fold must not require a local session. A device that never called
/// `joinDoc(doc)` (its doc opened before the mesh replica existed) must
/// still fold VERIFIED peer frames for `doc` — observation only, never
/// announcement (ADR 0031 §1: presence is doc-scoped; nothing here
/// sends). Frames a local session owns are skipped; unauthenticated
/// frames are dropped as named data, never folded.
final class _FakeEndpoint implements EphemeralFrameTransport {
  _FakeEndpoint(this.peerId, this._hub);

  final String peerId;
  final _FakeHub _hub;
  final sent = <MeshEphemeralFrame>[];

  // Broadcast fan-in with buffering until the FIRST listen — mirrors the
  // app's _PresenceLink so a session AND an observer can both listen.
  final _pending = <MeshEphemeralFrame>[];
  late final _frames = StreamController<MeshEphemeralFrame>.broadcast(
    onListen: _flushPending,
  );

  void _flushPending() {
    if (_pending.isEmpty) return;
    final buffered = List.of(_pending);
    _pending.clear();
    buffered.forEach(_frames.add);
  }

  @override
  EphemeralLinkState get connectionState => EphemeralLinkState.connected;

  @override
  Stream<EphemeralLinkState> get connectionChanges => const Stream.empty();

  @override
  Stream<MeshEphemeralFrame> get frames => _frames.stream;

  @override
  Future<void> send(final MeshEphemeralFrame frame) async {
    sent.add(frame);
    _hub._deliverFrom(peerId, frame);
  }

  void _receive(final MeshEphemeralFrame frame) {
    if (_frames.hasListener) {
      _frames.add(frame);
    } else {
      _pending.add(frame);
    }
  }

  void dispose() {
    unawaited(_frames.close());
  }
}

final class _FakeHub {
  final Map<String, _FakeEndpoint> _endpoints = {};

  _FakeEndpoint endpoint(final String peerId) =>
      _endpoints.putIfAbsent(peerId, () => _FakeEndpoint(peerId, this));

  void _deliverFrom(final String from, final MeshEphemeralFrame frame) {
    for (final endpoint in _endpoints.values) {
      if (endpoint.peerId != from) endpoint._receive(frame);
    }
  }
}

/// Lets async signing/verification chains and cross-endpoint delivery
/// settle.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

MeshPresenceSession _session({
  required final _FakeEndpoint transport,
  required final MeshPresenceTracker tracker,
  final String docId = 'doc/1',
  final EphemeralFrameSigner? signer,
  final EphemeralFrameAuthenticator? authenticator,
}) => MeshPresenceSession(
  transport: transport,
  tracker: tracker,
  docId: docId,
  signer: signer,
  authenticator: authenticator,
);

void main() {
  final t0 = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  test(
    'observer folds a verified peer frame for a doc with NO local '
    'session — presence is observable without joining',
    () async {
      final hub = _FakeHub();
      final host = hub.endpoint('device-a');
      final peer = hub.endpoint('device-b');
      final peerTracker = MeshPresenceTracker(actorId: 'device-b');
      final peerKeys = await PairingService.newIdentityKeyPair();
      final peerSession = _session(
        transport: peer,
        tracker: peerTracker,
        docId: 'agent-doc-1',
        signer: MeshFrameSigner(identityKeyPair: peerKeys),
      );
      unawaited(peerSession.open(now: t0));

      // Host: tracker + authenticator exist (link attached), but NO
      // session — the measured two-device topology.
      final hostTracker = MeshPresenceTracker(actorId: 'device-a');
      final hostAuth = MeshFrameAuthenticator();
      final observer = MeshPresenceObserver(
        tracker: hostTracker,
        authenticator: hostAuth,
        selfId: 'device-a',
        clock: () => t0,
      );
      final sub = observer.attach(host.frames);
      addTearDown(() async {
        await observer.dispose();
        await sub.cancel();
        await peerSession.close(now: t0);
        host.dispose();
        peer.dispose();
      });

      await _settle(); // peer's signed join travels to the host

      expect(
        hostTracker.presence('agent-doc-1').map((e) => e.peerId),
        contains('device-b'),
        reason: 'the host never joined, but the peer announcement must '
            'still be folded (observation, not announcement)',
      );
      expect(observer.rejectedFrameCount, 0);
    },
  );

  test(
    'observer skips frames for docs a local session owns and never '
    'folds its own echo',
    () async {
      final hub = _FakeHub();
      final host = hub.endpoint('device-a');
      final peer = hub.endpoint('device-b');
      final peerTracker = MeshPresenceTracker(actorId: 'device-b');
      final peerKeys = await PairingService.newIdentityKeyPair();
      final peerSession = _session(
        transport: peer,
        tracker: peerTracker,
        signer: MeshFrameSigner(identityKeyPair: peerKeys),
      );
      unawaited(peerSession.open(now: t0));

      final hostTracker = MeshPresenceTracker(actorId: 'device-a');
      final hostAuth = MeshFrameAuthenticator();
      var sessionOpen = false;
      final hostSession = _session(
        transport: host,
        tracker: hostTracker,
        authenticator: hostAuth,
      );
      final observer = MeshPresenceObserver(
        tracker: hostTracker,
        authenticator: hostAuth,
        selfId: 'device-a',
        hasLocalSession: (final docId) => sessionOpen && docId == 'doc/1',
        clock: () => t0,
      );
      final sub = observer.attach(host.frames);
      addTearDown(() async {
        await observer.dispose();
        await sub.cancel();
        await peerSession.close(now: t0);
        await hostSession.close(now: t0);
        host.dispose();
        peer.dispose();
      });

      await _settle();
      // Pre-session: the observer owns the fold.
      expect(
        hostTracker.presence('doc/1').map((e) => e.peerId),
        contains('device-b'),
      );

      // Session takes over the doc; the observer must not double-fold
      // (and double-reject) frames for it.
      sessionOpen = true;
      await hostSession.open(now: t0.add(const Duration(seconds: 1)));
      await peerSession.notifyActivity(now: t0.add(const Duration(seconds: 2)));
      await _settle();

      expect(
        hostTracker.presence('doc/1').map((e) => e.peerId),
        contains('device-b'),
      );
      expect(observer.rejectedFrameCount, 0);
    },
  );

  test(
    'observer drops unauthenticated frames as named data and never '
    'folds them',
    () async {
      final hub = _FakeHub();
      final host = hub.endpoint('device-a');
      final tracker = MeshPresenceTracker(actorId: 'device-a');
      final observer = MeshPresenceObserver(
        tracker: tracker,
        authenticator: MeshFrameAuthenticator(),
        selfId: 'device-a',
        clock: () => t0,
      );
      final sub = observer.attach(host.frames);
      addTearDown(() async {
        await observer.dispose();
        await sub.cancel();
        host.dispose();
      });

      // Unsigned frame (no signature at all), built with a scratch
      // tracker (announce folds locally) and sent from a scratch
      // endpoint so it arrives AT the observed host.
      final scratchTracker = MeshPresenceTracker(actorId: 'device-c');
      final op = scratchTracker.announce(
        docId: 'doc/1',
        event: MeshEphemeralEvent.join,
        now: t0,
      );
      await hub.endpoint('device-c').send(op);
      // Signed but by an unknown peer with a key the receiver cannot
      // trust yet (no ride-along) — unauthenticated.
      final forgerTracker = MeshPresenceTracker(actorId: 'device-x');
      final forgerPair = await PairingService.newIdentityKeyPair();
      final forgerSession = MeshPresenceSession(
        transport: hub.endpoint('device-x'),
        tracker: forgerTracker,
        docId: 'doc/1',
        signer: MeshFrameSigner(
          identityKeyPair: forgerPair,
          publishIdentityKey: false,
        ),
      );
      unawaited(forgerSession.open(now: t0));
      addTearDown(() async {
        await forgerSession.close(now: t0);
        hub.endpoint('device-x').dispose();
      });

      await _settle();

      expect(tracker.presence('doc/1'), isEmpty);
      expect(observer.rejectedFrameCount, 2);
      expect(
        observer.rejections.map((r) => r.reason).toSet(),
        {
          MeshFrameRejectionReason.unsigned,
          MeshFrameRejectionReason.unauthenticated,
        },
      );
    },
  );

  test(
    'observer drops frames whose kernel op is already expired (ttl '
    'backstop without any session cycle)',
    () async {
      final hub = _FakeHub();
      final host = hub.endpoint('device-a');
      final peer = hub.endpoint('device-b');
      final peerTracker = MeshPresenceTracker(actorId: 'device-b');
      final peerKeys = await PairingService.newIdentityKeyPair();
      // Peer announces with a clock in the past: by the time the host
      // folds it, the op's ttl has already elapsed.
      final past = t0.subtract(const Duration(hours: 1));
      final peerSession = MeshPresenceSession(
        transport: peer,
        tracker: peerTracker,
        docId: 'doc/1',
        signer: MeshFrameSigner(identityKeyPair: peerKeys),
        clock: () => past,
      );
      unawaited(peerSession.open(now: past));

      final hostTracker = MeshPresenceTracker(actorId: 'device-a');
      final observer = MeshPresenceObserver(
        tracker: hostTracker,
        authenticator: MeshFrameAuthenticator(),
        selfId: 'device-a',
        clock: () => t0,
      );
      final sub = observer.attach(host.frames);
      addTearDown(() async {
        await observer.dispose();
        await sub.cancel();
        await peerSession.close(now: past);
        host.dispose();
        peer.dispose();
      });

      await _settle();
      expect(hostTracker.presence('doc/1', now: t0), isEmpty);
    },
  );
}
