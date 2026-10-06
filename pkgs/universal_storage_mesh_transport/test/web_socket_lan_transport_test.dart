// ignore_for_file: prefer_final_parameters, prefer_const_constructors
// The LAN WebSocket transport, lifted from vosges' proven gesture mesh
// (controller/desktop, paired sessions): nonce-bound hello/ack, signed
// payload frames with inbound sequence monotonicity, connection-fatal
// authentication failures. Generic here: closure crypto seams + wire
// kind/channel parameters, no gesture vocabulary.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

/// A deterministic sealer/verifier pair over a shared secret: signs
/// `sha`-less (test-only) — the signature is the secret XORed with the
/// canonical bytes, bounded to 16 bytes. Enough to prove the transport
/// enforces the seams; real crypto lives in the callers' packages.
(Future<Uint8List> Function(MeshEphemeralFrame), Future<bool> Function(MeshEphemeralFrame))
testSeams(String secret) {
  List<int> seal(List<int> input) => [
        for (var i = 0; i < 16; i++) input.isEmpty ? 0 : secret.codeUnitAt(i % secret.length) ^ input[i % input.length],
      ];

  Future<Uint8List> sealer(MeshEphemeralFrame frame) async =>
      Uint8List.fromList(seal(frame.signingInput()));

  Future<bool> verifier(MeshEphemeralFrame frame) async {
    final expected = seal(frame.signingInput());
    final signature = frame.signature;
    if (signature == null || signature.length != expected.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (signature[i] != expected[i]) return false;
    }
    return true;
  }

  return (sealer, verifier);
}

MeshPeerRecord peerOf(int port, {String peerId = 'device-a'}) =>
    MeshPeerRecord(
      peerId: peerId,
      displayName: peerId,
      endpointHints: {'host': '127.0.0.1', 'port': '$port'},
    );

void main() {
  group('WebSocketLanTransport', () {
    test('unsigned mode: handshake, bidirectional payloads, clean close',
        () async {
      final server = WebSocketLanTransport(selfId: 'device-a');
      await server.start();
      addTearDown(server.close);

      final served = Completer<MeshSession>();
      server.incoming.listen(served.complete);

      final client = await server.connect(peerOf(server.port));
      final hostSession = await served.future.timeout(
        const Duration(seconds: 5),
      );

      final received = <int>[];
      hostSession.inbound.listen(received.addAll);
      await client.send(utf8.encode('ping'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(utf8.decode(received), 'ping');

      final echoed = Completer<Uint8List>();
      client.inbound.listen(echoed.complete);
      await hostSession.send(utf8.encode('pong'));
      expect(utf8.decode(await echoed.future), 'pong');

      await client.close();
      await hostSession.close();
    });

    test('signed mode: a wrong-secret peer is refused at the handshake '
        '(fatal, never a session source)', () async {
      final (sealer, verifier) = testSeams('pair-secret');
      final server = WebSocketLanTransport(
        selfId: 'device-a',
        requireAuthentication: true,
        frameSealer: sealer,
        frameVerifier: verifier,
      );
      await server.start();
      addTearDown(server.close);

      // The honest peer pairs and works.
      final served = Completer<MeshSession>();
      server.incoming.listen(served.complete);
      final client = await server.connect(peerOf(server.port));
      final hostSession = await served.future.timeout(
        const Duration(seconds: 5),
      );
      final received = <int>[];
      hostSession.inbound.listen(received.addAll);
      await client.send(utf8.encode('ping'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(utf8.decode(received), 'ping');

      // The rogue signs with a different secret: the server refuses its
      // hello — the connect throws, the session never exists.
      final (wrongSeal, wrongVerify) = testSeams('other-secret');
      final rogue = WebSocketLanTransport(
        selfId: 'device-b',
        requireAuthentication: true,
        frameSealer: wrongSeal,
        frameVerifier: wrongVerify,
      );
      await expectLater(
        rogue.connect(peerOf(server.port)),
        throwsA(isA<MeshConnectionException>()),
      );
      // The honest session survives the rogue's attempt.
      final before = received.length;
      await client.send(utf8.encode('still-here'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(utf8.decode(received.sublist(before)), 'still-here');
      await client.close();
      await hostSession.close();
    });

    test('connect without a host/port hint throws a named exception', () {
      final server = WebSocketLanTransport(selfId: 'device-a');
      expect(
        () => server.connect(
          MeshPeerRecord(peerId: 'device-b', displayName: 'b'),
        ),
        throwsA(isA<MeshConnectionException>()),
      );
    });

    test('custom wire kinds interop (vosges vocabulary)', () async {
      final server = WebSocketLanTransport(
        selfId: 'device-a',
        helloKind: 'vosges_hello',
        helloAckKind: 'vosges_hello_ack',
        channelId: 'vosges/gesture',
      );
      await server.start();
      addTearDown(server.close);
      final served = Completer<MeshSession>();
      server.incoming.listen(served.complete);
      final client = await server.connect(peerOf(server.port));
      await served.future.timeout(const Duration(seconds: 5));
      await client.close();
    });
  });
}
