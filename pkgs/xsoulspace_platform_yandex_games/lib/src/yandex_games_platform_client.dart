import 'dart:async';

import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';
import 'package:xsoulspace_platform_foundation/xsoulspace_platform_foundation.dart';
import 'package:xsoulspace_platform_gamification_interface/xsoulspace_platform_gamification_interface.dart';
import 'package:xsoulspace_platform_multiplayer_interface/xsoulspace_platform_multiplayer_interface.dart';
import 'package:xsoulspace_platform_social_interface/xsoulspace_platform_social_interface.dart';
import 'package:xsoulspace_ysdk_games_js/xsoulspace_ysdk_games_js.dart';

import 'yandex_games_platform_config.dart';

typedef YandexGamesClientInitializer =
    Future<YsdkClient> Function({bool signed, String expectedGlobal});

final class YandexGamesPlatformClient implements PlatformClient {
  YandexGamesPlatformClient({required this.config, required this.initClient});

  final YandexGamesPlatformConfig config;
  final YandexGamesClientInitializer initClient;

  final CapabilityRegistry _capabilities = CapabilityRegistry();
  final StreamController<PlatformEvent> _eventsController =
      StreamController<PlatformEvent>.broadcast();

  YsdkClient? _sdkClient;
  var _disposed = false;

  @override
  PlatformId get platformId => PlatformId.yandexGames;

