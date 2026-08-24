import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

void main() {
  test('addressed relay creates private logical sessions', () async {
    final relay = AddressedRelayServer(port: 0);
    final port = await relay.start();
    addTearDown(relay.dispose);
    final endpoint = Uri.parse('ws://127.0.0.1:$port');

    final a = AddressedRelayClient(selfId: 'a', endpoint: endpoint);
    final b = AddressedRelayClient(selfId: 'b', endpoint: endpoint);
    await a.openRelay();
    await b.openRelay();

    final inbound = b.incoming.first;
    final session = await a.connect(
      const MeshPeerRecord(peerId: 'b', displayName: 'B'),
    );
    final remote = await inbound;
    expect(remote.remotePeerId, 'a');

    final receivedMessages = <String>[];
    final receivedBinary = <Uint8List>[];
    remote.inbound.listen((bytes) {
      receivedBinary.add(bytes);
      if (receivedBinary.length == 1) {
        receivedMessages.add(utf8.decode(bytes));
      }
    });
    await session.send(Uint8List.fromList('ping'.codeUnits));

    final payload = Uint8List.fromList([0, 255, 10, 128]);
    await session.send(payload);
    while (receivedBinary.length < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(receivedMessages.single, 'ping');
    expect(receivedBinary.last, payload);
  });
}
