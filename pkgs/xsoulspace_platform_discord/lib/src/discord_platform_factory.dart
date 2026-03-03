import 'package:xsoulspace_discord_js/xsoulspace_discord_js.dart';
import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';
import 'package:xsoulspace_platform_foundation/xsoulspace_platform_foundation.dart';

import 'discord_platform_client.dart';
import 'discord_platform_config.dart';

final class DiscordPlatformFactory implements PlatformAdapterFactory {
  DiscordPlatformFactory({
    required this.config,
    this.priority = 0,
    this.environmentProbe,
    this.initClient,
  });

  final DiscordPlatformConfig config;
  @override
  final int priority;

  final bool Function(String expectedGlobal)? environmentProbe;
  final DiscordClientInitializer? initClient;

  @override
  PlatformId get platformId => PlatformId.discord;

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

    if (config.autoLoadBridge &&
        config.bridgeAutoloadHook != null &&
        config.bridgeScriptUrl != null) {
      return true;
    }

    return Discord.isAvailable(expectedGlobal: config.expectedSdkGlobal);
  }

  @override
  Future<PlatformClient> createClient() async {
    return DiscordPlatformClient(
      config: config,
      initClient:
          initClient ??
          ({required final clientId, required final expectedGlobal}) {
            return Discord.init(
              clientId: clientId,
              expectedGlobal: expectedGlobal,
            );
          },
    );
  }
}
