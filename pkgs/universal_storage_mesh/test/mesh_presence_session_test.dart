import 'dart:async';

import 'package:test/test.dart';
import 'package:universal_storage_mesh/universal_storage_mesh.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

/// In-proc fake transport pair-hub for headless session tests (ADR 0031
/// §2: any transport plugs in without touching the session). [send] fans
/// out to every other endpoint, mirroring the relay's broadcast.
final class _FakeEndpoint implements EphemeralFrameTransport {
  _FakeEndpoint(this.peerId, this._hub);

  final String peerId;
  final _FakeHub _hub;
  final _frames = StreamController<MeshEphemeralFrame>();
  final sent = <MeshEphemeralFrame>[];

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
    _frames.add(frame);
  }

  /// Never awaited: a listener-less single-subscription controller's
  /// close future does not complete.
  void dispose() {
    unawaited(_frames.close());
  }
}

final class _FakeHub {
  final Map<String, _FakeEndpoint> _endpoints = {};

  _FakeEndpoint endpoint(final String peerId) => _endpoints.putIfAbsent(
    peerId,
    () => _FakeEndpoint(peerId, this),
  );

  void _deliverFrom(final String from, final MeshEphemeralFrame frame) {
    for (final endpoint in _endpoints.values) {
      if (endpoint.peerId != from) endpoint._receive(frame);
    }
  }
}

MeshPresenceSession _session({
  required final _FakeEndpoint transport,
  required final MeshPresenceTracker tracker,
  final PresenceConfig presenceConfig = PresenceConfig.interactive,
  final EphemeralFrameSigner? signer,
  final EphemeralFrameAuthenticator? authenticator,
  final DateTime Function()? clock,
}) => MeshPresenceSession(
  transport: transport,
  tracker: tracker,
  docId: 'doc/1',
  presenceConfig: presenceConfig,
  signer: signer,
  authenticator: authenticator,
  clock: clock,
);

