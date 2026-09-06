import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

void main() {
  const frame = MeshEphemeralFrame(
    docId: 'notes/todo.json',
    fromPeerId: 'device-a',
    event: MeshEphemeralEvent.join,
    payload: {'display': 'Alice', 'cursor': 42},
    ttl: Duration(seconds: 30),
    issuedAtMs: 1700000000000,
  );

  group('frame signature (ADR 0031 §3)', () {
    test('signingInput binds exactly payload + fromPeerId + issuedAtMs', () {
      final input = utf8.decode(frame.signingInput());
      final decoded = jsonDecode(input) as Map<dynamic, dynamic>;
      expect(
        decoded.keys,
        unorderedEquals(['payload', 'from_peer_id', 'issued_at_ms']),
      );
      expect(decoded['payload'], frame.payload);
      expect(decoded['from_peer_id'], frame.fromPeerId);
      expect(decoded['issued_at_ms'], frame.issuedAtMs);

      // The binding is sensitive to every component of the triple.
      final otherPayload = MeshEphemeralFrame(
        docId: frame.docId,
        fromPeerId: frame.fromPeerId,
        event: frame.event,
        ttl: frame.ttl,
        payload: {...frame.payload, 'cursor': 43},
        issuedAtMs: frame.issuedAtMs,
      );
      expect(
        otherPayload.signingInput(),
        isNot(frame.signingInput()),
        reason: 'changing the payload changes the signed bytes',
      );
      final otherIssuer = MeshEphemeralFrame(
        docId: frame.docId,
        fromPeerId: 'device-b',
        event: frame.event,
        ttl: frame.ttl,
        payload: frame.payload,
        issuedAtMs: frame.issuedAtMs,
      );
      expect(otherIssuer.signingInput(), isNot(frame.signingInput()));
      final otherStamp = MeshEphemeralFrame(
        docId: frame.docId,
        fromPeerId: frame.fromPeerId,
        event: frame.event,
        ttl: frame.ttl,
        payload: frame.payload,
        issuedAtMs: frame.issuedAtMs! + 1,
      );
      expect(otherStamp.signingInput(), isNot(frame.signingInput()));
    });

    test('signingInput is deterministic across re-encoding', () {
      final encoded = MeshEphemeralFrame.decode(frame.encode());
      expect(encoded.signingInput(), frame.signingInput());
      // And stable across repeated calls.
      expect(frame.signingInput(), frame.signingInput());
    });

    test('withSignature round-trips through the wire format', () {
      final signature = Uint8List.fromList(List.filled(64, 7));
      final signed = frame.withSignature(signature);
      expect(signed.signature, signature);

      final decoded = MeshEphemeralFrame.decode(signed.encode());
      expect(decoded, signed);
      expect(decoded.signature, signature);
      // Doc/event/ttl stay untouched by signing.
      expect(decoded.docId, frame.docId);
      expect(decoded.event, frame.event);
      expect(decoded.ttl, frame.ttl);
    });

    test('unsigned frames stay decodable and carry no signature', () {
      final decoded = MeshEphemeralFrame.decode(frame.encode());
      expect(decoded.signature, isNull);
      expect(decoded, frame);
    });

    test('tryDecode skips malformed and unknown-version bytes', () {
      expect(MeshEphemeralFrame.tryDecode(frame.encode()), frame);
      expect(
        MeshEphemeralFrame.tryDecode(
          Uint8List.fromList('nope'.codeUnits),
        ),
        isNull,
      );
      final bumped = utf8
          .decode(frame.encode())
          .replaceFirst('"v":1', '"v":999');
      expect(
        MeshEphemeralFrame.tryDecode(Uint8List.fromList(utf8.encode(bumped))),
        isNull,
      );
    });
  });
}
