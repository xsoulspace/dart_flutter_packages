import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';
import 'package:xsoulspace_vkplay_js/xsoulspace_vkplay_js.dart';

abstract interface class VkPlayRawCapability implements PlatformCapability {
  VkPlayClient get client;

  Future<Object?> callRaw(String methodName, {Map<String, Object?>? params});
}
