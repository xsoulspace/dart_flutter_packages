import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';
import 'package:xsoulspace_platform_crazygames/xsoulspace_platform_crazygames.dart';
import 'package:xsoulspace_platform_foundation/xsoulspace_platform_foundation.dart';
import 'package:xsoulspace_platform_gamification_interface/xsoulspace_platform_gamification_interface.dart';
import 'package:xsoulspace_platform_social_interface/xsoulspace_platform_social_interface.dart';
import 'package:xsoulspace_platform_yandex_games/xsoulspace_platform_yandex_games.dart';

import 'src/steam_factories_stub.dart'
    if (dart.library.io) 'src/steam_factories_io.dart'
    as steam;

Future<void> main() async {
  final runtime = PlatformRuntime(
    factories: <PlatformAdapterFactory>[
      ...steam.buildSteamFactories(),
      YandexGamesPlatformFactory(
        priority: 10,
        config: const YandexGamesPlatformConfig(),
      ),
      CrazyGamesPlatformFactory(
        priority: 20,
        config: const CrazyGamesPlatformConfig(),
      ),
    ],
    initOptions: const PlatformInitOptions(
      missingCapabilityBehavior: MissingCapabilityBehavior.permissive,
    ),
  );

  final start = await runtime.start();
  print('Active platform: ${start.activePlatform.name}');
  print(
    'Capabilities: ${start.capabilityTypes.map((final e) => e.toString()).join(', ')}',
  );

  final identity = runtime.maybe<IdentityCapability>();
  if (identity != null) {
    final player = await identity.currentPlayer();
    print('Current player: ${player?.displayName ?? 'anonymous'}');
  }

  final leaderboard = runtime.maybe<LeaderboardWriteCapability>();
  if (leaderboard != null) {
    await leaderboard.submitScore('default', 1234);
    print('Submitted sample score to leaderboard.');
  }

  await runtime.stop();
}
