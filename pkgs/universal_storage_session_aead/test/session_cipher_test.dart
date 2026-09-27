import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';
import 'package:universal_storage_session_aead/universal_storage_session_aead.dart';

// Asserting both outcomes of the identical record is the point of the
// replay tests; the shared receiver is intentional.
// ignore_for_file: cascade_invocations

/// Deterministic 32-byte test keys (values are irrelevant; the cipher
/// treats them as opaque).
SecretKeyData _key(final int seed) => SecretKeyData(
  Uint8List.fromList(List.generate(32, (final i) => (i + seed) & 0xff)),
);

SessionCipher _initiator() =>
    SessionCipher(sendKey: _key(2), receiveKey: _key(1));

SessionCipher _responder() =>
    SessionCipher(sendKey: _key(1), receiveKey: _key(2));

void main() {
  test('seal → open round-trips between directions', () {
    final initiator = _initiator();
    final responder = _responder();

    final payload = Uint8List.fromList(utf8.encode('pointer_move 0.4 0.6'));
    final opened = responder.open(initiator.seal(payload));
    expect(opened, equals(payload));
    final reply = initiator.open(responder.seal(payload));
    expect(reply, equals(payload));
  });

  test('reflection fails: a direction cannot open its own records', () {
    final initiator = _initiator();
    final record = initiator.seal(utf8.encode('hello'));
    expect(initiator.open(record), isNull);
  });

  test('empty payload round-trips (tag-only control record)', () {
    final initiator = _initiator();
    final responder = _responder();
    final record = initiator.seal(const <int>[]);
    expect(record.length, SessionAeadProtocol.headerLength + 16);
    expect(responder.open(record), equals(Uint8List(0)));
  });

  test('tampered ciphertext, tag, or header drops the record', () {
    final initiator = _initiator();
    final responder = _responder();
    final payload = Uint8List.fromList(utf8.encode('a very secret frame'));

    Uint8List flipped(final Uint8List record, final int index) =>
        Uint8List.fromList(record)
          ..[index] = record[index] ^ 0x01;

    final sealed = initiator.seal(payload);
    const ciphertextIndex = SessionAeadProtocol.headerLength + 2;
    expect(responder.open(flipped(sealed, ciphertextIndex)), isNull);

    final sealed2 = initiator.seal(payload);
    expect(responder.open(flipped(sealed2, sealed2.length - 1)), isNull);

    // The sequence is AAD: flipping a header bit breaks the tag.
    final sealed3 = initiator.seal(payload);
    expect(responder.open(flipped(sealed3, 3)), isNull);
  });

  test('replayed and late records drop as named data', () {
    final initiator = _initiator();
    final responder = _responder();

    final first = initiator.seal(utf8.encode('one'));
    expect(responder.open(first), isNotNull);
    // Replay of the same record: rejected.
    expect(responder.open(first), isNull);

    final second = initiator.seal(utf8.encode('two'));
    expect(responder.open(second), isNotNull);
    // Anything at or below the newest sequence (a late copy of `first`)
    // stays rejected.
    expect(responder.open(first), isNull);
  });

  test('short records and foreign versions drop without throwing', () {
    final responder = _responder();
    expect(responder.open(Uint8List(0)), isNull);
    expect(responder.open(Uint8List(10)), isNull);
    expect(
      responder.open(Uint8List.fromList([0x02, ...List.filled(24, 0)])),
      isNull,
    );
  });

  test('sequences strictly increase per direction', () {
    final initiator = _initiator();
    final responder = _responder();
    expect(initiator.sentCount, 0);
    initiator.seal(utf8.encode('a'));
    initiator.seal(utf8.encode('b'));
    initiator.seal(utf8.encode('c'));
    expect(initiator.sentCount, 3);

    // A fresh dialer (same key pair shape) restarts its sequence — the
    // responder counts opens, not the initiator's totals.
    final dialer = _initiator();
    expect(responder.receivedCount, 0);
    responder.open(dialer.seal(utf8.encode('d')));
    expect(responder.receivedCount, 1);
    responder.open(dialer.seal(utf8.encode('e')));
    expect(responder.receivedCount, 2);
    // Failed opens never advance the sequence.
    final tampered = dialer.seal(utf8.encode('x'))..[10] ^= 0xff;
    expect(responder.open(tampered), isNull);
    expect(responder.receivedCount, 2);
  });
}
