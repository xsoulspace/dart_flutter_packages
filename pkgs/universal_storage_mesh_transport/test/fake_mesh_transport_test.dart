import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

void main() {
  test('initiated sessions deliver messages to the responder', () async {
    final pair = FakeMeshPair.paired();
    final bReceived = <String>[];

    // B is the responder: it handles incoming sessions.
    pair.b.onIncomingSession = (final session) async {
      session.inbound.listen(
        (final bytes) => bReceived.add(String.fromCharCodes(bytes)),
      );
    };

    // A initiates toward B.
    final session = await pair.a.connect(
      const MeshPeerRecord(peerId: 'device-b', displayName: 'B'),
    );
    await session.send(Uint8List.fromList('ping'.codeUnits));

    // Responder session arrives via microtask; flush it.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(bReceived, ['ping']);
  });

  test('failNextConnect simulates partition and auto-resets', () async {
    final pair = FakeMeshPair.paired();
    pair.b.failNextConnect = true;

    await expectLater(
      pair.b.connect(const MeshPeerRecord(peerId: 'device-a', displayName: 'A')),
      throwsA(isA<MeshConnectionException>()),
    );
    // Reset happened: next attempt proceeds.
    final session = await pair.b.connect(
      const MeshPeerRecord(peerId: 'device-a', displayName: 'A'),
    );
    expect(session.remotePeerId, 'device-a');
  });

  test('frame codec round-trips split and concatenated writes', () {
    final decoder = FrameDecoder();
    final message = Uint8List.fromList(List.generate(1000, (final i) => i % 256));
    final framed = frameMessage(message);

    // Split the frame into awkward chunks.
    final received = <Uint8List>[
      ...decoder.feed(framed.sublist(0, 2)),
      ...decoder.feed(framed.sublist(2, 5)),
      ...decoder.feed(framed.sublist(5)),
    ];

    expect(received, hasLength(1));
    expect(received.first, message);
  });
}
