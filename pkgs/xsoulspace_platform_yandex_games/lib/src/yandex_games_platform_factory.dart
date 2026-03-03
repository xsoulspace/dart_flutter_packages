import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';
import 'package:xsoulspace_platform_foundation/xsoulspace_platform_foundation.dart';
import 'package:xsoulspace_ysdk_games_js/xsoulspace_ysdk_games_js.dart';

import 'yandex_games_platform_client.dart';
import 'yandex_games_platform_config.dart';

final class YandexGamesPlatformFactory implements PlatformAdapterFactory {
  YandexGamesPlatformFactory({
    required this.config,
    this.priority = 0,
    this.environmentProbe,
    this.initClient,
  });

  final YandexGamesPlatformConfig config;
  @override
  final int priority;
  final bool Function()? environmentProbe;
  final Future<YsdkClient> Function({bool signed})? initClient;

  @override
  PlatformId get platformId => PlatformId.yandexGames;

  @override
  Future<bool> isSupportedEnvironment() async {
    final probe = environmentProbe;
    return probe?.call() ?? true;
  }

  @override
  Future<PlatformClient> createClient() async {
    return YandexGamesPlatformClient(
      config: config,
      initClient: initClient ?? YandexGames.init,
    );
  }
}
