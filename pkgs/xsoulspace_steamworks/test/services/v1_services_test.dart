import 'package:test/test.dart';
import 'package:xsoulspace_steamworks/xsoulspace_steamworks.dart';

import '../support/fakes.dart';

void main() {
  test('v1 services expose user/friends/stats/achievements', () async {
    final fakeApi = FakeSteamNativeApi();
    final client = SteamClient(
      nativeApiFactory: FakeSteamNativeApiFactory(fakeApi),
    );

    final result = await client.initialize(
      const SteamInitConfig(appId: 480, autoPumpCallbacks: false),
    );
    expect(result.success, true);

    expect(client.user.isLoggedOn, true);
    expect(client.user.steamId, 76561197960287930);
    expect(client.friends.personaName, 'Player');
    expect(client.friends.getFriendCount(), 3);
    expect(client.friends.getFriendSteamIds(), <int>[111, 222, 333]);
    expect(client.friends.getFriendPersonaName(222), 'Bob');

    expect(await client.stats.requestCurrentStats(), true);
    expect(client.stats.setIntStat('kills', 7), true);
    expect(client.stats.getIntStat('kills'), 7);
    expect(client.stats.setFloatStat('accuracy', 0.75), true);
    expect(client.stats.getFloatStat('accuracy'), closeTo(0.75, 0.0001));
    expect(await client.stats.storeStats(), true);

    expect(client.achievements.getAchievement('ACH_WIN_ONE_GAME'), isNull);
    expect(client.achievements.setAchievement('ACH_WIN_ONE_GAME'), true);
    expect(client.achievements.getAchievement('ACH_WIN_ONE_GAME'), true);
    expect(client.achievements.clearAchievement('ACH_WIN_ONE_GAME'), true);
    expect(client.achievements.getAchievement('ACH_WIN_ONE_GAME'), false);

    await client.shutdown();
  });
}
