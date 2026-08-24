import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:test/test.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test('addressed relay creates private logical sessions', () async {
    final clients = <String, WebSocketChannel>{};
    final handler = webSocketHandler((channel, _) async {
      String? peerId;
      channel.stream.listen((message) {
        final envelope = AddressedRelayProtocol.decode(message as List<int>);
        if (envelope.toPeerId.isEmpty) {
          peerId = envelope.fromPeerId;
          clients[peerId!] = channel;
          return;
        }
        clients[envelope.toPeerId]?.sink.add(message);
      });
    });
    final server = await shelf_io.serve(
      const shelf.Pipeline().addHandler(handler),
      '127.0.0.1',
      0,
    );
    addTearDown(() => server.close(force: true));
    final endpoint = Uri.parse('ws://127.0.0.1:${server.port}');

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

    final received = Completer<String>();
    remote.inbound.listen(
      (bytes) => received.complete(utf8.decode(bytes)),
    );
    await session.send(Uint8List.fromList('ping'.codeUnits));
    expect(await received.future, 'ping');
  });
}
