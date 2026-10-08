// The claiming transport is the one-server-two-planes seam (ADR 0047
// consumer story): sync-marked sessions go to the claimed plane, realtime
// sessions to passthrough, and nothing is decided before the first frame.
// These tests prove the ROUTING contract: exactly-once per session, the
// deciding frame forwarded, silent sessions parked then passed through,
// dead-before-first-frame sessions dropped, and outbound dials untouched.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

Uint8List _frame(final Map<String, Object?> json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

bool _isSyncHello(final Uint8List frame) {
  try {
    final decoded = jsonDecode(utf8.decode(frame));
    return decoded is Map && decoded['type'] == 'hello';
  } on FormatException {
    return false;
  }
}

void main() {
  test('sync-marked sessions are claimed, and the deciding frame is forwarded', () async {
    final hub = FakeMeshHub();
    final planes = ClaimingMeshTransport(inner: hub, claim: _isSyncHello);
    final claimed = <MeshSession>[];
    planes.incoming.listen(claimed.add);
    final passthrough = <MeshSession>[];
    planes.passthrough.incoming.listen(passthrough.add);

    final dial = hub.openSession('phone');
    dial.receive(_frame({'type': 'hello', 'v': 2}));
    await pumpEventQueue();
    expect(claimed, hasLength(1));
    expect(passthrough, isEmpty);

    // The consumer sees the hello it must answer, then every later frame.
    final inbound = <String>[];
    final ready = Completer<void>();
    claimed.single.inbound.listen((final frame) {
      inbound.add(utf8.decode(frame));
      if (!ready.isCompleted) ready.complete();
    });
    await ready.future;
    expect(inbound.single, contains('hello'));
    dial.receive(_frame({'type': 'vv'}));
    await pumpEventQueue();
    expect(inbound, hasLength(2));
  });

  test('realtime sessions pass through with every frame', () async {
    final hub = FakeMeshHub();
    final planes = ClaimingMeshTransport(inner: hub, claim: _isSyncHello);
    final claimed = <MeshSession>[];
    planes.incoming.listen(claimed.add);
    final passthrough = <MeshSession>[];
    planes.passthrough.incoming.listen(passthrough.add);

    final dial = hub.openSession('phone');
    dial.receive(_frame({'session_id': 's', 'event_type': 'heartbeat'}));
    await pumpEventQueue();
    expect(claimed, isEmpty);
    expect(passthrough, hasLength(1));

    final inbound = <String>[];
    final ready = Completer<void>();
    passthrough.single.inbound.listen((final frame) {
      inbound.add(utf8.decode(frame));
      if (!ready.isCompleted) ready.complete();
    });
    await ready.future;
    expect(inbound.single, contains('heartbeat'));
  });

  test('a session silent past the claim timeout routes to passthrough', () async {
    final hub = FakeMeshHub();
    final planes = ClaimingMeshTransport(
      inner: hub,
      claim: _isSyncHello,
      claimTimeout: const Duration(milliseconds: 30),
    );
    final claimed = <MeshSession>[];
    planes.incoming.listen(claimed.add);
    final passthrough = <MeshSession>[];
    planes.passthrough.incoming.listen(passthrough.add);

    hub.openSession('quiet-phone');
    await pumpEventQueue();
    expect(claimed, isEmpty);
    expect(passthrough, isEmpty, reason: 'parked while silent');

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(passthrough, hasLength(1), reason: 'timeout routes to realtime');
    expect(claimed, isEmpty);
  });

  test('a session that dies before its first frame is dropped, not routed', () async {
    final hub = FakeMeshHub();
    final planes = ClaimingMeshTransport(
      inner: hub,
      claim: _isSyncHello,
      claimTimeout: const Duration(seconds: 30),
    );
    final claimed = <MeshSession>[];
    planes.incoming.listen(claimed.add);
    final passthrough = <MeshSession>[];
    planes.passthrough.incoming.listen(passthrough.add);

    final dial = hub.openSession('ghost');
    await pumpEventQueue();
    expect(hub.openSessions, hasLength(1));
    dial.closeLocally();
    await pumpEventQueue();
    expect(claimed, isEmpty);
    expect(passthrough, isEmpty, reason: 'dead sessions belong to no plane');
  });

  test('a session closed before its first frame is dropped, not routed', () async {
    final hub = FakeMeshHub();
    final planes = ClaimingMeshTransport(
      inner: hub,
      claim: _isSyncHello,
      claimTimeout: const Duration(seconds: 30),
    );
    final claimed = <MeshSession>[];
    planes.incoming.listen(claimed.add);
    final passthrough = <MeshSession>[];
    planes.passthrough.incoming.listen(passthrough.add);

    final dial = hub.openSession('shy');
    await pumpEventQueue();
    await dial.close();
    await pumpEventQueue();
    expect(claimed, isEmpty);
    expect(passthrough, isEmpty);
  });

  test('outbound dials pass through untouched', () async {
    final pair = FakeMeshPair.paired(a: 'host', b: 'phone');
    final planes = ClaimingMeshTransport(inner: pair.a, claim: _isSyncHello);
    pair.b.incoming.listen((final session) async {
      await session.send(_frame({'type': 'hello', 'v': 2}));
    });
    final dialed = await planes.passthrough.connect(
      const MeshPeerRecord(peerId: 'phone', displayName: 'phone'),
    );
    final first = await dialed.inbound.first.timeout(
      const Duration(seconds: 5),
    );
    expect(utf8.decode(first), contains('hello'));
  });

  test('dispose closes still-parked sessions and stops routing', () async {
    final hub = FakeMeshHub();
    final planes = ClaimingMeshTransport(
      inner: hub,
      claim: _isSyncHello,
      claimTimeout: const Duration(seconds: 30),
    );
    final claimed = <MeshSession>[];
    planes.incoming.listen(claimed.add);
    final passthrough = <MeshSession>[];
    planes.passthrough.incoming.listen(passthrough.add);

    final dial = hub.openSession('parked');
    await pumpEventQueue();
    expect(hub.openSessions, hasLength(1));
    await planes.dispose();
    expect(dial.closedByPeer, isTrue, reason: 'parked sessions are closed');
    // Routing stopped with the inner subscription: a new session reaches
    // neither plane.
    hub.openSession('after-dispose');
    await pumpEventQueue();
    expect(claimed, isEmpty);
    expect(passthrough, isEmpty);
  });
}
