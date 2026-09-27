import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

void main() {
  test('hub hosts several peers with isolated sessions', () async {
    final hub = FakeMeshHub();
    final routed = <(String, String)>[];
    hub.incoming.listen((final session) {
      session.inbound.listen((final bytes) {
        routed.add((session.remotePeerId, utf8.decode(bytes)));
      });
    });

    final phone = hub.openSession('phone');
    final mac = hub.openSession('mac-controller');
    await Future<void>.delayed(Duration.zero);

    phone.receive(Uint8List.fromList(utf8.encode('p1')));
    mac.receive(Uint8List.fromList(utf8.encode('m1')));
    await Future<void>.delayed(Duration.zero);

    expect(routed, contains(('phone', 'p1')));
    expect(routed, contains(('mac-controller', 'm1')));
  });

  test('re-open replaces only that peer; send/close semantics hold',
      () async {
    final hub = FakeMeshHub();
    final first = hub.openSession('phone');
    hub.openSession('phone'); // reconnect under the same peer id

    // The replaced session is closed and rejects sends; the hub keeps only
    // the newest session per peer.
    await expectLater(first.send(Uint8List(1)), throwsStateError);

    final current = hub.openSessions.single;
    expect(current.remotePeerId, 'phone');
  });

  test('sent frames are captured for assertions', () async {
    final hub = FakeMeshHub();
    final session = hub.openSession('phone');
    await session.send(Uint8List.fromList(utf8.encode('heartbeat')));
    expect(utf8.decode(session.sent.single), 'heartbeat');
  });
}
