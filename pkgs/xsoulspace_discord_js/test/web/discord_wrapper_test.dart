@TestOn('browser')
library;

import 'dart:js_util' as js_util;

import 'package:test/test.dart';
import 'package:xsoulspace_discord_js/src/wrapper/discord_web.dart';

late final _DiscordSdkStub _stub;

void main() {
  setUpAll(() {
    _stub = _DiscordSdkStub()..install();
  });

  setUp(() {
    _stub.reset();
  });

  test('ready + auth/social flows', () async {
    final client = await Discord.init(clientId: 'app-42');

    expect(_stub.readyCalls, 1);

    final authorize = await client.authorize(
      const DiscordAuthorizeRequest(
        clientId: 'app-42',
        scope: <String>['identify', 'relationships.read'],
      ),
    );
    expect(authorize['code'], 'oauth-code-1');

    final auth = await client.authenticate(accessToken: 'token-1');
    expect(auth.accessToken, 'token-1');
    expect(auth.user.id, 'u-1');

    final user = await client.getUser(id: 'u-2');
    expect(user?.displayName, 'User u-2');

    final relationships = await client.getRelationships();
    expect(relationships, hasLength(2));
    expect(relationships.first.user.id, 'f-1');

    final invite = await client.openInviteDialog();
    expect(invite['opened'], true);

    final embedded = await client.inviteUserEmbedded(userId: 'f-1');
    expect(embedded['sent'], true);

    final share = await client.shareLink(message: 'join now');
    expect(share.success, isTrue);

    final moment = await client.openShareMomentDialog(
      mediaUrl: 'https://cdn.discordapp.com/moment.png',
    );
    expect(moment['opened'], true);

    final raw = await client.callRawCommand(
      'shareLink',
      params: <String, Object?>{'message': 'raw'},
    );
    expect(raw, isNotNull);
  });

  test(
    'event subscriptions for current user, relationship and raw hooks',
    () async {
      final client = await Discord.init(clientId: 'app-42');

      DiscordUser? updatedUser;
      DiscordRelationship? updatedRelationship;
      String? rawEventName;

      final currentUserSub = await client.onCurrentUserUpdate((final user) {
        updatedUser = user;
      });

      final relationshipSub = await client.onRelationshipUpdate((final value) {
        updatedRelationship = value;
      });

      final rawSub = await client.onRawEvent('CURRENT_USER_UPDATE', (
        final event,
      ) {
        rawEventName = event.event;
      });

      _stub.emit('CURRENT_USER_UPDATE', <String, Object?>{
        'id': 'u-9',
        'username': 'UpdatedUser',
        'global_name': 'Updated User',
      });
      _stub.emit('RELATIONSHIP_UPDATE', <String, Object?>{
        'type': 1,
        'user': <String, Object?>{'id': 'f-9', 'username': 'Friend 9'},
      });

      await Future<void>.delayed(const Duration(milliseconds: 1));

      expect(updatedUser?.id, 'u-9');
      expect(updatedRelationship?.user.id, 'f-9');
      expect(rawEventName, 'CURRENT_USER_UPDATE');

      await currentUserSub.cancel();
      await relationshipSub.cancel();
      await rawSub.cancel();

      expect(_stub.unsubscribeCalls, 3);
    },
  );
}

final class _DiscordSdkStub {
  int readyCalls = 0;
  int subscribeCalls = 0;
  int unsubscribeCalls = 0;

  final Map<String, List<Object>> _listeners = <String, List<Object>>{};

  void install() {
    final commands = js_util.jsify(<String, Object?>{
      'authorize': js_util.allowInterop((final Object? payload) {
        return js_util.jsify(<String, Object?>{'code': 'oauth-code-1'});
      }),
      'authenticate': js_util.allowInterop((final Object? payload) {
        final data = payload == null
            ? <String, Object?>{}
            : Map<String, Object?>.from(js_util.dartify(payload)! as Map);
        return js_util.jsify(<String, Object?>{
          'access_token': data['access_token'] ?? 'token-default',
          'user': <String, Object?>{
            'id': 'u-1',
            'username': 'DiscordUser',
            'global_name': 'Discord User',
          },
          'scopes': <String>['identify'],
          'application': <String, Object?>{'id': 'app-42'},
        });
      }),
      'getUser': js_util.allowInterop((final Object? payload) {
        final data = Map<String, Object?>.from(
          js_util.dartify(payload)! as Map,
        );
        final id = data['id']?.toString() ?? 'unknown';
        return js_util.jsify(<String, Object?>{
          'id': id,
          'username': 'User $id',
          'global_name': 'User $id',
        });
      }),
      'getRelationships': js_util.allowInterop(([final Object? payload]) {
        return js_util.jsify(<String, Object?>{
          'relationships': <Map<String, Object?>>[
            <String, Object?>{
              'type': 1,
              'user': <String, Object?>{'id': 'f-1', 'username': 'Friend 1'},
            },
            <String, Object?>{
              'type': 1,
              'user': <String, Object?>{'id': 'f-2', 'username': 'Friend 2'},
            },
          ],
        });
      }),
      'openInviteDialog': js_util.allowInterop(([final Object? payload]) {
        return js_util.jsify(<String, Object?>{'opened': true});
      }),
      'inviteUserEmbedded': js_util.allowInterop((final Object? payload) {
        return js_util.jsify(<String, Object?>{'sent': true});
      }),
      'shareLink': js_util.allowInterop((final Object? payload) {
        return js_util.jsify(<String, Object?>{
          'success': true,
          'didCopyLink': true,
          'didSendMessage': true,
        });
      }),
      'openShareMomentDialog': js_util.allowInterop((final Object? payload) {
        return js_util.jsify(<String, Object?>{'opened': true});
      }),
    });

    final sdk = js_util.jsify(<String, Object?>{
      'ready': js_util.allowInterop(() {
        readyCalls += 1;
      }),
      'commands': commands,
      'subscribe': js_util.allowInterop((
        final Object? event,
        final Object listener, [
        final Object? subscribeArgs,
      ]) {
        subscribeCalls += 1;
        final key = event?.toString() ?? '';
        _listeners.putIfAbsent(key, () => <Object>[]).add(listener);
      }),
      'unsubscribe': js_util.allowInterop((
        final Object? event,
        final Object listener, [
        final Object? unsubscribeArgs,
      ]) {
        unsubscribeCalls += 1;
        final key = event?.toString() ?? '';
        _listeners[key]?.remove(listener);
      }),
    });

    js_util.setProperty(js_util.globalThis, 'DiscordSDK', sdk);
  }

  void emit(final String event, final Map<String, Object?> payload) {
    final listeners = _listeners[event];
    if (listeners == null) {
      return;
    }

    final jsPayload = js_util.jsify(payload);
    for (final listener in listeners) {
      js_util.callMethod<Object?>(listener, 'call', <Object?>[null, jsPayload]);
    }
  }

  void reset() {
    readyCalls = 0;
    subscribeCalls = 0;
    unsubscribeCalls = 0;
    _listeners.clear();
  }
}
