import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';
import 'package:universal_storage_session_aead/universal_storage_session_aead.dart';

Uint8List _bytes(final int length, [final int seed = 0]) => Uint8List.fromList(
  List.generate(length, (final i) => (i * 7 + seed) & 0xff),
);

SessionHello _hello([final String id = 'device-a']) => SessionHello(
  ephemeralKey: _bytes(32, 1),
  peerId: id,
  identityKey: _bytes(32, 2),
);

void main() {
  test('hello round-trips through encode/parse', () {
    final hello = _hello();
    final parsed = SessionHello.parse(hello.encodeBody());
    expect(parsed.peerId, hello.peerId);
    expect(parsed.ephemeralKey, hello.ephemeralKey);
    expect(parsed.identityKey, hello.identityKey);
  });

  test('reply and confirm round-trip through encode/parse', () {
    final reply = SessionReply(
      hello: _hello('device-b'),
      signature: _bytes(64, 3),
    );
    final parsedReply = SessionReply.parse(reply.encode());
    expect(parsedReply.hello.peerId, 'device-b');
    expect(parsedReply.signature, reply.signature);

    final confirm = SessionConfirm(signature: _bytes(64, 4));
    final parsedConfirm = SessionConfirm.parse(confirm.encode());
    expect(parsedConfirm.signature, confirm.signature);
  });

  test('foreign protocol name and versions are rejected', () {
    final body = jsonEncode({
      'v': 1,
      'proto': 'mesh-pair/v1',
      'e': base64Encode(_bytes(32)),
      'id': 'device-a',
      'idk': base64Encode(_bytes(32)),
    });
    expect(
      () => SessionHello.parse(Uint8List.fromList(utf8.encode(body))),
      throwsA(isA<SessionHandshakeException>()),
    );

    final wrongVersion = jsonEncode({
      'v': 2,
      'proto': SessionAeadProtocol.name,
      'e': base64Encode(_bytes(32)),
      'id': 'device-a',
      'idk': base64Encode(_bytes(32)),
    });
    expect(
      () => SessionHello.parse(Uint8List.fromList(utf8.encode(wrongVersion))),
      throwsA(isA<SessionHandshakeException>()),
    );
  });

  test('malformed keys and signatures are rejected', () {
    Uint8List bodyWith(final Map<String, Object?> overrides) =>
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'v': 1,
              'proto': SessionAeadProtocol.name,
              'e': base64Encode(_bytes(32)),
              'id': 'device-a',
              'idk': base64Encode(_bytes(32)),
              ...overrides,
            }),
          ),
        );

    expect(
      () => SessionHello.parse(bodyWith({'e': base64Encode(_bytes(31))})),
      throwsA(isA<SessionHandshakeException>()),
    );
    expect(
      () => SessionHello.parse(bodyWith({'id': ''})),
      throwsA(isA<SessionHandshakeException>()),
    );
    expect(
      () => SessionReply.parse(bodyWith({'sig': base64Encode(_bytes(32))})),
      throwsA(isA<SessionHandshakeException>()),
    );
    expect(
      () => SessionReply.parse(
        Uint8List.fromList(utf8.encode(jsonEncode({
          'v': 1,
          'proto': SessionAeadProtocol.name,
          'e': base64Encode(_bytes(32)),
          'id': 'device-a',
          'idk': base64Encode(_bytes(32)),
        }))),
      ),
      throwsA(isA<SessionHandshakeException>()),
    );
  });

  test('signatures are role-bound and body-bound', () async {
    final identity = await Ed25519().newKeyPair();
    final helloBody = _hello().encodeBody();
    final replyBody = _hello('device-b').encodeBody();

    final responderSig = await SessionHandshakeCodec.sign(
      role: SessionHandshakeRole.responder,
      helloBody: helloBody,
      replyBody: replyBody,
      identityKeyPair: identity,
    );
    final publicKey = await identity.extractPublicKey();

    Future<bool> verifyWith({
      required final SessionHandshakeRole role,
      required final Uint8List sig,
    }) =>
        SessionHandshakeCodec.verify(
          role: role,
          helloBody: helloBody,
          replyBody: replyBody,
          signature: sig,
          identityKey: publicKey.bytes,
        );

    expect(
      await verifyWith(
        role: SessionHandshakeRole.responder,
        sig: responderSig,
      ),
      isTrue,
    );
    // The same signature over the INITIATOR transcript is meaningless.
    expect(
      await verifyWith(
        role: SessionHandshakeRole.initiator,
        sig: responderSig,
      ),
      isFalse,
    );
    // A flipped byte in either body invalidates it.
    expect(
      await SessionHandshakeCodec.verify(
        role: SessionHandshakeRole.responder,
        helloBody: Uint8List.fromList(helloBody)..[0] ^= 0x01,
        replyBody: replyBody,
        signature: responderSig,
        identityKey: publicKey.bytes,
      ),
      isFalse,
    );
  });

  test('both sides derive identical directional keys', () async {
    final x25519 = X25519();
    final initiatorEph = await x25519.newKeyPair();
    final responderEph = await x25519.newKeyPair();
    final initiatorPub = await initiatorEph.extractPublicKey();
    final responderPub = await responderEph.extractPublicKey();
    final helloBody = _hello().encodeBody();
    final replyBody = _hello('device-b').encodeBody();

    final initiatorShared = await SessionHandshakeCodec.sharedSecret(
      ownEphemeralKeyPair: initiatorEph,
      peerEphemeralKey: Uint8List.fromList(responderPub.bytes),
    );
    final responderShared = await SessionHandshakeCodec.sharedSecret(
      ownEphemeralKeyPair: responderEph,
      peerEphemeralKey: Uint8List.fromList(initiatorPub.bytes),
    );

    final initiatorKeys = await SessionHandshakeCodec.deriveKeys(
      shared: initiatorShared,
      initiatorId: 'device-a',
      responderId: 'device-b',
      helloBody: helloBody,
      replyBody: replyBody,
    );
    final responderKeys = await SessionHandshakeCodec.deriveKeys(
      shared: responderShared,
      initiatorId: 'device-a',
      responderId: 'device-b',
      helloBody: helloBody,
      replyBody: replyBody,
    );

    expect(
      initiatorKeys.responderToInitiator,
      responderKeys.responderToInitiator,
    );
    expect(
      initiatorKeys.initiatorToResponder,
      responderKeys.initiatorToResponder,
    );
    // Directions are distinct key material.
    expect(
      initiatorKeys.responderToInitiator,
      isNot(initiatorKeys.initiatorToResponder),
    );
    // The directional split mirrors PairingService: the initiator sends
    // under the key the responder receives with.
    final initiatorSend = await SessionHandshakeCodec.initiatorCipher(
      initiatorKeys,
    ).sendKey.extractBytes();
    final responderReceive = await SessionHandshakeCodec.responderCipher(
      responderKeys,
    ).receiveKey.extractBytes();
    expect(initiatorSend, responderReceive);
  });

  test('keys are bound to the transcript bytes', () async {
    final x25519 = X25519();
    final eph = await x25519.newKeyPair();
    final peer = await x25519.newKeyPair();
    final peerPub = await peer.extractPublicKey();
    final helloBody = _hello().encodeBody();

    Future<Uint8List> derive(final Uint8List replyBody) async {
      final shared = await SessionHandshakeCodec.sharedSecret(
        ownEphemeralKeyPair: eph,
        peerEphemeralKey: Uint8List.fromList(peerPub.bytes),
      );
      return (await SessionHandshakeCodec.deriveKeys(
        shared: shared,
        initiatorId: 'a',
        responderId: 'b',
        helloBody: helloBody,
        replyBody: replyBody,
      )).initiatorToResponder;
    }

    final keys1 = await derive(_hello('device-b').encodeBody());
    // A DIFFERENT reply body (e.g. attacker's ephemeral substituted) must
    // derive different keys even though the ECDH secret is identical —
    // that binding is what makes a relay-injected M2 useless.
    final shiftedReply = Uint8List.fromList(_hello('device-b').encodeBody());
    shiftedReply[shiftedReply.length - 2] ^= 0x01;
    final keys2 = await derive(shiftedReply);
    expect(keys1, isNot(keys2));
  });
}
