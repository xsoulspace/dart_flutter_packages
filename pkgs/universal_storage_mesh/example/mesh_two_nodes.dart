import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_mesh/universal_storage_mesh.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

import 'tcp_mesh_transport.dart';

/// Smallest end-to-end mesh example (ADR 0010 milestone).
///
/// Two "devices" in one process pair via a pasted pairing payload (the QR
/// content), then sync files over real TCP sockets. Run with:
///
/// ```sh
/// dart run example/mesh_two_nodes.dart
/// ```
Future<void> main() async {
  final tmp = await Directory.systemTemp.createTemp('mesh_example_');
  stdout.writeln('store: ${tmp.path}\n');

  // -- 1. Identity + transports -------------------------------------------
  final aliceId = await PairingService.newIdentityKeyPair();
  final aliceTransport = TcpMeshTransport(selfId: 'alice', bindPort: 45910);
  await aliceTransport.start();

  final bobTransport = TcpMeshTransport(selfId: 'bob', bindPort: 45911);
  await bobTransport.start();

  // -- 2. Pairing (QR scan equivalent) ------------------------------------
  final aliceEph = await X25519().newKeyPair();
  final qrPayload = await PairingService.buildQrPayload(
    identityKeyPair: aliceId,
    ephemeralKeyPair: aliceEph,
    peerId: 'alice',
    transportHint: 'tcp:127.0.0.1:45910',
  );
  stdout.writeln('pairing payload (QR content):');
  stdout.writeln(base64Encode(qrPayload));

  final alicePub = Uint8List.fromList((await aliceId.extractPublicKey()).bytes);
  final bobResult = await PairingService.acceptQrPayload(
    qrPayload: qrPayload,
    peerIdentityKey: alicePub,
    ownEphemeralKeyPair: await X25519().newKeyPair(),
    ourPeerId: 'bob',
  );
  stdout.writeln('bob verified alice: ${bobResult.peerId}\n');

  final bobEph = await X25519().newKeyPair();
  await PairingService.deriveInitiatorKeys(
    identityKeyPair: aliceId,
    ownEphemeralKeyPair: aliceEph,
    peerEphemeralPublic: Uint8List.fromList(
      (await bobEph.extractPublicKey()).bytes,
    ),
    ourPeerId: 'alice',
    peerId: 'bob',
  );

  // -- 3. Providers --------------------------------------------------------
  final alice = MeshStorageProvider();
  await alice.initWithConfig(
    MeshStorageConfig(storePath: '${tmp.path}/alice', peerId: 'alice'),
  );
  alice.attachTransport(aliceTransport);
  await alice.registerPeer(
    const MeshPeerRecord(
      peerId: 'bob',
      displayName: 'Bob',
      endpointHints: {'tcp': '127.0.0.1:45911'},
    ),
  );

  final bob = MeshStorageProvider();
  await bob.initWithConfig(
    MeshStorageConfig(storePath: '${tmp.path}/bob', peerId: 'bob'),
  );
  bob.attachTransport(bobTransport);
  await bob.registerPeer(
    const MeshPeerRecord(
      peerId: 'alice',
      displayName: 'Alice',
      endpointHints: {'tcp': '127.0.0.1:45910'},
    ),
  );

  // -- 4. Local writes, then sync over real sockets -----------------------
  await alice.createFile('notes/todo.json', '{"done":false,"task":"mesh"}');
  await bob.createFile('notes/other.json', '{"mood":"great"}');

  stdout.writeln('syncing…');
  await alice.sync();
  stdout.writeln('alice.sync done');
  await bob.sync();
  stdout.writeln('bob.sync done');

  stdout.writeln(
    'alice sees bob\'s file: ${await alice.getFile('notes/other.json')}',
  );
  stdout.writeln(
    'bob sees alice\'s file: ${await bob.getFile('notes/todo.json')}',
  );

  // -- 5. Cleanup ----------------------------------------------------------
  await alice.dispose();
  await bob.dispose();
  await aliceTransport.dispose();
  await bobTransport.dispose();
  await tmp.delete(recursive: true);
}
