import 'package:xsoulspace_discord_js/xsoulspace_discord_js.dart';
import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';

abstract interface class DiscordRawCapability implements PlatformCapability {
  DiscordClient get client;

  Future<Object?> callRaw(String methodName, {Map<String, Object?>? params});
}
