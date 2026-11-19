import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:xsoulspace_inference_xai/xsoulspace_inference_xai.dart';

void main() {
  test('an unregistered client never calls the issuer', () {
    final auth = GrokAuth(
      store: _MemoryStore(),
      registration: const LastAnswerGrokRegistration(clientId: ''),
    );
    expect(
      () => auth.begin(),
      throwsA(
        isA<GrokAuthException>().having(
          (error) => error.code,
          'code',
          'client_not_registered',
        ),
      ),
    );
    auth.close();
  });

  test('the authorize URL names Last Answer', () {
    final auth = GrokAuth(
      store: _MemoryStore(),
      registration: const LastAnswerGrokRegistration(clientId: 'la-client'),
    );
    final attempt = auth.begin();
    final params = attempt.authorizationUri.queryParameters;
    expect(attempt.authorizationUri.path, '/oauth2/authorize');
    expect(params['client_id'], 'la-client');
    expect(params['referrer'], 'last-answer');
    expect(params['redirect_uri'], LastAnswerGrokRegistration.redirectUri);
    expect(params['code_challenge_method'], 'S256');
    expect(params['scope'], contains('api:access'));
    expect(params['code_challenge'], isNot(params['state']));
    auth.close();
  });

  test('browser completion stores the subject and plan scope', () async {
    String? nonce;
    final server = await _Issuer.start(nonceOf: () => nonce);
    final store = _MemoryStore();
    final auth = GrokAuth(
      store: store,
      registration: const LastAnswerGrokRegistration(clientId: 'la-client'),
      tokenEndpoint: server.token,
      client: server.client,
    );
    final attempt = auth.begin();
    nonce = attempt.nonce;
    final account = await auth.complete(
      attempt,
      attempt.redirectUri.replace(
        queryParameters: {'code': 'one-time', 'state': attempt.state},
      ),
    );
    expect(account.subject, 'user-1');
    expect(account.email, 'person@example.com');
    expect(account.planEnabled, isTrue);
    expect(store.records['user-1']?.refreshToken, 'refresh-2');
    expect(server.received['code_verifier'], attempt.verifier);
    expect(server.received['client_id'], 'la-client');
    auth.close();
    await server.close();
  });

  test('a mismatched state is refused before the issuer is called', () async {
    final auth = GrokAuth(
      store: _MemoryStore(),
      registration: const LastAnswerGrokRegistration(clientId: 'la-client'),
    );
    final attempt = auth.begin();
    await expectLater(
      auth.complete(
        attempt,
        attempt.redirectUri.replace(
          queryParameters: {'code': 'x', 'state': 'other'},
        ),
      ),
      throwsA(
        isA<GrokAuthException>().having(
          (error) => error.code,
          'code',
          'invalid_callback',
        ),
      ),
    );
    auth.close();
  });

  test('device approval follows authorization_pending', () async {
    final server = await _Issuer.start(pendingPolls: 1);
    final auth = GrokAuth(
      store: _MemoryStore(),
      registration: const LastAnswerGrokRegistration(clientId: 'la-client'),
      tokenEndpoint: server.token,
      deviceEndpoint: server.device,
      client: server.client,
    );
    final attempt = await auth.beginDevice();
    expect(attempt.prompt.userCode, 'ABCD-1234');
    final account = await auth.completeDevice(attempt);
    expect(account.subject, 'user-1');
    expect(server.polls, 2);
    auth.close();
    await server.close();
  });

  test('refresh rotates the refresh token and keeps the subject', () async {
    final server = await _Issuer.start();
    final store = _MemoryStore();
    final auth = GrokAuth(
      store: store,
      registration: const LastAnswerGrokRegistration(clientId: 'la-client'),
      tokenEndpoint: server.token,
      clock: () => DateTime.utc(2026, 1, 1),
      client: server.client,
    );
    await store.write(
      GrokAccount(
        clientId: 'la-client',
        subject: 'user-1',
        email: 'person@example.com',
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        idToken: _jwt(),
        expiresAt: DateTime.utc(2026, 1, 1),
        scopes: {'openid', 'api:access'},
      ),
    );
    final account = await auth.accountForInference('user-1');
    expect(account.accessToken, 'access-1');
    expect(account.refreshToken, 'refresh-2');
    expect(store.records['user-1']?.subject, 'user-1');
    auth.close();
    await server.close();
  });
}

String _jwt({String? nonce}) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part({
    'sub': 'user-1',
    'aud': 'la-client',
    'email': 'person@example.com',
    'exp': 9999999999,
    'nonce': ?nonce,
  })}.sig';
}

final class _MemoryStore implements GrokCredentialStore {
  final records = <String, GrokAccount>{};

  @override
  Future<GrokAccount?> read(String subject) async => records[subject];

  @override
  Future<void> write(GrokAccount account) async {
    records[account.subject] = account;
  }

  @override
  Future<void> removeTokens(String subject) async {
    records.remove(subject);
  }
}

final class _Issuer {
  _Issuer._(this._server, this.pendingPolls, this.nonceOf);
  final HttpServer _server;
  final int pendingPolls;
  final String? Function() nonceOf;
  int polls = 0;
  Map<String, String> received = const {};
  final client = http.Client();

  Uri get token => Uri.parse('http://127.0.0.1:${_server.port}/token');
  Uri get device => Uri.parse('http://127.0.0.1:${_server.port}/device');

  static Future<_Issuer> start({
    int pendingPolls = 0,
    String? Function()? nonceOf,
  }) async {
    final issuer = _Issuer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      pendingPolls,
      nonceOf ?? () => null,
    );
    issuer._server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final fields = Uri.splitQueryString(body);
      issuer.received = fields;
      final pending =
          request.uri.path != '/device' &&
          fields['grant_type'] ==
              'urn:ietf:params:oauth:grant-type:device_code' &&
          issuer.polls++ < issuer.pendingPolls;
      final json = request.uri.path == '/device'
          ? {
              'device_code': 'device-secret',
              'user_code': 'ABCD-1234',
              'verification_uri': 'https://auth.x.ai/device',
              'expires_in': 600,
              'interval': 1,
            }
          : pending
          ? {'error': 'authorization_pending'}
          : {
              'access_token': 'access-1',
              'refresh_token': 'refresh-2',
              'id_token': _jwt(nonce: issuer.nonceOf()),
              'expires_in': 3600,
              'scope': 'openid profile email offline_access api:access',
              'token_type': 'Bearer',
            };
      request.response.statusCode = pending ? 400 : 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(json));
      await request.response.close();
    });
    return issuer;
  }

  Future<void> close() async {
    client.close();
    await _server.close(force: true);
  }
}
