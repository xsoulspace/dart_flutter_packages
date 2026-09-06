import 'dart:async';
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

  test('frames round-trip every event kind with payload and ttl', () {
    for (final event in MeshEphemeralEvent.values) {
      final f = MeshEphemeralFrame(
        docId: frame.docId,
        fromPeerId: frame.fromPeerId,
        event: event,
        payload: frame.payload,
        ttl: frame.ttl,
        issuedAtMs: frame.issuedAtMs,
      );
      final decoded = MeshEphemeralFrame.decode(f.encode());
      expect(decoded, f);
      expect(decoded.event, event);
      expect(decoded.payload, frame.payload);
      expect(decoded.ttl, frame.ttl);
      expect(decoded.issuedAtMs, frame.issuedAtMs);
    }
  });

  test('expiry is measured from issuedAtMs plus ttl', () {
    final issuedAt = DateTime.fromMillisecondsSinceEpoch(frame.issuedAtMs!);
    expect(
      frame.isExpiredAt(issuedAt.add(frame.ttl)),
      isFalse,
      reason: 'boundary instant is still live',
    );
    final longAfter = issuedAt.add(frame.ttl).add(const Duration(days: 1));
    expect(frame.isExpiredAt(longAfter), isTrue);
    expect(frame.isExpiredAt(issuedAt), isFalse);
    // Frames without an issuer timestamp make no expiry claim.
    const stampless = MeshEphemeralFrame(
      docId: 'd',
      fromPeerId: 'p',
      event: MeshEphemeralEvent.ping,
      ttl: Duration(seconds: 1),
    );
    expect(
      stampless.isExpiredAt(issuedAt.add(const Duration(days: 1))),
      isFalse,
    );
  });

  test('decode rejects unknown versions and garbage bytes', () {
    expect(
      () => MeshEphemeralFrame.decode(
        Uint8List.fromList('not json'.codeUnits),
      ),
      throwsA(anyOf(isArgumentError, isFormatException)),
    );
    final raw = frame.encode();
    final bumped = utf8.decode(raw).replaceFirst('"v":1', '"v":999');
    expect(
      () => MeshEphemeralFrame.decode(Uint8List.fromList(utf8.encode(bumped))),
      throwsArgumentError,
    );
  });

  test('frames round-trip through a fake relay session', () async {
    final pair = FakeMeshPair.paired();
    final received = <MeshEphemeralFrame>[];
    final done = Completer<void>();

    // Fire-and-forget receiver: frames arrive as long as the session
    // lives; the completer signals when all three were decoded.
    // ignore: unawaited_futures
    pair.b.incoming.listen((session) async {
      await for (final bytes in session.inbound) {
        received.add(MeshEphemeralFrame.decode(bytes));
        if (received.length == 3) done.complete();
      }
    });

    final session = await pair.a.connect(
      const MeshPeerRecord(peerId: 'device-b', displayName: 'B'),
    );
    for (final event in MeshEphemeralEvent.values) {
      await session.send(
        MeshEphemeralFrame(
          docId: frame.docId,
          fromPeerId: frame.fromPeerId,
          event: event,
          payload: frame.payload,
          ttl: frame.ttl,
          issuedAtMs: frame.issuedAtMs,
        ).encode(),
      );
    }

    await done.future.timeout(const Duration(seconds: 5));
    expect(received.map((f) => f.event), MeshEphemeralEvent.values);
    for (final f in received) {
      expect(f.docId, frame.docId);
      expect(f.fromPeerId, frame.fromPeerId);
      expect(f.payload, frame.payload);
      expect(f.ttl, frame.ttl);
      expect(f.issuedAtMs, frame.issuedAtMs);
    }
  });

  test('ephemeral frames relay unchanged through the addressed relay',
      () async {
    final relay = AddressedRelayServer(port: 0);
    final port = await relay.start();
    addTearDown(relay.dispose);
    final endpoint = Uri.parse('ws://127.0.0.1:$port');

    final a = AddressedRelayClient(selfId: 'device-a', endpoint: endpoint);
    final b = AddressedRelayClient(selfId: 'device-b', endpoint: endpoint);
    await a.openRelay();
    await b.openRelay();

    final inbound = b.incoming.first;
    // Opening the logical session is required for b to receive data; the
    // session handle itself is not needed since the ephemeral send is
    // addressed by peer id.
    await a.connect(
      const MeshPeerRecord(peerId: 'device-b', displayName: 'B'),
    );
    final remote = await inbound;

    final received = <Uint8List>[];
    final done = Completer<void>();
    remote.inbound.listen((bytes) {
      received.add(bytes);
      done.complete();
    });

    // Sent under the ephemeral envelope kind; delivered through the same
    // path as data — relayed, never treated durably.
    await a.sendEphemeral(
      toPeerId: 'device-b',
      payload: frame.encode(),
    );
    await done.future.timeout(const Duration(seconds: 5));
    expect(MeshEphemeralFrame.decode(received.single), frame);

    await a.close();
    await b.close();
  });
}
