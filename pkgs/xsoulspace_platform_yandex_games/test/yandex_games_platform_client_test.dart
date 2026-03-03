import 'dart:async';

import 'package:test/test.dart';
import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';
import 'package:xsoulspace_platform_gamification_interface/xsoulspace_platform_gamification_interface.dart';
import 'package:xsoulspace_platform_multiplayer_interface/xsoulspace_platform_multiplayer_interface.dart';
import 'package:xsoulspace_platform_social_interface/xsoulspace_platform_social_interface.dart';
import 'package:xsoulspace_platform_yandex_games/xsoulspace_platform_yandex_games.dart';
import 'package:xsoulspace_ysdk_games_js/xsoulspace_ysdk_games_js.dart';

void main() {
  test('non-web init returns notAvailable', () async {
    final client = YandexGamesPlatformClient(
      config: const YandexGamesPlatformConfig(),
      initClient: YandexGames.init,
    );

    final result = await client.init(const PlatformInitOptions());
    expect(result.isNotAvailable, isTrue);
  });

  test(
    'returns deterministic notAvailable when SDK global is missing',
    () async {
      var initCalled = false;
      final client = YandexGamesPlatformClient(
        config: const YandexGamesPlatformConfig(
          expectedSdkGlobal: 'MissingYsdkGlobal',
          sdkInjected: false,
        ),
        initClient:
            ({
              final bool signed = false,
              final String expectedGlobal = 'YaGames',
            }) async {
              initCalled = true;
              throw StateError('should not be called');
            },
      );

      final result = await client.init(const PlatformInitOptions());
      expect(result.isNotAvailable, isTrue);
      expect(
        result.message,
        'Yandex Games SDK global `MissingYsdkGlobal` was not detected.',
      );
      expect(initCalled, isFalse);
    },
  );

  test('identity, leaderboard, stats and multiplayer mappings', () async {
    final fakeSdk = _FakeYsdkClient();
    final client = YandexGamesPlatformClient(
      config: const YandexGamesPlatformConfig(),
      initClient:
          ({
            final bool signed = false,
            final String expectedGlobal = 'YaGames',
          }) async => fakeSdk,
    );

    final init = await client.init(const PlatformInitOptions());
    expect(init.isSuccess, isTrue);

    final identity = client.require<IdentityCapability>();
    final player = await identity.currentPlayer();
    expect(player?.id, 'player-1');
    expect(player?.displayName, 'Player One');
    expect(player?.isAnonymous, isFalse);

    final leaderboardRead = client.require<LeaderboardReadCapability>();
    final leaderboardWrite = client.require<LeaderboardWriteCapability>();

    final entries = await leaderboardRead.getEntries(
      'lb-main',
      const LeaderboardQuery(includeUser: true, quantityTop: 10),
    );
    expect(entries.entries, hasLength(1));
    expect(entries.entries.first.playerId, 'player-1');
    expect(entries.entries.first.score, 1500);

    final playerEntry = await leaderboardRead.getPlayerEntry('lb-main');
    expect(playerEntry?.playerName, 'Player One');

    await leaderboardWrite.submitScore('lb-main', 1999, extraData: 'meta');
    expect(fakeSdk.leaderboardsClient.lastScoreName, 'lb-main');
    expect(fakeSdk.leaderboardsClient.lastScoreValue, 1999);
    expect(fakeSdk.leaderboardsClient.lastScoreExtraData, 'meta');

    final statsRead = client.require<StatsReadCapability>();
    final statsWrite = client.require<StatsWriteCapability>();
    expect(await statsRead.getIntStat('coins'), 10);

    await statsWrite.setIntStat('coins', 20);
    expect(fakeSdk.player.stats['coins'], 20);

    final multiplayer = client.require<MultiplayerSessionCapability>();
    final initSession = await multiplayer.initSession(
      const MultiplayerSessionInitRequest(count: 2),
    );
    expect(initSession.opponents, hasLength(1));
    expect(initSession.opponents.first.id, 'op-1');

    await multiplayer.commitState(
      const MultiplayerCommitPayload(
        data: <String, Object?>{'turn': 1},
        time: 1,
      ),
    );
    expect(fakeSdk.multiplayerClient.sessionsClient.lastCommitPayload?.time, 1);

    final pushResult = await multiplayer.push(
      const MultiplayerMeta(meta1: 1, meta2: 2, meta3: 3),
    );
    expect(pushResult.status, 'ok');
  });

  test('dispose is idempotent', () async {
    final client = YandexGamesPlatformClient(
      config: const YandexGamesPlatformConfig(),
      initClient:
          ({
            final bool signed = false,
            final String expectedGlobal = 'YaGames',
          }) async => _FakeYsdkClient(),
    );

    final init = await client.init(const PlatformInitOptions());
    expect(init.isSuccess, isTrue);

    await client.dispose();
    await client.dispose();
  });
}

