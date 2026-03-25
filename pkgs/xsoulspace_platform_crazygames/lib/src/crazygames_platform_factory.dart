import 'package:xsoulspace_crazygames_js/xsoulspace_crazygames_js.dart';
import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';
import 'package:xsoulspace_platform_foundation/xsoulspace_platform_foundation.dart';

import 'crazygames_platform_client.dart';
import 'crazygames_platform_config.dart';

final class CrazyGamesPlatformFactory implements PlatformAdapterFactory {
  CrazyGamesPlatformFactory({
    required this.config,
    this.priority = 0,
    this.environmentProbe,
    this.initClient,
  });

  final CrazyGamesPlatformConfig config;
  @override
  final int priority;
  final bool Function(String expectedGlobal)? environmentProbe;
  final CrazyGamesClientInitializer? initClient;

  @override
  PlatformId get platformId => PlatformId.crazyGames;

  @override
  Future<bool> isSupportedEnvironment() async {
    final probe = environmentProbe;
    if (probe != null) {
      return probe(config.expectedSdkGlobal);
    }

    final injected = config.sdkInjected;
    if (injected != null) {
      return injected;
    }

    if (config.autoLoadSdk &&
        config.sdkScriptLoader != null &&
        config.sdkUrl != null) {
      return true;
    }

    return CrazyGames.isAvailable(expectedGlobal: config.expectedSdkGlobal);
  }

  @override
  Future<PlatformClient> createClient() async {
    return CrazyGamesPlatformClient(
      config: config,
      initClient: initClient ?? CrazyGames.init,
    );
  }
}
