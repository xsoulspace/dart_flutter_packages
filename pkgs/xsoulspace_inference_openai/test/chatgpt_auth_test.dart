import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_openai/xsoulspace_inference_openai.dart';
import 'support.dart';

void main() {
  late SigningFixture fixture;
  setUpAll(() {
    fixture = SigningFixture();
  });
  test('a tampered signature cannot publish credentials', () async {
    final store = MemoryCredentials();
    late ChatGptAuthorizationAttempt attempt;
    final auth = ChatGptAuth(
      store: store,
      client: MockClient((request) async {
        if (request.url.path.endsWith('openid-configuration')) {
          return http.Response(
            jsonEncode({
              'issuer': 'https://auth.openai.com',
              'jwks_uri': 'https://auth.openai.com/jwks',
              'revocation_endpoint': 'https://auth.openai.com/revoke',
            }),
            200,
          );
        }
        if (request.url.path == '/revoke') {
          return http.Response('', 200);
        }
        if (request.url.path == '/jwks') {
          return http.Response(jsonEncode(fixture.jwks), 200);
        }
        final parts = fixture.token(attempt.nonce).split('.');
        final signature = base64Url.decode(base64Url.normalize(parts[2]));
        signature[0] ^= 1;
        parts[2] = base64Url.encode(signature).replaceAll('=', '');
        return http.Response(
          jsonEncode({
            'access_token': 'access',
            'refresh_token': 'refresh',
            'id_token': parts.join('.'),
            'token_type': 'Bearer',
            'expires_in': 3600,
            'scope': 'chatgpt.tokens.use.direct',
          }),
          200,
        );
      }),
    );
    attempt = auth.begin(
      hostId: account().hostId,
      appName: 'Last Answer',
      redirectUri: Uri.parse('http://127.0.0.1:1455/auth/callback'),
    );
    await expectLater(
      auth.complete(
        attempt,
        attempt.redirectUri.replace(
          queryParameters: {
            'code': 'code',
            'state': attempt.state,
            'client_id': 'oaiapp_test',
          },
        ),
      ),
      throwsA(
        isA<ChatGptAuthException>().having(
          (e) => e.code,
          'code',
          'invalid_id_token',
        ),
      ),
    );
    expect(store.writes, 0);
  });
  final redirect = Uri.parse('http://127.0.0.1:1455/auth/callback');
  final authError = isA<ChatGptAuthException>();

  test('signed-out registration reauthorizes without retaining tokens', () {
    final auth = ChatGptAuth(store: MemoryCredentials());
    addTearDown(auth.close);
    final attempt = auth.begin(
      hostId: account().hostId,
      appName: 'Last Answer',
      redirectUri: redirect,
      registration: ChatGptRegistration(
        clientId: 'oaiapp_test',
        hostId: account().hostId,
        subject: 'subject',
      ),
    );
    expect(
      attempt.authorizationUri.queryParameters['client_id'],
      'oaiapp_test',
    );
    expect(
      attempt.authorizationUri.queryParameters.containsKey('id_token_hint'),
      false,
    );
    expect(attempt.account, isNull);
  });

  test(
    'fresh PKCE/state/nonce; host and issued registration survive reauthorization',
    () {
      final auth = ChatGptAuth(store: MemoryCredentials());
      addTearDown(auth.close);
      final first = auth.begin(
        hostId: account().hostId,
        appName: 'Last Answer',
        redirectUri: redirect,
      );
      final second = auth.begin(
        hostId: account().hostId,
        appName: 'Last Answer',
        redirectUri: redirect,
        account: account(),
      );
      expect(first.state, isNot(second.state));
      expect(first.nonce, isNot(second.nonce));
      expect(
        first.authorizationUri.queryParameters['client_id'],
        'dynamic_agent_client',
      );
      expect(
        second.authorizationUri.queryParameters['client_id'],
        'oaiapp_test',
      );
      expect(
        second.authorizationUri.queryParameters.containsKey('agent_name_hint'),
        false,
      );
      expect(
        first.authorizationUri.queryParameters['code_challenge'],
        base64Url
            .encode(sha256.convert(utf8.encode(first.verifier)).bytes)
            .replaceAll('=', ''),
      );
      expect(first.toString(), isNot(contains(first.verifier)));
      expect(ChatGptAuth.createHostId(), startsWith('urn:uuid:'));
    },
  );

  for (final change in <String, dynamic>{
    'iss': 'https://evil.example',
    'aud': 'other',
    'nonce': 'other',
    'exp': 1,
    'sub': '',
  }.entries) {
    test(
      'signed token rejects invalid ${change.key} without storing credentials',
      () async {
        final store = MemoryCredentials();
        late ChatGptAuthorizationAttempt attempt;
        final auth = ChatGptAuth(
          store: store,
          client: MockClient((request) async {
            if (request.url.path.endsWith('openid-configuration')) {
              return http.Response(
                jsonEncode({
                  'issuer': 'https://auth.openai.com',
                  'jwks_uri': 'https://auth.openai.com/jwks',
                  'revocation_endpoint': 'https://auth.openai.com/revoke',
                }),
                200,
              );
            }
            if (request.url.path == '/revoke') {
              return http.Response('', 200);
            }
            if (request.url.path == '/jwks') {
              return http.Response(jsonEncode(fixture.jwks), 200);
            }
            return http.Response(
              jsonEncode({
                'access_token': 'access',
                'refresh_token': 'refresh',
                'id_token': fixture.token(
                  attempt.nonce,
                  overrides: {change.key: change.value},
                ),
                'token_type': 'Bearer',
                'expires_in': 3600,
                'scope': 'chatgpt.tokens.use.direct',
              }),
              200,
            );
          }),
        );
        attempt = auth.begin(
          hostId: account().hostId,
          appName: 'Last Answer',
          redirectUri: redirect,
        );
        await expectLater(
          auth.complete(
            attempt,
            redirect.replace(
              queryParameters: {
                'code': 'code',
                'state': attempt.state,
                'client_id': 'oaiapp_test',
              },
            ),
          ),
          throwsA(authError),
        );
        expect(store.writes, 0);
      },
    );
  }

  test(
    'validated identity persists; identity-only consent does not authorize inference',
    () async {
      final store = MemoryCredentials();
      late ChatGptAuthorizationAttempt attempt;
      final auth = ChatGptAuth(
        store: store,
        client: MockClient((request) async {
          if (request.url.path.endsWith('openid-configuration')) {
            return http.Response(
              jsonEncode({
                'issuer': 'https://auth.openai.com',
                'jwks_uri': 'https://auth.openai.com/jwks',
                'revocation_endpoint': 'https://auth.openai.com/revoke',
              }),
              200,
            );
          }
          if (request.url.path == '/revoke') {
            return http.Response('', 200);
          }
          if (request.url.path == '/jwks') {
            return http.Response(jsonEncode(fixture.jwks), 200);
          }
          expect(request.bodyFields['client_id'], 'oaiapp_test');
          expect(request.bodyFields['redirect_uri'], redirect.toString());
          expect(request.bodyFields.containsKey('client_secret'), false);
          return http.Response(
            jsonEncode({
              'access_token': 'access',
              'refresh_token': 'refresh',
              'id_token': fixture.token(attempt.nonce),
              'token_type': 'Bearer',
              'expires_in': 3600,
              'scope': 'openid profile email',
            }),
            200,
          );
        }),
      );
      attempt = auth.begin(
        hostId: account().hostId,
        appName: 'Last Answer',
        redirectUri: redirect,
      );
      final callback = redirect.replace(
        queryParameters: {
          'code': 'code',
          'state': attempt.state,
          'client_id': 'oaiapp_test',
        },
      );
      final signedIn = await auth.complete(attempt, callback);
      expect(signedIn.subject, 'subject');
      expect(signedIn.planEnabled, false);
      await expectLater(
        auth.accountForInference('oaiapp_test'),
        throwsA(authError),
      );
      await expectLater(auth.complete(attempt, callback), throwsA(authError));
      expect(store.writes, 1);
    },
  );

  test(
    'wrong state, duplicate parameters and account replacement never exchange a code',
    () async {
      var calls = 0;
      final auth = ChatGptAuth(
        store: MemoryCredentials(),
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      final attempt = auth.begin(
        hostId: account().hostId,
        appName: 'Last Answer',
        redirectUri: redirect,
        account: account(),
      );
      await expectLater(
        auth.complete(
          attempt,
          redirect.replace(query: 'state=wrong&code=secret'),
        ),
        throwsA(authError),
      );
      await expectLater(
        auth.complete(
          attempt,
          redirect.replace(
            query: 'state=${attempt.state}&state=${attempt.state}&code=secret',
          ),
        ),
        throwsA(authError),
      );
      await expectLater(
        auth.complete(
          attempt,
          redirect.replace(
            queryParameters: {
              'state': attempt.state,
              'code': 'secret',
              'client_id': 'other',
            },
          ),
        ),
        throwsA(authError),
      );
      expect(calls, 0);
    },
  );

  test('simultaneous refreshes rotate and persist exactly once', () async {
    final store = MemoryCredentials();
    await store.write(account(expiresAt: DateTime.utc(2020)));
    final entered = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    final auth = ChatGptAuth(
      store: store,
      client: MockClient((request) async {
        calls++;
        entered.complete();
        await release.future;
        expect(request.bodyFields['grant_type'], 'refresh_token');
        expect(request.bodyFields.containsKey('scope'), false);
        return http.Response(
          jsonEncode({
            'access_token': 'rotated-access',
            'refresh_token': 'rotated-refresh',
            'token_type': 'Bearer',
            'expires_in': 3600,
          }),
          200,
        );
      }),
    );
    final a = auth.accountForInference('oaiapp_test');
    await entered.future;
    final b = auth.accountForInference('oaiapp_test');
    release.complete();
    final results = await Future.wait([a, b]);
    expect(calls, 1);
    expect(store.writes, 2);
    expect(results.every((a) => a.refreshToken == 'rotated-refresh'), true);
  });

  test(
    'sign out clears local tokens while exposing unconfirmed remote revocation',
    () async {
      final store = MemoryCredentials();
      await store.write(account());
      final auth = ChatGptAuth(
        store: store,
        client: MockClient((_) async => http.Response('sensitive', 503)),
      );
      expect(await auth.signOut('oaiapp_test'), false);
      expect(await store.read('oaiapp_test'), isNull);
    },
  );
}
