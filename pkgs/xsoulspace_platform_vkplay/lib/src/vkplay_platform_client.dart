import 'dart:async';

import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';
import 'package:xsoulspace_platform_foundation/xsoulspace_platform_foundation.dart';
import 'package:xsoulspace_platform_social_interface/xsoulspace_platform_social_interface.dart';
import 'package:xsoulspace_vkplay_js/xsoulspace_vkplay_js.dart';

import 'vkplay_platform_config.dart';
import 'vkplay_raw_capability.dart';
import 'vkplay_social_gateway.dart';

typedef VkPlayClientInitializer =
    Future<VkPlayClient> Function({String? appId, String expectedGlobal});

final class VkPlayPlatformClient implements PlatformClient {
  VkPlayPlatformClient({required this.config, required this.initClient});

  final VkPlayPlatformConfig config;
  final VkPlayClientInitializer initClient;

  final CapabilityRegistry _capabilities = CapabilityRegistry();
  final StreamController<PlatformEvent> _eventsController =
      StreamController<PlatformEvent>.broadcast();

  VkPlayClient? _sdkClient;

  @override
  PlatformId get platformId => PlatformId.vkPlay;

  @override
  Future<PlatformInitResult> init(final PlatformInitOptions options) async {
    final bool sdkReady;
    try {
      sdkReady = await _ensureSdkReady();
    } on Object catch (error) {
      return PlatformInitResult.failure(
        message: 'VK Play SDK loader failed.',
        error: error,
      );
    }
    if (!sdkReady) {
      return PlatformInitResult.notAvailable(
        message:
            'VK Play SDK global `${config.expectedSdkGlobal}` was not detected.',
      );
    }

    try {
      _sdkClient = await initClient(
        appId: config.appId,
        expectedGlobal: config.expectedSdkGlobal,
      );
    } on UnsupportedError catch (error) {
      return PlatformInitResult.notAvailable(message: error.toString());
    } on StateError catch (error) {
      return PlatformInitResult.notAvailable(message: error.message);
    } on Object catch (error) {
      return PlatformInitResult.failure(
        message: 'VK Play init failed.',
        error: error,
      );
    }

    final sdk = _sdkClient!;

    final identity = _VkPlayIdentityCapability(sdk);
    _capabilities.register<IdentityCapability>(identity);
    _capabilities.registerDynamic(identity.runtimeType, identity);

    final friends = _VkPlayFriendsCapability(sdk);
    _capabilities.register<FriendsCapability>(friends);
    _capabilities.registerDynamic(friends.runtimeType, friends);

    final gateway = config.socialGateway;
    if (gateway != null && config.enableInviteCapability) {
      final invite = _VkPlayInviteCapability(gateway);
      _capabilities.register<InviteCapability>(invite);
      _capabilities.registerDynamic(invite.runtimeType, invite);
    }
    if (gateway != null && config.enableFeedShareCapability) {
      final feedShare = _VkPlayFeedShareCapability(gateway);
      _capabilities.register<FeedShareCapability>(feedShare);
      _capabilities.registerDynamic(feedShare.runtimeType, feedShare);
    }

    if (config.enableRawCapability) {
      final raw = _VkPlayRawCapability(sdk);
      _capabilities.register<VkPlayRawCapability>(raw);
      _capabilities.registerDynamic(raw.runtimeType, raw);
    }

    _eventsController.add(
      PlatformEvent.now(
        name: 'vkplay.initialized',
        payload: <String, Object?>{
          'expectedSdkGlobal': config.expectedSdkGlobal,
          'capabilities': capabilityTypes
              .map((final type) => type.toString())
              .toList(growable: false),
        },
      ),
    );

    return PlatformInitResult.success(message: 'VK Play initialized.');
  }

  @override
  Future<void> dispose() async {
    await _eventsController.close();
  }

  @override
  bool supports<T extends PlatformCapability>() => _capabilities.supports<T>();

  @override
  T require<T extends PlatformCapability>() {
    final capability = maybe<T>();
    if (capability == null) {
      throw MissingPlatformCapabilityException(
        capabilityType: T,
        supportedCapabilities: capabilityTypes,
        behavior: MissingCapabilityBehavior.strict,
        platformId: platformId,
      );
    }
    return capability;
  }

  @override
  T? maybe<T extends PlatformCapability>() => _capabilities.maybe<T>();

  @override
  Set<Type> get capabilityTypes => _capabilities.types;

  @override
  Stream<PlatformEvent> get events => _eventsController.stream;

