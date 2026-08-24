import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:qr/qr.dart';

import 'package:universal_storage_mesh/universal_storage_mesh.dart';

/// Demonstrates the signed `mesh-pair/v1` QR payload end to end.
///
/// Alice builds and displays the payload; Bob verifies it and derives the
/// matching transport keys. Run with:
///
/// ```sh
/// dart run example/qr_pairing.dart
/// ```
Future<void> main() async {
  final aliceIdentity = await PairingService.newIdentityKeyPair();
  final aliceEphemeral = await X25519().newKeyPair();
  final qrPayload = await PairingService.buildQrPayload(
    identityKeyPair: aliceIdentity,
    ephemeralKeyPair: aliceEphemeral,
    peerId: 'alice',
    transportHint: 'tcp:192.168.1.20:45910',
  );

  stdout.writeln('scan this mesh-pair/v1 code:\n');
  stdout.writeln(_terminalQr(qrPayload));

  final bobEphemeral = await X25519().newKeyPair();
  final accepted = await PairingService.acceptQrPayload(
    qrPayload: qrPayload,
    peerIdentityKey: Uint8List.fromList(
      (await aliceIdentity.extractPublicKey()).bytes,
    ),
    ownEphemeralKeyPair: bobEphemeral,
    ourPeerId: 'bob',
  );
  stdout.writeln('bob verified alice: ${accepted.peerId}');

  await PairingService.deriveInitiatorKeys(
    identityKeyPair: aliceIdentity,
    ownEphemeralKeyPair: aliceEphemeral,
    peerEphemeralPublic: Uint8List.fromList(
      (await bobEphemeral.extractPublicKey()).bytes,
    ),
    ourPeerId: 'alice',
    peerId: 'bob',
  );
  stdout.writeln('alice derived matching keys for bob');
}

String _terminalQr(final Uint8List payload) {
  final qr = QrCode(
    payload: QrPayload.fromTypedData(payload),
    errorCorrectLevel: QrErrorCorrectLevel.medium,
  );
  final image = QrImage(qr);
  final modules = image.moduleCount;
  final buffer = StringBuffer();

  String half(final bool top, final bool bottom) => !top && !bottom
      ? '██'
      : top && !bottom
      ? '▀▀'
      : !top && bottom
      ? '▄▄'
      : '  ';

  for (var y = 0; y < modules; y += 2) {
    final line = StringBuffer();
    for (var x = 0; x < modules; x++) {
      final bottom = y + 1 < modules && image.isDark(y + 1, x);
      line.write(half(image.isDark(y, x), bottom));
    }
    buffer.writeln(line.toString().trimRight());
  }
  return buffer.toString();
}
