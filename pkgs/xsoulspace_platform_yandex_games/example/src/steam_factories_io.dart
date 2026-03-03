import 'package:xsoulspace_platform_foundation/xsoulspace_platform_foundation.dart';
import 'package:xsoulspace_platform_steam/xsoulspace_platform_steam.dart';

List<PlatformAdapterFactory> buildSteamFactories() {
  return <PlatformAdapterFactory>[
    SteamPlatformFactory(
      priority: 0,
      config: const SteamPlatformConfig(appId: 480, autoPumpCallbacks: false),
    ),
  ];
}
