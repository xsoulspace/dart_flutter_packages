import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_openai/xsoulspace_inference_openai.dart';
import 'support.dart';

final class GatedStore implements ChatGptCredentialStore {
  GatedStore({this.failRollback = false});
  final bool failRollback;
  final inner = MemoryCredentials();
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<ChatGptAccount?> read(String clientId) => inner.read(clientId);
  @override
  Future<void> removeTokens(String clientId) => inner.removeTokens(clientId);
  @override
  Future<void> write(ChatGptAccount account) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    if (failRollback && inner.writes >= 2) {
      throw StateError('restoration unavailable');
    }
    await inner.write(account);
  }
}

void main() {
  late SigningFixture fixture;
  setUpAll(() {
    fixture = SigningFixture();
  });
  final redirect = Uri.parse('http://127.0.0.1:1455/auth/callback');
  ChatGptAuthorizationAttempt begin(ChatGptAuth auth) => auth.begin(
    hostId: account().hostId,
    appName: 'Last Answer',
    redirectUri: redirect,
    account: account(),
  );
  Uri callback(ChatGptAuthorizationAttempt attempt) => redirect.replace(
    queryParameters: {
      'state': attempt.state,
      'code': 'fixture',
      'client_id': 'oaiapp_test',
    },
  );
  http.Response discovery() => http.Response(
    jsonEncode({
      'issuer': 'https://auth.openai.com',
      'jwks_uri': 'https://auth.openai.com/jwks',
      'revocation_endpoint': 'https://auth.openai.com/revoke',
    }),
    200,
  );
  http.Response token(String nonce, String access) => http.Response(
    jsonEncode({
      'id_token': fixture.token(nonce),
      'access_token': access,
      'refresh_token': '$access-refresh',
      'token_type': 'Bearer',
      'expires_in': 3600,
      'scope': 'chatgpt.tokens.use.direct',
    }),
    200,
  );

  test('signout invalidates a blocked older authorization', () async {
    final store = MemoryCredentials();
    await store.write(account());
    final entered = Completer<void>();
    final release = Completer<void>();
    late ChatGptAuthorizationAttempt attempt;
    final revoked = <String>[];
    final auth = ChatGptAuth(
      store: store,
      client: MockClient((request) async {
        if (request.url.path.endsWith('openid-configuration')) {
          return discovery();
        }
        if (request.url.path == '/revoke') {
          revoked.add(request.bodyFields['token']!);
          return http.Response('', 200);
        }
        if (request.url.path == '/jwks') {
          return http.Response(jsonEncode(fixture.jwks), 200);
        }
        if (request.url.path == '/revoke') return http.Response('', 200);
        entered.complete();
        await release.future;
        return token(attempt.nonce, 'new');
      }),
    );
    attempt = begin(auth);
    final rejected = expectLater(
      auth.complete(attempt, callback(attempt)),
      throwsA(
        isA<ChatGptAuthException>().having(
          (e) => e.code,
          'code',
          'authorization_cancelled',
        ),
      ),
    );
    await entered.future;
    final signout = auth.signOut('oaiapp_test');
    release.complete();
    await rejected;
    expect(await signout, true);
    expect(await store.read('oaiapp_test'), isNull);
    expect(revoked, containsAll(['new-refresh', 'test-refresh']));
    await expectLater(
      auth.accountForInference('oaiapp_test'),
      throwsA(isA<ChatGptAuthException>()),
    );
  });

  test(
    'failed cancellation rollback fences credentials from inference',
    () async {
      final store = GatedStore(failRollback: true);
      await store.inner.write(account());
      late ChatGptAuthorizationAttempt attempt;
      final auth = ChatGptAuth(
        store: store,
        client: MockClient((request) async {
          if (request.url.path.endsWith('openid-configuration')) {
            return discovery();
          }
          if (request.url.path == '/jwks') {
            return http.Response(jsonEncode(fixture.jwks), 200);
          }
          if (request.url.path == '/revoke') return http.Response('', 200);
          return token(attempt.nonce, 'new');
        }),
      );
      attempt = begin(auth);
      final rejected = expectLater(
        auth.complete(attempt, callback(attempt)),
        throwsA(
          isA<ChatGptAuthException>().having(
            (e) => e.code,
            'code',
            'credential_publication_unsettled',
          ),
        ),
      );
      await store.entered.future;
      auth.cancelAuthorization(attempt);
      store.release.complete();
      await rejected;
      expect((await store.read('oaiapp_test'))!.accessToken, 'new');
      await expectLater(
        auth.accountForInference('oaiapp_test'),
        throwsA(
          isA<ChatGptAuthException>().having(
            (e) => e.code,
            'code',
            'credential_publication_unsettled',
          ),
        ),
      );
    },
  );

  test(
    'signout reports failed cleanup of discarded authorization session',
    () async {
      final store = MemoryCredentials();
      await store.write(account());
      final entered = Completer<void>();
      final release = Completer<void>();
      late ChatGptAuthorizationAttempt attempt;
      final auth = ChatGptAuth(
        store: store,
        client: MockClient((request) async {
          if (request.url.path.endsWith('openid-configuration')) {
            return discovery();
          }
          if (request.url.path == '/jwks') {
            return http.Response(jsonEncode(fixture.jwks), 200);
          }
          if (request.url.path == '/revoke') {
            return http.Response(
              '',
              request.bodyFields['token'] == 'new-refresh' ? 503 : 200,
            );
          }
          entered.complete();
          await release.future;
          return token(attempt.nonce, 'new');
        }),
      );
      attempt = begin(auth);
      final rejected = expectLater(
        auth.complete(attempt, callback(attempt)),
        throwsA(
          isA<ChatGptAuthException>().having(
            (e) => e.code,
            'code',
            'authorization_cleanup_unconfirmed',
          ),
        ),
      );
      await entered.future;
      final signout = auth.signOut('oaiapp_test');
      release.complete();
      await rejected;
      expect(await signout, false);
      expect(await store.read('oaiapp_test'), isNull);
    },
  );

  test(
    'cancelled protected-store write settles then restores old credentials',
    () async {
      final store = GatedStore();
      await store.inner.write(account());
      late ChatGptAuthorizationAttempt attempt;
      final auth = ChatGptAuth(
        store: store,
        client: MockClient((request) async {
          if (request.url.path.endsWith('openid-configuration')) {
            return discovery();
          }
          if (request.url.path == '/revoke') {
            return http.Response('', 200);
          }
          if (request.url.path == '/jwks') {
            return http.Response(jsonEncode(fixture.jwks), 200);
          }
          return token(attempt.nonce, 'new');
        }),
      );
      attempt = begin(auth);
      final rejected = expectLater(
        auth.complete(attempt, callback(attempt)),
        throwsA(isA<ChatGptAuthException>()),
      );
      await store.entered.future;
      auth.cancelAuthorization(attempt);
      store.release.complete();
      await rejected;
      await auth.settleAuthorization(attempt);
      expect((await store.read('oaiapp_test'))!.accessToken, 'test-access');
    },
  );

  for (final first in ['refresh', 'authorization']) {
    test(
      '$first and concurrent reauthorization share one mutation lane',
      () async {
        final store = MemoryCredentials();
        await store.write(account());
        final entered = Completer<void>();
        final release = Completer<void>();
        var exchanges = 0;
        final refreshInputs = <String>[];
        late ChatGptAuthorizationAttempt attempt;
        final auth = ChatGptAuth(
          store: store,
          client: MockClient((request) async {
            if (request.url.path.endsWith('openid-configuration')) {
              return discovery();
            }
            if (request.url.path == '/revoke') {
              return http.Response('', 200);
            }
            if (request.url.path == '/jwks') {
              return http.Response(jsonEncode(fixture.jwks), 200);
            }
            final kind = request.bodyFields['grant_type'];
            if (++exchanges == 1) {
              entered.complete();
              await release.future;
            }
            if (kind == 'refresh_token') {
              refreshInputs.add(request.bodyFields['refresh_token']!);
              return http.Response(
                jsonEncode({
                  'access_token': 'rotated',
                  'refresh_token': 'rotated-refresh',
                  'token_type': 'Bearer',
                  'expires_in': 3600,
                }),
                200,
              );
            }
            return token(attempt.nonce, 'authorized');
          }),
        );
        attempt = begin(auth);
        final a = first == 'refresh'
            ? auth.refresh('oaiapp_test')
            : auth.complete(attempt, callback(attempt));
        await entered.future;
        final b = first == 'refresh'
            ? auth.complete(attempt, callback(attempt))
            : auth.refresh('oaiapp_test');
        expect(exchanges, 1);
        release.complete();
        await Future.wait([a, b]);
        expect(
          (await store.read('oaiapp_test'))!.accessToken,
          first == 'refresh' ? 'authorized' : 'rotated',
        );
        expect(
          refreshInputs.single,
          first == 'refresh' ? 'test-refresh' : 'authorized-refresh',
        );
      },
    );
  }

  test('invalid loopback setup closes its socket', () async {
    final listener = await ChatGptLoopback.bind();
    final auth = ChatGptAuth(store: MemoryCredentials());
    addTearDown(auth.close);
    await expectLater(
      listener.authorize(
        auth: auth,
        hostId: 'invalid',
        appName: 'Last Answer',
        openBrowser: (_) async {},
      ),
      throwsA(isA<ChatGptAuthException>()),
    );
    final browser = http.Client();
    addTearDown(browser.close);
    await expectLater(
      browser.get(listener.redirectUri),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'external listener close cancels an authorization waiting for browser',
    () async {
      final listener = await ChatGptLoopback.bind();
      final auth = ChatGptAuth(store: MemoryCredentials());
      addTearDown(auth.close);
      final opened = Completer<void>();
      final rejected = expectLater(
        listener.authorize(
          auth: auth,
          hostId: account().hostId,
          appName: 'Last Answer',
          openBrowser: (_) async {
            opened.complete();
          },
        ),
        throwsA(
          isA<ChatGptAuthException>().having(
            (e) => e.code,
            'code',
            'authorization_cancelled',
          ),
        ),
      );
      await opened.future;
      await listener.close();
      await rejected;
    },
  );
}
