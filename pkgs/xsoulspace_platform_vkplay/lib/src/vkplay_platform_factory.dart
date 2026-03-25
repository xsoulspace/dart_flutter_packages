import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';
import 'package:xsoulspace_platform_foundation/xsoulspace_platform_foundation.dart';
import 'package:xsoulspace_vkplay_js/xsoulspace_vkplay_js.dart';

import 'vkplay_platform_client.dart';
import 'vkplay_platform_config.dart';

final class VkPlayPlatformFactory implements PlatformAdapterFactory {
  VkPlayPlatformFactory({
    required this.config,
    this.priority = 0,
    this.environmentProbe,
    this.initClient,
  });

  final VkPlayPlatformConfig config;
  @override
  final int priority;

  final bool Function(String expectedGlobal)? environmentProbe;
  final VkPlayClientInitializer? initClient;

  @override
  PlatformId get platformId => PlatformId.vkPlay;

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

    return VkPlay.isAvailable(expectedGlobal: config.expectedSdkGlobal);
  }

  @override
  Future<PlatformClient> createClient() async {
    return VkPlayPlatformClient(
      config: config,
      initClient: initClient ?? VkPlay.init,
    );
  }
}
