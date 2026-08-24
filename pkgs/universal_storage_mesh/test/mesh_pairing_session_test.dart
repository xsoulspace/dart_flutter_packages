import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';
import 'package:universal_storage_mesh/universal_storage_mesh.dart';
import 'package:universal_storage_mesh_transport/'
    'universal_storage_mesh_transport.dart';

void main() {
  test('pairing session creates and accepts a signed peer record', () async {
    final aliceIdentity = await PairingService.newIdentityKeyPair();
    final bobIdentity = await PairingService.newIdentityKeyPair();
    final alice = MeshPairingSession(
      selfId: 'device-a',
      identityKeyPair: aliceIdentity,
      ephemeralKeyPair: X25519().newKeyPair(),
    );
    final bob = MeshPairingSession(
      selfId: 'device-b',
      identityKeyPair: bobIdentity,
      ephemeralKeyPair: X25519().newKeyPair(),
    );

    final qrPayload = await alice.createQrPayload();
    expect(alice.pairingCode(), base64Encode(qrPayload));

    final peer = await bob.acceptQrPayload(qrPayload);
    expect(peer.peerId, 'device-a');
    expect(
      peer.identityKey,
      Uint8List.fromList((await aliceIdentity.extractPublicKey()).bytes),
    );

    expect(bob.createQrPayload, throwsStateError);
    expect(() => bob.acceptQrPayload(qrPayload), throwsStateError);
  });

  test('peer records round-trip pairing identity keys', () {
    const peer = MeshPeerRecord(
      peerId: 'device-a',
      displayName: 'Device A',
      identityKey: [1, 2, 255],
    );
    final restored = MeshPeerRecord.fromJson(peer.toJson());
    expect(restored.identityKey, peer.identityKey);
  });
}
