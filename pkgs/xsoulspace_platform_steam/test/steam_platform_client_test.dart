import 'package:test/test.dart';
import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';
import 'package:xsoulspace_platform_gamification_interface/xsoulspace_platform_gamification_interface.dart';
import 'package:xsoulspace_platform_social_interface/xsoulspace_platform_social_interface.dart';
import 'package:xsoulspace_platform_steam/xsoulspace_platform_steam.dart';
import 'package:xsoulspace_steamworks/xsoulspace_steamworks.dart';

import 'support/fakes.dart';

void main() {
  SteamPlatformClient buildClient(final FakeSteamNativeApi api) {
    final steamClient = SteamClient(
      nativeApiFactory: FakeSteamNativeApiFactory(api),
    );

    return SteamPlatformClient(
      config: const SteamPlatformConfig(appId: 480, autoPumpCallbacks: false),
      steamClient: steamClient,
    );
  }

  test('init/shutdown is idempotent', () async {
    final api = FakeSteamNativeApi();
    final client = buildClient(api);

    final initResult = await client.init(const PlatformInitOptions());
    expect(initResult.isSuccess, isTrue);

    await client.dispose();
    await client.dispose();
    expect(api.shutdownCalled, isTrue);
  });

  test('achievement unlock/read/clear flow', () async {
    final api = FakeSteamNativeApi();
    final client = buildClient(api);

    await client.init(const PlatformInitOptions());

    final read = client.require<AchievementReadCapability>();
    final write = client.require<AchievementWriteCapability>();

    expect(await read.getAchievement('ACH_WIN_ONE_GAME'), isNull);

    await write.unlockAchievement('ACH_WIN_ONE_GAME');
    expect(
      await read.getAchievement('ACH_WIN_ONE_GAME'),
      isA<AchievementState>().having(
        (final state) => state.unlocked,
        'unlocked',
        isTrue,
      ),
    );

    await write.clearAchievement('ACH_WIN_ONE_GAME');
    expect(
      await read.getAchievement('ACH_WIN_ONE_GAME'),
      isA<AchievementState>().having(
        (final state) => state.unlocked,
        'unlocked',
        isFalse,
      ),
    );
  });

  test('stats read/write/flush flow', () async {
    final api = FakeSteamNativeApi();
    final client = buildClient(api);

    await client.init(const PlatformInitOptions());

    final read = client.require<StatsReadCapability>();
    final write = client.require<StatsWriteCapability>();
    final sync = client.require<StatsSyncCapability>();

    await sync.requestCurrentStats();
    await write.setIntStat('kills', 7);
    await write.setDoubleStat('accuracy', 0.75);
    expect(await read.getIntStat('kills'), 7);
    expect(await read.getDoubleStat('accuracy'), closeTo(0.75, 0.0001));
    await sync.flushStats();
  });

  test('friends list mapping is correct', () async {
    final api = FakeSteamNativeApi();
    final client = buildClient(api);

    await client.init(const PlatformInitOptions());

    final friendsCapability = client.require<FriendsCapability>();
    final friends = await friendsCapability.listFriends(limit: 2, offset: 1);

    expect(friends, hasLength(2));
    expect(friends[0].id, '222');
    expect(friends[0].displayName, 'Bob');
    expect(friends[1].id, '333');
    expect(friends[1].displayName, 'Charlie');
  });
}
