import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';
import 'package:universal_storage_mesh/universal_storage_mesh.dart';

void main() {
  group('PairingService', () {
    late SimpleKeyPair aliceIdentity;
    late Uint8List aliceIdentityPub;

    setUp(() async {
      aliceIdentity = await PairingService.newIdentityKeyPair();
      final pub = await aliceIdentity.extractPublicKey();
      aliceIdentityPub = Uint8List.fromList(pub.bytes);
    });

    test('build → accept derives matching keys on both sides', () async {
      // Alice (initiator) builds the QR; Bob scans it.
      final aliceEph = await X25519().newKeyPair();
      final qr = await PairingService.buildQrPayload(
        identityKeyPair: aliceIdentity,
        ephemeralKeyPair: aliceEph,
        peerId: 'device-a',
      );

      final bobEph = await X25519().newKeyPair();
      final bobResult = await PairingService.acceptQrPayload(
        qrPayload: qr,
        peerIdentityKey: aliceIdentityPub,
        ownEphemeralKeyPair: bobEph,
        ourPeerId: 'device-b',
      );
      expect(bobResult.peerId, 'device-a');

      // Alice derives her side from Bob's ephemeral public key.
      final bobPubBytes = Uint8List.fromList(
        (await bobEph.extractPublicKey()).bytes,
      );
      final aliceResult = await PairingService.deriveInitiatorKeys(
        identityKeyPair: aliceIdentity,
        ownEphemeralKeyPair: aliceEph,
        peerEphemeralPublic: bobPubBytes,
        ourPeerId: 'device-a',
        peerId: 'device-b',
      );

      // Both sides must agree on who sends with which key.
      expect(
        await bobResult.receiveKey.extractBytes(),
        await aliceResult.sendKey.extractBytes(),
        reason: 'what Bob receives is what Alice sent',
      );
      expect(
        await bobResult.sendKey.extractBytes(),
        await aliceResult.receiveKey.extractBytes(),
        reason: 'what Alice receives is what Bob sent',
      );
    });

    test('transport hint round-trips and stays signature-protected', () async {
      const hint = 'ws://192.168.1.20:54321';
      final qr = await PairingService.buildQrPayload(
        identityKeyPair: aliceIdentity,
        ephemeralKeyPair: await X25519().newKeyPair(),
        peerId: 'device-a',
        transportHint: hint,
      );
      final result = await PairingService.acceptQrPayload(
        qrPayload: qr,
        peerIdentityKey: aliceIdentityPub,
        ownEphemeralKeyPair: await X25519().newKeyPair(),
        ourPeerId: 'device-b',
      );
      expect(result.transportHint, hint);

      // Tampering with the hint must invalidate the signature.
      final body = utf8.decode(
        qr.sublist('mesh-pair/v1\n'.length, qr.length - 64),
      );
      final forgedBody = utf8.encode(body.replaceAll(hint, 'ws://evil:1'));
      final forged = Uint8List.fromList([
        ...utf8.encode('mesh-pair/v1\n'),
        ...forgedBody,
        ...qr.sublist(qr.length - 64),
      ]);
      await expectLater(
        PairingService.acceptQrPayload(
          qrPayload: forged,
          peerIdentityKey: aliceIdentityPub,
          ownEphemeralKeyPair: await X25519().newKeyPair(),
          ourPeerId: 'device-b',
        ),
        throwsA(isA<PairingException>()),
      );
    });

    test('tampered payload is rejected', () async {
      final aliceEph = await X25519().newKeyPair();
      final qr = await PairingService.buildQrPayload(
        identityKeyPair: aliceIdentity,
        ephemeralKeyPair: aliceEph,
        peerId: 'device-a',
      );
      final tampered = Uint8List.fromList(qr);
      tampered[tampered.length - 70] ^= 0x01;

      await expectLater(
        PairingService.acceptQrPayload(
          qrPayload: tampered,
          peerIdentityKey: aliceIdentityPub,
          ownEphemeralKeyPair: await X25519().newKeyPair(),
          ourPeerId: 'device-b',
        ),
        throwsA(isA<PairingException>()),
      );
    });

    test('wrong identity key is rejected', () async {
      final aliceEph = await X25519().newKeyPair();
      final qr = await PairingService.buildQrPayload(
        identityKeyPair: aliceIdentity,
        ephemeralKeyPair: aliceEph,
        peerId: 'device-a',
      );
      final mallory = await PairingService.newIdentityKeyPair();
      final malloryPub = Uint8List.fromList(
        (await mallory.extractPublicKey()).bytes,
      );

      await expectLater(
        PairingService.acceptQrPayload(
          qrPayload: qr,
          peerIdentityKey: malloryPub,
          ownEphemeralKeyPair: await X25519().newKeyPair(),
          ourPeerId: 'device-b',
        ),
        throwsA(isA<PairingException>()),
      );
    });

    test('malformed payload (bad prefix) is rejected', () async {
      final garbage = Uint8List.fromList(utf8.encode('not-a-pair-code'));
      await expectLater(
        PairingService.acceptQrPayload(
          qrPayload: garbage,
          peerIdentityKey: aliceIdentityPub,
          ownEphemeralKeyPair: await X25519().newKeyPair(),
          ourPeerId: 'device-b',
        ),
        throwsA(isA<PairingException>()),
      );
    });
  });
}
