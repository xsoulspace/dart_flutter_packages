import 'package:test/test.dart';
import 'package:xsoulspace_vkplay_server_api/xsoulspace_vkplay_server_api.dart';

void main() {
  test('sendInvite signs and posts form payload', () async {
    final transport = _FakeTransport(
      response: const VkPlayTransportResponse(
        statusCode: 200,
        body: '{"ok":true}',
      ),
    );

    final client = VkPlayServerApiClient(
      baseUri: Uri.parse('https://api.example.com/'),
      secret: 'secret',
      appId: 'app-1',
      transport: transport,
    );

    final response = await client.sendInvite(
      userId: 'u1',
      message: 'join',
      payload: 'room=1',
    );

    expect(response.isSuccess, isTrue);
    expect(response.data, containsPair('ok', true));

    final request = transport.lastRequest;
    expect(request, isNotNull);
    expect(request!.uri.toString(), 'https://api.example.com/invite/send');
    expect(request.form, containsPair('app_id', 'app-1'));
    expect(request.form, containsPair('user_id', 'u1'));
    expect(request.form, contains('sig'));
  });

  test('buildBillingUrl attaches signed query parameters', () {
    final client = VkPlayServerApiClient(
      baseUri: Uri.parse('https://api.example.com/'),
      secret: 'secret',
      appId: 'app-1',
      transport: _FakeTransport(
        response: const VkPlayTransportResponse(statusCode: 200, body: '{}'),
      ),
    );

    final uri = client.buildBillingUrl(
      userId: 'u1',
      itemId: 'coins_10',
      orderId: 'o-9',
    );

    expect(uri.toString(), contains('billing/frame'));
    expect(uri.queryParameters, containsPair('user_id', 'u1'));
    expect(uri.queryParameters, containsPair('item_id', 'coins_10'));
    expect(uri.queryParameters, contains('sig'));
  });

  test('verifyBillingCallback delegates to signer', () {
    final client = VkPlayServerApiClient(
      baseUri: Uri.parse('https://api.example.com/'),
      secret: 'secret',
      transport: _FakeTransport(
        response: const VkPlayTransportResponse(statusCode: 200, body: '{}'),
      ),
    );

    const signer = VkPlaySigner();
    final payload = <String, Object?>{'user_id': 'u1', 'event': 'billing'};
    final sig = signer.sign(params: payload, secret: 'secret');

    final withSig = <String, Object?>{...payload, 'sig': sig};
    expect(client.verifyBillingCallback(payload: withSig), isTrue);
  });
}

final class _FakeTransport implements VkPlayTransport {
  _FakeTransport({required this.response});

  final VkPlayTransportResponse response;
  VkPlayTransportRequest? lastRequest;

  @override
  Future<VkPlayTransportResponse> send(
    final VkPlayTransportRequest request,
  ) async {
    lastRequest = request;
    return response;
  }
}
