@TestOn('browser')
library;

import 'dart:js_util' as js_util;

import 'package:test/test.dart';
import 'package:xsoulspace_vkplay_js/src/wrapper/vkplay_web.dart';

late final _VkPlaySdkStub _stub;

void main() {
  setUpAll(() {
    _stub = _VkPlaySdkStub()..install();
  });

  setUp(() {
    _stub.reset();
  });

  test('init + identity + friends', () async {
    final client = await VkPlay.init(appId: 'app-42');

    expect(_stub.initCalls, 1);
    expect(_stub.lastInitPayload, containsPair('app_id', 'app-42'));

    final status = await client.getLoginStatus();
    expect(status.authorized, isTrue);
    expect(status.userId, 'u-1');

    final info = await client.userInfo();
    expect(info?.id, 'u-1');
    expect(info?.displayName, 'Player One');

    final profile = await client.userProfile();
    expect(profile?.displayName, 'Player One');

    final friends = await client.userFriends(limit: 2, offset: 1);
    expect(friends, hasLength(2));
    expect(friends.first.id, 'f-2');

    final socialFriends = await client.userSocialFriends(limit: 1);
    expect(socialFriends, hasLength(1));
    expect(socialFriends.first.isSocial, isTrue);
  });

  test('invite/share/raw calls', () async {
    final client = await VkPlay.init();

    final invite = await client.invite(
      const VkPlayInvitePayload(message: 'join', recipientIds: <String>['u2']),
    );
    expect(invite, containsPair('sent', true));

    final share = await client.shareToFeed(
      const VkPlayFeedSharePayload(message: 'check', linkUrl: 'https://x.dev'),
    );
    expect(share, containsPair('shared', true));

    final raw = await client.callRaw(
      'customMethod',
      params: <String, Object?>{'value': 9},
    );
    expect(raw, equals(10));
  });
}

final class _VkPlaySdkStub {
  int initCalls = 0;
  Map<String, Object?>? lastInitPayload;

  void install() {
    final api = js_util.jsify(<String, Object?>{
      'init': js_util.allowInterop((final Object? payload) {
        initCalls += 1;
        if (payload != null) {
          lastInitPayload = Map<String, Object?>.from(
            js_util.dartify(payload)! as Map,
          );
        }
      }),
      'getLoginStatus': js_util.allowInterop(() {
        return js_util.jsify(<String, Object?>{
          'authorized': true,
          'userId': 'u-1',
        });
      }),
      'userInfo': js_util.allowInterop(() {
        return js_util.jsify(<String, Object?>{
          'id': 'u-1',
          'name': 'Player One',
          'avatar': 'https://example.com/u1.png',
        });
      }),
      'userProfile': js_util.allowInterop(() {
        return js_util.jsify(<String, Object?>{
          'id': 'u-1',
          'displayName': 'Player One',
          'avatarUrl': 'https://example.com/u1.png',
        });
      }),
      'userFriends': js_util.allowInterop((final Object? payload) {
        final params = payload == null
            ? <String, Object?>{}
            : Map<String, Object?>.from(js_util.dartify(payload)! as Map);

        final all = <Map<String, Object?>>[
          <String, Object?>{'id': 'f-1', 'name': 'Friend 1'},
          <String, Object?>{'id': 'f-2', 'name': 'Friend 2'},
          <String, Object?>{'id': 'f-3', 'name': 'Friend 3'},
        ];

        final limit = (params['limit'] as int?) ?? all.length;
        final offset = (params['offset'] as int?) ?? 0;
        final end = (offset + limit).clamp(0, all.length);
        final slice = all.sublist(offset.clamp(0, all.length), end);
        return js_util.jsify(slice);
      }),
      'userSocialFriends': js_util.allowInterop((final Object? payload) {
        return js_util.jsify(<Map<String, Object?>>[
          <String, Object?>{'id': 'sf-1', 'name': 'Social Friend 1'},
        ]);
      }),
      'showInviteBox': js_util.allowInterop((final Object? payload) {
        return js_util.jsify(<String, Object?>{'sent': true});
      }),
      'postToFeed': js_util.allowInterop((final Object? payload) {
        return js_util.jsify(<String, Object?>{'shared': true});
      }),
      'customMethod': js_util.allowInterop((final Object? payload) {
        final params = Map<String, Object?>.from(
          js_util.dartify(payload)! as Map,
        );
        return (params['value']! as int) + 1;
      }),
    });

    js_util.setProperty(js_util.globalThis, 'iframeApi', api);
  }

  void reset() {
    initCalls = 0;
    lastInitPayload = null;
  }
}