  @override
  Future<PlatformInitResult> init(final PlatformInitOptions options) async {
    final bool sdkReady;
    try {
      sdkReady = await _ensureSdkReady();
    } on Object catch (error) {
      return PlatformInitResult.failure(
        message: 'Yandex Games SDK loader failed.',
        error: error,
      );
    }

    if (!sdkReady) {
      return PlatformInitResult.notAvailable(message: _notAvailableMessage());
    }

    try {
      _sdkClient = await initClient(
        signed: config.signed,
        expectedGlobal: config.expectedSdkGlobal,
      );
    } on UnsupportedError catch (error) {
      return PlatformInitResult.notAvailable(message: error.toString());
    } on StateError {
      return PlatformInitResult.notAvailable(message: _notAvailableMessage());
    } on Object catch (error) {
      return PlatformInitResult.failure(
        message: 'Yandex Games init failed.',
        error: error,
      );
    }

    final sdk = _sdkClient!;

    final identity = _YandexIdentityCapability(sdk);
    _capabilities.register<IdentityCapability>(identity);
    _capabilities.registerDynamic(identity.runtimeType, identity);

    final leaderboardRead = _YandexLeaderboardReadCapability(sdk);
    _capabilities.register<LeaderboardReadCapability>(leaderboardRead);
    _capabilities.registerDynamic(leaderboardRead.runtimeType, leaderboardRead);

    final leaderboardWrite = _YandexLeaderboardWriteCapability(sdk);
    _capabilities.register<LeaderboardWriteCapability>(leaderboardWrite);
    _capabilities.registerDynamic(
      leaderboardWrite.runtimeType,
      leaderboardWrite,
    );

    final statsRead = _YandexStatsReadCapability(sdk);
    _capabilities.register<StatsReadCapability>(statsRead);
    _capabilities.registerDynamic(statsRead.runtimeType, statsRead);

    final statsWrite = _YandexStatsWriteCapability(sdk);
    _capabilities.register<StatsWriteCapability>(statsWrite);
    _capabilities.registerDynamic(statsWrite.runtimeType, statsWrite);

    final multiplayer = _YandexMultiplayerSessionCapability(sdk);
    _capabilities.register<MultiplayerSessionCapability>(multiplayer);
    _capabilities.registerDynamic(multiplayer.runtimeType, multiplayer);

    _emit(PlatformEvent.now(name: 'yandex.initialized'));
    return PlatformInitResult.success(message: 'Yandex Games initialized.');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _sdkClient = null;
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

  void _emit(final PlatformEvent event) {
    if (_disposed || _eventsController.isClosed) {
      return;
    }
    _eventsController.add(event);
  }

  Future<bool> _ensureSdkReady() async {
    final injectedOverride = config.sdkInjected;
    if (injectedOverride != null) {
      return injectedOverride;
    }

    final available = YandexGames.isAvailable(
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
    return YandexGames.isAvailable(expectedGlobal: config.expectedSdkGlobal);
  }

  String _notAvailableMessage() {
    return 'Yandex Games SDK global `${config.expectedSdkGlobal}` was not detected.';
  }
}

final class _YandexIdentityCapability implements IdentityCapability {
  const _YandexIdentityCapability(this._sdk);

  final YsdkClient _sdk;

  @override
  String get capabilityName => 'identity';

  @override
  Stream<PlayerIdentity?> get authChanges =>
      const Stream<PlayerIdentity?>.empty();

  @override
  Future<PlayerIdentity?> currentPlayer() async {
    try {
      final player = await _sdk.getPlayerUnsigned();
      final id = player.getUniqueId();
      final name = player.getName();
      final avatar = player.getPhoto('medium');
      final authorized = player.isAuthorized();
      return PlayerIdentity(
        id: id.isEmpty ? 'anonymous' : id,
        displayName: name.isEmpty ? 'Guest' : name,
        avatarUrl: avatar.isEmpty ? null : avatar,
        isAnonymous: !authorized,
      );
    } on Object {
      return null;
    }
  }
}

final class _YandexLeaderboardReadCapability
    implements LeaderboardReadCapability {
  const _YandexLeaderboardReadCapability(this._sdk);

  final YsdkClient _sdk;

  @override
  String get capabilityName => 'leaderboard.read';

  @override
  Future<LeaderboardEntries> getEntries(
    final String leaderboardId,
    final LeaderboardQuery q,
  ) async {
    final entries = await _sdk.leaderboards.getEntries(
      leaderboardId,
      includeUser: q.includeUser,
      quantityAround: q.quantityAround,
      quantityTop: q.quantityTop ?? q.limit,
    );

    return LeaderboardEntries(
      entries: entries.entries
          .map(
            (final item) => LeaderboardEntry(
              playerId: item.player.uniqueId,
              playerName: item.player.publicName,
              rank: item.rank,
              score: item.score,
              extraData: item.extraData,
            ),
          )
          .toList(growable: false),
      userRank: entries.userRank,
      total: entries.entries.length,
    );
  }

  @override
  Future<LeaderboardEntry?> getPlayerEntry(final String leaderboardId) async {
    try {
      final entry = await _sdk.leaderboards.getPlayerEntry(leaderboardId);
      return LeaderboardEntry(
        playerId: entry.player.uniqueId,
        playerName: entry.player.publicName,
        rank: entry.rank,
        score: entry.score,
        extraData: entry.extraData,
      );
    } on Object {
      return null;
    }
  }
}

final class _YandexLeaderboardWriteCapability
    implements LeaderboardWriteCapability {
  const _YandexLeaderboardWriteCapability(this._sdk);

  final YsdkClient _sdk;

  @override
  String get capabilityName => 'leaderboard.write';

  @override
  Future<void> submitScore(
    final String leaderboardId,
    final int score, {
    final String? extraData,
  }) async {
    await _sdk.leaderboards.setScore(
      leaderboardId,
      score,
      extraData: extraData,
    );
  }
}

final class _YandexStatsReadCapability implements StatsReadCapability {
  const _YandexStatsReadCapability(this._sdk);

  final YsdkClient _sdk;

  @override
  String get capabilityName => 'stats.read';

  @override
  Future<int?> getIntStat(final String name) async {
    final value = await _getStat(name);
    if (value == null) {
      return null;
    }
    return value.toInt();
  }

  @override
  Future<double?> getDoubleStat(final String name) async {
    final value = await _getStat(name);
    return value?.toDouble();
  }

  Future<num?> _getStat(final String name) async {
    final player = await _sdk.getPlayerUnsigned();
    final stats = await player.getStats(<String>[name]);
    final value = stats[name];
    return value is num ? value : null;
  }
}

final class _YandexStatsWriteCapability implements StatsWriteCapability {
  const _YandexStatsWriteCapability(this._sdk);

  final YsdkClient _sdk;

  @override
  String get capabilityName => 'stats.write';

  @override
  Future<void> setIntStat(final String name, final int value) async {
    final player = await _sdk.getPlayerUnsigned();
    await player.setStats(<String, num>{name: value});
  }

  @override
  Future<void> setDoubleStat(final String name, final double value) async {
    final player = await _sdk.getPlayerUnsigned();
    await player.setStats(<String, num>{name: value});
  }
}

final class _YandexMultiplayerSessionCapability
    implements MultiplayerSessionCapability {
  const _YandexMultiplayerSessionCapability(this._sdk);

  final YsdkClient _sdk;

  @override
  String get capabilityName => 'multiplayer.session';

  @override
  Future<MultiplayerSessionInitResult> initSession(
    final MultiplayerSessionInitRequest request,
  ) async {
    final options = MultiplayerInitOptionsModel(
      count: request.count,
      isEventBased: request.isEventBased,
      maxOpponentTurnTime: request.maxOpponentTurnTime,
      meta: request.metaRanges == null
          ? null
          : MultiplayerMetaRangesModel(
              meta1: _rangeOrDefault(request.metaRanges!.meta1),
              meta2: _rangeOrDefault(request.metaRanges!.meta2),
              meta3: _rangeOrDefault(request.metaRanges!.meta3),
            ),
    );

    final opponents = await _sdk.multiplayer.sessions.init(options: options);
    return MultiplayerSessionInitResult(
      opponents: opponents
          .map(
            (final item) => MultiplayerSessionOpponent(
              id: item.id,
              meta: MultiplayerMeta(
                meta1: item.meta.meta1,
                meta2: item.meta.meta2,
                meta3: item.meta.meta3,
              ),
              transactions: item.transactions
                  .map(
                    (final tx) =>
                        MultiplayerTransaction(data: tx.data, time: tx.time),
                  )
                  .toList(growable: false),
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<void> commitState(final MultiplayerCommitPayload payload) async {
    _sdk.multiplayer.sessions.commit(
      MultiplayerCommitPayloadModel(data: payload.data, time: payload.time),
    );
  }

  @override
  Future<MultiplayerPushResult> push(final MultiplayerMeta meta) async {
    final result = await _sdk.multiplayer.sessions.push(
      MultiplayerMetaModel(
        meta1: meta.meta1 ?? 0,
        meta2: meta.meta2 ?? 0,
        meta3: meta.meta3 ?? 0,
      ),
    );

    return MultiplayerPushResult(
      status: result.status,
      data: result.data,
      error: result.error,
    );
  }

  MultiplayerMetaRangeModel _rangeOrDefault(final MultiplayerMetaRange? range) {
    return MultiplayerMetaRangeModel(
      min: range?.min ?? 0,
      max: range?.max ?? 0,
    );
  }
}
