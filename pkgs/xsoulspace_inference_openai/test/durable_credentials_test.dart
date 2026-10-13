import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_openai/xsoulspace_inference_openai.dart';

import 'support.dart';

final class FencedCredentials implements RecoverableChatGptCredentialStore {
  ChatGptAccount? value = account();
  bool pending = false;
  bool failFinish = false;
  bool cleanupUnconfirmed = false;
  bool cancelled = false;
  Future<void> Function()? beforeFinish;
  @override
  Future<ChatGptAccount?> read(String clientId) async {
    if (pending) {
      throw const ChatGptAuthException('credential_recovery_required');
    }
    return value;
  }

  @override
  Future<ChatGptCredentialMutation> beginMutation(String clientId) async {
    final previousPending = pending;
    if (previousPending) cleanupUnconfirmed = true;
    pending = true;
    cancelled = false;
    return ChatGptCredentialMutation(
      previous: value,
      wasUnsettled: previousPending,
      hasUnconfirmedCleanup: cleanupUnconfirmed,
    );
  }

  @override
  Future<void> cancelMutation(String clientId) async {
    pending = true;
    cancelled = true;
  }

  @override
  Future<void> finishMutation(
    String clientId, {
    bool cleanupConfirmed = true,
    bool rollback = false,
  }) async {
    if (failFinish) throw StateError('protected store unavailable');
    await beforeFinish?.call();
    if (cancelled && !rollback) {
      throw const ChatGptAuthException('credential_mutation_cancelled');
    }
    pending = false;
    cancelled = false;
    if (!cleanupConfirmed) cleanupUnconfirmed = true;
  }

  @override
  Future<void> write(ChatGptAccount account) async => value = account;
  @override
  Future<void> removeTokens(String clientId) async => value = null;
}

