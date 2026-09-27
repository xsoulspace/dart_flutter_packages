import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_storage_mesh/universal_storage_mesh.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

void main() {
  test('isolate signer output verifies through the real authenticator',
      () async {
    final keyPair = await PairingService.newIdentityKeyPair();
    final signer = await IsolateFrameSigner.spawn(keyPair);
    final publicKey = await keyPair.extractPublicKey();

    final frame = MeshEphemeralFrame(
      docId: 'vosges/gesture',
      fromPeerId: 'peer-a',
      event: MeshEphemeralEvent.ping,
      ttl: const Duration(seconds: 30),
      issuedAtMs: DateTime.now().millisecondsSinceEpoch,
      payload: <String, Object?>{'purpose': 'gesture', 'sequence': 1},
    );
    final signature = await signer.sign(frame);

    // Tampering in either direction must flip the verdict.
    final authenticator = MeshFrameAuthenticator(
      identityKeys: {
        'peer-a': Uint8List.fromList(publicKey.bytes),
      },
      trustOnFirstUse: false,
    );
    expect(
      await authenticator.verify(frame.withSignature(signature)),
      isTrue,
    );
    final tampered = MeshEphemeralFrame(
      docId: frame.docId,
      fromPeerId: frame.fromPeerId,
      event: frame.event,
      ttl: frame.ttl,
      issuedAtMs: frame.issuedAtMs,
      payload: <String, Object?>{'purpose': 'gesture', 'sequence': 2},
    ).withSignature(signature);
    expect(await authenticator.verify(tampered), isFalse);
  });

  test('isolate signer signs many frames back to back', () async {
    final keyPair = await PairingService.newIdentityKeyPair();
    final signer = await IsolateFrameSigner.spawn(keyPair);
    for (var i = 0; i < 5; i++) {
      final frame = MeshEphemeralFrame(
        docId: 'vosges/gesture',
        fromPeerId: 'peer-a',
        event: MeshEphemeralEvent.ping,
        ttl: const Duration(seconds: 30),
        issuedAtMs: i,
        payload: <String, Object?>{'i': i},
      );
      final signature = await signer.sign(frame);
      expect(signature, hasLength(64));
    }
  });
}
