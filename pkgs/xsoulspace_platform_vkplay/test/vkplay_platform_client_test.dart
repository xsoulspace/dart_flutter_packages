import 'package:test/test.dart';
import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';
import 'package:xsoulspace_platform_social_interface/xsoulspace_platform_social_interface.dart';
import 'package:xsoulspace_platform_vkplay/xsoulspace_platform_vkplay.dart';
import 'package:xsoulspace_vkplay_js/xsoulspace_vkplay_js.dart';

void main() {
  test('returns notAvailable when SDK init is unsupported', () async {
    final client = VkPlayPlatformClient(
      config: const VkPlayPlatformConfig(sdkInjected: true),
      initClient:
          ({
            final String? appId,
            final String expectedGlobal = 'iframeApi',
          }) async {
            throw UnsupportedError('web only');
          },
    );

    final result = await client.init(const PlatformInitOptions());
    expect(result.isNotAvailable, isTrue);
  });

  test('registers identity/friends/raw and maps values', () async {
    final sdk = _FakeVkPlayClient();
    final client = VkPlayPlatformClient(
      config: const VkPlayPlatformConfig(sdkInjected: true),
      initClient:
          ({
            final String? appId,
            final String expectedGlobal = 'iframeApi',
          }) async => sdk,
    );

    final init = await client.init(const PlatformInitOptions());
    expect(init.isSuccess, isTrue);

    final identity = client.require<IdentityCapability>();
    final player = await identity.currentPlayer();

    expect(player, isNotNull);
    expect(player!.id, 'user-1');
    expect(player.displayName, 'Player One');

    final friends = await client.require<FriendsCapability>().listFriends();
    expect(friends, hasLength(3));
    expect(friends.first.id, 'f-1');

    final raw = client.require<VkPlayRawCapability>();
    final rawResult = await raw.callRaw(
      'customMethod',
      params: <String, Object?>{'value': 9},
    );
    expect(rawResult, equals(10));
  });

  test(
    'friends pagination applies offset only once after merge/dedupe',
    () async {
      final sdk = _FakeVkPlayClient();
      final client = VkPlayPlatformClient(
        config: const VkPlayPlatformConfig(sdkInjected: true),
        initClient:
            ({
              final String? appId,
              final String expectedGlobal = 'iframeApi',
            }) async => sdk,
      );

      await client.init(const PlatformInitOptions());

      final friends = await client.require<FriendsCapability>().listFriends(
        limit: 1,
        offset: 1,
      );
      expect(friends, hasLength(1));
      expect(friends.first.id, 'f-2');
    },
  );

  test('invite/share capabilities delegate to backend gateway', () async {
    final gateway = _FakeGateway();
    final client = VkPlayPlatformClient(
      config: VkPlayPlatformConfig(sdkInjected: true, socialGateway: gateway),
      initClient:
          ({
            final String? appId,
            final String expectedGlobal = 'iframeApi',
          }) async => _FakeVkPlayClient(),
    );

    final init = await client.init(const PlatformInitOptions());
    expect(init.isSuccess, isTrue);

    final inviteResult = await client.require<InviteCapability>().invite(
      const InviteRequest(message: 'join'),
    );
    expect(inviteResult.sent, isTrue);
    expect(gateway.lastInvite?.message, 'join');

    final shareResult = await client.require<FeedShareCapability>().shareToFeed(
      const FeedShareRequest(message: 'share'),
    );
    expect(shareResult.shared, isTrue);
    expect(gateway.lastFeedShare?.message, 'share');
  });

  test('invite/share are absent without gateway', () async {
    final client = VkPlayPlatformClient(
      config: const VkPlayPlatformConfig(sdkInjected: true),
      initClient:
          ({
            final String? appId,
            final String expectedGlobal = 'iframeApi',
          }) async => _FakeVkPlayClient(),
    );

    final init = await client.init(const PlatformInitOptions());
    expect(init.isSuccess, isTrue);

    expect(client.maybe<InviteCapability>(), isNull);
    expect(client.maybe<FeedShareCapability>(), isNull);
  });

  test('dispose is idempotent', () async {
    final client = VkPlayPlatformClient(
      config: const VkPlayPlatformConfig(sdkInjected: true),
      initClient:
          ({
            final String? appId,
            final String expectedGlobal = 'iframeApi',
          }) async => _FakeVkPlayClient(),
    );
    await client.init(const PlatformInitOptions());

    await client.dispose();
    await client.dispose();
  });
}

final class _FakeVkPlayClient extends VkPlayClient {
  _FakeVkPlayClient();

  @override
  Future<void> init({final String? appId}) async {}

  @override
  Future<VkPlayLoginStatus> getLoginStatus() async {
    return const VkPlayLoginStatus(authorized: true, userId: 'user-1');
  }

  @override
  Future<VkPlayUserInfo?> userInfo() async {
    return const VkPlayUserInfo(
      id: 'user-1',
      displayName: 'Player One',
      avatarUrl: 'https://example.com/u1.png',
    );
  }

  @override
  Future<VkPlayUserProfile?> userProfile() async {
    return const VkPlayUserProfile(
      id: 'user-1',
      displayName: 'Player One',
      avatarUrl: 'https://example.com/u1-profile.png',
    );
  }

  @override
  Future<List<VkPlayFriend>> userFriends({
    final int? limit,
    final int? offset,
  }) async {
    final friends = const <VkPlayFriend>[
      VkPlayFriend(id: 'f-1', displayName: 'Friend 1'),
      VkPlayFriend(id: 'f-2', displayName: 'Friend 2'),
    ];
    return _sliceFriends(friends, limit: limit, offset: offset);
  }

  @override
  Future<List<VkPlayFriend>> userSocialFriends({
    final int? limit,
    final int? offset,
  }) async {
    final friends = const <VkPlayFriend>[
      VkPlayFriend(id: 'f-2', displayName: 'Friend 2 social', isSocial: true),
      VkPlayFriend(id: 'f-3', displayName: 'Friend 3 social', isSocial: true),
    ];
    return _sliceFriends(friends, limit: limit, offset: offset);
  }

  @override
  Future<Object?> callRaw(
    final String methodName, {
    final Map<String, Object?>? params,
  }) async {
    if (methodName == 'customMethod') {
      return ((params?['value'] as int?) ?? 0) + 1;
    }
    return null;
  }

  List<VkPlayFriend> _sliceFriends(
    final List<VkPlayFriend> source, {
    final int? limit,
    final int? offset,
  }) {
    final safeOffset = (offset ?? 0).clamp(0, source.length);
    final start = source.skip(safeOffset);
    if (limit == null) {
      return start.toList(growable: false);
    }
    return start.take(limit.clamp(0, source.length)).toList(growable: false);
  }
}

final class _FakeGateway implements VkPlaySocialGateway {
  InviteRequest? lastInvite;
  FeedShareRequest? lastFeedShare;

  @override
  Future<InviteResult> invite(final InviteRequest request) async {
    lastInvite = request;
    return const InviteResult(sent: true, inviteId: 'invite-1');
  }

  @override
  Future<FeedShareResult> shareToFeed(final FeedShareRequest request) async {
    lastFeedShare = request;
    return const FeedShareResult(shared: true, postId: 'post-1');
  }
}