void main() {
  test(
    'failed reauthorization cannot unfreeze abandoned credentials',
    () async {
      final store = FencedCredentials()..pending = true;
      final fixture = SigningFixture();
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
          if (request.url.path == '/jwks') {
            return http.Response(jsonEncode(fixture.jwks), 200);
          }
          if (request.url.path == '/revoke') return http.Response('', 200);
          return http.Response(
            jsonEncode({
              'access_token': 'recovery-access',
              'refresh_token': 'recovery-refresh',
              'id_token': fixture.token('wrong-nonce'),
              'token_type': 'Bearer',
              'expires_in': 3600,
              'scope': 'chatgpt.tokens.use.direct',
            }),
            200,
          );
        }),
      );
      addTearDown(auth.close);
      final attempt = auth.begin(
        hostId: account().hostId,
        appName: 'Last Answer',
        account: account(),
        redirectUri: Uri.parse('http://127.0.0.1:1455/auth/callback'),
      );
      await expectLater(
        auth.complete(
          attempt,
          attempt.redirectUri.replace(
            queryParameters: {'code': 'code', 'state': attempt.state},
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
      final restarted = ChatGptAuth(store: store);
      addTearDown(restarted.close);
      await expectLater(
        restarted.accountForInference('oaiapp_test'),
        throwsA(
          isA<ChatGptAuthException>().having(
            (e) => e.code,
            'code',
            'credential_recovery_required',
          ),
        ),
      );
      expect(store.value!.accessToken, 'test-access');
      expect(store.pending, true);
    },
  );

  for (final stage in ['validation', 'commit']) {
    test(
      'acknowledged cancellation during $stage preserves prior healthy credentials',
      () async {
        final store = FencedCredentials();
        final entered = Completer<void>();
        final gate = Completer<void>();
        var finishes = 0;
        store.beforeFinish = () async {
          if (++finishes == 1 && stage == 'commit') {
            entered.complete();
            await gate.future;
          }
        };
        final fixture = SigningFixture();
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
            if (request.url.path == '/jwks') {
              if (stage == 'validation') {
                entered.complete();
                await gate.future;
              }
              return http.Response(jsonEncode(fixture.jwks), 200);
            }
            if (request.url.path == '/revoke') {
              expect(store.pending, true);
              return http.Response('', 200);
            }
            return http.Response(
              jsonEncode({
                'access_token': 'acquired-access',
                'refresh_token': 'acquired-refresh',
                'id_token': fixture.token(attempt.nonce),
                'token_type': 'Bearer',
                'expires_in': 3600,
                'scope': 'chatgpt.tokens.use.direct',
              }),
              200,
            );
          }),
        );
        addTearDown(auth.close);
        attempt = auth.begin(
          hostId: account().hostId,
          appName: 'Last Answer',
          account: account(),
          redirectUri: Uri.parse('http://127.0.0.1:1455/auth/callback'),
        );
        final pending = auth.complete(
          attempt,
          attempt.redirectUri.replace(
            queryParameters: {'code': 'code', 'state': attempt.state},
          ),
        );
        final failure = expectLater(
          pending,
          throwsA(
            isA<ChatGptAuthException>().having(
              (e) => e.code,
              'code',
              'authorization_cancelled',
            ),
          ),
        );
        await entered.future;
        await auth.cancelAuthorization(attempt);
        gate.complete();
        await failure;
        expect(store.pending, false);
        expect((await store.read('oaiapp_test'))!.accessToken, 'test-access');
        expect(store.cleanupUnconfirmed, false);
      },
    );
  }

  test(
    'refresh fences before remote rotation and commits after publication',
    () async {
      final store = FencedCredentials();
      final auth = ChatGptAuth(
        store: store,
        client: MockClient((request) async {
          expect(store.pending, true);
          return http.Response(
            jsonEncode({
              'access_token': 'rotated-access',
              'refresh_token': 'rotated-refresh',
              'token_type': 'Bearer',
              'expires_in': 3600,
              'scope': 'chatgpt.tokens.use.direct',
            }),
            200,
          );
        }),
      );
      addTearDown(auth.close);
      expect((await auth.refresh('oaiapp_test')).accessToken, 'rotated-access');
      expect(store.pending, false);
    },
  );

  test(
    'failed durable commit remains unavailable to a new auth owner',
    () async {
      final store = FencedCredentials()..failFinish = true;
      final transport = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'access_token': 'rotated-access',
            'refresh_token': 'rotated-refresh',
            'token_type': 'Bearer',
            'expires_in': 3600,
            'scope': 'chatgpt.tokens.use.direct',
          }),
          200,
        ),
      );
      final auth = ChatGptAuth(store: store, client: transport);
      addTearDown(auth.close);
      await expectLater(auth.refresh('oaiapp_test'), throwsStateError);
      expect(store.pending, true);
      final restarted = ChatGptAuth(store: store);
      addTearDown(restarted.close);
      await expectLater(
        restarted.accountForInference('oaiapp_test'),
        throwsA(
          isA<ChatGptAuthException>().having(
            (e) => e.code,
            'code',
            'credential_recovery_required',
          ),
        ),
      );
    },
  );

  test(
    'recovery signout clears local authority but retains remote uncertainty',
    () async {
      final store = FencedCredentials()..pending = true;
      final auth = ChatGptAuth(
        store: store,
        client: MockClient((request) async {
          if (request.url.path.endsWith('openid-configuration')) {
            return http.Response(
              jsonEncode({
                'revocation_endpoint': 'https://auth.openai.com/revoke',
              }),
              200,
            );
          }
          return http.Response('', 200);
        }),
      );
      addTearDown(auth.close);
      expect(await auth.signOut('oaiapp_test'), false);
      expect(store.pending, false);
      expect(store.value, null);
      expect(store.cleanupUnconfirmed, true);
      final restarted = ChatGptAuth(store: store);
      addTearDown(restarted.close);
      expect(await restarted.signOut('oaiapp_test'), false);
    },
  );
}
