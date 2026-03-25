import 'dart:collection';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:xsoulspace_discord_server_api/xsoulspace_discord_server_api.dart';

void main() {
  test('OAuth authorization-code exchange request/response mapping', () async {
    final transport = _FakeTransport()
      ..enqueue(
        const DiscordTransportResponse(
          statusCode: 200,
          body:
              '{"access_token":"at-1","token_type":"Bearer","expires_in":3600,"refresh_token":"rt-1","scope":"identify"}',
        ),
      );

    final oauth = DiscordOAuthClient(
      clientId: 'client-1',
      clientSecret: 'secret-1',
      redirectUri: 'https://example.com/callback',
      transport: transport,
    );

    final token = await oauth.exchangeAuthorizationCode(code: 'code-1');

    expect(token.accessToken, 'at-1');
    expect(token.refreshToken, 'rt-1');

    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, '/api/v10/oauth2/token');
    expect(request.form['grant_type'], 'authorization_code');
    expect(request.form['code'], 'code-1');
    expect(request.form['client_id'], 'client-1');
    expect(request.form['client_secret'], 'secret-1');
  });

  test('OAuth refresh and revoke mappings', () async {
    final transport = _FakeTransport()
      ..enqueue(
        const DiscordTransportResponse(
          statusCode: 200,
          body:
              '{"access_token":"at-2","token_type":"Bearer","expires_in":3600,"refresh_token":"rt-2"}',
        ),
      )
      ..enqueue(const DiscordTransportResponse(statusCode: 200, body: '{}'));

    final oauth = DiscordOAuthClient(
      clientId: 'client-1',
      clientSecret: 'secret-1',
      redirectUri: 'https://example.com/callback',
      transport: transport,
    );

    final refreshed = await oauth.refreshToken(refreshToken: 'rt-1');
    expect(refreshed.accessToken, 'at-2');

    await oauth.revokeToken(token: 'at-2');

    expect(transport.requests, hasLength(2));
    expect(transport.requests[0].form['grant_type'], 'refresh_token');
    expect(transport.requests[1].uri.path, '/api/v10/oauth2/token/revoke');
    expect(transport.requests[1].form['token'], 'at-2');
  });

  test('generic request serialization and getCurrentUser parsing', () async {
    final transport = _FakeTransport()
      ..enqueue(
        const DiscordTransportResponse(
          statusCode: 200,
          body: '{"ok":true,"value":9}',
        ),
      )
      ..enqueue(
        const DiscordTransportResponse(
          statusCode: 200,
          body: '{"id":"u-1","username":"tester","global_name":"Tester"}',
        ),
      );

    final client = DiscordServerApiClient(
      transport: transport,
      bearerToken: 'token-1',
    );

    final response = await client.request(
      method: 'POST',
      path: '/applications/1/custom',
      jsonBody: <String, Object?>{'hello': 'world'},
    );

    expect(response.statusCode, 200);
    expect(response.data['ok'], true);

    final firstRequest = transport.requests.first;
    expect(firstRequest.headers['authorization'], 'Bearer token-1');
    expect(firstRequest.headers['content-type'], 'application/json');
    final decodedBody = jsonDecode(firstRequest.body!) as Map<String, Object?>;
    expect(decodedBody['hello'], 'world');

    final user = await client.getCurrentUser();
    expect(user.id, 'u-1');
    expect(user.username, 'tester');
  });

  test('401/403/429 errors decode into structured DiscordApiError', () async {
    final transport = _FakeTransport()
      ..enqueue(
        const DiscordTransportResponse(
          statusCode: 401,
          body: '{"code": 40001, "message":"Unauthorized"}',
        ),
      )
      ..enqueue(
        const DiscordTransportResponse(
          statusCode: 403,
          body: '{"code": 50013, "message":"Missing Permissions"}',
        ),
      )
      ..enqueue(
        const DiscordTransportResponse(
          statusCode: 429,
          headers: <String, String>{
            'x-ratelimit-limit': '5',
            'x-ratelimit-remaining': '0',
            'x-ratelimit-reset-after': '1.5',
          },
          body:
              '{"code": 0, "message":"Too Many Requests", "retry_after":1.5, "global": true}',
        ),
      );

    final client = DiscordServerApiClient(transport: transport);

    await expectLater(
      () => client.request(method: 'GET', path: '/users/@me'),
      throwsA(
        isA<DiscordApiError>()
            .having((final e) => e.statusCode, 'statusCode', 401)
            .having((final e) => e.code, 'code', 40001)
            .having((final e) => e.message, 'message', 'Unauthorized'),
      ),
    );

    await expectLater(
      () => client.request(method: 'GET', path: '/users/@me'),
      throwsA(
        isA<DiscordApiError>()
            .having((final e) => e.statusCode, 'statusCode', 403)
            .having((final e) => e.code, 'code', 50013),
      ),
    );

    await expectLater(
      () => client.request(method: 'GET', path: '/users/@me'),
      throwsA(
        isA<DiscordApiError>()
            .having((final e) => e.statusCode, 'statusCode', 429)
            .having(
              (final e) => e.rateLimit.retryAfter,
              'retryAfter',
              const Duration(milliseconds: 1500),
            )
            .having((final e) => e.rateLimit.global, 'global', true)
            .having((final e) => e.rateLimit.limit, 'limit', 5)
            .having((final e) => e.rateLimit.remaining, 'remaining', 0),
      ),
    );
  });
}

final class _FakeTransport implements DiscordTransport {
  final List<DiscordTransportRequest> requests = <DiscordTransportRequest>[];
  final Queue<DiscordTransportResponse> _responses =
      Queue<DiscordTransportResponse>();

  void enqueue(final DiscordTransportResponse response) {
    _responses.add(response);
  }

  @override
  Future<DiscordTransportResponse> send(
    final DiscordTransportRequest request,
  ) async {
    requests.add(request);
    if (_responses.isEmpty) {
      throw StateError('No fake response queued.');
    }
    return _responses.removeFirst();
  }
}
