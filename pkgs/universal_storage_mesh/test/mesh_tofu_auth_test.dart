import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';
import 'package:universal_storage_mesh/universal_storage_mesh.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

/// v1 relay-owned TOFU with key pinning (ADR 0031 §3, see
/// [MeshFrameAuthenticator]'s class doc): pairing is asymmetric — the
/// host prints the pairing payload, the peer accepts — so the host never
/// learns the peer's identity key out of band and the peer's signed
/// frames were dropped host-side. These tests pin down the fix: an
/// unknown peer's first verifiable signed frame binds `peerId → key`,
/// registers the peer record (persisted with the replica, web store
/// included), and folds; later frames verify against the pin; a
/// different key for a bound peerId is rejected as named data; and
/// pre-shared (paired) peers are unchanged.
void main() {
  final t0 = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  Future<SimpleKeyPair> newKeyPair() => PairingService.newIdentityKeyPair();

  /// Builds a tracker-issued frame carrying the signer's public identity
  /// key ride-along ([kIdentityKeyPayloadKey]) and its signature —
  /// exactly what [MeshPresenceSession] sends when its signer is a
  /// [MeshFrameSigner].
  Future<MeshEphemeralFrame> signedFrame({
    required final MeshPresenceTracker tracker,
    required final SimpleKeyPair keyPair,
    final MeshEphemeralEvent event = MeshEphemeralEvent.join,
    final DateTime? now,
    final bool rideAlong = true,
    final Map<String, Object?>? extraPayload,
  }) async {
    final publicKey = await keyPair.extractPublicKey();
    final base = tracker.announce(
      docId: 'doc/1',
      event: event,
      now: now ?? t0,
      ttl: const Duration(seconds: 30),
      details: {'display': 'Peer'},
    );
    final frame = MeshEphemeralFrame(
      docId: base.docId,
      fromPeerId: base.fromPeerId,
      event: base.event,
      ttl: base.ttl,
      payload: {
        ...base.payload,
        if (rideAlong) kIdentityKeyPayloadKey: base64Encode(publicKey.bytes),
        ...?extraPayload,
      },
      issuedAtMs: base.issuedAtMs,
    );
    return frame.withSignature(
      await MeshFrameSigner(identityKeyPair: keyPair).sign(frame),
    );
  }

  group('TOFU binding (unknown peer)', () {
    test('first signed frame binds the key; second verifies against the '
        'pin', () async {
      final keyPair = await newKeyPair();
      final peerTracker = MeshPresenceTracker(actorId: 'peer-1');
      final authenticator = MeshFrameAuthenticator();
      expect(authenticator.identityKeys, isEmpty);

      final join = await signedFrame(tracker: peerTracker, keyPair: keyPair);
      expect(await authenticator.verify(join), isTrue);
      // Bound on first contact: peerId → key is pinned.
      expect(
        authenticator.identityKeys['peer-1'],
        (await keyPair.extractPublicKey()).bytes,
      );

      // Later frames from the same peer verify against the pin.
      final ping = await signedFrame(
        tracker: peerTracker,
        keyPair: keyPair,
        event: MeshEphemeralEvent.ping,
        now: t0.add(const Duration(seconds: 1)),
      );
      expect(await authenticator.verify(ping), isTrue);
      expect(authenticator.identityKeys, hasLength(1));
    });

    test('a signed frame without a usable ride-along stays rejected '
        '(named data, nothing learned)', () async {
      final keyPair = await newKeyPair();
      final peerTracker = MeshPresenceTracker(actorId: 'peer-1');
      final authenticator = MeshFrameAuthenticator();

      final frame = await signedFrame(
        tracker: peerTracker,
        keyPair: keyPair,
        rideAlong: false,
      );
      expect(await authenticator.verify(frame), isFalse);
      expect(authenticator.identityKeys, isEmpty);
    });

    test('unsigned frames stay rejected', () async {
      final authenticator = MeshFrameAuthenticator();
      final unsigned = MeshPresenceTracker(
        actorId: 'peer-1',
      ).announce(docId: 'doc/1', event: MeshEphemeralEvent.join, now: t0);
      expect(unsigned.signature, isNull);
      expect(await authenticator.verify(unsigned), isFalse);
      expect(authenticator.identityKeys, isEmpty);
    });

    test('malformed ride-alongs never learn a key', () async {
      final keyPair = await newKeyPair();
      final peerTracker = MeshPresenceTracker(actorId: 'peer-1');
      final authenticator = MeshFrameAuthenticator();

      // Not base64 at all.
      final garbage = await signedFrame(
        tracker: peerTracker,
        keyPair: keyPair,
        extraPayload: {kIdentityKeyPayloadKey: 'not base64 !!'},
      );
      expect(await authenticator.verify(garbage), isFalse);
      expect(authenticator.identityKeys, isEmpty);

      // Valid base64, wrong key length.
      final shortKey = await signedFrame(
        tracker: peerTracker,
        keyPair: keyPair,
        extraPayload: {
          kIdentityKeyPayloadKey: base64Encode(List.filled(10, 1)),
        },
      );
      expect(await authenticator.verify(shortKey), isFalse);
      expect(authenticator.identityKeys, isEmpty);

      // Well-formed 32-byte key the frame was NOT signed with: the
      // signature must verify against the CLAIMED key before any bind.
      final impostorKey = List<int>.filled(32, 7);
      final mismatch = await signedFrame(
        tracker: peerTracker,
        keyPair: keyPair,
        extraPayload: {kIdentityKeyPayloadKey: base64Encode(impostorKey)},
      );
      expect(await authenticator.verify(mismatch), isFalse);
      expect(authenticator.identityKeys, isEmpty);
    });
  });

  group('key pinning (bound peerId)', () {
    test(
      'a later frame with a different key is rejected as named data',
      () async {
        final victim = await newKeyPair();
        final attacker = await newKeyPair();
        final peerTracker = MeshPresenceTracker(actorId: 'peer-1');
        final authenticator = MeshFrameAuthenticator();

        final join = await signedFrame(tracker: peerTracker, keyPair: victim);
        expect(await authenticator.verify(join), isTrue);
        final pinned = authenticator.identityKeys['peer-1'];

        // Same peerId, attacker's key, attacker's signature: rejected.
        final forged = await signedFrame(
          tracker: peerTracker,
          keyPair: attacker,
          event: MeshEphemeralEvent.ping,
          now: t0.add(const Duration(seconds: 1)),
        );
        expect(await authenticator.verify(forged), isFalse);
        // The pin is immutable.
        expect(authenticator.identityKeys['peer-1'], pinned);
      },
    );
  });

  group('pre-shared (paired) peers unchanged', () {
    test(
      'a registered key takes precedence; TOFU never fires for it',
      () async {
        final paired = await newKeyPair();
        final attacker = await newKeyPair();
        final hostTracker = MeshPresenceTracker(actorId: 'host-1');
        final authenticator = MeshFrameAuthenticator(
          identityKeys: {'host-1': (await paired.extractPublicKey()).bytes},
        );

        // Pre-shared key verifies exactly as before the TOFU change.
        final join = await signedFrame(tracker: hostTracker, keyPair: paired);
        expect(await authenticator.verify(join), isTrue);

        // A frame made with any other key fails against the PIN — even
        // when it claims that key via the ride-along.
        final forged = await signedFrame(
          tracker: hostTracker,
          keyPair: attacker,
          event: MeshEphemeralEvent.ping,
          now: t0.add(const Duration(seconds: 1)),
        );
        expect(await authenticator.verify(forged), isFalse);
        expect(
          authenticator.identityKeys['host-1'],
          (await paired.extractPublicKey()).bytes,
        );
      },
    );

    test(
      'trustOnFirstUse: false restores the pre-shared-only posture',
      () async {
        final keyPair = await newKeyPair();
        final peerTracker = MeshPresenceTracker(actorId: 'peer-1');
        final authenticator = MeshFrameAuthenticator(trustOnFirstUse: false);

        final join = await signedFrame(tracker: peerTracker, keyPair: keyPair);
        expect(await authenticator.verify(join), isFalse);
        expect(authenticator.identityKeys, isEmpty);
      },
    );
  });

  group('persistence with the replica (web store included)', () {
    test('TOFU-learned key lands in the registry, persists, and re-pins '
        'after a reload', () async {
      // MemoryMeshKvStore is the web fallback backing — the exact store
      // the localStorage path degrades to (web store path covered).
      final backing = MemoryMeshKvStore();
      final registry = await MeshPeerRegistry.loadFromStore(
        store: backing,
        key: 'peers.json',
        filePath: '/replica/peers.json',
      );
      final keyPair = await newKeyPair();
      final peerTracker = MeshPresenceTracker(actorId: 'peer-1');
      final authenticator = MeshFrameAuthenticator(peerRegistry: registry);

      final join = await signedFrame(tracker: peerTracker, keyPair: keyPair);
      expect(await authenticator.verify(join), isTrue);

      // The peer registry gains the record — with the learned key.
      final record = registry.byId('peer-1');
      expect(record, isNotNull);
      expect(record!.displayName, 'peer-1');
      expect(record.identityKey, (await keyPair.extractPublicKey()).bytes);
      // Persisted in the replica backing (web store layout: JSON list).
      final persisted =
          (jsonDecode(await backing.read('peers.json') ?? '') as List<dynamic>)
              .cast<Map<String, dynamic>>();
      expect(
        persisted.single['identity_key'],
        base64Encode((await keyPair.extractPublicKey()).bytes),
      );

      // Simulated reload: a fresh registry over the same backing and a
      // fresh authenticator seeded the way hosts seed from peers. TOFU
      // is OFF to prove the pin came from the registry, not re-learning.
      final reloaded = await MeshPeerRegistry.loadFromStore(
        store: backing,
        key: 'peers.json',
      );
      final reloadedAuthenticator = MeshFrameAuthenticator(
        trustOnFirstUse: false,
        identityKeys: {
          for (final p in reloaded.peers)
            if (p.identityKey.isNotEmpty) p.peerId: p.identityKey,
        },
      );
      expect(reloadedAuthenticator.identityKeys['peer-1'], isNotNull);
      expect(await reloadedAuthenticator.verify(join), isTrue);

      // Pinning survives the reload: a different key is still rejected.
      final attacker = await newKeyPair();
      final forged = await signedFrame(
        tracker: peerTracker,
        keyPair: attacker,
        event: MeshEphemeralEvent.ping,
        now: t0.add(const Duration(seconds: 2)),
      );
      expect(await reloadedAuthenticator.verify(forged), isFalse);
    });

    test('a keyless registry record gains its key without losing its '
        'name', () async {
      final backing = MemoryMeshKvStore();
      final registry = await MeshPeerRegistry.loadFromStore(
        store: backing,
        key: 'peers.json',
      );
      await registry.register(
        const MeshPeerRecord(peerId: 'peer-1', displayName: 'Desk'),
      );

      final keyPair = await newKeyPair();
      final peerTracker = MeshPresenceTracker(actorId: 'peer-1');
      final authenticator = MeshFrameAuthenticator(peerRegistry: registry);

      final join = await signedFrame(tracker: peerTracker, keyPair: keyPair);
      expect(await authenticator.verify(join), isTrue);
      final record = registry.byId('peer-1')!;
      expect(record.displayName, 'Desk');
      expect(record.identityKey, (await keyPair.extractPublicKey()).bytes);
      expect(registry.peers, hasLength(1));
    });
  });

  group('session-level TOFU (the asymmetric-pairing fix)', () {
    test('host learns the peer from its first signed frame; presence goes '
        'live; forged keys are dropped', () async {
      final hub = _FakeHub();
      final endpointHost = hub.endpoint('host');
      final endpointPeer = hub.endpoint('peer-1');

      final hostTracker = MeshPresenceTracker(actorId: 'host');
      final peerTracker = MeshPresenceTracker(actorId: 'peer-1');
      final peerKeyPair = await newKeyPair();
      final registry = MeshPeerRegistry.inMemory();
      // The bare authenticator a host wires (v1 default: TOFU on).
      final authenticator = MeshFrameAuthenticator(peerRegistry: registry);

      final hostSession = MeshPresenceSession(
        transport: endpointHost,
        tracker: hostTracker,
        docId: 'doc/1',
        authenticator: authenticator,
      );
      final peerSession = MeshPresenceSession(
        transport: endpointPeer,
        tracker: peerTracker,
        docId: 'doc/1',
        signer: MeshFrameSigner(identityKeyPair: peerKeyPair),
      );

      await peerSession.open(details: {'display': 'Peer'});
      await hostSession.open();
      await _settle();

      // Presence is ALIVE host-side: the peer's signed join was
      // TOFU-bound and folded; the registry gained the record.
      expect(
        hostTracker.presence('doc/1').map((e) => e.peerId),
        containsAll(['host', 'peer-1']),
      );
      expect(hostSession.rejectedFrameCount, 0);
      expect(registry.byId('peer-1')!.identityKey, isNotEmpty);
      // The ride-along really is on the wire: the peer's join payload
      // carries its public identity key (base64).
      final sentJoin = endpointPeer.sent.single;
      expect(sentJoin.payload[kIdentityKeyPayloadKey], isA<String>());

      // Second frame (ping) verifies against the pin — no rejections.
      await peerSession.notifyActivity();
      await _settle();
      expect(hostSession.rejectedFrameCount, 0);
      expect(
        hostTracker.presence('doc/1').where((e) => e.peerId == 'peer-1'),
        hasLength(1),
      );

      // Same peerId, forged different key → dropped as named data.
      final attacker = await newKeyPair();
      final forged = await signedFrame(
        tracker: peerTracker,
        keyPair: attacker,
        event: MeshEphemeralEvent.ping,
        now: DateTime.now(),
      );
      endpointHost._receive(forged);
      await _settle();
      expect(hostSession.rejectedFrameCount, 1);
      expect(
        hostSession.rejections.single.reason,
        MeshFrameRejectionReason.unauthenticated,
      );
      expect(
        hostTracker.presence('doc/1').where((e) => e.peerId == 'peer-1'),
        hasLength(1),
      );

      await peerSession.close();
      await hostSession.close();
      endpointHost.dispose();
      endpointPeer.dispose();
    });
  });
}

/// Lets async signing/verification chains and cross-endpoint delivery
/// settle.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

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

  _FakeEndpoint endpoint(final String peerId) =>
      _endpoints.putIfAbsent(peerId, () => _FakeEndpoint(peerId, this));

  void _deliverFrom(final String from, final MeshEphemeralFrame frame) {
    for (final endpoint in _endpoints.values) {
      if (endpoint.peerId != from) endpoint._receive(frame);
    }
  }
}
