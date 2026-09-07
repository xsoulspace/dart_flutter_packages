import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_storage_mesh/universal_storage_mesh.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

/// Lets async signing/verification chains and relay round-trips settle.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 40));

void main() {
  test('adapter exposes relay connection state', () async {
    final relay = AddressedRelayServer(port: 0);
    final port = await relay.start();
    addTearDown(relay.dispose);
    final endpoint = Uri.parse('ws://127.0.0.1:$port');

    final client = AddressedRelayClient(selfId: 'device-a', endpoint: endpoint);
    final transport = AddressedRelayEphemeralTransport(client: client);
    addTearDown(transport.dispose);
    expect(transport.connectionState, EphemeralLinkState.disconnected);

    await client.openRelay();
    await _settle(); // state events are delivered asynchronously
    expect(transport.connectionState, EphemeralLinkState.connected);

    await client.close();
    await _settle();
    expect(transport.connectionState, EphemeralLinkState.disconnected);
  });

  test(
    'two presence sessions meet over one relay, signed and verified',
    () async {
      final relay = AddressedRelayServer(port: 0);
      final port = await relay.start();
      addTearDown(relay.dispose);
      final endpoint = Uri.parse('ws://127.0.0.1:$port');

      final clientA = AddressedRelayClient(
        selfId: 'device-a',
        endpoint: endpoint,
      );
      final clientB = AddressedRelayClient(
        selfId: 'device-b',
        endpoint: endpoint,
      );
      await clientA.openRelay();
      await clientB.openRelay();

      final transportA = AddressedRelayEphemeralTransport(client: clientA);
      final transportB = AddressedRelayEphemeralTransport(client: clientB);

      final keyPairA = await PairingService.newIdentityKeyPair();
      final publicKeyA = await keyPairA.extractPublicKey();

      final trackerA = MeshPresenceTracker(actorId: 'device-a');
      final trackerB = MeshPresenceTracker(actorId: 'device-b');
      final sessionA = MeshPresenceSession(
        transport: transportA,
        tracker: trackerA,
        docId: 'doc/1',
        signer: MeshFrameSigner(identityKeyPair: keyPairA),
      );
      final sessionB = MeshPresenceSession(
        transport: transportB,
        tracker: trackerB,
        docId: 'doc/1',
        authenticator: MeshFrameAuthenticator(
          identityKeys: {'device-a': publicKeyA.bytes},
        ),
      );

      await sessionA.open(details: {'display': 'Alice'});
      await sessionB.open(details: {'display': 'Bob'});

      // Broadcast fan-out: both sessions learn about each other; B verifies
      // A's signature against the registered identity key before folding.
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (trackerB.presence('doc/1').length < 2 ||
          trackerA.presence('doc/1').length < 2) {
        if (DateTime.now().isAfter(deadline)) {
          fail('presence did not converge over the relay in time');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final onB = trackerB.presence('doc/1');
      expect(
        onB.singleWhere((e) => e.peerId == 'device-a').details['display'],
        'Alice',
      );
      expect(
        trackerA
            .presence('doc/1')
            .singleWhere((e) => e.peerId == 'device-b')
            .details['display'],
        'Bob',
      );
      expect(sessionB.rejectedFrameCount, 0);

      // A leave over the relay removes the peer from the remote fold.
      await sessionA.close();
      final leaveDeadline = DateTime.now().add(const Duration(seconds: 5));
      while (trackerB.presence('doc/1').any((e) => e.peerId == 'device-a')) {
        if (DateTime.now().isAfter(leaveDeadline)) {
          fail('leave did not propagate over the relay in time');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(trackerB.presence('doc/1').map((e) => e.peerId), ['device-b']);

      // A forged frame relayed under A's name is dropped as named data.
      final forged = MeshEphemeralFrame(
        docId: 'doc/1',
        fromPeerId: 'device-a',
        event: MeshEphemeralEvent.join,
        ttl: const Duration(seconds: 30),
        issuedAtMs: DateTime.now().millisecondsSinceEpoch,
        signature: _garbageSignature(),
      );
      await clientA.sendEphemeral(
        toPeerId: 'device-b',
        payload: forged.encode(),
      );
      await _settle();
      expect(sessionB.rejectedFrameCount, 1);
      expect(
        sessionB.rejections.single.reason,
        MeshFrameRejectionReason.unauthenticated,
      );
      expect(trackerB.presence('doc/1').map((e) => e.peerId), ['device-b']);

      await sessionB.close();
      await transportA.dispose();
      await transportB.dispose();
      await clientA.close();
      await clientB.close();
    },
  );
}

Uint8List _garbageSignature() => Uint8List.fromList(List.filled(64, 0xAB));