/// Lets async signing/verification chains and cross-endpoint delivery
/// settle.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  final t0 = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  group('session lifecycle over a fake transport (ADR 0031 §2)', () {
    test('join on open, ping on activity, leave on close', () async {
      final hub = _FakeHub();
      final endpoint = hub.endpoint('device-a');
      final tracker = MeshPresenceTracker(actorId: 'device-a');
      final session = _session(
        transport: endpoint,
        tracker: tracker,
        presenceConfig: const PresenceConfig(
          minPingInterval: Duration(milliseconds: 10),
          maxPingInterval: Duration(milliseconds: 40),
        ),
      );

      expect(session.isOpen, isFalse);
      await session.open(now: t0, details: {'display': 'Alice'});
      expect(session.isOpen, isTrue);

      // Join is folded locally AND published as a frame.
      expect(endpoint.sent, hasLength(1));
      final join = endpoint.sent.single;
      expect(join.event, MeshEphemeralEvent.join);
      expect(join.docId, 'doc/1');
      expect(tracker.presence('doc/1'), hasLength(1));
      expect(tracker.presence('doc/1').single.details['display'], 'Alice');

      // Activity pings immediately (no ping sent yet).
      await session.notifyActivity(now: t0.add(const Duration(seconds: 1)));
      expect(endpoint.sent, hasLength(2));
      expect(endpoint.sent.last.event, MeshEphemeralEvent.ping);

      // Throttled: a burst of activity does not flood frames.
      await session.notifyActivity(
        now: t0.add(const Duration(seconds: 1, milliseconds: 5)),
      );
      expect(endpoint.sent, hasLength(2));

      await session.close(now: t0.add(const Duration(seconds: 2)));
      expect(session.isOpen, isFalse);
      expect(endpoint.sent.last.event, MeshEphemeralEvent.leave);
      expect(tracker.presence('doc/1'), isEmpty);
      endpoint.dispose();
    });

    test('ttl expiry via sweep: silent peers drop out, idempotently', () async {
      final hub = _FakeHub();
      final endpoint = hub.endpoint('device-a');
      final tracker = MeshPresenceTracker(actorId: 'device-a');
      final session = _session(
        transport: endpoint,
        tracker: tracker,
        presenceConfig: const PresenceConfig(
          minPingInterval: Duration(seconds: 1),
          maxPingInterval: Duration(seconds: 5),
        ),
        clock: () => t0, // fixed fake clock for stamp determinism
      );

      // Join ttl = ttlFactor × maxPingInterval = 15s (ADR 0031 §5).
      await session.open(now: t0);
      const ttl = Duration(milliseconds: 15000);
      expect(tracker.presence('doc/1'), hasLength(1));

      final atBoundary = t0.add(ttl);
      expect(session.sweep(now: atBoundary), 0);
      expect(
        session.sweep(now: atBoundary.add(const Duration(milliseconds: 1))),
        1,
      );
      expect(tracker.presence('doc/1'), isEmpty);
      expect(session.sweep(now: atBoundary.add(const Duration(seconds: 1))), 0);

      await session.close();
      endpoint.dispose();
    });

    test('frames for other channels are ignored, not folded, not rejected',
        () async {
      final hub = _FakeHub();
      final endpoint = hub.endpoint('device-a');
      final tracker = MeshPresenceTracker(actorId: 'device-a');
      final session = _session(transport: endpoint, tracker: tracker);

      await session.open(now: t0);
      // A foreign-channel frame (built by a real tracker, by construction
      // valid) must be ignored: not folded, not rejected.
      hub.endpoint('device-b')._receive(
        MeshPresenceTracker(
          actorId: 'device-b',
        ).announce(docId: 'doc/2', event: MeshEphemeralEvent.join, now: t0),
      );
      await _settle();
      expect(tracker.presence('doc/1'), hasLength(1)); // only the local peer
      expect(tracker.presence('doc/2'), isEmpty);
      expect(session.rejectedFrameCount, 0);

      await session.close();
      endpoint.dispose();
    });
  });

  group('two sessions over one fake transport (ADR 0031 §2)', () {
    test('sessions see each other; leave removes the peer from the fold',
        () async {
      final hub = _FakeHub();
      final endpointA = hub.endpoint('device-a');
      final endpointB = hub.endpoint('device-b');
      final trackerA = MeshPresenceTracker(actorId: 'device-a');
      final trackerB = MeshPresenceTracker(actorId: 'device-b');
      final sessionA = _session(transport: endpointA, tracker: trackerA);
      final sessionB = _session(transport: endpointB, tracker: trackerB);

      await sessionA.open(details: {'display': 'Alice'});
      await sessionB.open(details: {'display': 'Bob'});
      await _settle();

      final onA = trackerA.presence('doc/1');
      expect(onA.map((e) => e.peerId), containsAll(['device-a', 'device-b']));
      expect(
        onA.singleWhere((e) => e.peerId == 'device-b').details['display'],
        'Bob',
      );
      expect(
        trackerB.presence('doc/1').map((e) => e.peerId),
        containsAll(['device-a', 'device-b']),
      );

      await sessionA.close();
      await _settle();
      expect(trackerB.presence('doc/1').map((e) => e.peerId), ['device-b']);

      await sessionB.close();
      endpointA.dispose();
      endpointB.dispose();
    });
  });

  group('frame authentication (ADR 0031 §3)', () {
    test('signed frames fold; tampered and forged frames are dropped as '
        'named data', () async {
      final hub = _FakeHub();
      final endpointA = hub.endpoint('device-a');
      final endpointB = hub.endpoint('device-b');

      final keyPairA = await PairingService.newIdentityKeyPair();
      final keyPairC = await PairingService.newIdentityKeyPair();
      final publicKeyA = await keyPairA.extractPublicKey();

      final trackerA = MeshPresenceTracker(actorId: 'device-a');
      final trackerB = MeshPresenceTracker(actorId: 'device-b');
      final authenticatorB = MeshFrameAuthenticator(
        identityKeys: {'device-a': publicKeyA.bytes},
      );
      final sessionA = _session(
        transport: endpointA,
        tracker: trackerA,
        signer: MeshFrameSigner(identityKeyPair: keyPairA),
      );
      final sessionB = _session(
        transport: endpointB,
        tracker: trackerB,
        authenticator: authenticatorB,
      );

      // A's signed join verifies against A's registered key, then folds.
      await sessionB.open(); // subscribes B before A's frame arrives
      await sessionA.open();
      await _settle();
      expect(sessionB.rejectedFrameCount, 0);
      expect(trackerB.presence('doc/1').map((e) => e.peerId), [
        'device-a',
        'device-b',
      ]);

      // Tampered: a real signature, but over a mutated payload.
      final signed = endpointA.sent.single;
      endpointB._receive(
        MeshEphemeralFrame(
          docId: signed.docId,
          fromPeerId: signed.fromPeerId,
          event: signed.event,
          ttl: signed.ttl,
          payload: {...signed.payload, 'op': 'smuggled'},
          issuedAtMs: DateTime.now().millisecondsSinceEpoch,
          signature: signed.signature,
        ),
      );
      await _settle();
      expect(sessionB.rejectedFrameCount, 1);
      expect(
        sessionB.rejections.single.reason,
        MeshFrameRejectionReason.unauthenticated,
      );
      expect(sessionB.rejections.single.frame.fromPeerId, 'device-a');
      expect(sessionB.rejections.single.frame.docId, 'doc/1');
      // Rejection never touched the fold: A is still present.
      expect(
        trackerB
            .presence('doc/1')
            .where((e) => e.peerId == 'device-a'),
        hasLength(1),
      );

      // Forged: C signs a frame claiming to be A — no fold, no trace.
      final forgedBase = MeshEphemeralFrame(
        docId: signed.docId,
        fromPeerId: 'device-a',
        event: signed.event,
        ttl: signed.ttl,
        payload: signed.payload,
        issuedAtMs: signed.issuedAtMs,
      );
      endpointB._receive(
        forgedBase.withSignature(
          await MeshFrameSigner(identityKeyPair: keyPairC).sign(forgedBase),
        ),
      );
      await _settle();
      expect(sessionB.rejectedFrameCount, 2);
      expect(
        trackerB
            .presence('doc/1')
            .where((e) => e.peerId == 'device-a'),
        hasLength(1),
      );

      await sessionA.close();
      await sessionB.close();
      endpointA.dispose();
      endpointB.dispose();
    });

    test('unsigned frames are rejected when an authenticator is configured',
        () async {
      final hub = _FakeHub();
      final endpointA = hub.endpoint('device-a');
      final endpointB = hub.endpoint('device-b');
      final keyPairA = await PairingService.newIdentityKeyPair();
      final publicKeyA = await keyPairA.extractPublicKey();
      final trackerB = MeshPresenceTracker(actorId: 'device-b');
      final sessionB = _session(
        transport: endpointB,
        tracker: trackerB,
        authenticator: MeshFrameAuthenticator(
          identityKeys: {'device-a': publicKeyA.bytes},
        ),
      );
      await sessionB.open();

      endpointB._receive(
        MeshEphemeralFrame(
          docId: 'doc/1',
          fromPeerId: 'device-a',
          event: MeshEphemeralEvent.join,
          ttl: const Duration(seconds: 30),
          issuedAtMs: t0.millisecondsSinceEpoch,
        ),
      );
      await _settle();
      expect(sessionB.rejectedFrameCount, 1);
      expect(
        sessionB.rejections.single.reason,
        MeshFrameRejectionReason.unsigned,
      );
      expect(trackerB.presence('doc/1').map((e) => e.peerId), ['device-b']);

      await sessionB.close();
      endpointA.dispose();
      endpointB.dispose();
    });
  });

  group('adaptive cadence (ADR 0031 §5)', () {
    test('idle cycles run at the max bound, activity pings immediately',
        () async {
      final hub = _FakeHub();
      final endpoint = hub.endpoint('device-a');
      final tracker = MeshPresenceTracker(actorId: 'device-a');
      final session = _session(
        transport: endpoint,
        tracker: tracker,
        presenceConfig: const PresenceConfig(
          minPingInterval: Duration(milliseconds: 10),
          maxPingInterval: Duration(milliseconds: 60),
        ),
      );

      await session.open();
      // Idle: the cycle runs at the max bound — 3+ pings within 200ms.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final pingsBefore = endpoint.sent
          .where((f) => f.event == MeshEphemeralEvent.ping)
          .length;
      expect(pingsBefore, greaterThanOrEqualTo(3));

      // Activity: immediate ping, stamped with the activity-cadence ttl.
      await session.notifyActivity();
      expect(endpoint.sent.last.event, MeshEphemeralEvent.ping);
      expect(
        endpoint.sent.last.ttl,
        const Duration(milliseconds: 30),
        reason: 'ttl = ttlFactor × pingInterval = 3 × 10ms under activity',
      );
      // Throttle: an immediate second burst adds nothing (min interval).
      final afterActivity = endpoint.sent.length;
      await session.notifyActivity();
      expect(endpoint.sent.length, afterActivity);

      await session.close();
      endpoint.dispose();
    });

    test('every published frame keeps the ttl invariant', () async {
      final hub = _FakeHub();
      final endpoint = hub.endpoint('device-a');
      final tracker = MeshPresenceTracker(actorId: 'device-a');
      const config = PresenceConfig(
        minPingInterval: Duration(milliseconds: 10),
        maxPingInterval: Duration(milliseconds: 60),
      );
      final session = _session(
        transport: endpoint,
        tracker: tracker,
        presenceConfig: config,
      );

      await session.open();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await session.notifyActivity();
      await _settle();

      for (final frame in endpoint.sent) {
        final ttl = frame.ttl;
        expect(
          ttl,
          anyOf(
            config.ttlFor(config.minPingInterval),
            config.ttlFor(config.maxPingInterval),
          ),
          reason: 'ttl = ttlFactor × pingInterval, within preset bounds',
        );
      }

      await session.close();
      endpoint.dispose();
    });
  });
}