  Future<bool> _ensureSdkReady() async {
    final injectedOverride = config.sdkInjected;
    if (injectedOverride != null) {
      return injectedOverride;
    }

    final available = VkPlay.isAvailable(
      expectedGlobal: config.expectedSdkGlobal,
    );
    if (available) {
      return true;
    }

    if (!config.autoLoadSdk) {
      return false;
    }

    final loader = config.sdkScriptLoader;
    final sdkUrl = config.sdkUrl;
    if (loader == null || sdkUrl == null) {
      return false;
    }

    await loader(sdkUrl);
    return VkPlay.isAvailable(expectedGlobal: config.expectedSdkGlobal);
  }
}

final class _VkPlayIdentityCapability implements IdentityCapability {
  const _VkPlayIdentityCapability(this._client);

  final VkPlayClient _client;

  @override
  String get capabilityName => 'identity';

  @override
  Stream<PlayerIdentity?> get authChanges =>
      const Stream<PlayerIdentity?>.empty();

  @override
  Future<PlayerIdentity?> currentPlayer() async {
    final login = await _client.getLoginStatus();
    if (!login.authorized) {
      return null;
    }

    final info = await _client.userInfo();
    final profile = await _client.userProfile();

    final id = _firstNotEmpty(<String?>[
      profile?.id,
      info?.id,
      login.userId,
      'anonymous',
    ])!;

    final displayName = _firstNotEmpty(<String?>[
      profile?.displayName,
      info?.displayName,
      'Guest',
    ])!;

    final avatarUrl = _firstNotEmpty(<String?>[
      profile?.avatarUrl,
      info?.avatarUrl,
    ]);

    return PlayerIdentity(
      id: id,
      displayName: displayName,
      avatarUrl: avatarUrl,
      isAnonymous: id == 'anonymous',
      metadata: <String, Object?>{
        'login': login.metadata,
        if (info != null) 'userInfo': info.metadata,
        if (profile != null) 'userProfile': profile.metadata,
      },
    );
  }
}

final class _VkPlayFriendsCapability implements FriendsCapability {
  const _VkPlayFriendsCapability(this._client);

  final VkPlayClient _client;

  @override
  String get capabilityName => 'friends';

  @override
  Future<List<PlayerFriend>> listFriends({
    final int? limit,
    final int? offset,
  }) async {
    final merged = <String, PlayerFriend>{};

    final primary = await _client.userFriends(limit: limit, offset: offset);
    for (final friend in primary) {
      merged[friend.id] = _mapFriend(friend);
    }

    final social = await _client.userSocialFriends(
      limit: limit,
      offset: offset,
    );
    for (final friend in social) {
      merged.putIfAbsent(friend.id, () => _mapFriend(friend));
    }

    final allFriends = merged.values.toList(growable: false);
    final safeOffset = (offset ?? 0).clamp(0, allFriends.length);
    final sliced = allFriends.skip(safeOffset);

    if (limit == null) {
      return sliced.toList(growable: false);
    }

    return sliced
        .take(limit.clamp(0, allFriends.length))
        .toList(growable: false);
  }

  PlayerFriend _mapFriend(final VkPlayFriend friend) {
    return PlayerFriend(
      id: friend.id,
      displayName: friend.displayName,
      avatarUrl: friend.avatarUrl,
    );
  }
}

final class _VkPlayInviteCapability implements InviteCapability {
  const _VkPlayInviteCapability(this._gateway);

  final VkPlaySocialGateway _gateway;

  @override
  String get capabilityName => 'invite';

  @override
  Future<InviteResult> invite(final InviteRequest request) {
    return _gateway.invite(request);
  }
}

final class _VkPlayFeedShareCapability implements FeedShareCapability {
  const _VkPlayFeedShareCapability(this._gateway);

  final VkPlaySocialGateway _gateway;

  @override
  String get capabilityName => 'feed.share';

  @override
  Future<FeedShareResult> shareToFeed(final FeedShareRequest request) {
    return _gateway.shareToFeed(request);
  }
}

final class _VkPlayRawCapability implements VkPlayRawCapability {
  const _VkPlayRawCapability(this.client);

  @override
  final VkPlayClient client;

  @override
  String get capabilityName => 'vkplay.raw';

  @override
  Future<Object?> callRaw(
    final String methodName, {
    final Map<String, Object?>? params,
  }) {
    return client.callRaw(methodName, params: params);
  }
}

String? _firstNotEmpty(final List<String?> values) {
  for (final value in values) {
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}
