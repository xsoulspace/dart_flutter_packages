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
  final bool Function()? environmentProbe;
  final Future<CrazyGamesClient> Function()? initClient;

  @override
  PlatformId get platformId => PlatformId.crazyGames;

  @override
  Future<bool> isSupportedEnvironment() async {
    final probe = environmentProbe;
    return probe?.call() ?? true;
  }

  @override
  Future<PlatformClient> createClient() async {
    return CrazyGamesPlatformClient(
      config: config,
      initClient: initClient ?? CrazyGames.init,
    );
  }
}
