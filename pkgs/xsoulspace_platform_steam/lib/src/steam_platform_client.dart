import 'dart:async';

import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';
import 'package:xsoulspace_platform_foundation/xsoulspace_platform_foundation.dart';
import 'package:xsoulspace_platform_gamification_interface/xsoulspace_platform_gamification_interface.dart';
import 'package:xsoulspace_platform_social_interface/xsoulspace_platform_social_interface.dart';
import 'package:xsoulspace_steamworks/xsoulspace_steamworks.dart';

import 'steam_platform_config.dart';

final class SteamPlatformClient implements PlatformClient {
  SteamPlatformClient({
    required this.config,
    required final SteamClient steamClient,
  }) : _steamClient = steamClient;

  final SteamPlatformConfig config;
  final SteamClient _steamClient;

  final CapabilityRegistry _capabilities = CapabilityRegistry();
  final StreamController<PlatformEvent> _eventsController =
      StreamController<PlatformEvent>.broadcast();

  StreamSubscription<SteamEvent>? _steamEventsSubscription;
  var _disposed = false;

  @override
  PlatformId get platformId => PlatformId.steam;

  @override
  Future<PlatformInitResult> init(final PlatformInitOptions options) async {
    if (_steamEventsSubscription == null) {
      _steamEventsSubscription = _steamClient.events.listen(_onSteamEvent);
    }

    final configOverride = options.read<SteamPlatformConfig>('steam.config');
    final effectiveConfig = configOverride ?? config;

    try {
      final result = await _steamClient.initialize(
        effectiveConfig.toSteamInitConfig(),
      );
      if (!result.success) {
        if (result.errorCode == SteamInitErrorCode.restartRequired) {
          return PlatformInitResult.notAvailable(
            message: result.message ?? 'Steam restart required.',
          );
        }
        return PlatformInitResult.failure(
          message: result.message ?? 'Steam init failed.',
          error: result.errorCode,
        );
      }

      _registerCapabilities();
      _emit(
        PlatformEvent.now(
          name: 'steam.initialized',
          payload: <String, Object?>{'appId': effectiveConfig.appId},
        ),
      );
      return PlatformInitResult.success(message: 'Steam initialized.');
    } on UnsupportedError catch (error) {
      return PlatformInitResult.notAvailable(message: error.toString());
    } on Object catch (error) {
      return PlatformInitResult.failure(
        message: 'Steam adapter failed to initialize.',
        error: error,
      );
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _steamEventsSubscription?.cancel();
    _steamEventsSubscription = null;
    await _steamClient.shutdown();
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

  void _registerCapabilities() {
    final identity = _SteamIdentityCapability(_steamClient);
    _capabilities.register<IdentityCapability>(identity);
    _capabilities.registerDynamic(identity.runtimeType, identity);

    final friends = _SteamFriendsCapability(_steamClient);
    _capabilities.register<FriendsCapability>(friends);
    _capabilities.registerDynamic(friends.runtimeType, friends);

    final achievementRead = _SteamAchievementReadCapability(_steamClient);
    _capabilities.register<AchievementReadCapability>(achievementRead);
    _capabilities.registerDynamic(achievementRead.runtimeType, achievementRead);

    final achievementWrite = _SteamAchievementWriteCapability(_steamClient);
    _capabilities.register<AchievementWriteCapability>(achievementWrite);
    _capabilities.registerDynamic(
      achievementWrite.runtimeType,
      achievementWrite,
    );

    final statsRead = _SteamStatsReadCapability(_steamClient);
    _capabilities.register<StatsReadCapability>(statsRead);
    _capabilities.registerDynamic(statsRead.runtimeType, statsRead);

    final statsWrite = _SteamStatsWriteCapability(_steamClient);
    _capabilities.register<StatsWriteCapability>(statsWrite);
    _capabilities.registerDynamic(statsWrite.runtimeType, statsWrite);

    final statsSync = _SteamStatsSyncCapability(_steamClient);
    _capabilities.register<StatsSyncCapability>(statsSync);
    _capabilities.registerDynamic(statsSync.runtimeType, statsSync);
  }

  void _onSteamEvent(final SteamEvent event) {
    if (_disposed || _eventsController.isClosed) {
      return;
    }

    switch (event) {
      case final SteamLifecycleEvent lifecycle:
        _emit(
          PlatformEvent(
            name: 'steam.lifecycle.${lifecycle.state.name}',
            timestamp: lifecycle.timestamp,
          ),
        );
      case final SteamCallbackEvent callback:
        _emit(
          PlatformEvent(
            name: 'steam.callback',
            timestamp: callback.timestamp,
            payload: <String, Object?>{
              'callbackId': callback.callbackId,
              'payloadSize': callback.payloadSize,
            },
          ),
        );
      case final SteamAsyncCallResolvedEvent resolved:
        _emit(
          PlatformEvent(
            name: 'steam.async.resolved',
            timestamp: resolved.timestamp,
            payload: <String, Object?>{
              'apiCallHandle': resolved.apiCallHandle,
              'callbackId': resolved.callbackId,
              'failed': resolved.failed,
            },
          ),
        );
      case final SteamAsyncCallTimeoutEvent timeout:
        _emit(
          PlatformEvent(
            name: 'steam.async.timeout',
            timestamp: timeout.timestamp,
            payload: <String, Object?>{
              'apiCallHandle': timeout.apiCallHandle,
              'callbackId': timeout.expectedCallbackId,
              'timeoutMs': timeout.timeout.inMilliseconds,
            },
          ),
        );
      case final SteamErrorEvent error:
        _emit(
          PlatformEvent(
            name: 'steam.error',
            timestamp: error.timestamp,
            payload: <String, Object?>{'message': error.message},
          ),
        );
    }
  }

  void _emit(final PlatformEvent event) {
    if (_disposed || _eventsController.isClosed) {
      return;
    }
    _eventsController.add(event);
  }
}

final class _SteamIdentityCapability implements IdentityCapability {
  const _SteamIdentityCapability(this._client);

  final SteamClient _client;

  @override
  String get capabilityName => 'identity';

  @override
  Stream<PlayerIdentity?> get authChanges =>
      const Stream<PlayerIdentity?>.empty();

  @override
  Future<PlayerIdentity?> currentPlayer() async {
    if (!_client.user.isLoggedOn) {
      return null;
    }

    return PlayerIdentity(
      id: _client.user.steamId.toString(),
      displayName: _client.friends.personaName,
      metadata: <String, Object?>{'steamId': _client.user.steamId},
    );
  }
}

final class _SteamFriendsCapability implements FriendsCapability {
  const _SteamFriendsCapability(this._client);

  final SteamClient _client;

  @override
  String get capabilityName => 'friends';

  @override
  Future<List<PlayerFriend>> listFriends({
    final int? limit,
    final int? offset,
  }) async {
    final ids = _client.friends.getFriendSteamIds();
    final safeOffset = (offset ?? 0).clamp(0, ids.length);
    final sliced = ids.skip(safeOffset).toList(growable: false);
    final limited = limit == null
        ? sliced
        : sliced.take(limit.clamp(0, sliced.length)).toList(growable: false);

    return limited
        .map(
          (final id) => PlayerFriend(
            id: id.toString(),
            displayName: _client.friends.getFriendPersonaName(id),
          ),
        )
        .toList(growable: false);
  }
}

final class _SteamAchievementReadCapability
    implements AchievementReadCapability {
  const _SteamAchievementReadCapability(this._client);

  final SteamClient _client;

  @override
  String get capabilityName => 'achievement.read';

  @override
  Future<AchievementState?> getAchievement(final String id) async {
    final value = _client.achievements.getAchievement(id);
    if (value == null) {
      return null;
    }
    return AchievementState(id: id, unlocked: value);
  }
}

final class _SteamAchievementWriteCapability
    implements AchievementWriteCapability {
  const _SteamAchievementWriteCapability(this._client);

  final SteamClient _client;

  @override
  String get capabilityName => 'achievement.write';

  @override
  Future<void> unlockAchievement(final String id) async {
    final ok = _client.achievements.setAchievement(id);
    if (!ok) {
      throw PlatformException(
        code: PlatformExceptionCode.internal,
        message: 'Failed to unlock Steam achievement: $id',
        platformId: PlatformId.steam,
      );
    }
  }

  @override
  Future<void> clearAchievement(final String id) async {
    final ok = _client.achievements.clearAchievement(id);
    if (!ok) {
      throw PlatformException(
        code: PlatformExceptionCode.internal,
        message: 'Failed to clear Steam achievement: $id',
        platformId: PlatformId.steam,
      );
    }
  }
}

final class _SteamStatsReadCapability implements StatsReadCapability {
  const _SteamStatsReadCapability(this._client);

  final SteamClient _client;

  @override
  String get capabilityName => 'stats.read';

  @override
  Future<int?> getIntStat(final String name) async =>
      _client.stats.getIntStat(name);

  @override
  Future<double?> getDoubleStat(final String name) async =>
      _client.stats.getFloatStat(name);
}

final class _SteamStatsWriteCapability implements StatsWriteCapability {
  const _SteamStatsWriteCapability(this._client);

  final SteamClient _client;

  @override
  String get capabilityName => 'stats.write';

  @override
  Future<void> setIntStat(final String name, final int value) async {
    final ok = _client.stats.setIntStat(name, value);
    if (!ok) {
      throw PlatformException(
        code: PlatformExceptionCode.internal,
        message: 'Failed to set Steam int stat: $name',
        platformId: PlatformId.steam,
      );
    }
  }

  @override
  Future<void> setDoubleStat(final String name, final double value) async {
    final ok = _client.stats.setFloatStat(name, value);
    if (!ok) {
      throw PlatformException(
        code: PlatformExceptionCode.internal,
        message: 'Failed to set Steam float stat: $name',
        platformId: PlatformId.steam,
      );
    }
  }
}

final class _SteamStatsSyncCapability implements StatsSyncCapability {
  const _SteamStatsSyncCapability(this._client);

  final SteamClient _client;

  @override
  String get capabilityName => 'stats.sync';

  @override
  Future<void> requestCurrentStats() async {
    final ok = await _client.stats.requestCurrentStats();
    if (!ok) {
      throw const PlatformException(
        code: PlatformExceptionCode.internal,
        message: 'Failed to request current Steam stats.',
        platformId: PlatformId.steam,
      );
    }
  }

  @override
  Future<void> flushStats() async {
    final ok = await _client.stats.storeStats();
    if (!ok) {
      throw const PlatformException(
        code: PlatformExceptionCode.internal,
        message: 'Failed to flush Steam stats.',
        platformId: PlatformId.steam,
      );
    }
  }
}
