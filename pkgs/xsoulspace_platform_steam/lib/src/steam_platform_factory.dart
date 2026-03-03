import 'dart:io';

import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';
import 'package:xsoulspace_platform_foundation/xsoulspace_platform_foundation.dart';
import 'package:xsoulspace_steamworks/xsoulspace_steamworks.dart';

import 'steam_platform_client.dart';
import 'steam_platform_config.dart';

final class SteamPlatformFactory implements PlatformAdapterFactory {
  SteamPlatformFactory({
    required this.config,
    this.priority = 0,
    this.clientFactory,
    this.environmentProbe,
  });

  final SteamPlatformConfig config;
  @override
  final int priority;

  final SteamClient Function()? clientFactory;
  final bool Function()? environmentProbe;

  @override
  PlatformId get platformId => PlatformId.steam;

  @override
  Future<bool> isSupportedEnvironment() async {
    final probe = environmentProbe;
    if (probe != null) {
      return probe();
    }
    return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  }

  @override
  Future<PlatformClient> createClient() async {
    return SteamPlatformClient(
      config: config,
      steamClient: clientFactory?.call() ?? SteamClient(),
    );
  }
}
