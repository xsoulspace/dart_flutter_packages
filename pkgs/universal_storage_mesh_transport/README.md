# universal_storage_mesh_transport

Transport seam for mesh sync
([ADR 0010](../../docs/decisions/0010_mesh_sync_architecture.md)): peer and
session interfaces, length-prefixed framing for stream transports, and a
deterministic fake transport for headless tests. Real radio transports
(LAN mDNS+TCP first, BLE-class later) are separate packages implementing
`MeshTransport`.

North Star: [../universal_storage_mesh/docs/north_star.mdx](../universal_storage_mesh/docs/north_star.mdx)
(the transport seam is one slice of the mesh center).

## Contract

```dart
abstract interface class MeshTransport {
  /// Sessions initiated by remote peers; every inbound session delivered
  /// exactly once.
  Stream<MeshSession> get incoming;

  /// Opens a session to a previously paired [peer].
  /// Throws [MeshConnectionException] when this transport cannot reach
  /// that peer — never silently connects somewhere else.
  Future<MeshSession> connect(MeshPeerRecord peer);
}

abstract interface class MeshSession {
  String get remotePeerId;
  Stream<Uint8List> get inbound;
  Future<void> send(Uint8List payload);
  Future<void> close();
}
```

Implementations know nothing about documents or convergence: frames carry
convergence-kernel envelopes only. Real transports must establish session
keys from pairing material before delivering any inbound bytes; the fake
transport used in tests is plaintext by design.

## Testing your transport

`FakeMeshPair.paired()` gives two linked transports for provider tests:

```dart
final pair = FakeMeshPair.paired(a: 'device-a', b: 'device-b');
pair.b.incoming.listen(responderHandler);
final session = await pair.a.connect(
  const MeshPeerRecord(peerId: 'device-b', displayName: 'B'),
);
```

For stream-based real transports, `frameMessage` + `FrameDecoder` provide
4-byte big-endian length framing with incremental de-framing.
