import 'dart:async';

import 'package:xsoulspace_crazygames_js/xsoulspace_crazygames_js.dart';
import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';
import 'package:xsoulspace_platform_foundation/xsoulspace_platform_foundation.dart';
import 'package:xsoulspace_platform_gamification_interface/xsoulspace_platform_gamification_interface.dart';
import 'package:xsoulspace_platform_social_interface/xsoulspace_platform_social_interface.dart';

import 'crazygames_platform_config.dart';

final class CrazyGamesPlatformClient implements PlatformClient {
  CrazyGamesPlatformClient({required this.config, required this.initClient});

  final CrazyGamesPlatformConfig config;
  final Future<CrazyGamesClient> Function() initClient;

  final CapabilityRegistry _capabilities = CapabilityRegistry();
  final StreamController<PlatformEvent> _eventsController =
      StreamController<PlatformEvent>.broadcast();

  CrazyGamesClient? _client;
  _CrazyIdentityCapability? _identityCapability;

  @override
  PlatformId get platformId => PlatformId.crazyGames;

  @override
  Future<PlatformInitResult> init(final PlatformInitOptions options) async {
    try {
      _client = await initClient();
    } on UnsupportedError catch (error) {
      return PlatformInitResult.notAvailable(message: error.toString());
    } on Object catch (error) {
      return PlatformInitResult.failure(
        message: 'CrazyGames init failed.',
        error: error,
      );
    }

    final client = _client!;
    _identityCapability = _CrazyIdentityCapability(client);

    final identity = _identityCapability!;
    _capabilities.register<IdentityCapability>(identity);
    _capabilities.registerDynamic(identity.runtimeType, identity);

    final friends = _CrazyFriendsCapability(client);
    _capabilities.register<FriendsCapability>(friends);
    _capabilities.registerDynamic(friends.runtimeType, friends);

    final leaderboardWrite = _CrazyLeaderboardWriteCapability(client);
    _capabilities.register<LeaderboardWriteCapability>(leaderboardWrite);
    _capabilities.registerDynamic(
      leaderboardWrite.runtimeType,
      leaderboardWrite,
    );

    _eventsController.add(PlatformEvent.now(name: 'crazygames.initialized'));
    return PlatformInitResult.success(message: 'CrazyGames initialized.');
  }

  @override
  Future<void> dispose() async {
    await _identityCapability?.dispose();
    _identityCapability = null;
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
}

final class _CrazyIdentityCapability implements IdentityCapability {
  _CrazyIdentityCapability(this._client);

  final CrazyGamesClient _client;

  final StreamController<PlayerIdentity?> _authController =
      StreamController<PlayerIdentity?>.broadcast();

  Object? _authListener;
  var _listenerAttached = false;

  @override
  String get capabilityName => 'identity';

  @override
  Stream<PlayerIdentity?> get authChanges {
    _ensureAuthListener();
    return _authController.stream;
  }

  @override
  Future<PlayerIdentity?> currentPlayer() async {
    final user = await _client.user.getUser();
    if (user == null) {
      return null;
    }
    return _mapUser(user);
  }

  Future<void> dispose() async {
    if (_listenerAttached && _authListener != null) {
      _client.user.removeAuthListener(_authListener!);
    }
    _listenerAttached = false;
    _authListener = null;
    await _authController.close();
  }

  void _ensureAuthListener() {
    if (_listenerAttached) {
      return;
    }
    _authListener = _client.user.addAuthListener((final user) {
      _authController.add(user == null ? null : _mapUser(user));
    });
    _listenerAttached = true;
  }

  PlayerIdentity _mapUser(final User user) {
    final id = user.id;
    return PlayerIdentity(
      id: (id == null || id.isEmpty) ? 'anonymous' : id,
      displayName: user.username,
      avatarUrl: user.profilePictureUrl.isEmpty ? null : user.profilePictureUrl,
      isAnonymous: id == null || id.isEmpty,
    );
  }
}

final class _CrazyFriendsCapability implements FriendsCapability {
  const _CrazyFriendsCapability(this._client);

  final CrazyGamesClient _client;

  @override
  String get capabilityName => 'friends';

  @override
  Future<List<PlayerFriend>> listFriends({
    final int? limit,
    final int? offset,
  }) async {
    final rawOffset = offset ?? 0;
    final requested = limit ?? 10;
    final fetchSize = (rawOffset + requested).clamp(1, 100);

    final pageData = await _client.user.listFriends(page: 1, size: fetchSize);

    return pageData.friends
        .skip(rawOffset)
        .take(requested)
        .map(
          (final friend) => PlayerFriend(
            id: friend.id,
            displayName: friend.username,
            avatarUrl: friend.profilePictureUrl,
          ),
        )
        .toList(growable: false);
  }
}

final class _CrazyLeaderboardWriteCapability
    implements LeaderboardWriteCapability {
  const _CrazyLeaderboardWriteCapability(this._client);

  final CrazyGamesClient _client;

  @override
  String get capabilityName => 'leaderboard.write';

  @override
  Future<void> submitScore(
    final String leaderboardId,
    final int score, {
    final String? extraData,
  }) async {
    if (extraData != null && extraData.isNotEmpty) {
      _client.user.addScoreEncrypted(score, extraData);
      return;
    }
    _client.user.addScore(score);
  }
}
