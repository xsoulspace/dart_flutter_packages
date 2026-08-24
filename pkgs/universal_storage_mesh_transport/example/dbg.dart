import 'dart:async';
import 'dart:typed_data';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

Future<void> main() async {
  final pair = FakeMeshPair.paired();
  final received = <String>[];
  pair.b.incoming.listen((session) {
    // ignore: avoid_print
    print('responder session arrived');
    session.inbound.listen((bytes) {
      // ignore: avoid_print
      print('got: ${String.fromCharCodes(bytes)}');
      received.add(String.fromCharCodes(bytes));
    });
  });
  final s = await pair.a.connect(
    const MeshPeerRecord(peerId: 'device-b', displayName: 'B'),
  );
  // ignore: avoid_print
  print('connected, sending');
  await s.send(Uint8List.fromList('ping'.codeUnits));
  await Future<void>.delayed(const Duration(milliseconds: 50));
  // ignore: avoid_print
  print('received=$received');
}
