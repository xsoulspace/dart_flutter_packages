import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart' as pc;
import 'package:xsoulspace_inference_openai/xsoulspace_inference_openai.dart';

final class MemoryCredentials implements ChatGptCredentialStore {
  final records = <String, ChatGptAccount>{};
  int writes = 0;
  @override
  Future<ChatGptAccount?> read(String clientId) async => records[clientId];
  @override
  Future<void> write(ChatGptAccount account) async {
    writes++;
    records[account.clientId] = account;
  }

  @override
  Future<void> removeTokens(String clientId) async {
    records.remove(clientId);
  }
}

ChatGptAccount account({DateTime? expiresAt, Set<String>? scopes}) =>
    ChatGptAccount(
      clientId: 'oaiapp_test',
      hostId: 'urn:uuid:12345678-1234-4123-8123-123456789abc',
      subject: 'subject',
      accessToken: 'test-access',
      refreshToken: 'test-refresh',
      idToken: 'test-id',
      expiresAt: expiresAt ?? DateTime.utc(2099),
      scopes: scopes ?? {'chatgpt.tokens.use.direct'},
    );

final class SigningFixture {
  SigningFixture() {
    final random = pc.FortunaRandom()
      ..seed(
        pc.KeyParameter(Uint8List.fromList(List.generate(32, (i) => i + 1))),
      );
    final generator = pc.RSAKeyGenerator()
      ..init(
        pc.ParametersWithRandom(
          pc.RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
          random,
        ),
      );
    keys = generator.generateKeyPair();
  }
  late final pc.AsymmetricKeyPair<pc.RSAPublicKey, pc.RSAPrivateKey> keys;
  Map<String, dynamic> get jwks => {
    'keys': [
      {
        'kty': 'RSA',
        'kid': 'fixture',
        'alg': 'RS256',
        'use': 'sig',
        'n': _integer(keys.publicKey.modulus!),
        'e': _integer(keys.publicKey.exponent!),
      },
    ],
  };
  String token(String nonce, {Map<String, dynamic> overrides = const {}}) {
    final header = _encode({'alg': 'RS256', 'kid': 'fixture'});
    final payload = _encode({
      'iss': 'https://auth.openai.com',
      'aud': 'oaiapp_test',
      'sub': 'subject',
      'exp': DateTime.utc(2099).millisecondsSinceEpoch ~/ 1000,
      'nonce': nonce,
      ...overrides,
    });
    final signer = pc.Signer('SHA-256/RSA')
      ..init(true, pc.PrivateKeyParameter<pc.RSAPrivateKey>(keys.privateKey));
    final signature =
        signer.generateSignature(
              Uint8List.fromList(utf8.encode('$header.$payload')),
            )
            as pc.RSASignature;
    return '$header.$payload.${base64Url.encode(signature.bytes).replaceAll('=', '')}';
  }

  String _encode(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  String _integer(BigInt value) {
    var hex = value.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    return base64Url
        .encode(
          List.generate(
            hex.length ~/ 2,
            (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
          ),
        )
        .replaceAll('=', '');
  }
}
