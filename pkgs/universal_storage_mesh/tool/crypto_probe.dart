import 'package:cryptography/cryptography.dart';

Future<void> main() async {
  final algo = Ed25519();
  final keyPair = await algo.newKeyPair();
  final pub = await keyPair.extractPublicKey();
  print('ed25519 ok: ${pub.bytes.length} bytes');
  final x = X25519();
  final k1 = await x.newKeyPair();
  final k2 = await x.newKeyPair();
  final s1 = await x.sharedSecretKey(
    keyPair: k1,
    remotePublicKey: await k2.extractPublicKey(),
  );
  final s2 = await x.sharedSecretKey(
    keyPair: k2,
    remotePublicKey: await k1.extractPublicKey(),
  );
  final b1 = await s1.extractBytes();
  final b2 = await s2.extractBytes();
  var equal = b1.length == b2.length;
  for (var i = 0; equal && i < b1.length; i++) {
    if (b1[i] != b2[i]) equal = false;
  }
  print('x25519 shared secrets match: $equal (${b1.length} bytes)');
}
