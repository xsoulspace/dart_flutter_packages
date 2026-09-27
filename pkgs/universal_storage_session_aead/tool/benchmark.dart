import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';
import 'package:universal_storage_session_aead/universal_storage_session_aead.dart';

/// Empirical cost of the session-AEAD channel on THIS machine.
///
/// Run from the package directory:
/// ```
/// dart run tool/benchmark.dart
/// ```
///
/// The number that matters next to the measured Ed25519 sign (the
/// per-frame cost the session channel REPLACES): sealing a frame must be
/// orders of magnitude cheaper, or the handshake is pointless.
Future<void> main() async {
  const header = 'mesh-session/v1 benchmark';

  // -- Session cipher: per-frame cost -------------------------------------
  for (final size in const [48, 1024]) {
    final payload = Uint8List(size);
    final initiator = _cipherPair();
    final responder = _cipherPair();
    // Warmup.
    for (var i = 0; i < 200; i++) {
      responder.open(initiator.seal(payload));
    }
    const iterations = 2000;
    final sealWatch = Stopwatch()..start();
    final records = List.generate(iterations, (_) => initiator.seal(payload));
    sealWatch.stop();
    final openWatch = Stopwatch()..start();
    records.forEach(responder.open);
    openWatch.stop();
    _line(
      '$header | seal ${size}B',
      sealWatch.elapsedMicroseconds / iterations,
      unit: 'µs/op',
    );
    _line(
      '$header | open ${size}B',
      openWatch.elapsedMicroseconds / iterations,
      unit: 'µs/op',
    );
  }

  // -- Full handshake ------------------------------------------------------
  final a = await _identity('device-a');
  final b = await _identity('device-b');
  Future<void> handshake() async {
    final pair = FakeMeshPair.paired(a: a.$3, b: b.$3);
    final accepted = Completer<MeshSession>();
    final subscription = pair.b.incoming.listen(
      (final raw) => unawaited(
        SessionAeadSession.accept(
          raw: raw,
          identityKeyPair: b.$1,
          selfId: b.$3,
          pinnedIdentityKeys: {a.$3: a.$2},
        ).then(accepted.complete),
      ),
    );
    final dialer = await SessionAeadSession.start(
      raw: await pair.a.connect(
        MeshPeerRecord(peerId: b.$3, displayName: b.$3, identityKey: b.$2),
      ),
      identityKeyPair: a.$1,
      selfId: a.$3,
      remotePeerId: b.$3,
      expectedPeerIdentityKey: b.$2,
    );
    final host = await accepted.future;
    await dialer.close();
    await host.close();
    await subscription.cancel();
  }

  for (var i = 0; i < 3; i++) {
    await handshake(); // warmup
  }
  const handshakeRuns = 7;
  final times = <double>[];
  for (var i = 0; i < handshakeRuns; i++) {
    final watch = Stopwatch()..start();
    await handshake();
    times.add(watch.elapsedMicroseconds / 1000);
  }
  times.sort();
  _line(
    '$header | handshake (2×Ed25519 sign + X25519 + HKDF)',
    times[times.length ~/ 2],
    unit: 'ms/op (median of $handshakeRuns)',
  );

  // -- Context: the per-frame cost this channel replaces -------------------
  final ed25519 = Ed25519();
  final payload = Uint8List(48);
  await ed25519.sign(payload, keyPair: a.$1); // warmup
  const signRuns = 10;
  final signWatch = Stopwatch()..start();
  for (var i = 0; i < signRuns; i++) {
    await ed25519.sign(payload, keyPair: a.$1);
  }
  signWatch.stop();
  _line(
    '$header | Ed25519 sign (contrast: what the channel replaces)',
    signWatch.elapsedMicroseconds / signRuns / 1000,
    unit: 'ms/op',
  );
}

SessionCipher _cipherPair() {
  final send = Uint8List.fromList(
    List.generate(32, (final i) => (i + 3) & 0xff),
  );
  final receive = Uint8List.fromList(
    List.generate(32, (final i) => (i + 11) & 0xff),
  );
  return SessionCipher(
    sendKey: SecretKeyData(send),
    receiveKey: SecretKeyData(receive),
  );
}

Future<(SimpleKeyPair, Uint8List, String)> _identity(final String id) async {
  final keyPair = await Ed25519().newKeyPair();
  final publicKey = await keyPair.extractPublicKey();
  return (keyPair, Uint8List.fromList(publicKey.bytes), id);
}

void _line(
  final String label,
  final double value, {
  required final String unit,
}) {
  // ignore: avoid_print
  print('${label.padRight(64)} ${value.toStringAsFixed(2)} $unit');
}
