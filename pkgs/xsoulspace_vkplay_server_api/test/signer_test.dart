import 'package:test/test.dart';
import 'package:xsoulspace_vkplay_server_api/xsoulspace_vkplay_server_api.dart';

void main() {
  test('signs sorted top-level params with md5', () {
    const signer = VkPlaySigner();

    final signature = signer.sign(
      params: <String, Object?>{'b': '2', 'a': '1'},
      secret: 'secret',
    );

    expect(signature, 'd37cfe88ec8ff020e497f5197bf3ba1c');
  });

  test('nested map order is preserved', () {
    const signer = VkPlaySigner();

    final sigA = signer.sign(
      params: <String, Object?>{
        'payload': <String, Object?>{'z': 1, 'a': 2},
        'uid': '1',
      },
      secret: 'secret',
    );

    final sigB = signer.sign(
      params: <String, Object?>{
        'payload': <String, Object?>{'a': 2, 'z': 1},
        'uid': '1',
      },
      secret: 'secret',
    );

    expect(sigA, isNot(equals(sigB)));
  });

  test('verifies callback signature', () {
    const signer = VkPlaySigner();
    final payload = <String, Object?>{
      'event': 'billing',
      'user_id': 'u1',
      'amount': '99',
    };

    final sig = signer.sign(params: payload, secret: 'secret');
    final withSig = <String, Object?>{...payload, 'sig': sig};

    expect(
      verifyVkPlayCallbackSignature(payload: withSig, secret: 'secret'),
      isTrue,
    );
  });
}