final class _FakeYsdkClient extends YsdkClient {
  _FakeYsdkClient();

  final _FakeYsdkPlayer player = _FakeYsdkPlayer();
  final _FakeLeaderboardsClient leaderboardsClient = _FakeLeaderboardsClient();
  final _FakeMultiplayerClient multiplayerClient = _FakeMultiplayerClient();

  @override
  YsdkLeaderboardsClient get leaderboards => leaderboardsClient;

  @override
  YsdkMultiplayerClient get multiplayer => multiplayerClient;

  @override
  Future<YsdkPlayer> getPlayerUnsigned() async => player;
}

final class _FakeYsdkPlayer extends YsdkPlayer {
  _FakeYsdkPlayer();

  final Map<String, num> stats = <String, num>{'coins': 10};

  @override
  String getUniqueId() => 'player-1';

  @override
  String getName() => 'Player One';

  @override
  String getPhoto(final String size) => 'https://example.com/player.png';

  @override
  bool isAuthorized() => true;

  @override
  Future<Map<String, Object?>> getStats([final List<String>? keys]) async {
    if (keys == null || keys.isEmpty) {
      return stats.map(
        (final key, final value) => MapEntry<String, Object?>(key, value),
      );
    }
    return <String, Object?>{
      for (final key in keys)
        if (stats.containsKey(key)) key: stats[key],
    };
  }

  @override
  Future<void> setStats(final Map<String, num> nextStats) async {
    stats.addAll(nextStats);
  }
}

final class _FakeLeaderboardsClient extends YsdkLeaderboardsClient {
  String? lastScoreName;
  int? lastScoreValue;
  String? lastScoreExtraData;

  @override
  Future<LeaderboardEntriesDataModel> getEntries(
    final String leaderboardName, {
    final bool? includeUser,
    final int? quantityAround,
    final int? quantityTop,
  }) async {
    return LeaderboardEntriesDataModel(
      entries: <LeaderboardEntryModel>[_entry()],
      leaderboard: _description(),
      userRank: 1,
    );
  }

  @override
  Future<LeaderboardEntryModel> getPlayerEntry(
    final String leaderboardName,
  ) async {
    return _entry();
  }

  @override
  Future<void> setScore(
    final String leaderboardName,
    final int score, {
    final String? extraData,
  }) async {
    lastScoreName = leaderboardName;
    lastScoreValue = score;
    lastScoreExtraData = extraData;
  }

  LeaderboardEntryModel _entry() {
    return const LeaderboardEntryModel(
      player: LeaderboardPlayerModel(
        lang: 'en',
        publicName: 'Player One',
        uniqueId: 'player-1',
        scopePermissions: <String, String>{},
      ),
      rank: 1,
      score: 1500,
      formattedScore: '1 500',
      extraData: 'meta',
    );
  }

  LeaderboardDescriptionModel _description() {
    return const LeaderboardDescriptionModel(
      appId: 'app',
      isDefault: true,
      name: 'lb-main',
      type: 'numeric',
      invertSortOrder: false,
      decimalOffset: 0,
      title: <String, String>{'en': 'Leaderboard'},
    );
  }
}

final class _FakeMultiplayerClient extends YsdkMultiplayerClient {
  final _FakeMultiplayerSessionsClient sessionsClient =
      _FakeMultiplayerSessionsClient();

  @override
  YsdkMultiplayerSessionsClient get sessions => sessionsClient;
}

final class _FakeMultiplayerSessionsClient
    extends YsdkMultiplayerSessionsClient {
  MultiplayerCommitPayloadModel? lastCommitPayload;

  @override
  void commit(final MultiplayerCommitPayloadModel payload) {
    lastCommitPayload = payload;
  }

  @override
  Future<List<MultiplayerSessionOpponentModel>> init({
    final MultiplayerInitOptionsModel? options,
  }) async {
    return const <MultiplayerSessionOpponentModel>[
      MultiplayerSessionOpponentModel(
        id: 'op-1',
        meta: MultiplayerMetaModel(meta1: 1, meta2: 2, meta3: 3),
        transactions: <MultiplayerCommitPayloadModel>[
          MultiplayerCommitPayloadModel(
            data: <String, Object?>{'turn': 1},
            time: 1,
          ),
        ],
      ),
    ];
  }

  @override
  Future<CallbackBaseMessageDataModel> push(
    final MultiplayerMetaModel meta,
  ) async {
    return const CallbackBaseMessageDataModel(status: 'ok', data: null);
  }
}
